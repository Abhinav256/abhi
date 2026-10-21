package models

import "time"

type Rating struct {
	ID          string    `json:"id"`
	RideID      string    `json:"ride_id"`
	RaterID     string    `json:"rater_id"`
	RateeID     string    `json:"ratee_id"`
	RatingValue int       `json:"rating_value"` // 1 to 5
	Feedback    string    `json:"feedback,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type RatingItem struct {
	RateeID     string `json:"ratee_id"`
	RatingValue int    `json:"rating_value"` // 1 to 5
	Feedback    string `json:"feedback,omitempty"`
}

type SubmitRatingsRequest struct {
	RideID  string       `json:"ride_id"`
	Ratings []RatingItem `json:"ratings"`
}

type RatingParticipant struct {
	ID           string `json:"id"`
	FullName     string `json:"full_name"`
	PhotoURL     string `json:"photo_url,omitempty"`
	Role         string `json:"role"` // "driver" or "passenger"
	AlreadyRated bool   `json:"already_rated"`
}

type PendingRatingResponse struct {
	HasPendingRating bool                `json:"has_pending_rating"`
	RideID           string              `json:"ride_id,omitempty"`
	FromLocation     string              `json:"from_location,omitempty"`
	ToLocation       string              `json:"to_location,omitempty"`
	JourneyDate      string              `json:"journey_date,omitempty"`
	IsDriver         bool                `json:"is_driver,omitempty"`
	Participants     []RatingParticipant `json:"participants,omitempty"`
}

type UserRatingSummary struct {
	UserID        string   `json:"user_id"`
	AverageRating *float64 `json:"average_rating"`
	TotalRatings  int      `json:"total_ratings"`
}
