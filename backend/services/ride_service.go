package services

import (
	"context"
	"encoding/json"
	"fmt"
	"math"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/config"
	"github.com/abhishare16/Abhi-Share/backend/models"
)

type RideService struct {
	DB                  *pgxpool.Pool
	ReferralService     *ReferralService
	WalletService       *WalletService
	RouteService        *RouteService
	Config              *config.Config
	NotificationService *NotificationService
}

func NewRideService(db *pgxpool.Pool, cfg *config.Config) *RideService {
	return &RideService{
		DB:     db,
		Config: cfg,
	}
}

// computeExtraPay calculates the AbhiShare charge and total passenger price.
// Formula: app_amount = round(user_amount * percentage / 100)
//          total_amount = user_amount + app_amount
func (s *RideService) computeExtraPay(userAmount float64) (appAmount float64, totalAmount float64) {
	pct := 4.0
	if s.Config != nil && s.Config.ExtraPayPercent >= 0 {
		pct = s.Config.ExtraPayPercent
	}
	appAmount = math.Round(userAmount * pct / 100.0)
	totalAmount = userAmount + appAmount
	return
}

func (s *RideService) CreateRide(
	ctx context.Context,
	request models.CreateRideRequest,
) (string, float64, float64, float64, error) {

	// Verify that driver is eligible to create rides (wallet balance not at or below -₹100 limit).
	if s.WalletService != nil {
		if err := s.WalletService.CheckRideCreationEligibility(ctx, request.DriverID); err != nil {
			return "", 0, 0, 0, err
		}
	}

	// Validate that the authenticated driver exists and get their gender.
	var driverGender string

	err := s.DB.QueryRow(
		ctx,
		`SELECT gender
		 FROM users
		 WHERE id = $1`,
		request.DriverID,
	).Scan(&driverGender)

	if err != nil {
		if err == pgx.ErrNoRows {
			return "", 0, 0, 0, fmt.Errorf("driver not found")
		}
		return "", 0, 0, 0, err
	}

	// Security check: Only verified female users can create Women Only rides.
	if request.IsWomenOnly && driverGender != "female" {
		return "", 0, 0, 0, fmt.Errorf("only verified female drivers can create Women Only rides")
	}

	// Get the vehicle and verify that it belongs to the driver.
	var vehicleType string
	var vehicleOwnerID string

	err = s.DB.QueryRow(
		ctx,
		`SELECT vehicle_type, user_id
		 FROM vehicles
		 WHERE id = $1`,
		request.VehicleID,
	).Scan(
		&vehicleType,
		&vehicleOwnerID,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return "", 0, 0, 0, fmt.Errorf("vehicle not found")
		}

		return "", 0, 0, 0, err
	}

	if vehicleOwnerID != request.DriverID {
		return "", 0, 0, 0, fmt.Errorf("vehicle does not belong to driver")
	}

	// Validate the maximum passenger seats based on vehicle type.
	maxSeats := 0

	switch vehicleType {
	case "two_wheeler":
		maxSeats = 1

	case "five_seater":
		maxSeats = 4

	case "seven_seater":
		maxSeats = 6

	default:
		return "", 0, 0, 0, fmt.Errorf("invalid vehicle type")
	}

	if request.AvailableSeats < 1 ||
		request.AvailableSeats > maxSeats {
		return "", 0, 0, 0, fmt.Errorf(
			"available seats must be between 1 and %d for this vehicle",
			maxSeats,
		)
	}

	if request.PricePerSeat < 0 {
		return "", 0, 0, 0, fmt.Errorf("price per seat cannot be negative")
	}

	// Compute Extra Pay pricing on the backend.
	userAmount := request.PricePerSeat
	appAmount, totalAmount := s.computeExtraPay(userAmount)

	// Prepare route serialization
	var routeGeometryBytes []byte
	if request.RouteGeometry != nil {
		routeGeometryBytes, _ = json.Marshal(request.RouteGeometry)
	}
	var routeWaypointsBytes []byte
	if request.RouteWaypoints != nil {
		routeWaypointsBytes, _ = json.Marshal(request.RouteWaypoints)
	}

	// Server-side safety: if coordinates are given but route wasn't supplied, calculate route
	if len(routeGeometryBytes) == 0 && request.PickupLatitude != nil && request.PickupLongitude != nil &&
		request.DestinationLatitude != nil && request.DestinationLongitude != nil && s.RouteService != nil {
		calc, err := s.RouteService.CalculateRoutes(
			ctx,
			*request.PickupLatitude, *request.PickupLongitude,
			*request.DestinationLatitude, *request.DestinationLongitude,
		)
		if err == nil && calc != nil && calc.DefaultRoute != nil {
			def := calc.DefaultRoute
			routeGeometryBytes, _ = json.Marshal(def.Coordinates)
			routeWaypointsBytes, _ = json.Marshal(def.IntermediatePoints)
			dist := def.DistanceMeters
			dur := def.DurationSeconds
			sum := def.Summary
			request.RouteDistance = &dist
			request.RouteDuration = &dur
			request.RouteSummary = &sum
		}
	}

	// New rides start as drafts.
	var rideID string

	err = s.DB.QueryRow(
		ctx,
		`INSERT INTO rides (
			driver_id,
			vehicle_id,
			from_location,
			to_location,
			pickup_latitude,
			pickup_longitude,
			destination_latitude,
			destination_longitude,
			route_geometry,
			route_distance,
			route_duration,
			route_summary,
			route_waypoints,
			journey_date,
			departure_time,
			estimated_arrival_time,
			available_seats,
			price_per_seat,
			user_amount,
			app_amount,
			total_amount,
			is_women_only,
			status
		)
		VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, 'draft'
		)
		RETURNING id`,
		request.DriverID,
		request.VehicleID,
		request.FromLocation,
		request.ToLocation,
		request.PickupLatitude,
		request.PickupLongitude,
		request.DestinationLatitude,
		request.DestinationLongitude,
		routeGeometryBytes,
		request.RouteDistance,
		request.RouteDuration,
		request.RouteSummary,
		routeWaypointsBytes,
		request.JourneyDate,
		request.DepartureTime,
		request.EstimatedArrivalTime,
		request.AvailableSeats,
		request.PricePerSeat,
		userAmount,
		appAmount,
		totalAmount,
		request.IsWomenOnly,
	).Scan(&rideID)

	if err != nil {
		return "", 0, 0, 0, err
	}

	return rideID, userAmount, appAmount, totalAmount, nil
}

