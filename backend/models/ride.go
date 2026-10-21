package models

import "time"

type Ride struct {
	ID                    string     `json:"id"`
	DriverID              string     `json:"driver_id"`
	VehicleID             string     `json:"vehicle_id"`
	FromLocation          string     `json:"from_location"`
	ToLocation            string     `json:"to_location"`
	PickupLatitude        *float64   `json:"pickup_latitude,omitempty"`
	PickupLongitude       *float64   `json:"pickup_longitude,omitempty"`
	DestinationLatitude   *float64   `json:"destination_latitude,omitempty"`
	DestinationLongitude  *float64   `json:"destination_longitude,omitempty"`
	RouteGeometry         any        `json:"route_geometry,omitempty"`
	RouteDistance         *float64   `json:"route_distance,omitempty"`
	RouteDuration         *float64   `json:"route_duration,omitempty"`
	RouteSummary          *string    `json:"route_summary,omitempty"`
	RouteWaypoints        any        `json:"route_waypoints,omitempty"`
	JourneyDate           time.Time  `json:"journey_date"`
	DepartureTime         time.Time  `json:"departure_time"`
	EstimatedArrivalTime  time.Time  `json:"estimated_arrival_time"`
	AvailableSeats        int        `json:"available_seats"`
	PricePerSeat          float64    `json:"price_per_seat"`
	UserAmount            float64    `json:"user_amount"`
	AppAmount             float64    `json:"app_amount"`
	TotalAmount           float64    `json:"total_amount"`
	Status                string     `json:"status"`
	DriverSelfieURL       string     `json:"driver_selfie_url"`
	DriverSelfieExpiresAt *time.Time `json:"driver_selfie_expires_at"`
	RecurringScheduleID   *string    `json:"recurring_schedule_id,omitempty"`
	IsWomenOnly           bool       `json:"is_women_only"`
	CreatedAt             time.Time  `json:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
}

type CreateRideRequest struct {
	DriverID             string   `json:"driver_id"`
	VehicleID            string   `json:"vehicle_id"`
	FromLocation         string   `json:"from_location"`
	ToLocation           string   `json:"to_location"`
	PickupLatitude       *float64 `json:"pickup_latitude,omitempty"`
	PickupLongitude      *float64 `json:"pickup_longitude,omitempty"`
	DestinationLatitude  *float64 `json:"destination_latitude,omitempty"`
	DestinationLongitude *float64 `json:"destination_longitude,omitempty"`
	RouteGeometry        any      `json:"route_geometry,omitempty"`
	RouteDistance        *float64 `json:"route_distance,omitempty"`
	RouteDuration        *float64 `json:"route_duration,omitempty"`
	RouteSummary         *string  `json:"route_summary,omitempty"`
	RouteWaypoints       any      `json:"route_waypoints,omitempty"`
	JourneyDate          string   `json:"journey_date"`
	DepartureTime        string   `json:"departure_time"`
	EstimatedArrivalTime string   `json:"estimated_arrival_time"`
	AvailableSeats       int      `json:"available_seats"`
	PricePerSeat         float64  `json:"price_per_seat"`
	IsWomenOnly          bool     `json:"is_women_only"`
}

// RideDetail contains ride data enriched with driver, vehicle, route, and passenger segment match information.
type RideDetail struct {
	ID                    string     `json:"id"`
	DriverID              string     `json:"driver_id"`
	VehicleID             string     `json:"vehicle_id"`
	FromLocation          string     `json:"from_location"`
	ToLocation            string     `json:"to_location"`
	PickupLatitude        *float64   `json:"pickup_latitude,omitempty"`
	PickupLongitude       *float64   `json:"pickup_longitude,omitempty"`
	DestinationLatitude   *float64   `json:"destination_latitude,omitempty"`
	DestinationLongitude  *float64   `json:"destination_longitude,omitempty"`
	RouteGeometry         any        `json:"route_geometry,omitempty"`
	RouteDistance         *float64   `json:"route_distance,omitempty"`
	RouteDuration         *float64   `json:"route_duration,omitempty"`
	RouteSummary          *string    `json:"route_summary,omitempty"`
	RouteWaypoints        any        `json:"route_waypoints,omitempty"`
	JourneyDate           time.Time  `json:"journey_date"`
	DepartureTime         time.Time  `json:"departure_time"`
	EstimatedArrivalTime  time.Time  `json:"estimated_arrival_time"`
	AvailableSeats        int        `json:"available_seats"`
	PricePerSeat          float64    `json:"price_per_seat"`
	UserAmount            float64    `json:"user_amount"`
	AppAmount             float64    `json:"app_amount"`
	TotalAmount           float64    `json:"total_amount"`
	Status                string     `json:"status"`
	DriverSelfieURL       string     `json:"driver_selfie_url"`
	DriverSelfieExpiresAt *time.Time `json:"driver_selfie_expires_at"`
	RecurringScheduleID   *string    `json:"recurring_schedule_id,omitempty"`
	IsWomenOnly           bool       `json:"is_women_only"`
	CreatedAt             time.Time  `json:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
	DriverName            string     `json:"driver_name"`
	DriverGender          string     `json:"driver_gender,omitempty"`
	DriverPhone           string     `json:"driver_phone,omitempty"`
	VehicleModel          string     `json:"vehicle_model"`
	VehicleNumber         string     `json:"vehicle_number"`
	VehicleType           string     `json:"vehicle_type"`
	VehiclePhotoURL       string     `json:"vehicle_photo_url"`

	// Passenger Segment Match Metadata (calculated automatically during search)
	IsRouteMatched          bool     `json:"is_route_matched,omitempty"`
	SegmentDistanceKm       float64  `json:"segment_distance_km,omitempty"`
	SegmentPricePerSeat     float64  `json:"segment_price_per_seat,omitempty"`
	SegmentUserAmount       float64  `json:"segment_user_amount,omitempty"`
	SegmentAppAmount        float64  `json:"segment_app_amount,omitempty"`
	SegmentTotalAmount      float64  `json:"segment_total_amount,omitempty"`
	PickupDistanceAlong     float64  `json:"pickup_distance_along_route,omitempty"`
	DropDistanceAlong       float64  `json:"drop_distance_along_route,omitempty"`
	AvailableSegmentSeats   int      `json:"available_segment_seats,omitempty"`
	PassengerPickupName     string   `json:"passenger_pickup_name,omitempty"`
	PassengerDropName       string   `json:"passenger_drop_name,omitempty"`
}
