package services

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/config"
	"github.com/abhishare16/Abhi-Share/backend/models"
)

type RecurringScheduleService struct {
	DB                  *pgxpool.Pool
	NotificationService *NotificationService
	WalletService       *WalletService
	Config              *config.Config
}

func NewRecurringScheduleService(db *pgxpool.Pool, notifService *NotificationService, cfg *config.Config) *RecurringScheduleService {
	return &RecurringScheduleService{
		DB:                  db,
		NotificationService: notifService,
		Config:              cfg,
	}
}

// GenerateDates computes the list of future ride dates based on recurrence rule.
func (s *RecurringScheduleService) GenerateDates(
	recurrenceType string,
	selectedWeekdays []string,
	startDateStr string,
	endDateStr *string,
	occurrenceCount *int,
	departureTimeStr string,
) ([]time.Time, error) {
	startDate, err := time.Parse("2006-01-02", startDateStr)
	if err != nil {
		return nil, fmt.Errorf("invalid start date format, expected YYYY-MM-DD: %w", err)
	}

	depTime, err := time.Parse("15:04", departureTimeStr)
	if err != nil {
		// Try "15:04:05" if seconds were provided
		depTime, err = time.Parse("15:04:05", departureTimeStr)
		if err != nil {
			return nil, fmt.Errorf("invalid departure time format: %w", err)
		}
	}

	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	if startDate.Before(today) {
		return nil, fmt.Errorf("start date cannot be in the past")
	}

	var endDate *time.Time
	if endDateStr != nil && strings.TrimSpace(*endDateStr) != "" {
		parsed, err := time.Parse("2006-01-02", strings.TrimSpace(*endDateStr))
		if err != nil {
			return nil, fmt.Errorf("invalid end date format: %w", err)
		}
		if parsed.Before(startDate) {
			return nil, fmt.Errorf("end date cannot be before start date")
		}
		endDate = &parsed
	}

	maxOccurrences := 60 // Safe limit to prevent database overload
	if occurrenceCount != nil && *occurrenceCount > 0 {
		if *occurrenceCount < maxOccurrences {
			maxOccurrences = *occurrenceCount
		}
	}

	// Helper for weekday matching
	weekdayMap := make(map[time.Weekday]bool)
	for _, w := range selectedWeekdays {
		switch strings.ToLower(strings.TrimSpace(w)) {
		case "mon", "monday", "1":
			weekdayMap[time.Monday] = true
		case "tue", "tuesday", "2":
			weekdayMap[time.Tuesday] = true
		case "wed", "wednesday", "3":
			weekdayMap[time.Wednesday] = true
		case "thu", "thursday", "4":
			weekdayMap[time.Thursday] = true
		case "fri", "friday", "5":
			weekdayMap[time.Friday] = true
		case "sat", "saturday", "6":
			weekdayMap[time.Saturday] = true
		case "sun", "sunday", "0", "7":
			weekdayMap[time.Sunday] = true
		}
	}

	var dates []time.Time
	current := startDate

	// If start date is today, check if departure time has already passed
	if current.Equal(today) {
		currentDeparture := time.Date(now.Year(), now.Month(), now.Day(), depTime.Hour(), depTime.Minute(), 0, 0, now.Location())
		if currentDeparture.Before(now.Add(5 * time.Minute)) {
			// Advance to next day if today's departure has passed
			current = current.AddDate(0, 0, 1)
		}
	}

	// Maximum search range: 120 days
	searchLimit := startDate.AddDate(0, 0, 120)
	if endDate != nil && endDate.Before(searchLimit) {
		searchLimit = *endDate
	}

	cleanType := strings.ToLower(strings.TrimSpace(recurrenceType))

	for !current.After(searchLimit) && len(dates) < maxOccurrences {
		shouldInclude := false

		switch cleanType {
		case "daily", "every_day", "everyday":
			shouldInclude = true
			current = current.AddDate(0, 0, 1)

		case "weekly", "every_week":
			shouldInclude = true
			current = current.AddDate(0, 0, 7)

		case "biweekly", "every_2_weeks", "every_two_weeks":
			shouldInclude = true
			current = current.AddDate(0, 0, 14)

		case "custom":
			if len(weekdayMap) == 0 {
				return nil, fmt.Errorf("custom recurrence requires at least one selected weekday")
			}
			if weekdayMap[current.Weekday()] {
				shouldInclude = true
			}
			current = current.AddDate(0, 0, 1)

		default:
			return nil, fmt.Errorf("unsupported recurrence type: %s", recurrenceType)
		}

		if shouldInclude {
			// Revert the step to get the date that matched
			var matchedDate time.Time
			switch cleanType {
			case "daily", "every_day", "everyday", "custom":
				matchedDate = current.AddDate(0, 0, -1)
			case "weekly", "every_week":
				matchedDate = current.AddDate(0, 0, -7)
			case "biweekly", "every_2_weeks", "every_two_weeks":
				matchedDate = current.AddDate(0, 0, -14)
			}

			if endDate != nil && matchedDate.After(*endDate) {
				break
			}
			dates = append(dates, matchedDate)
		}
	}

	if len(dates) == 0 {
		return nil, fmt.Errorf("no valid future dates found for the given schedule criteria")
	}

	return dates, nil
}