func (s *RideService) UploadDriverSelfie(
	ctx context.Context,
	rideID string,
	driverID string,
	selfieURL string,
) error {

	result, err := s.DB.Exec(
		ctx,
		`UPDATE rides
		 SET driver_selfie_url = $1,
		     status = 'selfie_uploaded',
		     updated_at = NOW()
		 WHERE id = $2
		   AND driver_id = $3
		   AND status IN ('draft', 'selfie_uploaded')`,
		selfieURL,
		rideID,
		driverID,
	)

	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		var exists bool

		err := s.DB.QueryRow(
			ctx,
			`SELECT EXISTS(
				SELECT 1
				FROM rides
				WHERE id = $1
			)`,
			rideID,
		).Scan(&exists)

		if err != nil {
			return err
		}

		if !exists {
			return fmt.Errorf("ride not found")
		}

		return fmt.Errorf(
			"ride is not available for selfie upload",
		)
	}

	return nil
}

func (s *RideService) PublishRide(
	ctx context.Context,
	rideID string,
	driverID string,
) error {

	result, err := s.DB.Exec(
		ctx,
		`UPDATE rides
		 SET status = 'active',
		     updated_at = NOW()
		 WHERE id = $1
		   AND driver_id = $2
		   AND status = 'selfie_uploaded'
		   AND driver_selfie_url IS NOT NULL
		   AND driver_selfie_url <> ''`,
		rideID,
		driverID,
	)

	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		var exists bool

		err := s.DB.QueryRow(
			ctx,
			`SELECT EXISTS(
				SELECT 1
				FROM rides
				WHERE id = $1
			)`,
			rideID,
		).Scan(&exists)

		if err != nil {
			return err
		}

		if !exists {
			return fmt.Errorf("ride not found")
		}

		return fmt.Errorf(
			"ride cannot be published. Complete the selfie step first",
		)
	}

	s.DB.Exec(ctx,
		`INSERT INTO notifications (user_id, type, title, message, ride_id)
		 VALUES ($1, 'ride_created', 'Ride Published', 'Your ride has been successfully published and is now active.', $2)`,
		driverID, rideID)

	if s.NotificationService != nil {
		s.NotificationService.SendPush(ctx, driverID, "ride_created", "Ride Published", "Your ride has been successfully published and is now active.", map[string]string{
			"ride_id": rideID,
		})
	}

	if s.ReferralService != nil {
		_ = s.ReferralService.HandleRidePublished(ctx, driverID)
	}

	return nil
}

