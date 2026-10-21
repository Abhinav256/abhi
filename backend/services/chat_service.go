package services

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/models"
)

type ChatService struct {
	DB                  *pgxpool.Pool
	NotificationService *NotificationService
}

func NewChatService(db *pgxpool.Pool, notifSvc *NotificationService) *ChatService {
	return &ChatService{
		DB:                  db,
		NotificationService: notifSvc,
	}
}

// GetOrCreateConversation retrieves or initializes a 1-to-1 conversation for a confirmed/completed booking.
func (s *ChatService) GetOrCreateConversation(ctx context.Context, userID, bookingID string) (*models.ChatConversationItem, error) {
	if strings.TrimSpace(bookingID) == "" {
		return nil, fmt.Errorf("booking_id is required")
	}

	// 1. Fetch booking and ride details to verify authorization
	var (
		rideID        string
		driverID      string
		passengerID   string
		bookingStatus string
		rideStatus    string
		rideDate      time.Time
		rideTime      string
		fromLocation  string
		toLocation    string
		pricePerSeat  float64
		isWomenOnly   bool
	)

	err := s.DB.QueryRow(ctx, `
		SELECT b.ride_id, r.driver_id, b.passenger_id, b.status, r.status,
		       r.journey_date, r.departure_time::text, r.from_location, r.to_location, r.price_per_seat, r.is_women_only
		FROM bookings b
		JOIN rides r ON r.id = b.ride_id
		WHERE b.id = $1
	`, bookingID).Scan(
		&rideID, &driverID, &passengerID, &bookingStatus, &rideStatus,
		&rideDate, &rideTime, &fromLocation, &toLocation, &pricePerSeat, &isWomenOnly,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("booking not found")
		}
		return nil, fmt.Errorf("failed to fetch booking: %w", err)
	}

	// 2. Strict authorization check: Only driver or passenger of this booking can chat
	if userID != driverID && userID != passengerID {
		return nil, fmt.Errorf("unauthorized: you are not a participant in this booking")
	}

	// 3. Find existing conversation or create new one
	var (
		convID           string
		status           string
		lastMessageAt    time.Time
		isProtected      bool
		protectionReason *string
	)

	err = s.DB.QueryRow(ctx, `
		SELECT id, status, last_message_at, is_protected, protection_reason
		FROM chat_conversations
		WHERE booking_id = $1
	`, bookingID).Scan(&convID, &status, &lastMessageAt, &isProtected, &protectionReason)

	if errors.Is(err, pgx.ErrNoRows) {
		if rideStatus == "completed" || bookingStatus == "completed" {
			return nil, fmt.Errorf("chat is unavailable: this ride has already been completed")
		}

		// New conversation
		initStatus := "active"
		if bookingStatus == "cancelled" {
			initStatus = "read_only"
		}

		err = s.DB.QueryRow(ctx, `
			INSERT INTO chat_conversations (
				ride_id, booking_id, driver_id, passenger_id, status, last_message_at
			) VALUES ($1, $2, $3, $4, $5, NOW())
			ON CONFLICT (booking_id) DO UPDATE SET updated_at = NOW()
			RETURNING id, status, last_message_at, is_protected, protection_reason
		`, rideID, bookingID, driverID, passengerID, initStatus).Scan(&convID, &status, &lastMessageAt, &isProtected, &protectionReason)
		if err != nil {
			return nil, fmt.Errorf("failed to create chat conversation: %w", err)
		}
	} else if err != nil {
		return nil, fmt.Errorf("failed to query chat conversation: %w", err)
	} else if (rideStatus == "completed" || bookingStatus == "completed") && status != "completed" {
		status = "completed"
		_, _ = s.DB.Exec(ctx, `UPDATE chat_conversations SET status = 'completed', updated_at = NOW() WHERE id = $1`, convID)
	}

	// 4. Build other participant summary (NEVER expose phone numbers!)
	otherUserID := passengerID
	otherRole := "passenger"
	if userID == passengerID {
		otherUserID = driverID
		otherRole = "driver"
	}

	var otherSummary models.ChatParticipantSummary
	otherSummary.ID = otherUserID
	otherSummary.Role = otherRole

	var fullName, nickname, gender, phone string
	err = s.DB.QueryRow(ctx, `
		SELECT COALESCE(full_name, ''), COALESCE(nickname, ''), COALESCE(gender, ''), COALESCE(phone, '')
		FROM users
		WHERE id = $1
	`, otherUserID).Scan(&fullName, &nickname, &gender, &phone)
	if err == nil {
		otherSummary.FullName = fullName
		otherSummary.Nickname = nickname
		otherSummary.Gender = gender
		if bookingStatus == "confirmed" || bookingStatus == "completed" {
			otherSummary.Phone = phone
		}
	}

	// Calculate other user rating
	var avgRating float64
	_ = s.DB.QueryRow(ctx, `
		SELECT COALESCE(AVG(rating), 5.0)
		FROM ratings
		WHERE rated_user_id = $1
	`, otherUserID).Scan(&avgRating)
	otherSummary.Rating = avgRating

	// 5. Unread count for current user
	var unreadCount int
	_ = s.DB.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM chat_messages
		WHERE conversation_id = $1
		  AND is_read = false
		  AND (sender_id != $2 OR sender_id IS NULL)
	`, convID, userID).Scan(&unreadCount)

	// 6. Last message
	var lastMsg *models.ChatMessage
	var lm models.ChatMessage
	err = s.DB.QueryRow(ctx, `
		SELECT id, conversation_id, sender_id, sender_role, message_type, content, client_message_id, is_read, read_at, created_at
		FROM chat_messages
		WHERE conversation_id = $1
		ORDER BY created_at DESC
		LIMIT 1
	`, convID).Scan(
		&lm.ID, &lm.ConversationID, &lm.SenderID, &lm.SenderRole, &lm.MessageType,
		&lm.Content, &lm.ClientMessageID, &lm.IsRead, &lm.ReadAt, &lm.CreatedAt,
	)
	if err == nil {
		lastMsg = &lm
	}

	return &models.ChatConversationItem{
		ID:               convID,
		RideID:           rideID,
		BookingID:        bookingID,
		Status:           status,
		LastMessageAt:    lastMessageAt,
		OtherParticipant: otherSummary,
		Ride: models.ChatRideSummary{
			ID:            rideID,
			FromLocation:  fromLocation,
			ToLocation:    toLocation,
			JourneyDate:   rideDate.Format("2006-01-02"),
			DepartureTime: rideTime,
			PricePerSeat:  pricePerSeat,
			Status:        rideStatus,
			IsWomenOnly:   isWomenOnly,
		},
		BookingStatus:    bookingStatus,
		UnreadCount:      unreadCount,
		LastMessage:      lastMsg,
		IsProtected:      isProtected,
		ProtectionReason: protectionReason,
	}, nil
}

// ListConversations returns all active and recent chat conversations for the user.
func (s *ChatService) ListConversations(ctx context.Context, userID string) ([]models.ChatConversationItem, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT c.id, c.ride_id, c.booking_id, c.driver_id, c.passenger_id, c.status, c.last_message_at,
		       b.status AS booking_status,
		       r.from_location, r.to_location, r.journey_date, r.departure_time::text, r.price_per_seat, r.status AS ride_status, r.is_women_only,
		       u_other.id AS other_id, COALESCE(u_other.full_name, '') AS other_name,
		       COALESCE(u_other.nickname, '') AS other_nickname, COALESCE(u_other.gender, '') AS other_gender,
		       COALESCE(u_other.phone, '') AS other_phone,
		       CASE WHEN c.driver_id = $1 THEN 'passenger' ELSE 'driver' END AS other_role,
		       COALESCE((
		           SELECT COUNT(*) FROM chat_messages m
		           WHERE m.conversation_id = c.id
		             AND m.is_read = false
		             AND (m.sender_id != $1 OR m.sender_id IS NULL)
		       ), 0) AS unread_count,
		       c.is_protected, c.protection_reason
		FROM chat_conversations c
		JOIN bookings b ON b.id = c.booking_id
		JOIN rides r ON r.id = c.ride_id
		JOIN users u_other ON u_other.id = CASE WHEN c.driver_id = $1 THEN c.passenger_id ELSE c.driver_id END
		WHERE (c.driver_id = $1 OR c.passenger_id = $1)
		  AND r.status != 'completed'
		  AND b.status != 'completed'
		  AND c.status != 'completed'
		ORDER BY c.last_message_at DESC
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to list conversations: %w", err)
	}
	defer rows.Close()

	var items []models.ChatConversationItem
	for rows.Next() {
		var (
			convID           string
			rideID           string
			bookingID        string
			driverID         string
			passengerID      string
			status           string
			lastMessageAt    time.Time
			bookingStatus    string
			fromLocation     string
			toLocation       string
			rideDate         time.Time
			rideTime         string
			pricePerSeat     float64
			rideStatus       string
			isWomenOnly      bool
			otherID          string
			otherName        string
			otherNickname    string
			otherGender      string
			otherPhone       string
			otherRole        string
			unreadCount      int
			isProtected      bool
			protectionReason *string
		)

		if err := rows.Scan(
			&convID, &rideID, &bookingID, &driverID, &passengerID, &status, &lastMessageAt,
			&bookingStatus, &fromLocation, &toLocation, &rideDate, &rideTime, &pricePerSeat, &rideStatus, &isWomenOnly,
			&otherID, &otherName, &otherNickname, &otherGender, &otherPhone, &otherRole, &unreadCount,
			&isProtected, &protectionReason,
		); err != nil {
			return nil, fmt.Errorf("failed to scan conversation item: %w", err)
		}

		itemOtherPhone := ""
		if bookingStatus == "confirmed" || bookingStatus == "completed" {
			itemOtherPhone = otherPhone
		}

		item := models.ChatConversationItem{
			ID:            convID,
			RideID:        rideID,
			BookingID:     bookingID,
			Status:        status,
			LastMessageAt: lastMessageAt,
			OtherParticipant: models.ChatParticipantSummary{
				ID:       otherID,
				FullName: otherName,
				Nickname: otherNickname,
				Gender:   otherGender,
				Phone:    itemOtherPhone,
				Role:     otherRole,
				Rating:   5.0, // default rating
			},
			Ride: models.ChatRideSummary{
				ID:            rideID,
				FromLocation:  fromLocation,
				ToLocation:    toLocation,
				JourneyDate:   rideDate.Format("2006-01-02"),
				DepartureTime: rideTime,
				PricePerSeat:  pricePerSeat,
				Status:        rideStatus,
				IsWomenOnly:   isWomenOnly,
			},
			BookingStatus:    bookingStatus,
			UnreadCount:      unreadCount,
			IsProtected:      isProtected,
			ProtectionReason: protectionReason,
		}

		// Retrieve latest message preview for this conversation
		var lm models.ChatMessage
		err = s.DB.QueryRow(ctx, `
			SELECT id, conversation_id, sender_id, sender_role, message_type, content, client_message_id, is_read, read_at, created_at
			FROM chat_messages
			WHERE conversation_id = $1
			ORDER BY created_at DESC
			LIMIT 1
		`, convID).Scan(
			&lm.ID, &lm.ConversationID, &lm.SenderID, &lm.SenderRole, &lm.MessageType,
			&lm.Content, &lm.ClientMessageID, &lm.IsRead, &lm.ReadAt, &lm.CreatedAt,
		)
		if err == nil {
			item.LastMessage = &lm
		}

		items = append(items, item)
	}

	return items, nil
}

// GetConversationByID returns a single conversation item after verifying participation.
func (s *ChatService) GetConversationByID(ctx context.Context, userID, convID string) (*models.ChatConversationItem, error) {
	var bookingID string
	err := s.DB.QueryRow(ctx, `
		SELECT booking_id 
		FROM chat_conversations 
		WHERE id = $1 AND (driver_id = $2 OR passenger_id = $2)
	`, convID, userID).Scan(&bookingID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("conversation not found or access denied")
		}
		return nil, err
	}

	return s.GetOrCreateConversation(ctx, userID, bookingID)
}

// GetMessages returns paginated messages for an authorized participant.
func (s *ChatService) GetMessages(ctx context.Context, userID, convID string, limit, offset int) ([]models.ChatMessage, error) {
	// Verify membership
	var exists bool
	err := s.DB.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM chat_conversations
			WHERE id = $1 AND (driver_id = $2 OR passenger_id = $2)
		)
	`, convID, userID).Scan(&exists)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, fmt.Errorf("conversation not found or access denied")
	}

	if limit <= 0 {
		limit = 50
	}
	if limit > 100 {
		limit = 100
	}
	if offset < 0 {
		offset = 0
	}

	rows, err := s.DB.Query(ctx, `
		SELECT id, conversation_id, sender_id, sender_role, message_type, content, client_message_id, is_read, read_at, created_at
		FROM chat_messages
		WHERE conversation_id = $1
		ORDER BY created_at ASC
		LIMIT $2 OFFSET $3
	`, convID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch messages: %w", err)
	}
	defer rows.Close()

	var msgs []models.ChatMessage
	for rows.Next() {
		var m models.ChatMessage
		if err := rows.Scan(
			&m.ID, &m.ConversationID, &m.SenderID, &m.SenderRole, &m.MessageType,
			&m.Content, &m.ClientMessageID, &m.IsRead, &m.ReadAt, &m.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("failed to scan message: %w", err)
		}
		msgs = append(msgs, m)
	}

	return msgs, nil
}

