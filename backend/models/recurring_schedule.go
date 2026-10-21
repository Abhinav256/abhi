package models

import "time"

type RecurringSchedule struct {
	ID               string                 `json:"id"`
	UserID           string                 `json:"user_id"`
	RecurrenceType   string                 `json:"recurrence_type"` // daily, weekly, biweekly, custom
	SelectedWeekdays []string               `json:"selected_weekdays"`
	StartDate        string                 `json:"start_date"`
	EndDate          *string                `json:"end_date,omitempty"`
	OccurrenceCount  *int                   `json:"occurrence_count,omitempty"`
	RideTemplate     map[string]interface{} `json:"ride_template"`
	Status           string                 `json:"status"` // draft, active, paused, cancelled
	CreatedAt        time.Time              `json:"created_at"`
	UpdatedAt        time.Time              `json:"updated_at"`

	// Enriched fields for responses
	TotalRides     int          `json:"total_rides"`
	ActiveRides    int          `json:"active_rides"`
	CompletedRides int          `json:"completed_rides"`
	CancelledRides int          `json:"cancelled_rides"`
	Rides          []RideDetail `json:"rides,omitempty"`
}

type CreateRecurringScheduleRequest struct {
	VehicleID            string   `json:"vehicle_id"`
	FromLocation         string   `json:"from_location"`
	ToLocation           string   `json:"to_location"`
	DepartureTime        string   `json:"departure_time"`
	EstimatedArrivalTime string   `json:"estimated_arrival_time"`
	AvailableSeats       int      `json:"available_seats"`
	PricePerSeat         float64  `json:"price_per_seat"`
	IsWomenOnly          bool     `json:"is_women_only"`
	RecurrenceType       string   `json:"recurrence_type"` // daily, weekly, biweekly, custom
	SelectedWeekdays     []string `json:"selected_weekdays"`
	StartDate            string   `json:"start_date"`
	EndDate              *string  `json:"end_date,omitempty"`
	OccurrenceCount      *int     `json:"occurrence_count,omitempty"`
}

type UpdateRecurringScheduleRequest struct {
	AvailableSeats *int     `json:"available_seats,omitempty"`
	PricePerSeat   *float64 `json:"price_per_seat,omitempty"`
	EndDate        *string  `json:"end_date,omitempty"`
}