// CreateRecurringSchedule creates the schedule record and generates draft rides for all dates.
func (s *RecurringScheduleService) CreateRecurringSchedule(
	ctx context.Context,
	userID string,
	req models.CreateRecurringScheduleRequest,
) (string, []string, float64, float64, float64, error) {
	// Verify that driver is eligible to create rides (wallet balance not at or below -₹100 limit)
	if s.WalletService != nil {
		if err := s.WalletService.CheckRideCreationEligibility(ctx, userID); err != nil {
			return "", nil, 0, 0, 0, err
		}
	}

	// Verify user exists
	var userExists bool
	err := s.DB.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)`, userID).Scan(&userExists)
	if err != nil {
		return "", nil, 0, 0, 0, err
	}
	if !userExists {
		return "", nil, 0, 0, 0, fmt.Errorf("user not found")
	}

	// Verify vehicle exists and belongs to user
	var vehicleType string
	var vehicleOwnerID string
	err = s.DB.QueryRow(ctx,
		`SELECT vehicle_type, user_id FROM vehicles WHERE id = $1`,
		req.VehicleID,
	).Scan(&vehicleType, &vehicleOwnerID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", nil, 0, 0, 0, fmt.Errorf("vehicle not found")
		}
		return "", nil, 0, 0, 0, err
	}
	if vehicleOwnerID != userID {
		return "", nil, 0, 0, 0, fmt.Errorf("vehicle does not belong to driver")
	}

	// Validate seats
	maxSeats := 1
	switch vehicleType {
	case "five_seater":
		maxSeats = 4
	case "seven_seater":
		maxSeats = 6
	}
	if req.AvailableSeats < 1 || req.AvailableSeats > maxSeats {
		return "", nil, 0, 0, 0, fmt.Errorf("available seats must be between 1 and %d for this vehicle", maxSeats)
	}

	if req.PricePerSeat < 0 {
		return "", nil, 0, 0, 0, fmt.Errorf("price per seat cannot be negative")
	}

	// Generate the dates
	dates, err := s.GenerateDates(
		req.RecurrenceType,
		req.SelectedWeekdays,
		req.StartDate,
		req.EndDate,
		req.OccurrenceCount,
		req.DepartureTime,
	)
	if err != nil {
		return "", nil, 0, 0, 0, err
	}

	templateData := map[string]interface{}{
		"vehicle_id":             req.VehicleID,
		"from_location":          req.FromLocation,
		"to_location":            req.ToLocation,
		"departure_time":         req.DepartureTime,
		"estimated_arrival_time": req.EstimatedArrivalTime,
		"available_seats":        req.AvailableSeats,
		"price_per_seat":         req.PricePerSeat,
		"is_women_only":          req.IsWomenOnly,
	}

	if req.IsWomenOnly {
		var driverGender string
		err := s.DB.QueryRow(ctx, `SELECT gender FROM users WHERE id = $1`, userID).Scan(&driverGender)
		if err != nil || driverGender != "female" {
			return "", nil, 0, 0, 0, fmt.Errorf("only verified female drivers can create Women Only recurring rides")
		}
	}

	templateJSON, err := json.Marshal(templateData)
	if err != nil {
		return "", nil, 0, 0, 0, fmt.Errorf("failed to encode ride template: %w", err)
	}

	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return "", nil, 0, 0, 0, err
	}
	defer tx.Rollback(ctx)

	var scheduleID string
	err = tx.QueryRow(ctx,
		`INSERT INTO recurring_schedules (
			user_id,
			recurrence_type,
			selected_weekdays,
			start_date,
			end_date,
			occurrence_count,
			ride_template,
			status
		) VALUES ($1, $2, $3, $4, $5, $6, $7, 'draft')
		RETURNING id`,
		userID,
		req.RecurrenceType,
		req.SelectedWeekdays,
		req.StartDate,
		req.EndDate,
		len(dates),
		templateJSON,
	).Scan(&scheduleID)
	if err != nil {
		return "", nil, 0, 0, 0, fmt.Errorf("failed to create recurring schedule: %w", err)
	}

	var rideIDs []string
	userAmount := req.PricePerSeat
	appAmount := 0.0
	totalAmount := userAmount
	if s.Config != nil && s.Config.ExtraPayPercent > 0 {
		appAmount = math.Round(userAmount * s.Config.ExtraPayPercent / 100.0)
		totalAmount = userAmount + appAmount
	}

	for _, date := range dates {
		var rideID string
		dateStr := date.Format("2006-01-02")
		err = tx.QueryRow(ctx,
			`INSERT INTO rides (
				driver_id,
				vehicle_id,
				from_location,
				to_location,
				journey_date,
				departure_time,
				estimated_arrival_time,
				available_seats,
				price_per_seat,
				user_amount,
				app_amount,
				total_amount,
				is_women_only,
				status,
				recurring_schedule_id
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, 'draft', $14)
			RETURNING id`,
			userID,
			req.VehicleID,
			req.FromLocation,
			req.ToLocation,
			dateStr,
			req.DepartureTime,
			req.EstimatedArrivalTime,
			req.AvailableSeats,
			req.PricePerSeat,
			userAmount,
			appAmount,
			totalAmount,
			req.IsWomenOnly,
			scheduleID,
		).Scan(&rideID)
		if err != nil {
			return "", nil, 0, 0, 0, fmt.Errorf("failed to create draft ride for date %s: %w", dateStr, err)
		}
		rideIDs = append(rideIDs, rideID)
	}

	if err := tx.Commit(ctx); err != nil {
		return "", nil, 0, 0, 0, err
	}

	return scheduleID, rideIDs, userAmount, appAmount, totalAmount, nil
}

// UploadSelfie assigns the uploaded driver selfie to the recurring schedule and all its draft rides.
func (s *RecurringScheduleService) UploadSelfie(
	ctx context.Context,
	scheduleID string,
	userID string,
	selfieURL string,
) error {
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var exists bool
	err = tx.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM recurring_schedules WHERE id = $1 AND user_id = $2)`,
		scheduleID, userID,
	).Scan(&exists)
	if err != nil || !exists {
		return fmt.Errorf("recurring schedule not found")
	}

	// Update template with selfie URL
	_, err = tx.Exec(ctx,
		`UPDATE recurring_schedules
		 SET ride_template = jsonb_set(ride_template, '{driver_selfie_url}', to_jsonb($1::text)),
		     updated_at = NOW()
		 WHERE id = $2 AND user_id = $3`,
		selfieURL, scheduleID, userID,
	)
	if err != nil {
		return fmt.Errorf("failed to update template selfie: %w", err)
	}

	// Update all draft rides belonging to this schedule
	_, err = tx.Exec(ctx,
		`UPDATE rides
		 SET driver_selfie_url = $1,
		     status = 'selfie_uploaded',
		     updated_at = NOW()
		 WHERE recurring_schedule_id = $2
		   AND driver_id = $3
		   AND status = 'draft'`,
		selfieURL, scheduleID, userID,
	)
	if err != nil {
		return fmt.Errorf("failed to update draft rides with selfie: %w", err)
	}

	return tx.Commit(ctx)
}