// SendMessage validates authorization, booking lifecycle, blocks, saves message, and notifies recipient.
func (s *ChatService) SendMessage(ctx context.Context, senderID, convID string, req models.SendMessageRequest) (*models.ChatMessage, error) {
	cleanContent := strings.TrimSpace(req.Content)
	if cleanContent == "" {
		return nil, fmt.Errorf("message content cannot be empty")
	}
	if len(cleanContent) > 1000 {
		return nil, fmt.Errorf("message is too long (maximum 1000 characters)")
	}

	msgType := strings.TrimSpace(strings.ToLower(req.MessageType))
	if msgType == "" {
		msgType = "text"
	}
	if msgType != "text" && msgType != "quick_reply" && msgType != "system" && msgType != "location" {
		msgType = "text"
	}

	// 1. Fetch conversation details & verify membership
	var (
		rideID        string
		bookingID     string
		driverID      string
		passengerID   string
		convStatus    string
		bookingStatus string
		rideStatus    string
		rideCompletedAt *time.Time
	)

	err := s.DB.QueryRow(ctx, `
		SELECT c.ride_id, c.booking_id, c.driver_id, c.passenger_id, c.status,
		       b.status AS booking_status, r.status AS ride_status, r.updated_at
		FROM chat_conversations c
		JOIN bookings b ON b.id = c.booking_id
		JOIN rides r ON r.id = c.ride_id
		WHERE c.id = $1
	`, convID).Scan(
		&rideID, &bookingID, &driverID, &passengerID, &convStatus,
		&bookingStatus, &rideStatus, &rideCompletedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("conversation not found")
		}
		return nil, fmt.Errorf("failed to load conversation: %w", err)
	}

	if senderID != driverID && senderID != passengerID {
		return nil, fmt.Errorf("unauthorized: you are not a participant in this conversation")
	}

	// Determine sender role & recipient
	var senderRole string
	var recipientID string
	if senderID == driverID {
		senderRole = "driver"
		recipientID = passengerID
	} else {
		senderRole = "passenger"
		recipientID = driverID
	}

	// 2. Lifecycle validation: Cancelled or completed rides cannot send messages
	if bookingStatus == "cancelled" || bookingStatus == "completed" || convStatus == "read_only" || convStatus == "completed" || rideStatus == "completed" {
		return nil, fmt.Errorf("cannot send messages: this ride or booking has already been completed or closed")
	}

	// 3. User block check
	var isBlocked bool
	err = s.DB.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM user_blocks
			WHERE (blocker_id = $1 AND blocked_id = $2)
			   OR (blocker_id = $2 AND blocked_id = $1)
		)
	`, senderID, recipientID).Scan(&isBlocked)
	if err == nil && isBlocked {
		return nil, fmt.Errorf("unable to send message: communication with this user is restricted")
	}

	// 4. Idempotency check with client_message_id
	if req.ClientMessageID != nil && *req.ClientMessageID != "" {
		var existing models.ChatMessage
		err = s.DB.QueryRow(ctx, `
			SELECT id, conversation_id, sender_id, sender_role, message_type, content, client_message_id, is_read, read_at, created_at
			FROM chat_messages
			WHERE conversation_id = $1 AND client_message_id = $2
		`, convID, *req.ClientMessageID).Scan(
			&existing.ID, &existing.ConversationID, &existing.SenderID, &existing.SenderRole,
			&existing.MessageType, &existing.Content, &existing.ClientMessageID,
			&existing.IsRead, &existing.ReadAt, &existing.CreatedAt,
		)
		if err == nil {
			// Already saved, return idempotently
			return &existing, nil
		}
	}

	// 5. Insert message atomically
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	var msg models.ChatMessage
	err = tx.QueryRow(ctx, `
		INSERT INTO chat_messages (
			conversation_id, sender_id, sender_role, message_type, content, client_message_id
		) VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, conversation_id, sender_id, sender_role, message_type, content, client_message_id, is_read, read_at, created_at
	`, convID, senderID, senderRole, msgType, cleanContent, req.ClientMessageID).Scan(
		&msg.ID, &msg.ConversationID, &msg.SenderID, &msg.SenderRole, &msg.MessageType,
		&msg.Content, &msg.ClientMessageID, &msg.IsRead, &msg.ReadAt, &msg.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to insert message: %w", err)
	}

	// Update conversation last_message_at
	_, err = tx.Exec(ctx, `
		UPDATE chat_conversations
		SET last_message_at = NOW(), updated_at = NOW()
		WHERE id = $1
	`, convID)
	if err != nil {
		return nil, fmt.Errorf("failed to update conversation timestamp: %w", err)
	}

	// 6. Create in-app notification for the recipient
	var senderName string
	_ = tx.QueryRow(ctx, `
		SELECT COALESCE(NULLIF(nickname, ''), full_name, 'A user')
		FROM users
		WHERE id = $1
	`, senderID).Scan(&senderName)

	preview := cleanContent
	if msgType == "location" {
		preview = "📍 Shared current location"
	} else if len(preview) > 80 {
		preview = preview[:77] + "..."
	}

	notifTitle := fmt.Sprintf("Message from %s", senderName)
	notifBody := preview
	_, _ = tx.Exec(ctx, `
		INSERT INTO notifications (user_id, type, title, message, ride_id, booking_id)
		VALUES ($1, 'chat_message', $2, $3, $4, $5)
	`, recipientID, notifTitle, notifBody, rideID, bookingID)

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit message transaction: %w", err)
	}

	if s.NotificationService != nil {
		s.NotificationService.SendPush(ctx, recipientID, "chat_message", notifTitle, notifBody, map[string]string{
			"ride_id":         rideID,
			"booking_id":      bookingID,
			"conversation_id": convID,
		})
	}

	return &msg, nil
}

// MarkMessagesAsRead marks all incoming messages in a conversation as read.
func (s *ChatService) MarkMessagesAsRead(ctx context.Context, userID, convID string) (int, error) {
	// Verify membership
	var bookingID string
	err := s.DB.QueryRow(ctx, `
		SELECT booking_id 
		FROM chat_conversations 
		WHERE id = $1 AND (driver_id = $2 OR passenger_id = $2)
	`, convID, userID).Scan(&bookingID)
	if err != nil {
		return 0, fmt.Errorf("conversation not found or access denied")
	}

	// Mark messages read
	cmd, err := s.DB.Exec(ctx, `
		UPDATE chat_messages
		SET is_read = true, read_at = NOW()
		WHERE conversation_id = $1
		  AND is_read = false
		  AND (sender_id != $2 OR sender_id IS NULL)
	`, convID, userID)
	if err != nil {
		return 0, fmt.Errorf("failed to mark messages as read: %w", err)
	}

	// Also mark chat notifications for this booking as read
	_, _ = s.DB.Exec(ctx, `
		UPDATE notifications
		SET is_read = true
		WHERE user_id = $1 AND type = 'chat_message' AND booking_id = $2 AND is_read = false
	`, userID, bookingID)

	return int(cmd.RowsAffected()), nil
}

// GetUnreadCount returns total unread chat messages for a user across all active conversations.
func (s *ChatService) GetUnreadCount(ctx context.Context, userID string) (int, error) {
	var total int
	err := s.DB.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM chat_messages m
		JOIN chat_conversations c ON c.id = m.conversation_id
		JOIN rides r ON r.id = c.ride_id
		JOIN bookings b ON b.id = c.booking_id
		WHERE (c.driver_id = $1 OR c.passenger_id = $1)
		  AND r.status != 'completed'
		  AND b.status != 'completed'
		  AND c.status != 'completed'
		  AND m.is_read = false
		  AND (m.sender_id != $1 OR m.sender_id IS NULL)
	`, userID).Scan(&total)
	if err != nil {
		return 0, err
	}
	return total, nil
}

