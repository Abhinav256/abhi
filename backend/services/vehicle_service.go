package services

import (
	"context"
	"errors"
	"strings"

	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type VehicleService struct {
	DB *pgxpool.Pool
}

func NewVehicleService(db *pgxpool.Pool) *VehicleService {
	return &VehicleService{
		DB: db,
	}
}

func (s *VehicleService) CreateVehicle(
	ctx context.Context,
	request models.CreateVehicleRequest,
) (string, error) {
	var vehicleID string

	err := s.DB.QueryRow(
		ctx,
		`INSERT INTO vehicles
		(user_id, vehicle_number, vehicle_type, model, rc_photo_url, vehicle_photo_url)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id`,
		request.UserID,
		request.VehicleNumber,
		request.VehicleType,
		request.Model,
		request.RCPhotoURL,
		request.VehiclePhotoURL,
	).Scan(&vehicleID)

	if err != nil {
		return "", err
	}

	return vehicleID, nil
}

func (s *VehicleService) GetVehicles(
	ctx context.Context,
	userID string,
) ([]models.Vehicle, error) {
	rows, err := s.DB.Query(
		ctx,
		`SELECT id, vehicle_number, vehicle_type, model,
		        rc_photo_url, vehicle_photo_url
		 FROM vehicles
		 WHERE user_id = $1
		 ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var vehicles []models.Vehicle

	for rows.Next() {
		var vehicle models.Vehicle

		err := rows.Scan(
			&vehicle.ID,
			&vehicle.VehicleNumber,
			&vehicle.VehicleType,
			&vehicle.Model,
			&vehicle.RCPhotoURL,
			&vehicle.VehiclePhotoURL,
		)
		if err != nil {
			return nil, err
		}

		vehicles = append(vehicles, vehicle)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	if vehicles == nil {
		vehicles = []models.Vehicle{}
	}

	return vehicles, nil
}

func (s *VehicleService) GetVehicle(
	ctx context.Context,
	vehicleID string,
) (*models.Vehicle, error) {
	var vehicle models.Vehicle

	err := s.DB.QueryRow(
		ctx,
		`SELECT id, user_id, vehicle_number, vehicle_type, model,
		        rc_photo_url, vehicle_photo_url
		 FROM vehicles
		 WHERE id = $1`,
		vehicleID,
	).Scan(
		&vehicle.ID,
		&vehicle.UserID,
		&vehicle.VehicleNumber,
		&vehicle.VehicleType,
		&vehicle.Model,
		&vehicle.RCPhotoURL,
		&vehicle.VehiclePhotoURL,
	)

	if err != nil {
		return nil, err
	}

	return &vehicle, nil
}

func (s *VehicleService) DeleteVehicle(
	ctx context.Context,
	vehicleID string,
	userID string,
) error {
	result, err := s.DB.Exec(
		ctx,
		`DELETE FROM vehicles WHERE id = $1 AND user_id = $2`,
		vehicleID,
		userID,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if (errors.As(err, &pgErr) && pgErr.Code == "23503") ||
			strings.Contains(err.Error(), "violates foreign key constraint") ||
			strings.Contains(err.Error(), "rides_vehicle_id_fkey") ||
			strings.Contains(err.Error(), "23503") {
			return errors.New("You cannot delete this vehicle because it has existing bookings.")
		}
		return err
	}

	if result.RowsAffected() == 0 {
		return errors.New("vehicle not found or access denied")
	}

	return nil
}
