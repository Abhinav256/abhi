package services

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/models"
)

type NotificationService struct {
	DB          *pgxpool.Pool
	PushService *PushService
}

func NewNotificationService(db *pgxpool.Pool, pushService ...*PushService) *NotificationService {
	var ps *PushService
	if len(pushService) > 0 {
		ps = pushService[0]
	}
	return &NotificationService{DB: db, PushService: ps}
}

func (s *NotificationService) CreateNotification(ctx context.Context, userID, notifType, title, message string) error {
	var notifID string
	err := s.DB.QueryRow(
		ctx,
		`INSERT INTO notifications (user_id, type, title, message) VALUES ($1, $2, $3, $4) RETURNING id`,
		userID, notifType, title, message,
	).Scan(&notifID)
	if err != nil {
		return err
	}

	if s.PushService != nil {
		go func() {
			data := map[string]string{
				"notification_id": notifID,
				"type":            notifType,
			}
			_ = s.PushService.SendPushToUser(context.Background(), userID, title, message, data)
			_, _ = s.DB.Exec(context.Background(), `UPDATE notifications SET push_sent = TRUE WHERE id = $1`, notifID)
		}()
	}

	return nil
}

// CreateNotificationWithContext creates a notification with ride and/or booking context.
func (s *NotificationService) CreateNotificationWithContext(ctx context.Context, userID, notifType, title, message string, rideID *string, bookingID *string) error {
	var notifID string
	err := s.DB.QueryRow(
		ctx,
		`INSERT INTO notifications (user_id, type, title, message, ride_id, booking_id) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
		userID, notifType, title, message, rideID, bookingID,
	).Scan(&notifID)
	if err != nil {
		return err
	}

	if s.PushService != nil {
		go func() {
			data := map[string]string{
				"notification_id": notifID,
				"type":            notifType,
			}
			if rideID != nil && *rideID != "" {
				data["ride_id"] = *rideID
			}
			if bookingID != nil && *bookingID != "" {
				data["booking_id"] = *bookingID
			}
			_ = s.PushService.SendPushToUser(context.Background(), userID, title, message, data)
			_, _ = s.DB.Exec(context.Background(), `UPDATE notifications SET push_sent = TRUE WHERE id = $1`, notifID)
		}()
	}

	return nil
}

// SendPush asynchronously delivers a push notification to user's registered devices.
func (s *NotificationService) SendPush(ctx context.Context, userID, notifType, title, message string, data map[string]string) {
	if s.PushService == nil {
		return
	}
	if data == nil {
		data = make(map[string]string)
	}
	data["type"] = notifType
	go func() {
		_ = s.PushService.SendPushToUser(context.Background(), userID, title, message, data)
	}()
}

func (s *NotificationService) GetUserNotifications(ctx context.Context, userID string) ([]models.Notification, error) {
	rows, err := s.DB.Query(
		ctx,
		`SELECT id, user_id, type, title, message, ride_id, booking_id, is_read, created_at
		 FROM notifications
		 WHERE user_id = $1
		 ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var notifs []models.Notification
	for rows.Next() {
		var n models.Notification
		if err := rows.Scan(&n.ID, &n.UserID, &n.Type, &n.Title, &n.Message, &n.RideID, &n.BookingID, &n.IsRead, &n.CreatedAt); err != nil {
			return nil, err
		}
		notifs = append(notifs, n)
	}

	return notifs, nil
}

func (s *NotificationService) MarkNotificationRead(ctx context.Context, userID, notifID string) error {
	_, err := s.DB.Exec(
		ctx,
		`UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2`,
		notifID, userID,
	)
	return err
}

func (s *NotificationService) GetNotificationDetail(ctx context.Context, userID, notifID string) (*models.NotificationDetail, error) {
	var n models.Notification
	err := s.DB.QueryRow(
		ctx,
		`SELECT id, user_id, type, title, message, ride_id, booking_id, is_read, created_at
		 FROM notifications
		 WHERE id = $1 AND user_id = $2`,
		notifID, userID,
	).Scan(&n.ID, &n.UserID, &n.Type, &n.Title, &n.Message, &n.RideID, &n.BookingID, &n.IsRead, &n.CreatedAt)
	if err != nil {
		return nil, err
	}

	if !n.IsRead {
		_, _ = s.DB.Exec(ctx, `UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2`, notifID, userID)
		n.IsRead = true
	}

	detail := &models.NotificationDetail{
		Notification: n,
	}

	// Fetch booking if booking_id exists
	if n.BookingID != nil && *n.BookingID != "" {
		var b models.Booking
		err := s.DB.QueryRow(
			ctx,
			`SELECT
				id, ride_id, passenger_id, passenger_name, passenger_age, passenger_gender,
				payment_mode, status, seats_booked, total_amount, created_at, updated_at
			 FROM bookings
			 WHERE id = $1`,
			*n.BookingID,
		).Scan(
			&b.ID, &b.RideID, &b.PassengerID, &b.PassengerName, &b.PassengerAge, &b.PassengerGender,
			&b.PaymentMode, &b.Status, &b.SeatsBooked, &b.TotalAmount, &b.CreatedAt, &b.UpdatedAt,
		)
		if err == nil {
			// Query sub-passengers if any
			pRows, pErr := s.DB.Query(
				ctx,
				`SELECT id, booking_id, passenger_number, passenger_name, passenger_age, passenger_gender, passenger_phone, created_at
				 FROM booking_passengers
				 WHERE booking_id = $1
				 ORDER BY passenger_number ASC`,
				b.ID,
			)
			if pErr == nil {
				defer pRows.Close()
				for pRows.Next() {
					var bp models.BookingPassenger
					if scanErr := pRows.Scan(
						&bp.ID, &bp.BookingID, &bp.PassengerNumber, &bp.PassengerName,
						&bp.PassengerAge, &bp.PassengerGender, &bp.PassengerPhone, &bp.CreatedAt,
					); scanErr == nil {
						b.Passengers = append(b.Passengers, bp)
					}
				}
			}

			detail.Booking = &b
			if (n.RideID == nil || *n.RideID == "") && b.RideID != "" {
				rideIDVal := b.RideID
				n.RideID = &rideIDVal
			}
		}
	}

	// Fetch ride if ride_id exists
	if n.RideID != nil && *n.RideID != "" {
		var r models.RideDetail
		err := s.DB.QueryRow(
			ctx,
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
				r.is_women_only,
				r.created_at,
				r.updated_at,
				u.full_name,
				u.gender,
				COALESCE(u.phone, ''),
				COALESCE(v.model, ''),
				COALESCE(v.vehicle_number, ''),
				COALESCE(v.vehicle_type, ''),
				COALESCE(v.vehicle_photo_url, '')
			FROM rides r
			INNER JOIN users u ON u.id = r.driver_id
			LEFT JOIN vehicles v ON v.id = r.vehicle_id
			WHERE r.id = $1`,
			*n.RideID,
		).Scan(
			&r.ID,
			&r.DriverID,
			&r.VehicleID,
			&r.FromLocation,
			&r.ToLocation,
			&r.JourneyDate,
			&r.DepartureTime,
			&r.EstimatedArrivalTime,
			&r.AvailableSeats,
			&r.PricePerSeat,
			&r.Status,
			&r.DriverSelfieURL,
			&r.DriverSelfieExpiresAt,
			&r.IsWomenOnly,
			&r.CreatedAt,
			&r.UpdatedAt,
			&r.DriverName,
			&r.DriverGender,
			&r.DriverPhone,
			&r.VehicleModel,
			&r.VehicleNumber,
			&r.VehicleType,
			&r.VehiclePhotoURL,
		)
		if err == nil {
			detail.Ride = &r
		}
	}

	return detail, nil
}