func (s *RideService) CompleteRide(
	ctx context.Context,
	rideID string,
	driverID string,
) error {

	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}

	defer func() {
		_ = tx.Rollback(ctx)
	}()

	// Lock the ride and verify ownership.
	var existingDriverID string
	var status string
	var fromLocation string
	var toLocation string
	var pricePerSeat float64

	err = tx.QueryRow(
		ctx,
		`SELECT driver_id, status, from_location, to_location, price_per_seat
		 FROM rides
		 WHERE id = $1
		 FOR UPDATE`,
		rideID,
	).Scan(&existingDriverID, &status, &fromLocation, &toLocation, &pricePerSeat)

	if err != nil {
		if err == pgx.ErrNoRows {
			return fmt.Errorf("ride not found")
		}
		return err
	}

	if existingDriverID != driverID {
		return fmt.Errorf("you do not have access to this ride")
	}

	if status != "active" {
		return fmt.Errorf("ride is not active")
	}

	// Calculate earnings from confirmed bookings on this ride:
	// booked_seats * price_per_seat (the driver's base price, not including app charge)
	var totalBookedSeats int
	err = tx.QueryRow(
		ctx,
		`SELECT COALESCE(SUM(seats_booked), 0)
		 FROM bookings
		 WHERE ride_id = $1 AND status IN ('confirmed', 'completed')`,
		rideID,
	).Scan(&totalBookedSeats)
	if err != nil {
		return err
	}

	rideEarnings := float64(totalBookedSeats) * pricePerSeat

	// Update ride to completed.
	_, err = tx.Exec(
		ctx,
		`UPDATE rides
		 SET status = 'completed',
		     completed_at = NOW(),
		     updated_at = NOW()
		 WHERE id = $1`,
		rideID,
	)
	if err != nil {
		return err
	}

	// Update bookings to completed.
	_, err = tx.Exec(
		ctx,
		`UPDATE bookings
		 SET status = 'completed',
		     updated_at = NOW()
		 WHERE ride_id = $1 AND status = 'confirmed'`,
		rideID,
	)
	if err != nil {
		return err
	}

	// Immediately transition conversations for this ride to completed status
	// so that active messaging ceases and chats are removed from active chat lists.
	_, err = tx.Exec(
		ctx,
		`UPDATE chat_conversations
		 SET status = 'completed',
		     updated_at = NOW()
		 WHERE ride_id = $1 AND status != 'completed'`,
		rideID,
	)
	if err != nil {
		return err
	}

	// Add earnings to driver's accumulated money_earned.
	if rideEarnings > 0 {
		_, err = tx.Exec(
			ctx,
			`UPDATE users
			 SET money_earned = money_earned + $1,
			     updated_at = NOW()
			 WHERE id = $2`,
			rideEarnings,
			driverID,
		)
		if err != nil {
			return err
		}
	}

	// Process referral rewards for driver (as referee or as referrer)
	if s.ReferralService != nil {
		if err := s.ReferralService.HandleRideCompleted(ctx, tx, driverID); err != nil {
			return fmt.Errorf("failed to process referral rewards: %w", err)
		}
	}

	// Atomic wallet settlement (UPI driver earnings credit & cash platform charge deduction).
	if s.WalletService != nil {
		if err := s.WalletService.SettleCompletedRide(ctx, tx, rideID, driverID); err != nil {
			return fmt.Errorf("failed to settle ride: %w", err)
		}
	}

	// Notification for the driver.
	driverMsg := fmt.Sprintf(
		"Your ride from %s to %s has been completed.",
		fromLocation, toLocation,
	)
	_, err = tx.Exec(
		ctx,
		`INSERT INTO notifications (user_id, type, title, message, ride_id)
		 VALUES ($1, 'ride_completed', 'Ride Completed', $2, $3)`,
		driverID, driverMsg, rideID,
	)
	if err != nil {
		return err
	}

	// Notify all passengers of the completed ride.
	rows, err := tx.Query(ctx,
		`SELECT passenger_id, passenger_name FROM bookings WHERE ride_id = $1 AND status IN ('confirmed', 'completed')`,
		rideID,
	)
	if err != nil {
		return err
	}

	type passenger struct {
		id   string
		name string
	}
	var passengers []passenger
	for rows.Next() {
		var p passenger
		if err := rows.Scan(&p.id, &p.name); err != nil {
			rows.Close()
			return err
		}
		passengers = append(passengers, p)
	}
	rows.Close()

	for _, p := range passengers {
		msg := fmt.Sprintf(
			"Your ride from %s to %s has been completed by the driver.",
			fromLocation, toLocation,
		)
		_, err = tx.Exec(
			ctx,
			`INSERT INTO notifications (user_id, type, title, message, ride_id)
			 VALUES ($1, 'ride_completed', 'Ride Completed', $2, $3)`,
			p.id, msg, rideID,
		)
		if err != nil {
			return err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return err
	}

	if s.NotificationService != nil {
		s.NotificationService.SendPush(ctx, driverID, "ride_completed", "Ride Completed", driverMsg, map[string]string{
			"ride_id": rideID,
		})
		for _, p := range passengers {
			msg := fmt.Sprintf(
				"Your ride from %s to %s has been completed by the driver.",
				fromLocation, toLocation,
			)
			s.NotificationService.SendPush(ctx, p.id, "ride_completed", "Ride Completed", msg, map[string]string{
				"ride_id": rideID,
			})
		}
	}

	return nil
}

