package models

type Vehicle struct {
	ID              string `json:"id"`
	UserID          string `json:"user_id,omitempty"`
	VehicleNumber   string `json:"vehicle_number"`
	VehicleType     string `json:"vehicle_type"`
	Model           string `json:"model"`
	RCPhotoURL      string `json:"rc_photo_url"`
	VehiclePhotoURL string `json:"vehicle_photo_url"`
}

type CreateVehicleRequest struct {
	UserID          string `json:"user_id"`
	VehicleNumber   string `json:"vehicle_number"`
	VehicleType     string `json:"vehicle_type"`
	Model           string `json:"model"`
	RCPhotoURL      string `json:"rc_photo_url"`
	VehiclePhotoURL string `json:"vehicle_photo_url"`
}
