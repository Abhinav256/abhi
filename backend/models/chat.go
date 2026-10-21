package models

import (
	"time"
)

// ChatConversation represents a 1-to-1 conversation between a ride driver and passenger for a specific booking.
type ChatConversation struct {
	ID            string    `json:"id"`
	RideID        string    `json:"ride_id"`
	BookingID     string    `json:"booking_id"`
	DriverID      string    `json:"driver_id"`
	PassengerID   string    `json:"passenger_id"`
	Status        string    `json:"status"` // 'active', 'archived', 'read_only'
	LastMessageAt time.Time `json:"last_message_at"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// ChatParticipantSummary provides profile and contact info of the other participant in confirmed bookings.
type ChatParticipantSummary struct {
	ID              string  `json:"id"`
	FullName        string  `json:"full_name"`
	Nickname        string  `json:"nickname"`
	Gender          string  `json:"gender"`
	Rating          float64 `json:"rating"`
	ProfilePhotoURL *string `json:"profile_photo_url,omitempty"`
	Role            string  `json:"role"` // "driver" or "passenger"
	Phone           string  `json:"phone,omitempty"`
}

// ChatRideSummary provides read-only journey context for the chat.
type ChatRideSummary struct {
	ID            string  `json:"id"`
	FromLocation  string  `json:"from_location"`
	ToLocation    string  `json:"to_location"`
	JourneyDate   string  `json:"journey_date"`
	DepartureTime string  `json:"departure_time"`
	PricePerSeat  float64 `json:"price_per_seat"`
	Status        string  `json:"status"`
	IsWomenOnly   bool    `json:"is_women_only"`
}

// ChatConversationItem represents a conversation card in the conversation list.
type ChatConversationItem struct {
	ID               string                 `json:"id"`
	RideID           string                 `json:"ride_id"`
	BookingID        string                 `json:"booking_id"`
	Status           string                 `json:"status"`
	LastMessageAt    time.Time              `json:"last_message_at"`
	OtherParticipant ChatParticipantSummary `json:"other_participant"`
	Ride             ChatRideSummary        `json:"ride"`
	BookingStatus    string                 `json:"booking_status"`
	UnreadCount      int                    `json:"unread_count"`
	LastMessage      *ChatMessage           `json:"last_message,omitempty"`
	IsProtected      bool                   `json:"is_protected"`
	ProtectionReason *string                `json:"protection_reason,omitempty"`
}

// ChatMessage represents a single persistent message in a conversation.
type ChatMessage struct {
	ID              string     `json:"id"`
	ConversationID  string     `json:"conversation_id"`
	SenderID        *string    `json:"sender_id,omitempty"`
	SenderRole      string     `json:"sender_role"` // 'driver', 'passenger', 'system'
	MessageType     string     `json:"message_type"` // 'text', 'system', 'quick_reply'
	Content         string     `json:"content"`
	ClientMessageID *string    `json:"client_message_id,omitempty"`
	IsRead          bool       `json:"is_read"`
	ReadAt          *time.Time `json:"read_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
}

// Request and response models
type GetOrCreateConversationRequest struct {
	BookingID string `json:"booking_id"`
}

type SendMessageRequest struct {
	Content         string  `json:"content"`
	MessageType     string  `json:"message_type,omitempty"` // default 'text'
	ClientMessageID *string `json:"client_message_id,omitempty"`
}

type BlockUserRequest struct {
	UserID string `json:"user_id"`
	Reason string `json:"reason,omitempty"`
}

type ReportUserRequest struct {
	UserID         string  `json:"user_id"`
	RideID         *string `json:"ride_id,omitempty"`
	ConversationID *string `json:"conversation_id,omitempty"`
	Reason         string  `json:"reason"`
	Description    string  `json:"description,omitempty"`
}

type UnreadCountResponse struct {
	TotalUnread int `json:"total_unread"`
}