func (s *RideService) CancelRide(
	ctx context.Context,
	rideID string,
	driverID string,
) error {

	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}

	defer func() {
		_ = tx.Rollback(ctx)
	}()

	// Lock the ride and verify ownership + status.
	var existingDriverID string
	var status string
	var fromLocation string
	var toLocation string

	err = tx.QueryRow(
		ctx,
		`SELECT driver_id, status, from_location, to_location
		 FROM rides
		 WHERE id = $1
		 FOR UPDATE`,
		rideID,
	).Scan(&existingDriverID, &status, &fromLocation, &toLocation)

	if err != nil {
		if err == pgx.ErrNoRows {
			return fmt.Errorf("ride not found")
		}
		return err
	}

	if existingDriverID != driverID {
		return fmt.Errorf("you do not have access to this ride")
	}

	if status != "active" {
		return fmt.Errorf("ride is not active")
	}

	// 1. Cancel the ride.
	_, err = tx.Exec(
		ctx,
		`UPDATE rides
		 SET status = 'cancelled',
		     updated_at = NOW()
		 WHERE id = $1`,
		rideID,
	)
	if err != nil {
		return err
	}

	// 2. Fetch all confirmed bookings BEFORE cancelling them (to get passenger info).
	rows, err := tx.Query(ctx,
		`SELECT id, passenger_id, passenger_name
		 FROM bookings
		 WHERE ride_id = $1 AND status = 'confirmed'
		 FOR UPDATE`,
		rideID,
	)
	if err != nil {
		return err
	}

	type affectedBooking struct {
		bookingID     string
		passengerID   string
		passengerName string
	}
	var affected []affectedBooking
	for rows.Next() {
		var ab affectedBooking
		if err := rows.Scan(&ab.bookingID, &ab.passengerID, &ab.passengerName); err != nil {
			rows.Close()
			return err
		}
		affected = append(affected, ab)
	}
	rows.Close()

	// 3. Cancel ALL confirmed bookings for this ride.
	_, err = tx.Exec(
		ctx,
		`UPDATE bookings
		 SET status = 'cancelled',
		     updated_at = NOW()
		 WHERE ride_id = $1
		   AND status = 'confirmed'`,
		rideID,
	)
	if err != nil {
		return err
	}

	// 4. Notification for the driver.
	driverMsg := fmt.Sprintf(
		"Your ride from %s to %s has been cancelled.",
		fromLocation, toLocation,
	)
	_, err = tx.Exec(
		ctx,
		`INSERT INTO notifications (user_id, type, title, message, ride_id)
		 VALUES ($1, 'ride_canceled', 'Ride Cancelled', $2, $3)`,
		driverID, driverMsg, rideID,
	)
	if err != nil {
		return err
	}

	// 5. Notification for each affected passenger.
	for _, ab := range affected {
		passengerMsg := fmt.Sprintf(
			"Your ride from %s to %s was cancelled by the ride creator.",
			fromLocation, toLocation,
		)
		_, err = tx.Exec(
			ctx,
			`INSERT INTO notifications (user_id, type, title, message, ride_id, booking_id)
			 VALUES ($1, 'ride_canceled', 'Ride Cancelled', $2, $3, $4)`,
			ab.passengerID, passengerMsg, rideID, ab.bookingID,
		)
		if err != nil {
			return err
		}
	}

	// Commit everything atomically: ride cancel + booking cancels + notifications.
	if err := tx.Commit(ctx); err != nil {
		return err
	}

	if s.NotificationService != nil {
		s.NotificationService.SendPush(ctx, driverID, "ride_canceled", "Ride Cancelled", driverMsg, map[string]string{
			"ride_id": rideID,
		})
		for _, ab := range affected {
			passengerMsg := fmt.Sprintf(
				"Your ride from %s to %s was cancelled by the ride creator.",
				fromLocation, toLocation,
			)
			s.NotificationService.SendPush(ctx, ab.passengerID, "ride_canceled", "Ride Cancelled", passengerMsg, map[string]string{
				"ride_id":    rideID,
				"booking_id": ab.bookingID,
			})
		}
	}

	return nil
}

