package services

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/config"
	"github.com/abhishare16/Abhi-Share/backend/models"
)

type BookingService struct {
	DB                  *pgxpool.Pool
	WalletService       *WalletService
	Config              *config.Config
	NotificationService *NotificationService
}

func NewBookingService(db *pgxpool.Pool, cfg ...*config.Config) *BookingService {
	var c *config.Config
	if len(cfg) > 0 {
		c = cfg[0]
	}
	return &BookingService{
		DB:     db,
		Config: c,
	}
}

func (s *BookingService) CreateBooking(
	ctx context.Context,
	request models.CreateBookingRequest,
) (string, error) {

	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return "", err
	}

	defer func() {
		_ = tx.Rollback(ctx)
	}()

	// Check passenger exists.
	var passengerExists bool

	err = tx.QueryRow(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM users
			WHERE id = $1
		)`,
		request.PassengerID,
	).Scan(&passengerExists)

	if err != nil {
		return "", err
	}

	if !passengerExists {
		return "", fmt.Errorf("passenger not found")
	}

	// Normalize seats_booked and passengers array for compatibility
	if request.SeatsBooked <= 0 {
		if len(request.Passengers) > 0 {
			request.SeatsBooked = len(request.Passengers)
		} else {
			request.SeatsBooked = 1
		}
	}

	if len(request.Passengers) == 0 {
		if strings.TrimSpace(request.PassengerName) != "" {
			request.Passengers = []models.PassengerInput{
				{
					Name:   strings.TrimSpace(request.PassengerName),
					Age:    request.PassengerAge,
					Gender: request.PassengerGender,
				},
			}
		} else {
			return "", fmt.Errorf("at least one passenger must be provided")
		}
	}

	if request.SeatsBooked != len(request.Passengers) {
		return "", fmt.Errorf("seats requested (%d) does not match passenger count (%d)", request.SeatsBooked, len(request.Passengers))
	}

	// Primary passenger fallback
	request.PassengerName = strings.TrimSpace(request.Passengers[0].Name)
	request.PassengerAge = request.Passengers[0].Age
	request.PassengerGender = request.Passengers[0].Gender

	// Validate each passenger
	validGenders := map[string]bool{
		"male":   true,
		"female": true,
		"other":  true,
	}

	for idx, p := range request.Passengers {
		name := strings.TrimSpace(p.Name)
		if name == "" {
			return "", fmt.Errorf("passenger %d: name cannot be empty", idx+1)
		}
		if p.Age < 18 {
			return "", fmt.Errorf("passenger %d (%s): must be at least 18 years old", idx+1, name)
		}
		if !validGenders[p.Gender] {
			return "", fmt.Errorf("passenger %d (%s): invalid gender. Use male, female, or other", idx+1, name)
		}
	}

	// Validate payment mode.
	if request.PaymentMode != "cash" &&
		request.PaymentMode != "upi" {
		return "", fmt.Errorf(
			"invalid payment mode. Use cash or upi",
		)
	}

	// Lock the ride row while checking and reserving the seats.
	var driverID string
	var availableSeats int
	var pricePerSeat float64
	var rideTotalAmount float64
	var userAmount float64
	var appAmount float64
	var rideStatus string
	var fromLocation string
	var toLocation string
	var isWomenOnly bool
	var rawGeometry []byte
	var routeDistance *float64
	var vehicleID string

	err = tx.QueryRow(
		ctx,
		`SELECT driver_id, available_seats, price_per_seat, total_amount, user_amount, app_amount, status, from_location, to_location, is_women_only, route_geometry, route_distance, vehicle_id
		 FROM rides
		 WHERE id = $1
		 FOR UPDATE`,
		request.RideID,
	).Scan(
		&driverID,
		&availableSeats,
		&pricePerSeat,
		&rideTotalAmount,
		&userAmount,
		&appAmount,
		&rideStatus,
		&fromLocation,
		&toLocation,
		&isWomenOnly,
		&rawGeometry,
		&routeDistance,
		&vehicleID,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return "", fmt.Errorf("ride not found")
		}

		return "", err
	}

	if rideStatus != "active" {
		return "", fmt.Errorf("ride is not active")
	}

	if availableSeats <= 0 {
		return "", fmt.Errorf("no seats available")
	}

	// Driver cannot book their own ride.
	if driverID == request.PassengerID {
		return "", fmt.Errorf("driver cannot book their own ride")
	}

	// Women Only Ride: Ensure every passenger travelling on this ride is female.
	if isWomenOnly {
		for idx := range request.Passengers {
			p := &request.Passengers[idx]
			passName := strings.TrimSpace(p.Name)

			if strings.ToLower(strings.TrimSpace(p.Gender)) != "female" {
				return "", fmt.Errorf("passenger %d (%s) is %s. Only female passengers can travel on Women Only rides", idx+1, passName, p.Gender)
			}

			p.Gender = "female"
		}

		request.PassengerGender = "female"
	}

	// Normalize booking locations
	bookingFrom := strings.TrimSpace(request.FromLocation)
	if bookingFrom == "" {
		bookingFrom = fromLocation
	}
	bookingTo := strings.TrimSpace(request.ToLocation)
	if bookingTo == "" {
		bookingTo = toLocation
	}

	// Determine if this booking is along a route segment
	// 1. If explicit segment distances are provided
	// 2. Or calculate from passenger coordinates against saved route geometry
	if (request.PickupDistanceAlongRoute == nil || request.DropDistanceAlongRoute == nil) &&
		request.PickupLatitude != nil && request.PickupLongitude != nil &&
		request.DestinationLatitude != nil && request.DestinationLongitude != nil &&
		len(rawGeometry) > 0 {
		var coords [][]float64
		if err := json.Unmarshal(rawGeometry, &coords); err == nil && len(coords) >= 2 {
			match := MatchRouteSegment(coords, *request.PickupLatitude, *request.PickupLongitude, *request.DestinationLatitude, *request.DestinationLongitude, 10000.0)
			if match.IsMatched {
				pDist := match.PickupDistanceMeters
				dDist := match.DropDistanceMeters
				request.PickupDistanceAlongRoute = &pDist
				request.DropDistanceAlongRoute = &dDist
			}
		}
	}

	isSegmentBooking := request.PickupDistanceAlongRoute != nil &&
		request.DropDistanceAlongRoute != nil &&
		*request.DropDistanceAlongRoute > *request.PickupDistanceAlongRoute

	seatPrice := rideTotalAmount
	if seatPrice <= 0 {
		seatPrice = pricePerSeat
	}
	if userAmount <= 0 {
		userAmount = pricePerSeat
	}

	if isSegmentBooking {
		// Determine vehicle capacity
		var vehicleType string
		_ = tx.QueryRow(ctx, `SELECT vehicle_type FROM vehicles WHERE id = $1`, vehicleID).Scan(&vehicleType)
		maxVehicleSeats := 4
		switch vehicleType {
		case "two_wheeler":
			maxVehicleSeats = 1
		case "five_seater":
			maxVehicleSeats = 4
		case "seven_seater":
			maxVehicleSeats = 6
		default:
			if availableSeats > maxVehicleSeats {
				maxVehicleSeats = availableSeats
			}
		}

		// Query existing confirmed bookings to check segment capacity
		bRows, bErr := tx.Query(
			ctx,
			`SELECT id, seats_booked, COALESCE(pickup_distance_along_route, 0), COALESCE(drop_distance_along_route, 0)
			 FROM bookings
			 WHERE ride_id = $1 AND status = 'confirmed'
			 FOR UPDATE`,
			request.RideID,
		)
		var existingBookings []BookingSegment
		if bErr == nil {
			for bRows.Next() {
				var bs BookingSegment
				if err := bRows.Scan(&bs.BookingID, &bs.SeatsBooked, &bs.PickupDistanceAlong, &bs.DropDistanceAlong); err == nil {
					existingBookings = append(existingBookings, bs)
				}
			}
			bRows.Close()
		}

		isAvail, availSeats, _ := CheckSegmentCapacity(
			maxVehicleSeats,
			existingBookings,
			*request.PickupDistanceAlongRoute,
			*request.DropDistanceAlongRoute,
			request.SeatsBooked,
		)

		if !isAvail {
			return "", fmt.Errorf("only %d seat(s) available along this route segment, cannot book %d seats", availSeats, request.SeatsBooked)
		}

		// Calculate proportional segment pricing
		totalDist := 0.0
		if routeDistance != nil && *routeDistance > 0 {
			totalDist = *routeDistance
		} else if len(rawGeometry) > 0 {
			var coords [][]float64
			_ = json.Unmarshal(rawGeometry, &coords)
			totalDist = ComputeTotalPolylineDistance(coords)
		}

		segmentRatio := 1.0
		if totalDist > 0 {
			segmentRatio = (*request.DropDistanceAlongRoute - *request.PickupDistanceAlongRoute) / totalDist
		}

		extraPayPct := 4.0
		if s.Config != nil && s.Config.ExtraPayPercent >= 0 {
			extraPayPct = s.Config.ExtraPayPercent
		}

		segUser, segApp, segTotal := ComputeSegmentPricing(userAmount, segmentRatio, extraPayPct)
		userAmount = segUser
		appAmount = segApp
		seatPrice = segTotal
	} else {
		// Full journey booking: verify overall available seats
		if availableSeats < request.SeatsBooked {
			return "", fmt.Errorf("only %d seat(s) available, cannot book %d seats", availableSeats, request.SeatsBooked)
		}
	}

	totalAmount := seatPrice * float64(request.SeatsBooked)
	driverEarnings := userAmount * float64(request.SeatsBooked)
	platformCharge := appAmount * float64(request.SeatsBooked)

	// Create booking with full location and route metadata
	var bookingID string

	err = tx.QueryRow(
		ctx,
		`INSERT INTO bookings (
			ride_id,
			passenger_id,
			passenger_name,
			passenger_age,
			passenger_gender,
			from_location,
			to_location,
			pickup_latitude,
			pickup_longitude,
			destination_latitude,
			destination_longitude,
			pickup_distance_along_route,
			drop_distance_along_route,
			payment_mode,
			status,
			seats_booked,
			total_amount,
			driver_earnings,
			platform_charge,
			settlement_status
		)
		VALUES (
			$1,
			$2,
			$3,
			$4,
			$5,
			$6,
			$7,
			$8,
			$9,
			$10,
			$11,
			$12,
			$13,
			$14,
			'confirmed',
			$15,
			$16,
			$17,
			$18,
			'unsettled'
		)
		RETURNING id`,
		request.RideID,
		request.PassengerID,
		request.PassengerName,
		request.PassengerAge,
		request.PassengerGender,
		bookingFrom,
		bookingTo,
		request.PickupLatitude,
		request.PickupLongitude,
		request.DestinationLatitude,
		request.DestinationLongitude,
		request.PickupDistanceAlongRoute,
		request.DropDistanceAlongRoute,
		request.PaymentMode,
		request.SeatsBooked,
		totalAmount,
		driverEarnings,
		platformCharge,
	).Scan(&bookingID)

	if err != nil {
		return "", err
	}

	// Insert each passenger into booking_passengers
	for idx := range request.Passengers {
		p := &request.Passengers[idx]
		var phonePtr *string
		trimmedPhone := strings.TrimSpace(p.Phone)
		if trimmedPhone != "" {
			phonePtr = &trimmedPhone
		}

		_, err = tx.Exec(
			ctx,
			`INSERT INTO booking_passengers (
				booking_id,
				passenger_number,
				passenger_name,
				passenger_age,
				passenger_gender,
				passenger_phone
			)
			VALUES ($1, $2, $3, $4, $5, $6)`,
			bookingID,
			idx+1,
			strings.TrimSpace(p.Name),
			p.Age,
			p.Gender,
			phonePtr,
		)
		if err != nil {
			return "", err
		}
	}

	// Atomically reserve the seats.
	_, err = tx.Exec(
		ctx,
		`UPDATE rides
		 SET available_seats = available_seats - $1,
		     updated_at = NOW()
		 WHERE id = $2`,
		request.SeatsBooked,
		request.RideID,
	)

	if err != nil {
		return "", err
	}

	// Create notifications within the transaction so they are
	// guaranteed to exist if the booking succeeds.

	// Notification for the passenger (booker).
	var passengerMsg string
	if request.SeatsBooked == 1 {
		passengerMsg = fmt.Sprintf(
			"Your seat has been confirmed on the ride from %s to %s.",
			bookingFrom, bookingTo,
		)
	} else {
		passengerMsg = fmt.Sprintf(
			"Your booking for %d seats has been confirmed on the ride from %s to %s.",
			request.SeatsBooked, bookingFrom, bookingTo,
		)
	}

	_, err = tx.Exec(
		ctx,
		`INSERT INTO notifications (user_id, type, title, message, ride_id, booking_id)
		 VALUES ($1, 'ride_booked', 'Ride Booked', $2, $3, $4)`,
		request.PassengerID, passengerMsg, request.RideID, bookingID,
	)
	if err != nil {
		return "", err
	}

	// Notification for the driver (ride creator).
	var driverMsg string
	if request.SeatsBooked == 1 {
		driverMsg = fmt.Sprintf(
			"%s booked a seat on your ride from %s to %s.",
			request.PassengerName, bookingFrom, bookingTo,
		)
	} else {
		driverMsg = fmt.Sprintf(
			"%s booked %d seats on your ride from %s to %s.",
			request.PassengerName, request.SeatsBooked, bookingFrom, bookingTo,
		)
	}

	_, err = tx.Exec(
		ctx,
		`INSERT INTO notifications (user_id, type, title, message, ride_id, booking_id)
		 VALUES ($1, 'ride_booked', 'New Booking', $2, $3, $4)`,
		driverID, driverMsg, request.RideID, bookingID,
	)
	if err != nil {
		return "", err
	}

	// Commit booking + seat reservation + notifications together.
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}

	if s.NotificationService != nil {
		s.NotificationService.SendPush(ctx, request.PassengerID, "ride_booked", "Ride Booked", passengerMsg, map[string]string{
			"ride_id":    request.RideID,
			"booking_id": bookingID,
		})
		s.NotificationService.SendPush(ctx, driverID, "ride_booked", "New Booking", driverMsg, map[string]string{
			"ride_id":    request.RideID,
			"booking_id": bookingID,
		})
	}

	return bookingID, nil
}

func (s *BookingService) CancelBooking(
	ctx context.Context,
	bookingID string,
	passengerID string,
) error {

	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}

	defer func() {
		_ = tx.Rollback(ctx)
	}()

	// Lock the booking and verify that the authenticated
	// user is the passenger who owns it.
	var rideID string
	var status string
	var bookingPassengerID string
	var passengerName string
	var seatsBooked int

	err = tx.QueryRow(
		ctx,
		`SELECT ride_id, passenger_id, status, passenger_name, seats_booked
		 FROM bookings
		 WHERE id = $1
		 FOR UPDATE`,
		bookingID,
	).Scan(
		&rideID,
		&bookingPassengerID,
		&status,
		&passengerName,
		&seatsBooked,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return fmt.Errorf("booking not found")
		}

		return err
	}

	if bookingPassengerID != passengerID {
		return fmt.Errorf("you do not have access to this booking")
	}

	if status != "confirmed" {
		return fmt.Errorf("only confirmed bookings can be cancelled")
	}

	// Lock the ride before restoring the seats.
	var rideStatus string
	var driverID string
	var fromLocation string
	var toLocation string

	err = tx.QueryRow(
		ctx,
		`SELECT status, driver_id, from_location, to_location
		 FROM rides
		 WHERE id = $1
		 FOR UPDATE`,
		rideID,
	).Scan(&rideStatus, &driverID, &fromLocation, &toLocation)

	if err != nil {
		if err == pgx.ErrNoRows {
			return fmt.Errorf("ride not found")
		}

		return err
	}

	// Mark booking as cancelled.
	_, err = tx.Exec(
		ctx,
		`UPDATE bookings
		 SET status = 'cancelled',
		     updated_at = NOW()
		 WHERE id = $1`,
		bookingID,
	)

	if err != nil {
		return err
	}

	// Restore available seats (only if ride is still active).
	if rideStatus == "active" {
		_, err = tx.Exec(
			ctx,
			`UPDATE rides
			 SET available_seats = available_seats + $1,
			     updated_at = NOW()
			 WHERE id = $2`,
			seatsBooked,
			rideID,
		)

		if err != nil {
			return err
		}
	}

	// Notification for the passenger.
	var passengerMsg string
	if seatsBooked == 1 {
		passengerMsg = fmt.Sprintf(
			"Your booking on the ride from %s to %s has been cancelled.",
			fromLocation, toLocation,
		)
	} else {
		passengerMsg = fmt.Sprintf(
			"Your booking for %d seats on the ride from %s to %s has been cancelled.",
			seatsBooked, fromLocation, toLocation,
		)
	}

	_, err = tx.Exec(
		ctx,
		`INSERT INTO notifications (user_id, type, title, message, ride_id, booking_id)
		 VALUES ($1, 'ride_canceled', 'Booking Cancelled', $2, $3, $4)`,
		passengerID, passengerMsg, rideID, bookingID,
	)
	if err != nil {
		return err
	}

	// Notification for the driver.
	var driverMsg string
	if seatsBooked == 1 {
		driverMsg = fmt.Sprintf(
			"%s cancelled their booking on your ride from %s to %s.",
			passengerName, fromLocation, toLocation,
		)
	} else {
		driverMsg = fmt.Sprintf(
			"%s cancelled their booking for %d seats on your ride from %s to %s.",
			passengerName, seatsBooked, fromLocation, toLocation,
		)
	}

	_, err = tx.Exec(
		ctx,
		`INSERT INTO notifications (user_id, type, title, message, ride_id, booking_id)
		 VALUES ($1, 'ride_canceled', 'Booking Cancelled', $2, $3, $4)`,
		driverID, driverMsg, rideID, bookingID,
	)
	if err != nil {
		return err
	}

	// Commit cancellation + seat restoration + notifications together.
	if err := tx.Commit(ctx); err != nil {
		return err
	}

	if s.NotificationService != nil {
		s.NotificationService.SendPush(ctx, passengerID, "ride_canceled", "Booking Cancelled", passengerMsg, map[string]string{
			"ride_id":    rideID,
			"booking_id": bookingID,
		})
		s.NotificationService.SendPush(ctx, driverID, "ride_canceled", "Booking Cancelled", driverMsg, map[string]string{
			"ride_id":    rideID,
			"booking_id": bookingID,
		})
	}

	return nil
}
