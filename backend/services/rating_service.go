package services

import (
	"context"
	"errors"
	"fmt"

	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/jackc/pgx/v5/pgxpool"
)

type RatingService struct {
	DB *pgxpool.Pool
}

func NewRatingService(db *pgxpool.Pool) *RatingService {
	return &RatingService{
		DB: db,
	}
}

// SubmitRatings records or updates rating values for participants in a completed ride.
func (s *RatingService) SubmitRatings(
	ctx context.Context,
	raterID string,
	req models.SubmitRatingsRequest,
) error {
	if req.RideID == "" {
		return errors.New("ride_id is required")
	}
	if len(req.Ratings) == 0 {
		return errors.New("at least one rating is required")
	}

	// Validate that the ride exists and is completed
	var status string
	var driverID string
	err := s.DB.QueryRow(
		ctx,
		`SELECT status, driver_id FROM rides WHERE id = $1`,
		req.RideID,
	).Scan(&status, &driverID)
	if err != nil {
		return fmt.Errorf("ride not found: %w", err)
	}

	if status != "completed" {
		return errors.New("ratings can only be submitted for completed rides")
	}

	// Verify that rater participated in the ride (as driver or confirmed passenger)
	isDriver := driverID == raterID
	if !isDriver {
		var confirmedCount int
		err = s.DB.QueryRow(
			ctx,
			`SELECT COUNT(*) FROM bookings WHERE ride_id = $1 AND passenger_id = $2 AND status IN ('confirmed', 'completed')`,
			req.RideID,
			raterID,
		).Scan(&confirmedCount)
		if err != nil || confirmedCount == 0 {
			return errors.New("you did not participate in this ride")
		}
	}

	// Insert/update each rating in a transaction
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	for _, item := range req.Ratings {
		if item.RateeID == "" {
			continue
		}
		if item.RateeID == raterID {
			return errors.New("you cannot rate yourself")
		}
		if item.RatingValue < 1 || item.RatingValue > 5 {
			return errors.New("rating value must be between 1 and 5")
		}

		_, err = tx.Exec(
			ctx,
			`INSERT INTO ratings (ride_id, rater_id, ratee_id, rating_value, feedback, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
			 ON CONFLICT (ride_id, rater_id, ratee_id)
			 DO UPDATE SET rating_value = EXCLUDED.rating_value, feedback = EXCLUDED.feedback, updated_at = NOW()`,
			req.RideID,
			raterID,
			item.RateeID,
			item.RatingValue,
			item.Feedback,
		)
		if err != nil {
			return fmt.Errorf("failed to save rating: %w", err)
		}
	}

	return tx.Commit(ctx)
}

// GetRideRatingParticipants returns participants to rate for a specific ride.
func (s *RatingService) GetRideRatingParticipants(
	ctx context.Context,
	rideID string,
	currentUserID string,
) (*models.PendingRatingResponse, error) {
	var fromLocation, toLocation, journeyDate, driverID, status string
	err := s.DB.QueryRow(
		ctx,
		`SELECT from_location, to_location, TO_CHAR(journey_date, 'YYYY-MM-DD'), driver_id, status
		 FROM rides WHERE id = $1`,
		rideID,
	).Scan(&fromLocation, &toLocation, &journeyDate, &driverID, &status)
	if err != nil {
		return nil, fmt.Errorf("ride not found: %w", err)
	}

	isDriver := driverID == currentUserID

	// Map existing ratings submitted by current user for this ride
	ratedMap := make(map[string]bool)
	ratingRows, err := s.DB.Query(
		ctx,
		`SELECT ratee_id FROM ratings WHERE ride_id = $1 AND rater_id = $2`,
		rideID,
		currentUserID,
	)
	if err == nil {
		for ratingRows.Next() {
			var rateeID string
			if err := ratingRows.Scan(&rateeID); err == nil {
				ratedMap[rateeID] = true
			}
		}
		ratingRows.Close()
	}

	var participants []models.RatingParticipant

	if isDriver {
		// Driver rates passengers
		rows, err := s.DB.Query(
			ctx,
			`SELECT u.id, u.full_name
			 FROM bookings b
			 JOIN users u ON u.id = b.passenger_id
			 WHERE b.ride_id = $1 AND b.status IN ('confirmed', 'completed')
			 ORDER BY b.created_at ASC`,
			rideID,
		)
		if err != nil {
			return nil, err
		}
		defer rows.Close()

		for rows.Next() {
			var p models.RatingParticipant
			p.Role = "passenger"
			if err := rows.Scan(&p.ID, &p.FullName); err != nil {
				continue
			}
			p.AlreadyRated = ratedMap[p.ID]
			participants = append(participants, p)
		}
	} else {
		// Passenger rates: 1. Driver, 2. Co-passengers
		var driverName string
		_ = s.DB.QueryRow(ctx, `SELECT full_name FROM users WHERE id = $1`, driverID).Scan(&driverName)
		participants = append(participants, models.RatingParticipant{
			ID:           driverID,
			FullName:     driverName,
			Role:         "driver",
			AlreadyRated: ratedMap[driverID],
		})

		// Co-passengers
		rows, err := s.DB.Query(
			ctx,
			`SELECT u.id, u.full_name
			 FROM bookings b
			 JOIN users u ON u.id = b.passenger_id
			 WHERE b.ride_id = $1 AND b.status IN ('confirmed', 'completed') AND b.passenger_id != $2
			 ORDER BY b.created_at ASC`,
			rideID,
			currentUserID,
		)
		if err == nil {
			for rows.Next() {
				var p models.RatingParticipant
				p.Role = "passenger"
				if err := rows.Scan(&p.ID, &p.FullName); err == nil {
					p.AlreadyRated = ratedMap[p.ID]
					participants = append(participants, p)
				}
			}
			rows.Close()
		}
	}

	return &models.PendingRatingResponse{
		HasPendingRating: len(participants) > 0,
		RideID:           rideID,
		FromLocation:     fromLocation,
		ToLocation:       toLocation,
		JourneyDate:      journeyDate,
		IsDriver:         isDriver,
		Participants:     participants,
	}, nil
}

