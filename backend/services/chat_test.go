package services

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/models"
)

func TestChatServiceScenarios(t *testing.T) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = defaultTestDBURL
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Fatalf("failed to connect to DB: %v", err)
	}
	defer pool.Close()

	notifSvc := NewNotificationService(pool)
	chatSvc := NewChatService(pool, notifSvc)

	// Clean transaction rollback wrapper
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("failed to begin tx: %v", err)
	}
	defer tx.Rollback(ctx)

	// Create 1 driver (User A) and 2 passengers (User B and User C) and 1 outsider (User D)
	nano := time.Now().UnixNano()
	var driverID, passBID, passCID, outsiderID string

	err = tx.QueryRow(ctx, `
		INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
		VALUES (gen_random_uuid(), $1, 'Chat Driver A', $2, '1990-01-01', 'male')
		RETURNING id
	`, fmt.Sprintf("+919998%06d", nano%1000000), fmt.Sprintf("chat_driver_%d@test.com", nano)).Scan(&driverID)
	if err != nil {
		t.Fatalf("failed to insert driver: %v", err)
	}

	err = tx.QueryRow(ctx, `
		INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
		VALUES (gen_random_uuid(), $1, 'Chat Passenger B', $2, '1992-02-02', 'female')
		RETURNING id
	`, fmt.Sprintf("+919998%06d", (nano+1)%1000000), fmt.Sprintf("chat_passb_%d@test.com", nano)).Scan(&passBID)
	if err != nil {
		t.Fatalf("failed to insert passenger B: %v", err)
	}

	err = tx.QueryRow(ctx, `
		INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
		VALUES (gen_random_uuid(), $1, 'Chat Passenger C', $2, '1994-03-03', 'male')
		RETURNING id
	`, fmt.Sprintf("+919998%06d", (nano+2)%1000000), fmt.Sprintf("chat_passc_%d@test.com", nano)).Scan(&passCID)
	if err != nil {
		t.Fatalf("failed to insert passenger C: %v", err)
	}

	err = tx.QueryRow(ctx, `
		INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
		VALUES (gen_random_uuid(), $1, 'Outsider D', $2, '1996-04-04', 'other')
		RETURNING id
	`, fmt.Sprintf("+919998%06d", (nano+3)%1000000), fmt.Sprintf("chat_outsider_%d@test.com", nano)).Scan(&outsiderID)
	if err != nil {
		t.Fatalf("failed to insert outsider: %v", err)
	}

	// Create vehicle for Driver A
	var vehicleID string
	err = tx.QueryRow(ctx, `
		INSERT INTO vehicles (id, user_id, vehicle_number, vehicle_type, model)
		VALUES (gen_random_uuid(), $1, $2, 'five_seater', 'Swift')
		RETURNING id
	`, driverID, fmt.Sprintf("TS09AB%04d", (nano/1000)%10000)).Scan(&vehicleID)
	if err != nil {
		t.Fatalf("failed to insert vehicle: %v", err)
	}

	// Create a ride published by Driver A
	var rideID string
	err = tx.QueryRow(ctx, `
		INSERT INTO rides (
			driver_id, vehicle_id, from_location, to_location, journey_date, departure_time, estimated_arrival_time,
			price_per_seat, available_seats, status, user_amount, app_amount, total_amount, settlement_status
		) VALUES (
			$1, $2, 'Secunderabad', 'Gachibowli', CURRENT_DATE + 2, '09:00:00', '10:30:00',
			150.00, 3, 'active', 150.00, 6.00, 156.00, 'unsettled'
		) RETURNING id
	`, driverID, vehicleID).Scan(&rideID)
	if err != nil {
		t.Fatalf("failed to insert ride: %v", err)
	}

	// Create confirmed booking for Passenger B
	var bookingBID string
	err = tx.QueryRow(ctx, `
		INSERT INTO bookings (
			ride_id, passenger_id, passenger_name, passenger_age, passenger_gender,
			payment_mode, status, seats_booked, total_amount, driver_earnings, platform_charge, settlement_status
		) VALUES (
			$1, $2, 'Chat Passenger B', 28, 'female',
			'cash', 'confirmed', 1, 156.00, 150.00, 6.00, 'unsettled'
		) RETURNING id
	`, rideID, passBID).Scan(&bookingBID)
	if err != nil {
		t.Fatalf("failed to insert booking B: %v", err)
	}

	// Create confirmed booking for Passenger C
	var bookingCID string
	err = tx.QueryRow(ctx, `
		INSERT INTO bookings (
			ride_id, passenger_id, passenger_name, passenger_age, passenger_gender,
			payment_mode, status, seats_booked, total_amount, driver_earnings, platform_charge, settlement_status
		) VALUES (
			$1, $2, 'Chat Passenger C', 26, 'male',
			'upi', 'confirmed', 1, 156.00, 150.00, 6.00, 'unsettled'
		) RETURNING id
	`, rideID, passCID).Scan(&bookingCID)
	if err != nil {
		t.Fatalf("failed to insert booking C: %v", err)
	}

	// Commit setup to allow chatSvc queries
	if err := tx.Commit(ctx); err != nil {
		t.Fatalf("failed to commit setup: %v", err)
	}

	// Cleanup at the end
	defer func() {
		_, _ = pool.Exec(ctx, `DELETE FROM rides WHERE id = $1`, rideID)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id IN ($1, $2, $3, $4)`, driverID, passBID, passCID, outsiderID)
	}()

	t.Run("Scenario 1 & 2: Ride creator and Passenger B can access 1-to-1 conversation", func(t *testing.T) {
		// Passenger B gets or creates conversation
		convB, err := chatSvc.GetOrCreateConversation(ctx, passBID, bookingBID)
		if err != nil {
			t.Fatalf("passenger B failed to get conversation: %v", err)
		}
		if convB.RideID != rideID || convB.BookingID != bookingBID {
			t.Errorf("unexpected conversation ride or booking ID: %+v", convB)
		}
		if convB.OtherParticipant.ID != driverID || convB.OtherParticipant.Role != "driver" {
			t.Errorf("expected other participant to be Driver A, got: %+v", convB.OtherParticipant)
		}

		// Driver A gets the exact same conversation
		convA, err := chatSvc.GetOrCreateConversation(ctx, driverID, bookingBID)
		if err != nil {
			t.Fatalf("driver A failed to get conversation: %v", err)
		}
		if convA.ID != convB.ID {
			t.Errorf("driver and passenger should get same conversation ID, got %s and %s", convA.ID, convB.ID)
		}
		if convA.OtherParticipant.ID != passBID || convA.OtherParticipant.Role != "passenger" {
			t.Errorf("expected driver's other participant to be Passenger B, got: %+v", convA.OtherParticipant)
		}
	})

	t.Run("Scenario 3: Separate private conversation for Passenger C on the same ride", func(t *testing.T) {
		convC, err := chatSvc.GetOrCreateConversation(ctx, passCID, bookingCID)
		if err != nil {
			t.Fatalf("passenger C failed to get conversation: %v", err)
		}

		convB, _ := chatSvc.GetOrCreateConversation(ctx, passBID, bookingBID)
		if convC.ID == convB.ID {
			t.Fatalf("Passenger B and Passenger C MUST have separate conversation IDs! Got %s", convC.ID)
		}

		// Send message in Conversation B
		clientMsgID := fmt.Sprintf("msg_%d", time.Now().UnixNano())
		msgB, err := chatSvc.SendMessage(ctx, passBID, convB.ID, models.SendMessageRequest{
			Content:         "Hello Driver from Passenger B",
			MessageType:     "text",
			ClientMessageID: &clientMsgID,
		})
		if err != nil {
			t.Fatalf("failed to send message in conv B: %v", err)
		}
		if msgB.Content != "Hello Driver from Passenger B" {
			t.Errorf("unexpected message content: %s", msgB.Content)
		}

		// Verify Passenger C CANNOT see messages from Conversation B
		msgsC, err := chatSvc.GetMessages(ctx, passCID, convC.ID, 50, 0)
		if err != nil {
			t.Fatalf("failed to fetch messages for conv C: %v", err)
		}
		for _, m := range msgsC {
			if m.ID == msgB.ID {
				t.Fatalf("CRITICAL PRIVACY VIOLATION: Passenger C can see Passenger B's message %s", m.ID)
			}
		}

		// Passenger C attempting to directly read Conversation B is rejected
		_, err = chatSvc.GetMessages(ctx, passCID, convB.ID, 50, 0)
		if err == nil {
			t.Fatalf("Passenger C should be denied access to Conversation B")
		}
	})

	t.Run("Scenario 4 & 5: Outsider without booking is denied access", func(t *testing.T) {
		convB, _ := chatSvc.GetOrCreateConversation(ctx, passBID, bookingBID)

		// Outsider D tries to get conversation
		_, err := chatSvc.GetOrCreateConversation(ctx, outsiderID, bookingBID)
		if err == nil {
			t.Fatalf("outsider D should be denied from creating or joining conversation")
		}

		// Outsider D tries to read messages
		_, err = chatSvc.GetMessages(ctx, outsiderID, convB.ID, 50, 0)
		if err == nil {
			t.Fatalf("outsider D should be denied from reading messages in conv B")
		}

		// Outsider D tries to send message
		_, err = chatSvc.SendMessage(ctx, outsiderID, convB.ID, models.SendMessageRequest{
			Content: "Hacking into chat",
		})
		if err == nil {
			t.Fatalf("outsider D should be denied from sending messages in conv B")
		}
	})

	t.Run("Scenario 7 & 8: Idempotent message sending and read receipts", func(t *testing.T) {
		convB, _ := chatSvc.GetOrCreateConversation(ctx, passBID, bookingBID)
		clientUUID := fmt.Sprintf("idemp_%d", time.Now().UnixNano())

		// First send
		msg1, err := chatSvc.SendMessage(ctx, driverID, convB.ID, models.SendMessageRequest{
			Content:         "I'm on my way",
			MessageType:     "quick_reply",
			ClientMessageID: &clientUUID,
		})
		if err != nil {
			t.Fatalf("failed to send first message: %v", err)
		}

		// Duplicate retry send with same client_message_id
		msg2, err := chatSvc.SendMessage(ctx, driverID, convB.ID, models.SendMessageRequest{
			Content:         "I'm on my way",
			MessageType:     "quick_reply",
			ClientMessageID: &clientUUID,
		})
		if err != nil {
			t.Fatalf("failed to send retry message: %v", err)
		}
		if msg1.ID != msg2.ID {
			t.Fatalf("expected identical message ID for idempotent retry, got %s and %s", msg1.ID, msg2.ID)
		}

		// Check Passenger B's unread count
		unread, err := chatSvc.GetUnreadCount(ctx, passBID)
		if err != nil {
			t.Fatalf("failed to get unread count: %v", err)
		}
		if unread < 1 {
			t.Errorf("expected at least 1 unread message for passenger B, got %d", unread)
		}

		// Passenger B marks messages as read
		marked, err := chatSvc.MarkMessagesAsRead(ctx, passBID, convB.ID)
		if err != nil {
			t.Fatalf("failed to mark messages read: %v", err)
		}
		if marked < 1 {
			t.Errorf("expected at least 1 message marked read, got %d", marked)
		}

		// Unread count should now be 0 for this conversation
		unreadAfter, err := chatSvc.GetUnreadCount(ctx, passBID)
		if err != nil {
			t.Fatalf("failed to get unread count after read: %v", err)
		}
		if unreadAfter != 0 {
			t.Errorf("expected 0 unread messages, got %d", unreadAfter)
		}

		// Send location message
		locPayload := `{"type":"location","latitude":17.4399,"longitude":78.4983,"map_url":"https://maps.google.com/?q=17.4399,78.4983","label":"Shared current location"}`
		locMsg, err := chatSvc.SendMessage(ctx, passBID, convB.ID, models.SendMessageRequest{
			Content:     locPayload,
			MessageType: "location",
		})
		if err != nil {
			t.Fatalf("failed to send location message: %v", err)
		}
		if locMsg.MessageType != "location" {
			t.Errorf("expected MessageType 'location', got %s", locMsg.MessageType)
		}
		if locMsg.Content != locPayload {
			t.Errorf("expected Content to match location payload")
		}
	})

	t.Run("Scenario 9: Cancelled booking cannot send messages", func(t *testing.T) {
		// Cancel booking C
		_, err = pool.Exec(ctx, `UPDATE bookings SET status = 'cancelled' WHERE id = $1`, bookingCID)
		if err != nil {
			t.Fatalf("failed to cancel booking C: %v", err)
		}

		convC, _ := chatSvc.GetOrCreateConversation(ctx, passCID, bookingCID)

		// Attempt to send message
		_, err = chatSvc.SendMessage(ctx, passCID, convC.ID, models.SendMessageRequest{
			Content: "Hello are you still coming?",
		})
		if err == nil {
			t.Fatalf("message sending should be rejected for cancelled booking")
		}
	})

	t.Run("Scenario 10: Block user prevents further messages", func(t *testing.T) {
		convB, _ := chatSvc.GetOrCreateConversation(ctx, passBID, bookingBID)

		// Driver blocks Passenger B
		err = chatSvc.BlockUser(ctx, driverID, models.BlockUserRequest{
			UserID: passBID,
			Reason: "Unruly passenger",
		})
		if err != nil {
			t.Fatalf("failed to block user: %v", err)
		}

		// Passenger B tries to message Driver
		_, err = chatSvc.SendMessage(ctx, passBID, convB.ID, models.SendMessageRequest{
			Content: "Why did you block me?",
		})
		if err == nil {
			t.Fatalf("message sending should be blocked between blocked users")
		}

		// Report user
		err = chatSvc.ReportUser(ctx, driverID, models.ReportUserRequest{
			UserID:         passBID,
			RideID:         &rideID,
			ConversationID: &convB.ID,
			Reason:         "Inappropriate communication",
			Description:    "Passenger was hostile",
		})
		if err != nil {
			t.Fatalf("failed to report user: %v", err)
		}
	})

	t.Run("Scenario 11: Ride completion immediately removes chat from active lists and rejects messages", func(t *testing.T) {
		now11 := time.Now().UnixNano()
		phone11 := fmt.Sprintf("+919991%06d", now11%1000000)
		email11 := fmt.Sprintf("lifecycle_%d@test.com", now11)

		// Create a separate ride and confirmed booking to test completion lifecycle
		var testRideID, testBookingID, pID string
		err = pool.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'Lifecycle Passenger', $2, '1995-05-05', 'female')
			RETURNING id
		`, phone11, email11).Scan(&pID)
		if err != nil {
			t.Fatalf("failed to insert passenger: %v", err)
		}
		defer func() {
			_, _ = pool.Exec(ctx, `DELETE FROM rides WHERE id = $1`, testRideID)
			_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, pID)
		}()

		err = pool.QueryRow(ctx, `
			INSERT INTO rides (
				driver_id, vehicle_id, from_location, to_location, journey_date, departure_time, estimated_arrival_time,
				price_per_seat, available_seats, status, user_amount, app_amount, total_amount, settlement_status
			) VALUES (
				$1, $2, 'Ameerpet', 'Hitech City', CURRENT_DATE + 1, '10:00:00', '11:00:00',
				100.00, 2, 'active', 100.00, 4.00, 104.00, 'unsettled'
			) RETURNING id
		`, driverID, vehicleID).Scan(&testRideID)
		if err != nil {
			t.Fatalf("failed to create ride: %v", err)
		}

		err = pool.QueryRow(ctx, `
			INSERT INTO bookings (
				ride_id, passenger_id, passenger_name, passenger_age, passenger_gender,
				payment_mode, status, seats_booked, total_amount, driver_earnings, platform_charge, settlement_status
			) VALUES (
				$1, $2, 'Lifecycle Passenger', 28, 'female',
				'cash', 'confirmed', 1, 104.00, 100.00, 4.00, 'unsettled'
			) RETURNING id
		`, testRideID, pID).Scan(&testBookingID)
		if err != nil {
			t.Fatalf("failed to create booking: %v", err)
		}

		// Initialize active conversation
		conv, err := chatSvc.GetOrCreateConversation(ctx, driverID, testBookingID)
		if err != nil {
			t.Fatalf("failed to create conversation: %v", err)
		}

		// Verify conversation is visible in active list
		driverListBefore, err := chatSvc.ListConversations(ctx, driverID)
		if err != nil {
			t.Fatalf("failed to list driver conversations: %v", err)
		}
		foundBefore := false
		for _, item := range driverListBefore {
			if item.ID == conv.ID {
				foundBefore = true
				break
			}
		}
		if !foundBefore {
			t.Fatalf("expected conversation to be in driver's active list before ride completion")
		}

		// Mark ride completed
		_, err = pool.Exec(ctx, `UPDATE rides SET status = 'completed', completed_at = NOW(), updated_at = NOW() WHERE id = $1`, testRideID)
		if err != nil {
			t.Fatalf("failed to complete ride: %v", err)
		}
		_, err = pool.Exec(ctx, `UPDATE bookings SET status = 'completed', updated_at = NOW() WHERE id = $1`, testBookingID)
		if err != nil {
			t.Fatalf("failed to complete booking: %v", err)
		}
		_, err = pool.Exec(ctx, `UPDATE chat_conversations SET status = 'completed', updated_at = NOW() WHERE id = $1`, conv.ID)
		if err != nil {
			t.Fatalf("failed to complete conversation: %v", err)
		}

		// Verify conversation is IMMEDIATELY removed from active list for both driver and passenger
		driverListAfter, err := chatSvc.ListConversations(ctx, driverID)
		if err != nil {
			t.Fatalf("failed to list driver conversations after completion: %v", err)
		}
		for _, item := range driverListAfter {
			if item.ID == conv.ID {
				t.Fatalf("completed ride conversation should NOT appear in driver's active chat list")
			}
		}

		passengerListAfter, err := chatSvc.ListConversations(ctx, pID)
		if err != nil {
			t.Fatalf("failed to list passenger conversations after completion: %v", err)
		}
		for _, item := range passengerListAfter {
			if item.ID == conv.ID {
				t.Fatalf("completed ride conversation should NOT appear in passenger's active chat list")
			}
		}

		// Verify messaging is rejected after ride completion
		_, err = chatSvc.SendMessage(ctx, driverID, conv.ID, models.SendMessageRequest{
			Content: "Are you still here?",
		})
		if err == nil {
			t.Fatalf("sending messages after ride completion should be strictly rejected")
		}

		// Database records are still retained
		var msgCount int
		err = pool.QueryRow(ctx, `SELECT COUNT(*) FROM chat_conversations WHERE id = $1`, conv.ID).Scan(&msgCount)
		if err != nil || msgCount == 0 {
			t.Fatalf("conversation record must be retained in database immediately after completion")
		}
	})

	t.Run("Scenario 12: Retention cleanup deletes expired unprotected chats and preserves protected ones", func(t *testing.T) {
		now12 := time.Now().UnixNano()
		phoneOld := fmt.Sprintf("+919992%06d", now12%1000000)
		emailOld := fmt.Sprintf("old_%d@test.com", now12)

		// 1. Create an unprotected conversation completed 8 days ago
		var oldRideID, oldBookingID, oldConvID, oldPID string
		err = pool.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'Old Passenger', $2, '1993-03-03', 'male')
			RETURNING id
		`, phoneOld, emailOld).Scan(&oldPID)
		if err != nil {
			t.Fatalf("failed to insert old passenger: %v", err)
		}
		defer func() {
			_, _ = pool.Exec(ctx, `DELETE FROM rides WHERE id = $1`, oldRideID)
			_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, oldPID)
		}()

		err = pool.QueryRow(ctx, `
			INSERT INTO rides (
				driver_id, vehicle_id, from_location, to_location, journey_date, departure_time, estimated_arrival_time,
				price_per_seat, available_seats, status, completed_at, user_amount, app_amount, total_amount, settlement_status
			) VALUES (
				$1, $2, 'Kondapur', 'Begumpet', CURRENT_DATE - 9, '08:00:00', '09:00:00',
				120.00, 2, 'completed', NOW() - INTERVAL '8 days', 120.00, 5.00, 125.00, 'settled'
			) RETURNING id
		`, driverID, vehicleID).Scan(&oldRideID)
		if err != nil {
			t.Fatalf("failed to create old ride: %v", err)
		}

		err = pool.QueryRow(ctx, `
			INSERT INTO bookings (
				ride_id, passenger_id, passenger_name, passenger_age, passenger_gender,
				payment_mode, status, seats_booked, total_amount, driver_earnings, platform_charge, settlement_status
			) VALUES (
				$1, $2, 'Old Passenger', 30, 'male',
				'cash', 'completed', 1, 125.00, 120.00, 5.00, 'settled'
			) RETURNING id
		`, oldRideID, oldPID).Scan(&oldBookingID)
		if err != nil {
			t.Fatalf("failed to create old booking: %v", err)
		}

		err = pool.QueryRow(ctx, `
			INSERT INTO chat_conversations (
				ride_id, booking_id, driver_id, passenger_id, status, is_protected, last_message_at
			) VALUES ($1, $2, $3, $4, 'completed', false, NOW() - INTERVAL '8 days')
			RETURNING id
		`, oldRideID, oldBookingID, driverID, oldPID).Scan(&oldConvID)
		if err != nil {
			t.Fatalf("failed to insert old conversation: %v", err)
		}

		// Insert messages into old conversation
		_, err = pool.Exec(ctx, `
			INSERT INTO chat_messages (conversation_id, sender_id, sender_role, message_type, content, is_read)
			VALUES ($1, $2, 'driver', 'text', 'Old message 1', true),
			       ($1, $3, 'passenger', 'text', 'Old message 2', true)
		`, oldConvID, driverID, oldPID)
		if err != nil {
			t.Fatalf("failed to insert old messages: %v", err)
		}

		// 2. Create a PROTECTED conversation completed 8 days ago (has a report)
		nowProt := time.Now().UnixNano() + 1
		phoneProt := fmt.Sprintf("+919993%06d", nowProt%1000000)
		emailProt := fmt.Sprintf("reported_%d@test.com", nowProt)

		var protectedRideID, protectedBookingID, protectedConvID, protPID string
		err = pool.QueryRow(ctx, `
			INSERT INTO users (id, phone, full_name, email, date_of_birth, gender)
			VALUES (gen_random_uuid(), $1, 'Reported Passenger', $2, '1991-01-01', 'female')
			RETURNING id
		`, phoneProt, emailProt).Scan(&protPID)
		if err != nil {
			t.Fatalf("failed to insert reported passenger: %v", err)
		}
		defer func() {
			_, _ = pool.Exec(ctx, `DELETE FROM rides WHERE id = $1`, protectedRideID)
			_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, protPID)
		}()

		err = pool.QueryRow(ctx, `
			INSERT INTO rides (
				driver_id, vehicle_id, from_location, to_location, journey_date, departure_time, estimated_arrival_time,
				price_per_seat, available_seats, status, completed_at, user_amount, app_amount, total_amount, settlement_status
			) VALUES (
				$1, $2, 'Madhapur', 'Miyapur', CURRENT_DATE - 9, '18:00:00', '19:00:00',
				110.00, 2, 'completed', NOW() - INTERVAL '8 days', 110.00, 4.00, 114.00, 'settled'
			) RETURNING id
		`, driverID, vehicleID).Scan(&protectedRideID)
		if err != nil {
			t.Fatalf("failed to create protected ride: %v", err)
		}

		err = pool.QueryRow(ctx, `
			INSERT INTO bookings (
				ride_id, passenger_id, passenger_name, passenger_age, passenger_gender,
				payment_mode, status, seats_booked, total_amount, driver_earnings, platform_charge, settlement_status
			) VALUES (
				$1, $2, 'Reported Passenger', 32, 'female',
				'cash', 'completed', 1, 114.00, 110.00, 4.00, 'settled'
			) RETURNING id
		`, protectedRideID, protPID).Scan(&protectedBookingID)
		if err != nil {
			t.Fatalf("failed to create protected booking: %v", err)
		}

		err = pool.QueryRow(ctx, `
			INSERT INTO chat_conversations (
				ride_id, booking_id, driver_id, passenger_id, status, is_protected, last_message_at
			) VALUES ($1, $2, $3, $4, 'completed', false, NOW() - INTERVAL '8 days')
			RETURNING id
		`, protectedRideID, protectedBookingID, driverID, protPID).Scan(&protectedConvID)
		if err != nil {
			t.Fatalf("failed to insert protected conversation: %v", err)
		}

		// Driver files report against Reported Passenger
		err = chatSvc.ReportUser(ctx, driverID, models.ReportUserRequest{
			UserID:         protPID,
			RideID:         &protectedRideID,
			ConversationID: &protectedConvID,
			Reason:         "Harassment",
			Description:    "Inappropriate conduct",
		})
		if err != nil {
			t.Fatalf("failed to report user: %v", err)
		}

		// 3. Execute cleanup job
		deletedCount, err := chatSvc.CleanupExpiredConversations(ctx)
		if err != nil {
			t.Fatalf("cleanup failed: %v", err)
		}
		if deletedCount < 1 {
			t.Errorf("expected at least 1 deleted conversation, got %d", deletedCount)
		}

		// 4. Verify unprotected conversation was deleted
		var oldExists bool
		_ = pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM chat_conversations WHERE id = $1)`, oldConvID).Scan(&oldExists)
		if oldExists {
			t.Errorf("expected unprotected expired conversation %s to be permanently deleted", oldConvID)
		}

		// Verify unprotected messages were cascade-deleted
		var remainingMsgs int
		_ = pool.QueryRow(ctx, `SELECT COUNT(*) FROM chat_messages WHERE conversation_id = $1`, oldConvID).Scan(&remainingMsgs)
		if remainingMsgs != 0 {
			t.Errorf("expected messages of deleted conversation to be cascade-deleted, found %d", remainingMsgs)
		}

		// 5. Verify protected conversation was PRESERVED
		var protExists bool
		_ = pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM chat_conversations WHERE id = $1)`, protectedConvID).Scan(&protExists)
		if !protExists {
			t.Errorf("expected reported conversation %s to be preserved by cleanup", protectedConvID)
		}

		// 6. Verify ride and booking records are untouched
		var rideStillExists, bookingStillExists bool
		_ = pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM rides WHERE id = $1)`, oldRideID).Scan(&rideStillExists)
		_ = pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM bookings WHERE id = $1)`, oldBookingID).Scan(&bookingStillExists)
		if !rideStillExists || !bookingStillExists {
			t.Errorf("unrelated ride and booking records must NOT be deleted by chat cleanup")
		}
	})
}
