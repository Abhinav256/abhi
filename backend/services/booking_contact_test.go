package services

import (
	"testing"

	"github.com/abhishare16/Abhi-Share/backend/models"
)

func TestBookingContactModel(t *testing.T) {
	resp := models.BookingContactResponse{
		BookingID:   "book-123",
		ContactName: "Abhinav Reddy",
		Phone:       "+919876543210",
		Role:        "driver",
	}

	if resp.BookingID != "book-123" {
		t.Errorf("expected BookingID book-123, got %s", resp.BookingID)
	}
	if resp.ContactName != "Abhinav Reddy" {
		t.Errorf("expected ContactName Abhinav Reddy, got %s", resp.ContactName)
	}
	if resp.Phone != "+919876543210" {
		t.Errorf("expected Phone +919876543210, got %s", resp.Phone)
	}
	if resp.Role != "driver" {
		t.Errorf("expected Role driver, got %s", resp.Role)
	}
}

func TestBookingWithRide_DriverPhoneField(t *testing.T) {
	bwr := models.BookingWithRide{
		ID:          "b-1",
		RideID:      "r-1",
		DriverPhone: "+919876543210",
	}

	if bwr.DriverPhone != "+919876543210" {
		t.Errorf("expected DriverPhone +919876543210, got %s", bwr.DriverPhone)
	}
}