func (s *RideService) DeleteDraft(
	ctx context.Context,
	rideID string,
	driverID string,
) error {
	result, err := s.DB.Exec(
		ctx,
		`DELETE FROM rides
		 WHERE id = $1
		   AND driver_id = $2
		   AND status IN ('draft', 'selfie_uploaded')`,
		rideID,
		driverID,
	)
	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		return fmt.Errorf("draft not found or you do not have permission to delete it")
	}

	return nil
}

func (s *RideService) UpdateDraft(
	ctx context.Context,
	rideID string,
	driverID string,
	request models.CreateRideRequest,
) error {
	var vehicleDriverID string
	var vehicleType string

	err := s.DB.QueryRow(
		ctx,
		`SELECT driver_id, vehicle_type
		 FROM vehicles
		 WHERE id = $1`,
		request.VehicleID,
	).Scan(&vehicleDriverID, &vehicleType)

	if err != nil {
		if err == pgx.ErrNoRows {
			return fmt.Errorf("vehicle not found")
		}
		return err
	}

	if vehicleDriverID != driverID {
		return fmt.Errorf("you do not own this vehicle")
	}

	maxSeats := 6
	if vehicleType == "two_wheeler" {
		maxSeats = 1
	}

	if request.AvailableSeats < 1 || request.AvailableSeats > maxSeats {
		return fmt.Errorf(
			"available seats must be between 1 and %d for this vehicle",
			maxSeats,
		)
	}

	if request.PricePerSeat < 0 {
		return fmt.Errorf("price per seat cannot be negative")
	}

	var routeGeometryBytes []byte
	if request.RouteGeometry != nil {
		routeGeometryBytes, _ = json.Marshal(request.RouteGeometry)
	}
	var routeWaypointsBytes []byte
	if request.RouteWaypoints != nil {
		routeWaypointsBytes, _ = json.Marshal(request.RouteWaypoints)
	}

	result, err := s.DB.Exec(
		ctx,
		`UPDATE rides
		 SET vehicle_id = $1,
		     from_location = $2,
		     to_location = $3,
		     pickup_latitude = COALESCE($4, pickup_latitude),
		     pickup_longitude = COALESCE($5, pickup_longitude),
		     destination_latitude = COALESCE($6, destination_latitude),
		     destination_longitude = COALESCE($7, destination_longitude),
		     route_geometry = CASE WHEN $8::jsonb IS NOT NULL THEN $8::jsonb ELSE route_geometry END,
		     route_distance = COALESCE($9, route_distance),
		     route_duration = COALESCE($10, route_duration),
		     route_summary = COALESCE($11, route_summary),
		     route_waypoints = CASE WHEN $12::jsonb IS NOT NULL THEN $12::jsonb ELSE route_waypoints END,
		     journey_date = $13,
		     departure_time = $14,
		     estimated_arrival_time = $15,
		     available_seats = $16,
		     price_per_seat = $17,
		     is_women_only = $18,
		     updated_at = NOW()
		 WHERE id = $19
		   AND driver_id = $20
		   AND status IN ('draft', 'selfie_uploaded')`,
		request.VehicleID,
		request.FromLocation,
		request.ToLocation,
		request.PickupLatitude,
		request.PickupLongitude,
		request.DestinationLatitude,
		request.DestinationLongitude,
		routeGeometryBytes,
		request.RouteDistance,
		request.RouteDuration,
		request.RouteSummary,
		routeWaypointsBytes,
		request.JourneyDate,
		request.DepartureTime,
		request.EstimatedArrivalTime,
		request.AvailableSeats,
		request.PricePerSeat,
		request.IsWomenOnly,
		rideID,
		driverID,
	)
	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		return fmt.Errorf("draft not found or you do not have permission to update it")
	}

	return nil
}

