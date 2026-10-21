package services

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/models"
)

type LocationService struct {
	DB *pgxpool.Pool
}

func NewLocationService(db *pgxpool.Pool) *LocationService {
	return &LocationService{DB: db}
}

func (s *LocationService) CreateLocation(ctx context.Context, userID string, req models.CreateSavedLocationRequest) (*models.SavedLocation, error) {
	var loc models.SavedLocation

	err := s.DB.QueryRow(
		ctx,
		`INSERT INTO saved_locations (user_id, name, address)
		 VALUES ($1, $2, $3)
		 RETURNING id, user_id, name, address, created_at, updated_at`,
		userID, req.Name, req.Address,
	).Scan(&loc.ID, &loc.UserID, &loc.Name, &loc.Address, &loc.CreatedAt, &loc.UpdatedAt)

	if err != nil {
		return nil, err
	}

	return &loc, nil
}

func (s *LocationService) GetLocations(ctx context.Context, userID string) ([]models.SavedLocation, error) {
	rows, err := s.DB.Query(
		ctx,
		`SELECT id, user_id, name, address, created_at, updated_at
		 FROM saved_locations
		 WHERE user_id = $1
		 ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var locs []models.SavedLocation
	for rows.Next() {
		var l models.SavedLocation
		if err := rows.Scan(&l.ID, &l.UserID, &l.Name, &l.Address, &l.CreatedAt, &l.UpdatedAt); err != nil {
			return nil, err
		}
		locs = append(locs, l)
	}

	return locs, nil
}
