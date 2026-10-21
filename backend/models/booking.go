package models

import "time"

type BookingPassenger struct {
	ID              string    `json:"id"`
	BookingID       string    `json:"booking_id"`
	PassengerNumber int       `json:"passenger_number"`
	PassengerName   string    `json:"passenger_name"`
	PassengerAge    int       `json:"passenger_age"`
	PassengerGender string    `json:"passenger_gender"`
	PassengerPhone  *string   `json:"passenger_phone,omitempty"`
	CreatedAt       time.Time `json:"created_at"`
}

type PassengerInput struct {
	Name   string `json:"name"`
	Age    int    `json:"age"`
	Gender string `json:"gender"`
	Phone  string `json:"phone,omitempty"`
}

type Booking struct {
	ID                       string             `json:"id"`
	RideID                   string             `json:"ride_id"`
	PassengerID              string             `json:"passenger_id"`
	PassengerName            string             `json:"passenger_name"`
	PassengerAge             int                `json:"passenger_age"`
	PassengerGender          string             `json:"passenger_gender"`
	FromLocation             string             `json:"from_location,omitempty"`
	ToLocation               string             `json:"to_location,omitempty"`
	PickupLatitude           *float64           `json:"pickup_latitude,omitempty"`
	PickupLongitude          *float64           `json:"pickup_longitude,omitempty"`
	DestinationLatitude      *float64           `json:"destination_latitude,omitempty"`
	DestinationLongitude     *float64           `json:"destination_longitude,omitempty"`
	PickupDistanceAlongRoute *float64           `json:"pickup_distance_along_route,omitempty"`
	DropDistanceAlongRoute   *float64           `json:"drop_distance_along_route,omitempty"`
	PaymentMode              string             `json:"payment_mode"`
	Status                   string             `json:"status"`
	SeatsBooked              int                `json:"seats_booked"`
	TotalAmount              float64            `json:"total_amount"`
	DriverEarnings           float64            `json:"driver_earnings,omitempty"`
	PlatformCharge           float64            `json:"platform_charge,omitempty"`
	SettlementStatus         string             `json:"settlement_status,omitempty"`
	Passengers               []BookingPassenger `json:"passengers,omitempty"`
	CreatedAt                time.Time          `json:"created_at"`
	UpdatedAt                time.Time          `json:"updated_at"`
}

type CreateBookingRequest struct {
	RideID                   string           `json:"ride_id"`
	PassengerID              string           `json:"passenger_id"`
	SeatsBooked              int              `json:"seats_booked"`
	PassengerName            string           `json:"passenger_name"`
	PassengerAge             int              `json:"passenger_age"`
	PassengerGender          string           `json:"passenger_gender"`
	FromLocation             string           `json:"from_location,omitempty"`
	ToLocation               string           `json:"to_location,omitempty"`
	PickupLatitude           *float64         `json:"pickup_latitude,omitempty"`
	PickupLongitude          *float64         `json:"pickup_longitude,omitempty"`
	DestinationLatitude      *float64         `json:"destination_latitude,omitempty"`
	DestinationLongitude     *float64         `json:"destination_longitude,omitempty"`
	PickupDistanceAlongRoute *float64         `json:"pickup_distance_along_route,omitempty"`
	DropDistanceAlongRoute   *float64         `json:"drop_distance_along_route,omitempty"`
	PaymentMode              string           `json:"payment_mode"`
	Passengers               []PassengerInput `json:"passengers"`
}

// BookingWithRide contains booking data enriched with ride information.
type BookingWithRide struct {
	ID                       string             `json:"id"`
	RideID                   string             `json:"ride_id"`
	PassengerID              string             `json:"passenger_id"`
	PassengerName            string             `json:"passenger_name"`
	PassengerAge             int                `json:"passenger_age"`
	PassengerGender          string             `json:"passenger_gender"`
	PaymentMode              string             `json:"payment_mode"`
	Status                   string             `json:"status"`
	SeatsBooked              int                `json:"seats_booked"`
	TotalAmount              float64            `json:"total_amount"`
	Passengers               []BookingPassenger `json:"passengers,omitempty"`
	CreatedAt                time.Time          `json:"created_at"`
	UpdatedAt                time.Time          `json:"updated_at"`
	FromLocation             string             `json:"from_location"`
	ToLocation               string             `json:"to_location"`
	PickupLatitude           *float64           `json:"pickup_latitude,omitempty"`
	PickupLongitude          *float64           `json:"pickup_longitude,omitempty"`
	DestinationLatitude      *float64           `json:"destination_latitude,omitempty"`
	DestinationLongitude     *float64           `json:"destination_longitude,omitempty"`
	PickupDistanceAlongRoute *float64           `json:"pickup_distance_along_route,omitempty"`
	DropDistanceAlongRoute   *float64           `json:"drop_distance_along_route,omitempty"`
	JourneyDate              time.Time          `json:"journey_date"`
	DepartureTime            time.Time          `json:"departure_time"`
	PricePerSeat             float64            `json:"price_per_seat"`
	RideStatus               string             `json:"ride_status"`
	DriverSelfieURL          string             `json:"driver_selfie_url"`
	DriverName               string             `json:"driver_name"`
	DriverPhone              string             `json:"driver_phone,omitempty"`
	IsWomenOnly              bool               `json:"is_women_only"`
}

type BookingContactResponse struct {
	BookingID   string `json:"booking_id"`
	ContactName string `json:"contact_name"`
	Phone       string `json:"phone"`
	Role        string `json:"role"`
}