// GetPendingRating checks if the user has any recently completed ride with unsubmitted ratings.
func (s *RatingService) GetPendingRating(
	ctx context.Context,
	userID string,
) (*models.PendingRatingResponse, error) {
	// 1. Check if user was driver on a completed ride with unrated passengers
	driverRideRows, err := s.DB.Query(
		ctx,
		`SELECT r.id
		 FROM rides r
		 WHERE r.driver_id = $1 AND r.status = 'completed'
		 ORDER BY r.updated_at DESC
		 LIMIT 5`,
		userID,
	)
	if err == nil {
		var candidateRideIDs []string
		for driverRideRows.Next() {
			var rid string
			if err := driverRideRows.Scan(&rid); err == nil {
				candidateRideIDs = append(candidateRideIDs, rid)
			}
		}
		driverRideRows.Close()

		for _, rideID := range candidateRideIDs {
			resp, err := s.GetRideRatingParticipants(ctx, rideID, userID)
			if err == nil && resp.HasPendingRating {
				// Check if any participant is NOT yet rated
				hasUnrated := false
				for _, p := range resp.Participants {
					if !p.AlreadyRated {
						hasUnrated = true
						break
					}
				}
				if hasUnrated {
					return resp, nil
				}
			}
		}
	}

	// 2. Check if user was a passenger on a completed ride with unrated driver/co-passengers
	passengerRideRows, err := s.DB.Query(
		ctx,
		`SELECT r.id
		 FROM bookings b
		 JOIN rides r ON r.id = b.ride_id
		 WHERE b.passenger_id = $1 AND b.status IN ('confirmed', 'completed') AND r.status = 'completed'
		 ORDER BY r.updated_at DESC
		 LIMIT 5`,
		userID,
	)
	if err == nil {
		var candidateRideIDs []string
		for passengerRideRows.Next() {
			var rid string
			if err := passengerRideRows.Scan(&rid); err == nil {
				candidateRideIDs = append(candidateRideIDs, rid)
			}
		}
		passengerRideRows.Close()

		for _, rideID := range candidateRideIDs {
			resp, err := s.GetRideRatingParticipants(ctx, rideID, userID)
			if err == nil && resp.HasPendingRating {
				hasUnrated := false
				for _, p := range resp.Participants {
					if !p.AlreadyRated {
						hasUnrated = true
						break
					}
				}
				if hasUnrated {
					return resp, nil
				}
			}
		}
	}

	return &models.PendingRatingResponse{
		HasPendingRating: false,
	}, nil
}

// GetUserRatingSummary returns the average rating and count for a user.
func (s *RatingService) GetUserRatingSummary(
	ctx context.Context,
	userID string,
) (*models.UserRatingSummary, error) {
	var avgRating *float64
	var totalRatings int

	err := s.DB.QueryRow(
		ctx,
		`SELECT ROUND(AVG(rating_value)::numeric, 1), COUNT(*)
		 FROM ratings
		 WHERE ratee_id = $1`,
		userID,
	).Scan(&avgRating, &totalRatings)
	if err != nil {
		return nil, err
	}

	return &models.UserRatingSummary{
		UserID:        userID,
		AverageRating: avgRating,
		TotalRatings:  totalRatings,
	}, nil
}