// GetMyRides returns all rides created by the given driver.
func (s *RideService) GetMyRides(
	ctx context.Context,
	driverID string,
) ([]models.Ride, error) {

	rows, err := s.DB.Query(
		ctx,
		`SELECT
			id,
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
			status,
			COALESCE(driver_selfie_url, ''),
			driver_selfie_expires_at,
			is_women_only,
			created_at,
			updated_at
		FROM rides
		WHERE driver_id = $1
		ORDER BY created_at DESC`,
		driverID,
	)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	var rides []models.Ride

	for rows.Next() {
		var ride models.Ride

		err := rows.Scan(
			&ride.ID,
			&ride.DriverID,
			&ride.VehicleID,
			&ride.FromLocation,
			&ride.ToLocation,
			&ride.JourneyDate,
			&ride.DepartureTime,
			&ride.EstimatedArrivalTime,
			&ride.AvailableSeats,
			&ride.PricePerSeat,
			&ride.UserAmount,
			&ride.AppAmount,
			&ride.TotalAmount,
			&ride.Status,
			&ride.DriverSelfieURL,
			&ride.DriverSelfieExpiresAt,
			&ride.IsWomenOnly,
			&ride.CreatedAt,
			&ride.UpdatedAt,
		)

		if err != nil {
			return nil, err
		}

		rides = append(rides, ride)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	if rides == nil {
		rides = []models.Ride{}
	}

	return rides, nil
}

// GetRideDetail returns a single ride enriched with driver and vehicle data.
func (s *RideService) GetRideDetail(
	ctx context.Context,
	rideID string,
) (*models.RideDetail, error) {

	var ride models.RideDetail

	var rawGeometry []byte
	var rawWaypoints []byte

	err := s.DB.QueryRow(
		ctx,
		`SELECT
			r.id,
			r.driver_id,
			r.vehicle_id,
			r.from_location,
			r.to_location,
			r.pickup_latitude,
			r.pickup_longitude,
			r.destination_latitude,
			r.destination_longitude,
			r.route_geometry,
			r.route_distance,
			r.route_duration,
			r.route_summary,
			r.route_waypoints,
			r.journey_date,
			r.departure_time,
			r.estimated_arrival_time,
			r.available_seats,
			r.price_per_seat,
			r.user_amount,
			r.app_amount,
			r.total_amount,
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
		rideID,
	).Scan(
		&ride.ID,
		&ride.DriverID,
		&ride.VehicleID,
		&ride.FromLocation,
		&ride.ToLocation,
		&ride.PickupLatitude,
		&ride.PickupLongitude,
		&ride.DestinationLatitude,
		&ride.DestinationLongitude,
		&rawGeometry,
		&ride.RouteDistance,
		&ride.RouteDuration,
		&ride.RouteSummary,
		&rawWaypoints,
		&ride.JourneyDate,
		&ride.DepartureTime,
		&ride.EstimatedArrivalTime,
		&ride.AvailableSeats,
		&ride.PricePerSeat,
		&ride.UserAmount,
		&ride.AppAmount,
		&ride.TotalAmount,
		&ride.Status,
		&ride.DriverSelfieURL,
		&ride.DriverSelfieExpiresAt,
		&ride.IsWomenOnly,
		&ride.CreatedAt,
		&ride.UpdatedAt,
		&ride.DriverName,
		&ride.DriverGender,
		&ride.DriverPhone,
		&ride.VehicleModel,
		&ride.VehicleNumber,
		&ride.VehicleType,
		&ride.VehiclePhotoURL,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("ride not found")
		}

		return nil, err
	}

	if len(rawGeometry) > 0 {
		var geom any
		if err := json.Unmarshal(rawGeometry, &geom); err == nil {
			ride.RouteGeometry = geom
		}
	}
	if len(rawWaypoints) > 0 {
		var wps any
		if err := json.Unmarshal(rawWaypoints, &wps); err == nil {
			ride.RouteWaypoints = wps
		}
	}

	return &ride, nil
}
