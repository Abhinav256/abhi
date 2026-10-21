package services

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/models"
)

type BookingQueryService struct {
	DB *pgxpool.Pool
}

func NewBookingQueryService(db *pgxpool.Pool) *BookingQueryService {
	return &BookingQueryService{
		DB: db,
	}
}

func (s *BookingQueryService) loadPassengersForBookings(
	ctx context.Context,
	bookingIDs []string,
) (map[string][]models.BookingPassenger, error) {
	result := make(map[string][]models.BookingPassenger)
	if len(bookingIDs) == 0 {
		return result, nil
	}

	rows, err := s.DB.Query(
		ctx,
		`SELECT
			id,
			booking_id,
			passenger_number,
			passenger_name,
			passenger_age,
			passenger_gender,
			passenger_phone,
			created_at
		FROM booking_passengers
		WHERE booking_id = ANY($1)
		ORDER BY passenger_number ASC`,
		bookingIDs,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var p models.BookingPassenger
		err := rows.Scan(
			&p.ID,
			&p.BookingID,
			&p.PassengerNumber,
			&p.PassengerName,
			&p.PassengerAge,
			&p.PassengerGender,
			&p.PassengerPhone,
			&p.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		result[p.BookingID] = append(result[p.BookingID], p)
	}

	return result, rows.Err()
}

func (s *BookingQueryService) GetBookingsForRide(
	ctx context.Context,
	rideID string,
	driverID string,
) ([]models.Booking, error) {

	// Only the driver who owns the ride can see its bookings.
	var rideExists bool

	err := s.DB.QueryRow(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM rides
			WHERE id = $1
			  AND driver_id = $2
		)`,
		rideID,
		driverID,
	).Scan(&rideExists)

	if err != nil {
		return nil, err
	}

	if !rideExists {
		return nil, fmt.Errorf("you do not have access to this ride")
	}

	rows, err := s.DB.Query(
		ctx,
		`SELECT
			id,
			ride_id,
			passenger_id,
			passenger_name,
			passenger_age,
			passenger_gender,
			COALESCE(from_location, ''),
			COALESCE(to_location, ''),
			payment_mode,
			status,
			seats_booked,
			total_amount,
			created_at,
			updated_at
		FROM bookings
		WHERE ride_id = $1
		ORDER BY created_at ASC`,
		rideID,
	)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	var bookings []models.Booking
	var bookingIDs []string

	for rows.Next() {
		var booking models.Booking

		err := rows.Scan(
			&booking.ID,
			&booking.RideID,
			&booking.PassengerID,
			&booking.PassengerName,
			&booking.PassengerAge,
			&booking.PassengerGender,
			&booking.FromLocation,
			&booking.ToLocation,
			&booking.PaymentMode,
			&booking.Status,
			&booking.SeatsBooked,
			&booking.TotalAmount,
			&booking.CreatedAt,
			&booking.UpdatedAt,
		)

		if err != nil {
			return nil, err
		}

		bookings = append(bookings, booking)
		bookingIDs = append(bookingIDs, booking.ID)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	if bookings == nil {
		bookings = []models.Booking{}
	}

	passengerMap, err := s.loadPassengersForBookings(ctx, bookingIDs)
	if err == nil {
		for i := range bookings {
			if ps, ok := passengerMap[bookings[i].ID]; ok && len(ps) > 0 {
				bookings[i].Passengers = ps
			} else if bookings[i].PassengerName != "" {
				bookings[i].Passengers = []models.BookingPassenger{
					{
						PassengerNumber: 1,
						PassengerName:   bookings[i].PassengerName,
						PassengerAge:    bookings[i].PassengerAge,
						PassengerGender: bookings[i].PassengerGender,
					},
				}
			}
		}
	}

	return bookings, nil
}

func (s *BookingQueryService) GetBookingsForPassenger(
	ctx context.Context,
	passengerID string,
) ([]models.BookingWithRide, error) {

	rows, err := s.DB.Query(
		ctx,
		`SELECT
			b.id,
			b.ride_id,
			b.passenger_id,
			b.passenger_name,
			b.passenger_age,
			b.passenger_gender,
			b.payment_mode,
			b.status,
			b.seats_booked,
			b.total_amount,
			b.created_at,
			b.updated_at,
			r.from_location,
			r.to_location,
			r.journey_date,
			r.departure_time,
			r.price_per_seat,
			r.status,
			COALESCE(r.driver_selfie_url, ''),
			COALESCE(u.full_name, ''),
			CASE WHEN b.status IN ('confirmed', 'completed') THEN COALESCE(u.phone, '') ELSE '' END AS driver_phone,
			r.is_women_only
		FROM bookings b
		INNER JOIN rides r ON r.id = b.ride_id
		INNER JOIN users u ON u.id = r.driver_id
		WHERE b.passenger_id = $1
		ORDER BY b.created_at DESC`,
		passengerID,
	)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	var bookings []models.BookingWithRide
	var bookingIDs []string

	for rows.Next() {
		var booking models.BookingWithRide

		err := rows.Scan(
			&booking.ID,
			&booking.RideID,
			&booking.PassengerID,
			&booking.PassengerName,
			&booking.PassengerAge,
			&booking.PassengerGender,
			&booking.PaymentMode,
			&booking.Status,
			&booking.SeatsBooked,
			&booking.TotalAmount,
			&booking.CreatedAt,
			&booking.UpdatedAt,
			&booking.FromLocation,
			&booking.ToLocation,
			&booking.JourneyDate,
			&booking.DepartureTime,
			&booking.PricePerSeat,
			&booking.RideStatus,
			&booking.DriverSelfieURL,
			&booking.DriverName,
			&booking.DriverPhone,
			&booking.IsWomenOnly,
		)

		if err != nil {
			return nil, err
		}

		bookings = append(bookings, booking)
		bookingIDs = append(bookingIDs, booking.ID)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	if bookings == nil {
		bookings = []models.BookingWithRide{}
	}

	passengerMap, err := s.loadPassengersForBookings(ctx, bookingIDs)
	if err == nil {
		for i := range bookings {
			if ps, ok := passengerMap[bookings[i].ID]; ok && len(ps) > 0 {
				bookings[i].Passengers = ps
			} else if bookings[i].PassengerName != "" {
				bookings[i].Passengers = []models.BookingPassenger{
					{
						PassengerNumber: 1,
						PassengerName:   bookings[i].PassengerName,
						PassengerAge:    bookings[i].PassengerAge,
						PassengerGender: bookings[i].PassengerGender,
					},
				}
			}
		}
	}

	return bookings, nil
}

func (s *BookingQueryService) GetBookingByID(
	ctx context.Context,
	bookingID string,
	userID string,
) (*models.Booking, error) {

	var booking models.Booking

	err := s.DB.QueryRow(
		ctx,
		`SELECT
			b.id,
			b.ride_id,
			b.passenger_id,
			b.passenger_name,
			b.passenger_age,
			b.passenger_gender,
			COALESCE(NULLIF(b.from_location, ''), r.from_location),
			COALESCE(NULLIF(b.to_location, ''), r.to_location),
			b.payment_mode,
			b.status,
			b.seats_booked,
			b.total_amount,
			b.created_at,
			b.updated_at
		FROM bookings b
		INNER JOIN rides r
			ON r.id = b.ride_id
		WHERE b.id = $1
		  AND (
			  b.passenger_id = $2
			  OR r.driver_id = $2
		  )`,
		bookingID,
		userID,
	).Scan(
		&booking.ID,
		&booking.RideID,
		&booking.PassengerID,
		&booking.PassengerName,
		&booking.PassengerAge,
		&booking.PassengerGender,
		&booking.FromLocation,
		&booking.ToLocation,
		&booking.PaymentMode,
		&booking.Status,
		&booking.SeatsBooked,
		&booking.TotalAmount,
		&booking.CreatedAt,
		&booking.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("booking not found or access denied")
		}

		return nil, err
	}

	passengerMap, err := s.loadPassengersForBookings(ctx, []string{booking.ID})
	if err == nil {
		if ps, ok := passengerMap[booking.ID]; ok && len(ps) > 0 {
			booking.Passengers = ps
		} else if booking.PassengerName != "" {
			booking.Passengers = []models.BookingPassenger{
				{
					PassengerNumber: 1,
					PassengerName:   booking.PassengerName,
					PassengerAge:    booking.PassengerAge,
					PassengerGender: booking.PassengerGender,
				},
			}
		}
	}

	return &booking, nil
}

// GetBookingContact returns authorized recipient contact info for direct phone calls.
// Only accessible to confirmed or completed booking participants (passenger or ride driver).
func (s *BookingQueryService) GetBookingContact(
	ctx context.Context,
	bookingID string,
	userID string,
) (*models.BookingContactResponse, error) {
	var (
		passengerID    string
		passengerName  string
		passengerPhone string
		driverID       string
		driverName     string
		driverPhone    string
		bookingStatus  string
	)

	err := s.DB.QueryRow(ctx, `
		SELECT 
			b.passenger_id,
			b.passenger_name,
			COALESCE(u_pass.phone, ''),
			r.driver_id,
			COALESCE(u_driver.full_name, ''),
			COALESCE(u_driver.phone, ''),
			b.status
		FROM bookings b
		INNER JOIN rides r ON r.id = b.ride_id
		INNER JOIN users u_driver ON u_driver.id = r.driver_id
		LEFT JOIN users u_pass ON u_pass.id = b.passenger_id
		WHERE b.id = $1
		  AND (b.passenger_id = $2 OR r.driver_id = $2)
	`, bookingID, userID).Scan(
		&passengerID,
		&passengerName,
		&passengerPhone,
		&driverID,
		&driverName,
		&driverPhone,
		&bookingStatus,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("booking not found or access denied")
		}
		return nil, err
	}

	if bookingStatus != "confirmed" && bookingStatus != "completed" {
		return nil, fmt.Errorf("phone contact is only available for confirmed bookings")
	}

	if userID == driverID {
		// Caller is driver -> contact recipient is passenger
		phone := passengerPhone
		if phone == "" {
			var bpPhone string
			_ = s.DB.QueryRow(ctx, `
				SELECT COALESCE(passenger_phone, '') 
				FROM booking_passengers 
				WHERE booking_id = $1 AND passenger_phone IS NOT NULL AND passenger_phone != ''
				ORDER BY passenger_number ASC 
				LIMIT 1
			`, bookingID).Scan(&bpPhone)
			phone = bpPhone
		}
		if phone == "" {
			return nil, fmt.Errorf("recipient phone number not found")
		}
		return &models.BookingContactResponse{
			BookingID:   bookingID,
			ContactName: passengerName,
			Phone:       phone,
			Role:        "passenger",
		}, nil
	}

	// Caller is passenger -> contact recipient is driver
	if driverPhone == "" {
		return nil, fmt.Errorf("driver phone number not found")
	}
	return &models.BookingContactResponse{
		BookingID:   bookingID,
		ContactName: driverName,
		Phone:       driverPhone,
		Role:        "driver",
	}, nil
}
