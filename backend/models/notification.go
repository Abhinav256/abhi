package models

import "time"

type Notification struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Type      string    `json:"type"`
	Title     string    `json:"title"`
	Message   string    `json:"message"`
	RideID    *string   `json:"ride_id,omitempty"`
	BookingID *string   `json:"booking_id,omitempty"`
	IsRead    bool      `json:"is_read"`
	CreatedAt time.Time `json:"created_at"`
}

type NotificationDetail struct {
	Notification
	Ride    *RideDetail `json:"ride,omitempty"`
	Booking *Booking    `json:"booking,omitempty"`
}