// PublishRecurringSchedule activates the schedule and publishes all generated rides.
func (s *RecurringScheduleService) PublishRecurringSchedule(
	ctx context.Context,
	scheduleID string,
	userID string,
) (int, error) {
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	res, err := tx.Exec(ctx,
		`UPDATE recurring_schedules
		 SET status = 'active',
		     updated_at = NOW()
		 WHERE id = $1 AND user_id = $2`,
		scheduleID, userID,
	)
	if err != nil || res.RowsAffected() == 0 {
		return 0, fmt.Errorf("recurring schedule not found or cannot be published")
	}

	// Publish all rides with selfie uploaded
	ridesRes, err := tx.Exec(ctx,
		`UPDATE rides
		 SET status = 'active',
		     updated_at = NOW()
		 WHERE recurring_schedule_id = $1
		   AND driver_id = $2
		   AND status = 'selfie_uploaded'
		   AND driver_selfie_url IS NOT NULL
		   AND driver_selfie_url <> ''`,
		scheduleID, userID,
	)
	if err != nil {
		return 0, fmt.Errorf("failed to activate schedule rides: %w", err)
	}

	count := int(ridesRes.RowsAffected())

	// Create notification
	_, _ = tx.Exec(ctx,
		`INSERT INTO notifications (user_id, type, title, message)
		 VALUES ($1, 'ride_created', 'Recurring Schedule Published',
		 'Your recurring ride schedule has been published with ' || $2::text || ' active rides.')`,
		userID, count,
	)

	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}

	return count, nil
}

