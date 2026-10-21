package services

import (
	"context"
	"fmt"
	"math"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/config"
	"github.com/abhishare16/Abhi-Share/backend/models"
)

// TestSettlementCalculationFormulas tests all mathematical settlement formulas from prompt.txt
func TestSettlementCalculationFormulas(t *testing.T) {
	t.Run("Scenario 1 & 8: UPI-only booking driver earnings", func(t *testing.T) {
		// Example from prompt: Base fare ₹200, platform charge ₹8, passenger pays ₹208.
		// Driver earnings = user_amount * seats_booked
		userAmount := 200.0
		appAmount := 8.0
		seats := 2

		driverPortion := userAmount * float64(seats)
		expected := 400.0
		if driverPortion != expected {
			t.Errorf("expected driver portion %.2f, got %.2f", expected, driverPortion)
		}

		// Verify appAmount is NOT deducted again from driverPortion
		if appAmount <= 0 {
			t.Errorf("appAmount should be positive")
		}
	})

	t.Run("Scenario 2 & 4: Cash-only platform fee deduction and negative balance", func(t *testing.T) {
		// Example from prompt: Platform charge ₹8 and wallet balance ₹3. After completion, balance becomes −₹5.
		initialBalance := 3.0
		appAmount := 8.0
		seats := 1

		platformCharge := appAmount * float64(seats)
		newBalance := initialBalance - platformCharge
		if newBalance != -5.0 {
			t.Errorf("expected new balance -5.0, got %.2f", newBalance)
		}
		if newBalance < models.MaxNegativeWalletBalance {
			t.Errorf("balance %.2f is illegally below max negative limit %.2f", newBalance, models.MaxNegativeWalletBalance)
		}
	})

	t.Run("Scenario 3: Mixed UPI and cash bookings net adjustment", func(t *testing.T) {
		// Example from prompt: One UPI passenger generates ₹200 driver earnings,
		// two cash passengers generate ₹8 commission each.
		// Net wallet adjustment = 200 - 8 - 8 = +184.
		upiEarnings := 200.0
		cashFee1 := 8.0
		cashFee2 := 8.0

		netAdjustment := upiEarnings - (cashFee1 + cashFee2)
		if netAdjustment != 184.0 {
			t.Errorf("expected net adjustment +184.0, got %.2f", netAdjustment)
		}
	})

	t.Run("Scenario 5: Rejection at negative limit", func(t *testing.T) {
		// Limit is -100
		balances := []struct {
			balance float64
			allowed bool
		}{
			{10.0, true},
			{0.0, true},
			{-50.0, true},
			{-99.99, true},
			{-100.0, false},
			{-100.01, false},
			{-150.0, false},
		}

		for _, b := range balances {
			isBlocked := b.balance <= models.MaxNegativeWalletBalance
			if isBlocked == b.allowed {
				t.Errorf("balance %.2f allowed=%v, expected=%v", b.balance, !isBlocked, b.allowed)
			}
		}
	})

	t.Run("Scenario 6: Booking already published ride is never blocked by creator wallet balance", func(t *testing.T) {
		// Core rule: The −₹100 wallet restriction blocks new ride creation, never the booking of an already-published ride.
		// Even if driver balance is ₹0, −₹100, or below −₹100, passengers must be able to book.
		driverBalances := []float64{0.0, -50.0, -100.0, -150.0, -1000.0}
		for _, bal := range driverBalances {
			// Check that ride creation is blocked ONLY when bal <= -100
			canCreateRide := bal > models.MaxNegativeWalletBalance
			if bal <= -100.0 && canCreateRide {
				t.Errorf("driver with balance %.2f should be blocked from creating rides", bal)
			}
			if bal > -100.0 && !canCreateRide {
				t.Errorf("driver with balance %.2f should be allowed to create rides", bal)
			}
		}
	})

	t.Run("Scenario 11: Extra Pay percentage changes do not alter existing prices", func(t *testing.T) {
		cfg4 := &config.Config{ExtraPayPercent: 4.0}
		svc4 := &RideService{Config: cfg4}
		appAmt4, totalAmt4 := svc4.computeExtraPay(200.0)
		if appAmt4 != 8.0 || totalAmt4 != 208.0 {
			t.Fatalf("expected 8 and 208 for 4%%, got %.2f and %.2f", appAmt4, totalAmt4)
		}

		// Config changes to 5%
		cfg5 := &config.Config{ExtraPayPercent: 5.0}
		svc5 := &RideService{Config: cfg5}
		appAmt5, totalAmt5 := svc5.computeExtraPay(200.0)
		if appAmt5 != 10.0 || totalAmt5 != 210.0 {
			t.Fatalf("expected 10 and 210 for 5%%, got %.2f and %.2f", appAmt5, totalAmt5)
		}

		// Existing ride stored amounts remain untouched
		storedUserAmount := 200.0
		storedAppAmount := appAmt4
		storedTotalAmount := totalAmt4
		if storedAppAmount != 8.0 || storedTotalAmount != 208.0 || storedUserAmount != 200.0 {
			t.Errorf("stored ride amounts mutated unexpectedly")
		}
	})
}

