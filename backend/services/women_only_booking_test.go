package services

import (
	"context"
	"os"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/models"
)

const defaultTestDBURL = "postgresql://abhishare_app.uqubmnnesyvvdeiwjnag:AbhiShare2026SecurePass!@aws-0-ap-south-1.pooler.supabase.com:5432/postgres?sslmode=require"

func TestWomenOnlyRideBookingValidation(t *testing.T) {
	ctx := context.Background()
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = defaultTestDBURL
	}
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Skipf("Skipping integration test; failed to connect to database: %v", err)
	}
	defer pool.Close()

	svc := NewBookingService(pool)

	// Ensure there is a Women Only ride with available seats
	var rideID string
	var driverID string
	err = pool.QueryRow(ctx, `
		SELECT id, driver_id FROM rides 
		WHERE is_women_only = true AND status = 'active' AND available_seats >= 2 
		LIMIT 1
	`).Scan(&rideID, &driverID)
	if err != nil {
		t.Skipf("No active Women Only ride with available seats found: %v", err)
	}

	maleBookerID := "5ae6aec6-32b1-4139-bd21-2b2bd80de79d" // Varun (male account)

	// Case 1: Male account booking for any female passenger (e.g., Akanksha) -> MUST SUCCEED
	t.Run("MaleAccountBookingForFemalePassengerSucceeds", func(t *testing.T) {
		req := models.CreateBookingRequest{
			RideID:      rideID,
			PassengerID: maleBookerID,
			PaymentMode: "cash",
			SeatsBooked: 1,
			Passengers: []models.PassengerInput{
				{
					Name:   "Akanksha",
					Age:    25,
					Gender: "female",
				},
			},
		}

		bookingID, err := svc.CreateBooking(ctx, req)
		if err != nil {
			t.Fatalf("Expected booking to succeed for female passenger Akanksha, but got error: %v", err)
		}
		if bookingID == "" {
			t.Fatalf("Expected booking ID, got empty string")
		}

		// Verify booking in database
		var bookingGender, passGender string
		_ = pool.QueryRow(ctx, `SELECT passenger_gender FROM bookings WHERE id = $1`, bookingID).Scan(&bookingGender)
		_ = pool.QueryRow(ctx, `SELECT passenger_gender FROM booking_passengers WHERE booking_id = $1`, bookingID).Scan(&passGender)

		if bookingGender != "female" {
			t.Errorf("Expected bookings.passenger_gender = 'female', got '%s'", bookingGender)
		}
		if passGender != "female" {
			t.Errorf("Expected booking_passengers.passenger_gender = 'female', got '%s'", passGender)
		}

		// Clean up test booking to restore available seats
		_, _ = pool.Exec(ctx, `DELETE FROM booking_passengers WHERE booking_id = $1`, bookingID)
		_, _ = pool.Exec(ctx, `DELETE FROM bookings WHERE id = $1`, bookingID)
		_, _ = pool.Exec(ctx, `UPDATE rides SET available_seats = available_seats + 1 WHERE id = $1`, rideID)
	})

	// Case 2: Male passenger on Women Only ride -> MUST FAIL
	t.Run("MalePassengerOnWomenOnlyRideFails", func(t *testing.T) {
		req := models.CreateBookingRequest{
			RideID:      rideID,
			PassengerID: maleBookerID,
			PaymentMode: "cash",
			SeatsBooked: 1,
			Passengers: []models.PassengerInput{
				{
					Name:   "Rahul",
					Age:    26,
					Gender: "male",
				},
			},
		}

		_, err := svc.CreateBooking(ctx, req)
		if err == nil {
			t.Fatalf("Expected booking to fail for male passenger, but it succeeded")
		}
		if !strings.Contains(err.Error(), "Only female passengers can travel") {
			t.Errorf("Expected error to mention 'Only female passengers can travel', got: %v", err)
		}
	})

	// Case 3: Multiple passengers where one is male -> MUST FAIL
	t.Run("MultiplePassengersOneMaleFails", func(t *testing.T) {
		req := models.CreateBookingRequest{
			RideID:      rideID,
			PassengerID: maleBookerID,
			PaymentMode: "cash",
			SeatsBooked: 2,
			Passengers: []models.PassengerInput{
				{
					Name:   "Akanksha",
					Age:    25,
					Gender: "female",
				},
				{
					Name:   "Rahul",
					Age:    26,
					Gender: "male",
				},
			},
		}

		_, err := svc.CreateBooking(ctx, req)
		if err == nil {
			t.Fatalf("Expected multi-passenger booking to fail due to male passenger, but it succeeded")
		}
		if !strings.Contains(err.Error(), "passenger 2") {
			t.Errorf("Expected error for passenger 2, got: %v", err)
		}
	})

	// Case 4: Multiple female passengers -> MUST SUCCEED
	t.Run("MultipleFemalePassengersSucceeds", func(t *testing.T) {
		req := models.CreateBookingRequest{
			RideID:      rideID,
			PassengerID: maleBookerID,
			PaymentMode: "cash",
			SeatsBooked: 2,
			Passengers: []models.PassengerInput{
				{
					Name:   "Akanksha",
					Age:    25,
					Gender: "female",
				},
				{
					Name:   "Priya",
					Age:    24,
					Gender: "female",
				},
			},
		}

		bookingID, err := svc.CreateBooking(ctx, req)
		if err != nil {
			t.Fatalf("Expected multi-passenger booking to succeed for female passengers, got error: %v", err)
		}

		// Clean up
		_, _ = pool.Exec(ctx, `DELETE FROM booking_passengers WHERE booking_id = $1`, bookingID)
		_, _ = pool.Exec(ctx, `DELETE FROM bookings WHERE id = $1`, bookingID)
		_, _ = pool.Exec(ctx, `UPDATE rides SET available_seats = available_seats + 2 WHERE id = $1`, rideID)
	})
}
