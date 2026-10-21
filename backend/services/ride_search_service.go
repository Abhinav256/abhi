package services

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/config"
	"github.com/abhishare16/Abhi-Share/backend/models"
)

type RideSearchService struct {
	DB     *pgxpool.Pool
	Config *config.Config
}

func NewRideSearchService(db *pgxpool.Pool, cfg *config.Config) *RideSearchService {
	return &RideSearchService{
		DB:     db,
		Config: cfg,
	}
}

func (s *RideSearchService) SearchRides(
	ctx context.Context,
	fromLocation string,
	toLocation string,
	journeyDate string,
	fromLat, fromLon, toLat, toLon *float64,
) ([]models.RideDetail, error) {

	hasCoords := fromLat != nil && fromLon != nil && toLat != nil && toLon != nil &&
		(*fromLat != 0 || *fromLon != 0) && (*toLat != 0 || *toLon != 0)

	// If coordinates are provided, we perform automatic route geometry matching
	if hasCoords {
		return s.searchRidesWithRouteMatching(
			ctx,
			fromLocation,
			toLocation,
			journeyDate,
			*fromLat, *fromLon, *toLat, *toLon,
		)
	}

	// Fallback to text-based matching if coordinates are not supplied
	return s.searchRidesLegacyText(ctx, fromLocation, toLocation, journeyDate)
}