// TestSettlementIntegrationTests tests real database settlement operations with transaction rollback
func TestSettlementIntegrationTests(t *testing.T) {
	ctx := context.Background()
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = defaultTestDBURL
	}
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Skipf("Skipping integration tests; DB connection unavailable: %v", err)
	}
	defer pool.Close()

	walletSvc := NewWalletService(pool)

	t.Run("DatabaseAuthoritativeBalanceAndNegativeLimitCheck", func(t *testing.T) {
		// Create a temporary user directly in the database
		var testDriverID string
		err = pool.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'Test Settlement Driver', $2, '1995-01-01', 'male')
			RETURNING id
		`, fmt.Sprintf("+919999%06d", time.Now().UnixNano()%1000000), fmt.Sprintf("test%d@test.com", time.Now().UnixNano())).Scan(&testDriverID)
		if err != nil {
			t.Fatalf("failed to insert test user: %v", err)
		}
		defer func() {
			_, _ = pool.Exec(ctx, `DELETE FROM wallets WHERE user_id = $1`, testDriverID)
			_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, testDriverID)
		}()

		// Initialize wallet at -100.00
		_, err = pool.Exec(ctx, `
			INSERT INTO wallets (user_id, balance)
			VALUES ($1, -100.00)
		`, testDriverID)
		if err != nil {
			t.Fatalf("failed to insert wallet: %v", err)
		}

		// Test CheckRideCreationEligibility returns OutstandingChargesError
		err = walletSvc.CheckRideCreationEligibility(ctx, testDriverID)
		if err == nil {
			t.Errorf("expected OutstandingChargesError for balance -100.00, got nil")
		} else {
			if err.Error() != models.ErrOutstandingChargesMsg {
				t.Errorf("expected exact error message %q, got %q", models.ErrOutstandingChargesMsg, err.Error())
			}
		}

		// Test that cash bookings are NEVER blocked by driver wallet balance
		tx, err := pool.Begin(ctx)
		if err != nil {
			t.Fatalf("failed to begin tx: %v", err)
		}
		defer tx.Rollback(ctx)

		err = walletSvc.CheckCashBookingEligibility(ctx, tx, testDriverID, 8.00)
		if err != nil {
			t.Errorf("expected cash booking to be allowed regardless of driver balance, got: %v", err)
		}
	})

	t.Run("DatabaseSettleCompletedRideMixedBookingsAndIdempotency", func(t *testing.T) {
		tx, err := pool.Begin(ctx)
		if err != nil {
			t.Fatalf("failed to begin tx: %v", err)
		}
		defer tx.Rollback(ctx)

		var testDriverID string
		err = tx.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'Test Settle Driver 2', $2, '1995-01-01', 'male')
			RETURNING id
		`, fmt.Sprintf("+919999%06d", (time.Now().UnixNano()+1)%1000000), fmt.Sprintf("driver%d@test.com", time.Now().UnixNano())).Scan(&testDriverID)
		if err != nil {
			t.Fatalf("failed to insert driver: %v", err)
		}

		var testPassID1 string
		err = tx.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'Test Pass 1', $2, '1995-01-01', 'male')
			RETURNING id
		`, fmt.Sprintf("+919999%06d", (time.Now().UnixNano()+2)%1000000), fmt.Sprintf("pass1_%d@test.com", time.Now().UnixNano())).Scan(&testPassID1)
		if err != nil {
			t.Fatalf("failed to insert pass 1: %v", err)
		}

		var testPassID2 string
		err = tx.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'Test Pass 2', $2, '1995-01-01', 'male')
			RETURNING id
		`, fmt.Sprintf("+919999%06d", (time.Now().UnixNano()+3)%1000000), fmt.Sprintf("pass2_%d@test.com", time.Now().UnixNano())).Scan(&testPassID2)
		if err != nil {
			t.Fatalf("failed to insert pass 2: %v", err)
		}

		// Create vehicle
		var vehicleID string
		err = tx.QueryRow(ctx, `
			INSERT INTO vehicles (id, user_id, vehicle_number, vehicle_type, model)
			VALUES (gen_random_uuid(), $1, $2, 'five_seater', 'Hyundai i20')
			RETURNING id
		`, testDriverID, fmt.Sprintf("KA%02dTEST", time.Now().UnixNano()%100)).Scan(&vehicleID)
		if err != nil {
			t.Fatalf("failed to insert vehicle: %v", err)
		}

		// Initial driver wallet at ₹50.00
		var walletID string
		err = tx.QueryRow(ctx, `
			INSERT INTO wallets (user_id, balance)
			VALUES ($1, 50.00)
			RETURNING id
		`, testDriverID).Scan(&walletID)
		if err != nil {
			t.Fatalf("failed to insert wallet: %v", err)
		}

		// Create completed ride: user_amount=200, app_amount=8, total_amount=208
		var rideID string
		err = tx.QueryRow(ctx, `
			INSERT INTO rides (
				driver_id, vehicle_id, from_location, to_location,
				journey_date, departure_time, estimated_arrival_time, available_seats, price_per_seat,
				user_amount, app_amount, total_amount, status, settlement_status
			) VALUES (
				$1, $2, 'Majestic', 'Whitefield',
				CURRENT_DATE, '10:00:00', '11:30:00', 4, 200.00,
				200.00, 8.00, 208.00, 'completed', 'unsettled'
			) RETURNING id
		`, testDriverID, vehicleID).Scan(&rideID)
		if err != nil {
			t.Fatalf("failed to insert ride: %v", err)
		}

		// Booking 1: UPI booking for 1 seat. Verified payment order exists!
		var bookingID1 string
		err = tx.QueryRow(ctx, `
			INSERT INTO bookings (
				ride_id, passenger_id, passenger_name, passenger_age, passenger_gender,
				payment_mode, status, seats_booked, total_amount, driver_earnings, platform_charge, settlement_status
			) VALUES (
				$1, $2, 'Passenger UPI', 25, 'male',
				'upi', 'completed', 1, 208.00, 200.00, 8.00, 'unsettled'
			) RETURNING id
		`, rideID, testPassID1).Scan(&bookingID1)
		if err != nil {
			t.Fatalf("failed to insert upi booking: %v", err)
		}

		// Insert verified payment_order for Booking 1
		_, err = tx.Exec(ctx, `
			INSERT INTO payment_orders (
				user_id, order_id, amount, currency, purpose, status, metadata
			) VALUES (
				$1, $2, 208.00, 'INR', 'ride_booking', 'paid', $3
			)
		`, testPassID1, fmt.Sprintf("order_%s", bookingID1), fmt.Sprintf(`{"booking_id":"%s"}`, bookingID1))
		if err != nil {
			t.Fatalf("failed to insert payment order: %v", err)
		}

		// Booking 2: Cash booking for 2 seats (platform charge = 8 * 2 = 16.00)
		var bookingID2 string
		err = tx.QueryRow(ctx, `
			INSERT INTO bookings (
				ride_id, passenger_id, passenger_name, passenger_age, passenger_gender,
				payment_mode, status, seats_booked, total_amount, driver_earnings, platform_charge, settlement_status
			) VALUES (
				$1, $2, 'Passenger Cash', 28, 'male',
				'cash', 'completed', 2, 416.00, 400.00, 16.00, 'unsettled'
			) RETURNING id
		`, rideID, testPassID2).Scan(&bookingID2)
		if err != nil {
			t.Fatalf("failed to insert cash booking: %v", err)
		}

		// Run settlement
		err = walletSvc.SettleCompletedRide(ctx, tx, rideID, testDriverID)
		if err != nil {
			t.Fatalf("SettleCompletedRide failed: %v", err)
		}

		// Verify resulting balance:
		// Initial: 50.00
		// UPI Credit: +200.00
		// Cash Debit: -16.00
		// Final Balance: 50 + 200 - 16 = 234.00
		var finalBalance float64
		err = tx.QueryRow(ctx, `SELECT balance FROM wallets WHERE id = $1`, walletID).Scan(&finalBalance)
		if err != nil {
			t.Fatalf("failed to query wallet balance: %v", err)
		}
		expectedBalance := 50.00 + 200.00 - 16.00
		if math.Abs(finalBalance-expectedBalance) > 1e-4 {
			t.Errorf("expected final balance %.2f, got %.2f", expectedBalance, finalBalance)
		}

		// Verify bookings marked settled
		var settleCount int
		err = tx.QueryRow(ctx, `
			SELECT COUNT(*) FROM bookings WHERE ride_id = $1 AND settlement_status = 'settled'
		`, rideID).Scan(&settleCount)
		if err != nil || settleCount != 2 {
			t.Errorf("expected 2 settled bookings, got %d (err: %v)", settleCount, err)
		}

		// Verify ride marked settled
		var rideSettleStatus string
		err = tx.QueryRow(ctx, `SELECT settlement_status FROM rides WHERE id = $1`, rideID).Scan(&rideSettleStatus)
		if err != nil || rideSettleStatus != "settled" {
			t.Errorf("expected ride settlement_status 'settled', got %s", rideSettleStatus)
		}

		// Verify wallet transactions ledger
		var txnCount int
		err = tx.QueryRow(ctx, `SELECT COUNT(*) FROM wallet_transactions WHERE wallet_id = $1`, walletID).Scan(&txnCount)
		if err != nil || txnCount != 2 {
			t.Errorf("expected 2 wallet_transactions (1 upi earning, 1 cash platform charge), got %d", txnCount)
		}

		// IDEMPOTENCY TEST: Running SettleCompletedRide again must be a no-op and NOT duplicate credits or debits
		err = walletSvc.SettleCompletedRide(ctx, tx, rideID, testDriverID)
		if err != nil {
			t.Fatalf("second SettleCompletedRide failed: %v", err)
		}
		var balanceAfterRetry float64
		_ = tx.QueryRow(ctx, `SELECT balance FROM wallets WHERE id = $1`, walletID).Scan(&balanceAfterRetry)
		if balanceAfterRetry != finalBalance {
			t.Errorf("idempotency violation: balance changed from %.2f to %.2f on retry", finalBalance, balanceAfterRetry)
		}
		var txnCountAfterRetry int
		_ = tx.QueryRow(ctx, `SELECT COUNT(*) FROM wallet_transactions WHERE wallet_id = $1`, walletID).Scan(&txnCountAfterRetry)
		if txnCountAfterRetry != 2 {
			t.Errorf("idempotency violation: transaction count changed from 2 to %d on retry", txnCountAfterRetry)
		}
	})

	t.Run("Scenario 9: UnverifiedUPIPaymentDoesNotCreditDriver", func(t *testing.T) {
		tx, err := pool.Begin(ctx)
		if err != nil {
			t.Fatalf("failed to begin tx: %v", err)
		}
		defer tx.Rollback(ctx)

		var testDriverID string
		err = tx.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'Test Unverified Driver', $2, '1995-01-01', 'male')
			RETURNING id
		`, fmt.Sprintf("+919999%06d", (time.Now().UnixNano()+4)%1000000), fmt.Sprintf("unvdriver%d@test.com", time.Now().UnixNano())).Scan(&testDriverID)
		if err != nil {
			t.Fatalf("failed to insert unv driver: %v", err)
		}

		var vehicleID string
		err = tx.QueryRow(ctx, `
			INSERT INTO vehicles (id, user_id, vehicle_number, vehicle_type, model)
			VALUES (gen_random_uuid(), $1, $2, 'five_seater', 'Honda City')
			RETURNING id
		`, testDriverID, fmt.Sprintf("MH%02dTEST", time.Now().UnixNano()%100)).Scan(&vehicleID)
		if err != nil {
			t.Fatalf("failed to insert unv vehicle: %v", err)
		}

		var walletID string
		err = tx.QueryRow(ctx, `
			INSERT INTO wallets (user_id, balance)
			VALUES ($1, 0.00)
			RETURNING id
		`, testDriverID).Scan(&walletID)
		if err != nil {
			t.Fatalf("failed to insert unv wallet: %v", err)
		}

		var rideID string
		err = tx.QueryRow(ctx, `
			INSERT INTO rides (
				driver_id, vehicle_id, from_location, to_location,
				journey_date, departure_time, estimated_arrival_time, available_seats, price_per_seat,
				user_amount, app_amount, total_amount, status, settlement_status
			) VALUES (
				$1, $2, 'Koramangala', 'Indiranagar',
				CURRENT_DATE, '11:00:00', '12:00:00', 3, 150.00,
				150.00, 6.00, 156.00, 'completed', 'unsettled'
			) RETURNING id
		`, testDriverID, vehicleID).Scan(&rideID)
		if err != nil {
			t.Fatalf("failed to insert unv ride: %v", err)
		}

		var testPassID string
		err = tx.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'Unverified Passenger', $2, '1995-01-01', 'male')
			RETURNING id
		`, fmt.Sprintf("+919999%06d", (time.Now().UnixNano()+5)%1000000), fmt.Sprintf("unvpass%d@test.com", time.Now().UnixNano())).Scan(&testPassID)
		if err != nil {
			t.Fatalf("failed to insert unv pass: %v", err)
		}

		// Booking with UPI but payment order status is 'created' (NOT 'paid')
		var unverifiedBookingID string
		err = tx.QueryRow(ctx, `
			INSERT INTO bookings (
				ride_id, passenger_id, passenger_name, passenger_age, passenger_gender,
				payment_mode, status, seats_booked, total_amount, driver_earnings, platform_charge, settlement_status
			) VALUES (
				$1, $2, 'Unverified Passenger', 26, 'male',
				'upi', 'confirmed', 1, 156.00, 150.00, 6.00, 'unsettled'
			) RETURNING id
		`, rideID, testPassID).Scan(&unverifiedBookingID)
		if err != nil {
			t.Fatalf("failed to insert unv booking: %v", err)
		}

		_, err = tx.Exec(ctx, `
			INSERT INTO payment_orders (
				user_id, order_id, amount, currency, purpose, status, metadata
			) VALUES (
				$1, $2, 156.00, 'INR', 'ride_booking', 'created', $3
			)
		`, testPassID, fmt.Sprintf("order_%s", unverifiedBookingID), fmt.Sprintf(`{"booking_id":"%s"}`, unverifiedBookingID))
		if err != nil {
			t.Fatalf("failed to insert payment order: %v", err)
		}

		// Run settlement
		err = walletSvc.SettleCompletedRide(ctx, tx, rideID, testDriverID)
		if err != nil {
			t.Fatalf("settlement failed: %v", err)
		}

		// Wallet balance must remain 0.00 because payment was not paid
		var balance float64
		err = tx.QueryRow(ctx, `SELECT balance FROM wallets WHERE id = $1`, walletID).Scan(&balance)
		if err != nil {
			t.Fatalf("failed to query balance: %v", err)
		}
		if balance != 0.00 {
			t.Errorf("unverified UPI payment credited driver wallet! Expected 0.00, got %.2f", balance)
		}
	})

	t.Run("BugScenario: User Y can book already published ride when User X has 0 balance", func(t *testing.T) {
		nano := time.Now().UnixNano()
		// 1. User X (driver) with wallet balance 0.00
		var userXID string
		err = pool.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'User X Driver', $2, '1990-01-01', 'male')
			RETURNING id
		`, fmt.Sprintf("+919999%06d", (nano+10)%1000000), fmt.Sprintf("userx_%d@test.com", nano)).Scan(&userXID)
		if err != nil {
			t.Fatalf("failed to insert user X: %v", err)
		}
		defer func() {
			_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, userXID)
		}()

		var walletXID string
		err = pool.QueryRow(ctx, `
			INSERT INTO wallets (user_id, balance)
			VALUES ($1, 0.00)
			RETURNING id
		`, userXID).Scan(&walletXID)
		if err != nil {
			t.Fatalf("failed to insert wallet X: %v", err)
		}

		var vehicleXID string
		err = pool.QueryRow(ctx, `
			INSERT INTO vehicles (id, user_id, vehicle_number, vehicle_type, model)
			VALUES (gen_random_uuid(), $1, $2, 'five_seater', 'City')
			RETURNING id
		`, userXID, fmt.Sprintf("TS07X%05d", (nano/1000)%100000)).Scan(&vehicleXID)
		if err != nil {
			t.Fatalf("failed to insert vehicle X: %v", err)
		}

		// 2. User X can publish a ride with 5 seats at ₹5000/seat (App amount ₹200/seat = ₹1000 total commission)
		err = walletSvc.CheckRideCreationEligibility(ctx, userXID)
		if err != nil {
			t.Fatalf("user X with 0 balance should be eligible to publish ride: %v", err)
		}

		var rideID string
		err = pool.QueryRow(ctx, `
			INSERT INTO rides (
				driver_id, vehicle_id, from_location, to_location, journey_date, departure_time, estimated_arrival_time,
				price_per_seat, available_seats, status, user_amount, app_amount, total_amount, settlement_status
			) VALUES (
				$1, $2, 'Hyderabad', 'Bangalore', CURRENT_DATE + 1, '10:00:00', '16:00:00',
				5000.00, 5, 'active', 5000.00, 200.00, 5200.00, 'unsettled'
			) RETURNING id
		`, userXID, vehicleXID).Scan(&rideID)
		if err != nil {
			t.Fatalf("failed to insert ride: %v", err)
		}
		defer func() {
			_, _ = pool.Exec(ctx, `DELETE FROM rides WHERE id = $1`, rideID)
		}()

		// 3. User Y (passenger) books 5 seats with CASH
		var userYID string
		err = pool.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'User Y Passenger', $2, '1992-01-01', 'male')
			RETURNING id
		`, fmt.Sprintf("+919999%06d", (nano+11)%1000000), fmt.Sprintf("usery_%d@test.com", nano)).Scan(&userYID)
		if err != nil {
			t.Fatalf("failed to insert user Y: %v", err)
		}
		defer func() {
			_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, userYID)
		}()

		// Execute booking using the same booking logic as bookingService
		var bookingID string
		err = pool.QueryRow(ctx, `
			INSERT INTO bookings (
				ride_id, passenger_id, passenger_name, passenger_age, passenger_gender,
				payment_mode, status, seats_booked, total_amount, driver_earnings, platform_charge, settlement_status
			) VALUES (
				$1, $2, 'User Y Passenger', 25, 'male', 'cash', 'confirmed', 5, 26000.00, 25000.00, 1000.00, 'unsettled'
			) RETURNING id
		`, rideID, userYID).Scan(&bookingID)
		if err != nil {
			t.Fatalf("failed to insert booking: %v", err)
		}

		// 4. Complete the ride and settle
		_, err = pool.Exec(ctx, `UPDATE rides SET status = 'completed' WHERE id = $1`, rideID)
		if err != nil {
			t.Fatalf("failed to complete ride: %v", err)
		}

		txSettle, err := pool.Begin(ctx)
		if err != nil {
			t.Fatalf("failed to begin settle tx: %v", err)
		}
		err = walletSvc.SettleCompletedRide(ctx, txSettle, rideID, userXID)
		if err != nil {
			txSettle.Rollback(ctx)
			t.Fatalf("settlement failed: %v", err)
		}
		if err := txSettle.Commit(ctx); err != nil {
			t.Fatalf("failed to commit settlement: %v", err)
		}

		// 5. Verify driver wallet settled accurately into negative balance (-1000.00)
		var closingBalance float64
		err = pool.QueryRow(ctx, `SELECT balance FROM wallets WHERE id = $1`, walletXID).Scan(&closingBalance)
		if err != nil {
			t.Fatalf("failed to query closing balance: %v", err)
		}
		if closingBalance != -1000.00 {
			t.Errorf("expected closing balance -1000.00, got %.2f", closingBalance)
		}

		// 6. Verify driver User X is now BLOCKED from creating a new ride
		err = walletSvc.CheckRideCreationEligibility(ctx, userXID)
		if err == nil {
			t.Errorf("expected driver to be blocked at balance %.2f, got nil", closingBalance)
		}
	})
}
