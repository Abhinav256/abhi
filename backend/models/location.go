package models

import "time"

type SavedLocation struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Name      string    `json:"name"`
	Address   string    `json:"address"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type CreateSavedLocationRequest struct {
	Name    string `json:"name"`
	Address string `json:"address"`
}

type AutocompleteLocation struct {
	Name             string  `json:"name"`
	FormattedAddress string  `json:"formatted_address"`
	Latitude         float64 `json:"latitude"`
	Longitude        float64 `json:"longitude"`
	PlaceID          string  `json:"place_id,omitempty"`
}

type AutocompleteResponse struct {
	Results []AutocompleteLocation `json:"results"`
}