func (s *RideSearchService) searchRidesWithRouteMatching(
	ctx context.Context,
	fromLocation string,
	toLocation string,
	journeyDate string,
	fromLat, fromLon, toLat, toLon float64,
) ([]models.RideDetail, error) {
	extraPayPct := 4.0
	if s.Config != nil && s.Config.ExtraPayPercent >= 0 {
		extraPayPct = s.Config.ExtraPayPercent
	}

	rows, err := s.DB.Query(
		ctx,
		`SELECT
			r.id,
			r.driver_id,
			r.vehicle_id,
			r.from_location,
			r.to_location,
			r.pickup_latitude,
			r.pickup_longitude,
			r.destination_latitude,
			r.destination_longitude,
			r.route_geometry,
			r.route_distance,
			r.route_duration,
			r.route_summary,
			r.route_waypoints,
			r.journey_date,
			r.departure_time,
			r.estimated_arrival_time,
			r.available_seats,
			r.price_per_seat,
			r.user_amount,
			r.app_amount,
			r.total_amount,
			r.status,
			COALESCE(r.driver_selfie_url, ''),
			r.driver_selfie_expires_at,
			r.is_women_only,
			r.created_at,
			r.updated_at,
			u.full_name,
			u.gender,
			v.model,
			v.vehicle_number,
			v.vehicle_type,
			COALESCE(v.vehicle_photo_url, '')
		FROM rides r
		INNER JOIN users u ON u.id = r.driver_id
		INNER JOIN vehicles v ON v.id = r.vehicle_id
		WHERE r.journey_date = $1
		  AND r.status = 'active'
		ORDER BY r.departure_time ASC`,
		journeyDate,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var matchedRides []models.RideDetail

	for rows.Next() {
		var ride models.RideDetail
		var rawGeometry []byte
		var rawWaypoints []byte

		err := rows.Scan(
			&ride.ID,
			&ride.DriverID,
			&ride.VehicleID,
			&ride.FromLocation,
			&ride.ToLocation,
			&ride.PickupLatitude,
			&ride.PickupLongitude,
			&ride.DestinationLatitude,
			&ride.DestinationLongitude,
			&rawGeometry,
			&ride.RouteDistance,
			&ride.RouteDuration,
			&ride.RouteSummary,
			&rawWaypoints,
			&ride.JourneyDate,
			&ride.DepartureTime,
			&ride.EstimatedArrivalTime,
			&ride.AvailableSeats,
			&ride.PricePerSeat,
			&ride.UserAmount,
			&ride.AppAmount,
			&ride.TotalAmount,
			&ride.Status,
			&ride.DriverSelfieURL,
			&ride.DriverSelfieExpiresAt,
			&ride.IsWomenOnly,
			&ride.CreatedAt,
			&ride.UpdatedAt,
			&ride.DriverName,
			&ride.DriverGender,
			&ride.VehicleModel,
			&ride.VehicleNumber,
			&ride.VehicleType,
			&ride.VehiclePhotoURL,
		)
		if err != nil {
			return nil, err
		}

		if len(rawGeometry) > 0 {
			var geom any
			if err := json.Unmarshal(rawGeometry, &geom); err == nil {
				ride.RouteGeometry = geom
			}
		}
		if len(rawWaypoints) > 0 {
			var wps any
			if err := json.Unmarshal(rawWaypoints, &wps); err == nil {
				ride.RouteWaypoints = wps
			}
		}

		// Try geometric polyline matching if route_geometry is present
		isMatched := false
		var matchResult RouteMatchResult

		if len(rawGeometry) > 0 {
			var coords [][]float64
			if err := json.Unmarshal(rawGeometry, &coords); err == nil && len(coords) >= 2 {
				matchResult = MatchRouteSegment(coords, fromLat, fromLon, toLat, toLon, 10000.0) // 10 km tolerance
				if matchResult.IsMatched {
					isMatched = true
				}
			}
		}

		// Calculate vehicle capacity
		maxSeats := 4
		switch ride.VehicleType {
		case "two_wheeler":
			maxSeats = 1
		case "five_seater":
			maxSeats = 4
		case "seven_seater":
			maxSeats = 6
		default:
			if ride.AvailableSeats > maxSeats {
				maxSeats = ride.AvailableSeats
			}
		}

		if isMatched {
			// Fetch confirmed bookings for this ride to check segment capacity
			bRows, bErr := s.DB.Query(
				ctx,
				`SELECT id, seats_booked, COALESCE(pickup_distance_along_route, 0), COALESCE(drop_distance_along_route, 0)
				 FROM bookings
				 WHERE ride_id = $1 AND status = 'confirmed'`,
				ride.ID,
			)
			var existingBookings []BookingSegment
			if bErr == nil {
				for bRows.Next() {
					var bs BookingSegment
					if err := bRows.Scan(&bs.BookingID, &bs.SeatsBooked, &bs.PickupDistanceAlong, &bs.DropDistanceAlong); err == nil {
						existingBookings = append(existingBookings, bs)
					}
				}
				bRows.Close()
			}

			isAvail, availSeats, _ := CheckSegmentCapacity(
				maxSeats,
				existingBookings,
				matchResult.PickupDistanceMeters,
				matchResult.DropDistanceMeters,
				1,
			)

			if isAvail && availSeats > 0 {
				segUser, segApp, segTotal := ComputeSegmentPricing(ride.UserAmount, matchResult.SegmentRatio, extraPayPct)

				ride.IsRouteMatched = true
				ride.SegmentDistanceKm = matchResult.SegmentDistanceKm
				ride.SegmentPricePerSeat = segTotal
				ride.SegmentUserAmount = segUser
				ride.SegmentAppAmount = segApp
				ride.SegmentTotalAmount = segTotal
				ride.PickupDistanceAlong = matchResult.PickupDistanceMeters
				ride.DropDistanceAlong = matchResult.DropDistanceMeters
				ride.AvailableSegmentSeats = availSeats
				ride.AvailableSeats = availSeats
				ride.PassengerPickupName = fromLocation
				ride.PassengerDropName = toLocation

				matchedRides = append(matchedRides, ride)
				continue
			}
		}

		// Fallback check: if locations textually match the driver's full route
		normFrom := strings.ToLower(strings.TrimSpace(fromLocation))
		normTo := strings.ToLower(strings.TrimSpace(toLocation))
		rFrom := strings.ToLower(strings.TrimSpace(ride.FromLocation))
		rTo := strings.ToLower(strings.TrimSpace(ride.ToLocation))

		if (normFrom == rFrom || strings.Contains(rFrom, normFrom) || strings.Contains(normFrom, rFrom)) &&
			(normTo == rTo || strings.Contains(rTo, normTo) || strings.Contains(normTo, rTo)) &&
			ride.AvailableSeats > 0 {
			ride.IsRouteMatched = false
			matchedRides = append(matchedRides, ride)
		}
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	if matchedRides == nil {
		matchedRides = []models.RideDetail{}
	}

	return matchedRides, nil
}

func (s *RideSearchService) searchRidesLegacyText(
	ctx context.Context,
	fromLocation string,
	toLocation string,
	journeyDate string,
) ([]models.RideDetail, error) {
	rows, err := s.DB.Query(
		ctx,
		`SELECT
			r.id,
			r.driver_id,
			r.vehicle_id,
			r.from_location,
			r.to_location,
			r.pickup_latitude,
			r.pickup_longitude,
			r.destination_latitude,
			r.destination_longitude,
			r.route_geometry,
			r.route_distance,
			r.route_duration,
			r.route_summary,
			r.route_waypoints,
			r.journey_date,
			r.departure_time,
			r.estimated_arrival_time,
			r.available_seats,
			r.price_per_seat,
			r.user_amount,
			r.app_amount,
			r.total_amount,
			r.status,
			COALESCE(r.driver_selfie_url, ''),
			r.driver_selfie_expires_at,
			r.is_women_only,
			r.created_at,
			r.updated_at,
			u.full_name,
			u.gender,
			v.model,
			v.vehicle_number,
			v.vehicle_type,
			COALESCE(v.vehicle_photo_url, '')
		FROM rides r
		INNER JOIN users u ON u.id = r.driver_id
		INNER JOIN vehicles v ON v.id = r.vehicle_id
		WHERE (r.from_location ILIKE '%' || $1 || '%' OR $1 ILIKE '%' || r.from_location || '%')
		  AND (r.to_location ILIKE '%' || $2 || '%' OR $2 ILIKE '%' || r.to_location || '%')
		  AND r.journey_date = $3
		  AND r.status = 'active'
		  AND r.available_seats > 0
		ORDER BY r.departure_time ASC`,
		fromLocation,
		toLocation,
		journeyDate,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var rides []models.RideDetail

	for rows.Next() {
		var ride models.RideDetail
		var rawGeometry []byte
		var rawWaypoints []byte

		err := rows.Scan(
			&ride.ID,
			&ride.DriverID,
			&ride.VehicleID,
			&ride.FromLocation,
			&ride.ToLocation,
			&ride.PickupLatitude,
			&ride.PickupLongitude,
			&ride.DestinationLatitude,
			&ride.DestinationLongitude,
			&rawGeometry,
			&ride.RouteDistance,
			&ride.RouteDuration,
			&ride.RouteSummary,
			&rawWaypoints,
			&ride.JourneyDate,
			&ride.DepartureTime,
			&ride.EstimatedArrivalTime,
			&ride.AvailableSeats,
			&ride.PricePerSeat,
			&ride.UserAmount,
			&ride.AppAmount,
			&ride.TotalAmount,
			&ride.Status,
			&ride.DriverSelfieURL,
			&ride.DriverSelfieExpiresAt,
			&ride.IsWomenOnly,
			&ride.CreatedAt,
			&ride.UpdatedAt,
			&ride.DriverName,
			&ride.DriverGender,
			&ride.VehicleModel,
			&ride.VehicleNumber,
			&ride.VehicleType,
			&ride.VehiclePhotoURL,
		)
		if err != nil {
			return nil, err
		}

		if len(rawGeometry) > 0 {
			var geom any
			if err := json.Unmarshal(rawGeometry, &geom); err == nil {
				ride.RouteGeometry = geom
			}
		}
		if len(rawWaypoints) > 0 {
			var wps any
			if err := json.Unmarshal(rawWaypoints, &wps); err == nil {
				ride.RouteWaypoints = wps
			}
		}

		rides = append(rides, ride)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	if rides == nil {
		rides = []models.RideDetail{}
	}

	return rides, nil
}