// BlockUser blocks another user from sending chat messages and atomically protects their conversations from 7-day cleanup.
func (s *ChatService) BlockUser(ctx context.Context, blockerID string, req models.BlockUserRequest) error {
	targetID := strings.TrimSpace(req.UserID)
	if targetID == "" {
		return fmt.Errorf("user_id is required")
	}
	if blockerID == targetID {
		return fmt.Errorf("cannot block yourself")
	}

	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO user_blocks (blocker_id, blocked_id, reason)
		VALUES ($1, $2, $3)
		ON CONFLICT (blocker_id, blocked_id) DO NOTHING
	`, blockerID, targetID, strings.TrimSpace(req.Reason))
	if err != nil {
		return err
	}

	// Atomically protect all conversations between these users from 7-day retention cleanup
	_, err = tx.Exec(ctx, `
		UPDATE chat_conversations
		SET is_protected = TRUE,
		    protection_reason = CASE
		        WHEN protection_reason IS NULL OR protection_reason = '' THEN 'blocked'
		        WHEN protection_reason NOT LIKE '%blocked%' THEN protection_reason || ',blocked'
		        ELSE protection_reason
		    END,
		    protected_at = COALESCE(protected_at, NOW()),
		    updated_at = NOW()
		WHERE (driver_id = $1 AND passenger_id = $2)
		   OR (driver_id = $2 AND passenger_id = $1)
	`, blockerID, targetID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// ReportUser files a user report for safety review and atomically protects their conversations from 7-day cleanup.
func (s *ChatService) ReportUser(ctx context.Context, reporterID string, req models.ReportUserRequest) error {
	targetID := strings.TrimSpace(req.UserID)
	if targetID == "" {
		return fmt.Errorf("user_id is required")
	}
	if reporterID == targetID {
		return fmt.Errorf("cannot report yourself")
	}

	reason := strings.TrimSpace(req.Reason)
	if reason == "" {
		reason = "Inappropriate behavior"
	}

	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO user_reports (reporter_id, reported_id, ride_id, conversation_id, reason, description)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, reporterID, targetID, req.RideID, req.ConversationID, reason, strings.TrimSpace(req.Description))
	if err != nil {
		return err
	}

	// Atomically protect conversation from 7-day retention cleanup
	_, err = tx.Exec(ctx, `
		UPDATE chat_conversations
		SET is_protected = TRUE,
		    protection_reason = CASE
		        WHEN protection_reason IS NULL OR protection_reason = '' THEN 'reported'
		        WHEN protection_reason NOT LIKE '%reported%' THEN protection_reason || ',reported'
		        ELSE protection_reason
		    END,
		    protected_at = COALESCE(protected_at, NOW()),
		    updated_at = NOW()
		WHERE (id = $1 AND $1 IS NOT NULL)
		   OR (ride_id = $2 AND $2 IS NOT NULL)
		   OR ((driver_id = $3 AND passenger_id = $4) OR (driver_id = $4 AND passenger_id = $3))
	`, req.ConversationID, req.RideID, reporterID, targetID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// CleanupExpiredConversations invokes the database cleanup function to permanently
// delete conversations and messages for completed rides older than 7 days that are not protected by reports or blocks.
func (s *ChatService) CleanupExpiredConversations(ctx context.Context) (int, error) {
	var deletedCount int
	err := s.DB.QueryRow(ctx, `SELECT deleted_count FROM cleanup_expired_chat_conversations()`).Scan(&deletedCount)
	if err != nil {
		return 0, fmt.Errorf("failed to execute chat cleanup: %w", err)
	}
	return deletedCount, nil
}