// GetUserRecurringSchedules retrieves all schedules for a user with status counts.
func (s *RecurringScheduleService) GetUserRecurringSchedules(
	ctx context.Context,
	userID string,
) ([]models.RecurringSchedule, error) {
	rows, err := s.DB.Query(ctx,
		`SELECT
			rs.id,
			rs.user_id,
			rs.recurrence_type,
			rs.selected_weekdays,
			rs.start_date::text,
			rs.end_date::text,
			rs.occurrence_count,
			rs.ride_template,
			rs.status,
			rs.created_at,
			rs.updated_at,
			COALESCE(COUNT(r.id), 0) AS total_rides,
			COALESCE(COUNT(r.id) FILTER (WHERE r.status = 'active'), 0) AS active_rides,
			COALESCE(COUNT(r.id) FILTER (WHERE r.status = 'completed'), 0) AS completed_rides,
			COALESCE(COUNT(r.id) FILTER (WHERE r.status = 'cancelled'), 0) AS cancelled_rides
		 FROM recurring_schedules rs
		 LEFT JOIN rides r ON r.recurring_schedule_id = rs.id
		 WHERE rs.user_id = $1
		 GROUP BY rs.id
		 ORDER BY rs.created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var schedules []models.RecurringSchedule
	for rows.Next() {
		var sc models.RecurringSchedule
		var weekdays []string
		var endDateStr *string
		var rawTemplate []byte

		err := rows.Scan(
			&sc.ID,
			&sc.UserID,
			&sc.RecurrenceType,
			&weekdays,
			&sc.StartDate,
			&endDateStr,
			&sc.OccurrenceCount,
			&rawTemplate,
			&sc.Status,
			&sc.CreatedAt,
			&sc.UpdatedAt,
			&sc.TotalRides,
			&sc.ActiveRides,
			&sc.CompletedRides,
			&sc.CancelledRides,
		)
		if err != nil {
			return nil, err
		}

		sc.SelectedWeekdays = weekdays
		sc.EndDate = endDateStr
		if len(rawTemplate) > 0 {
			_ = json.Unmarshal(rawTemplate, &sc.RideTemplate)
		}
		schedules = append(schedules, sc)
	}

	return schedules, nil
}

// GetRecurringScheduleDetail returns schedule metadata along with its rides.
func (s *RecurringScheduleService) GetRecurringScheduleDetail(
	ctx context.Context,
	scheduleID string,
	userID string,
) (*models.RecurringSchedule, error) {
	var sc models.RecurringSchedule
	var weekdays []string
	var endDateStr *string
	var rawTemplate []byte

	err := s.DB.QueryRow(ctx,
		`SELECT
			id,
			user_id,
			recurrence_type,
			selected_weekdays,
			start_date::text,
			end_date::text,
			occurrence_count,
			ride_template,
			status,
			created_at,
			updated_at
		 FROM recurring_schedules
		 WHERE id = $1 AND user_id = $2`,
		scheduleID, userID,
	).Scan(
		&sc.ID,
		&sc.UserID,
		&sc.RecurrenceType,
		&weekdays,
		&sc.StartDate,
		&endDateStr,
		&sc.OccurrenceCount,
		&rawTemplate,
		&sc.Status,
		&sc.CreatedAt,
		&sc.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("recurring schedule not found")
		}
		return nil, err
	}

	sc.SelectedWeekdays = weekdays
	sc.EndDate = endDateStr
	if len(rawTemplate) > 0 {
		_ = json.Unmarshal(rawTemplate, &sc.RideTemplate)
	}

	// Fetch rides
	rows, err := s.DB.Query(ctx,
		`SELECT
			r.id,
			r.driver_id,
			r.vehicle_id,
			r.from_location,
			r.to_location,
			r.journey_date,
			r.departure_time,
			r.estimated_arrival_time,
			r.available_seats,
			r.price_per_seat,
			r.status,
			COALESCE(r.driver_selfie_url, ''),
			r.driver_selfie_expires_at,
			r.recurring_schedule_id::text,
			r.created_at,
			r.updated_at,
			u.full_name AS driver_name,
			v.model AS vehicle_model,
			v.vehicle_number,
			v.vehicle_type,
			COALESCE(v.vehicle_photo_url, '') AS vehicle_photo_url
		 FROM rides r
		 JOIN users u ON u.id = r.driver_id
		 JOIN vehicles v ON v.id = r.vehicle_id
		 WHERE r.recurring_schedule_id = $1
		 ORDER BY r.journey_date ASC, r.departure_time ASC`,
		scheduleID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var rd models.RideDetail
		var recSchedID *string
		err := rows.Scan(
			&rd.ID,
			&rd.DriverID,
			&rd.VehicleID,
			&rd.FromLocation,
			&rd.ToLocation,
			&rd.JourneyDate,
			&rd.DepartureTime,
			&rd.EstimatedArrivalTime,
			&rd.AvailableSeats,
			&rd.PricePerSeat,
			&rd.Status,
			&rd.DriverSelfieURL,
			&rd.DriverSelfieExpiresAt,
			&recSchedID,
			&rd.CreatedAt,
			&rd.UpdatedAt,
			&rd.DriverName,
			&rd.VehicleModel,
			&rd.VehicleNumber,
			&rd.VehicleType,
			&rd.VehiclePhotoURL,
		)
		if err != nil {
			return nil, err
		}
		rd.RecurringScheduleID = recSchedID
		sc.Rides = append(sc.Rides, rd)

		sc.TotalRides++
		switch rd.Status {
		case "active":
			sc.ActiveRides++
		case "completed":
			sc.CompletedRides++
		case "cancelled":
			sc.CancelledRides++
		}
	}

	return &sc, nil
}

// PauseRecurringSchedule pauses an active recurring schedule.
func (s *RecurringScheduleService) PauseRecurringSchedule(
	ctx context.Context,
	scheduleID string,
	userID string,
) error {
	res, err := s.DB.Exec(ctx,
		`UPDATE recurring_schedules
		 SET status = 'paused', updated_at = NOW()
		 WHERE id = $1 AND user_id = $2 AND status = 'active'`,
		scheduleID, userID,
	)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("schedule not found or cannot be paused")
	}

	_ = s.NotificationService.CreateNotification(
		ctx,
		userID,
		"schedule_paused",
		"Recurring Schedule Paused",
		"Your recurring schedule has been paused.",
	)
	return nil
}

// ResumeRecurringSchedule resumes a paused recurring schedule.
func (s *RecurringScheduleService) ResumeRecurringSchedule(
	ctx context.Context,
	scheduleID string,
	userID string,
) error {
	res, err := s.DB.Exec(ctx,
		`UPDATE recurring_schedules
		 SET status = 'active', updated_at = NOW()
		 WHERE id = $1 AND user_id = $2 AND status = 'paused'`,
		scheduleID, userID,
	)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("schedule not found or cannot be resumed")
	}

	_ = s.NotificationService.CreateNotification(
		ctx,
		userID,
		"schedule_resumed",
		"Recurring Schedule Resumed",
		"Your recurring schedule has been resumed.",
	)
	return nil
}

// CancelRecurringSchedule cancels the recurring schedule and all future unbooked occurrences.
func (s *RecurringScheduleService) CancelRecurringSchedule(
	ctx context.Context,
	scheduleID string,
	userID string,
) error {
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	res, err := tx.Exec(ctx,
		`UPDATE recurring_schedules
		 SET status = 'cancelled', updated_at = NOW()
		 WHERE id = $1 AND user_id = $2 AND status IN ('active', 'paused', 'draft')`,
		scheduleID, userID,
	)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("schedule not found or already cancelled")
	}

	// Cancel future unbooked rides in the series
	_, err = tx.Exec(ctx,
		`UPDATE rides
		 SET status = 'cancelled', updated_at = NOW()
		 WHERE recurring_schedule_id = $1
		   AND driver_id = $2
		   AND journey_date >= CURRENT_DATE
		   AND status IN ('active', 'draft', 'selfie_uploaded')
		   AND id NOT IN (SELECT ride_id FROM bookings WHERE status = 'confirmed')`,
		scheduleID, userID,
	)
	if err != nil {
		return fmt.Errorf("failed to cancel future rides: %w", err)
	}

	_, _ = tx.Exec(ctx,
		`INSERT INTO notifications (user_id, type, title, message)
		 VALUES ($1, 'schedule_cancelled', 'Recurring Schedule Cancelled',
		 'Your recurring schedule and all future unbooked rides have been cancelled.')`,
		userID,
	)

	return tx.Commit(ctx)
}

// UpdateRecurringSchedule allows updating available seats or price per seat for future unbooked rides.
func (s *RecurringScheduleService) UpdateRecurringSchedule(
	ctx context.Context,
	scheduleID string,
	userID string,
	req models.UpdateRecurringScheduleRequest,
) error {
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var sc models.RecurringSchedule
	var rawTemplate []byte
	err = tx.QueryRow(ctx,
		`SELECT id, ride_template FROM recurring_schedules WHERE id = $1 AND user_id = $2 AND status = 'active'`,
		scheduleID, userID,
	).Scan(&sc.ID, &rawTemplate)
	if err != nil {
		return fmt.Errorf("active recurring schedule not found: %w", err)
	}

	template := make(map[string]interface{})
	if len(rawTemplate) > 0 {
		_ = json.Unmarshal(rawTemplate, &template)
	}

	if req.AvailableSeats != nil && *req.AvailableSeats > 0 {
		template["available_seats"] = *req.AvailableSeats
		_, err = tx.Exec(ctx,
			`UPDATE rides
			 SET available_seats = $1, updated_at = NOW()
			 WHERE recurring_schedule_id = $2
			   AND driver_id = $3
			   AND journey_date >= CURRENT_DATE
			   AND status = 'active'
			   AND id NOT IN (SELECT ride_id FROM bookings WHERE status = 'confirmed')`,
			*req.AvailableSeats, scheduleID, userID,
		)
		if err != nil {
			return err
		}
	}

	if req.PricePerSeat != nil && *req.PricePerSeat >= 0 {
		template["price_per_seat"] = *req.PricePerSeat
		_, err = tx.Exec(ctx,
			`UPDATE rides
			 SET price_per_seat = $1, updated_at = NOW()
			 WHERE recurring_schedule_id = $2
			   AND driver_id = $3
			   AND journey_date >= CURRENT_DATE
			   AND status = 'active'
			   AND id NOT IN (SELECT ride_id FROM bookings WHERE status = 'confirmed')`,
			*req.PricePerSeat, scheduleID, userID,
		)
		if err != nil {
			return err
		}
	}

	if req.EndDate != nil && strings.TrimSpace(*req.EndDate) != "" {
		_, err = tx.Exec(ctx,
			`UPDATE recurring_schedules
			 SET end_date = $1, updated_at = NOW()
			 WHERE id = $2 AND user_id = $3`,
			strings.TrimSpace(*req.EndDate), scheduleID, userID,
		)
		if err != nil {
			return err
		}
	}

	updatedTemplateJSON, _ := json.Marshal(template)
	_, err = tx.Exec(ctx,
		`UPDATE recurring_schedules
		 SET ride_template = $1, updated_at = NOW()
		 WHERE id = $2 AND user_id = $3`,
		updatedTemplateJSON, scheduleID, userID,
	)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}
