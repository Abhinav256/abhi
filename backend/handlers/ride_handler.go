package handlers

import (
	"context"
	"errors"

	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/abhishare16/Abhi-Share/backend/services"
	"github.com/abhishare16/Abhi-Share/backend/storage"
)

type RideHandler struct {
	Service *services.RideService
	Storage storage.Provider
}

func NewRideHandler(service *services.RideService, storageProvider storage.Provider) *RideHandler {
	return &RideHandler{
		Service: service,
		Storage: storageProvider,
	}
}

func (h *RideHandler) CreateRide(c *fiber.Ctx) error {
	driverID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	var request models.CreateRideRequest

	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Invalid request body",
			},
		)
	}

	request.DriverID = driverID

	if request.VehicleID == "" ||
		request.FromLocation == "" ||
		request.ToLocation == "" ||
		request.JourneyDate == "" ||
		request.DepartureTime == "" ||
		request.EstimatedArrivalTime == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Missing required ride details",
			},
		)
	}

	if request.AvailableSeats < 1 {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Available seats must be at least 1",
			},
		)
	}

	if request.PricePerSeat < 0 {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Price per seat cannot be negative",
			},
		)
	}

	rideID, userAmount, appAmount, totalAmount, err := h.Service.CreateRide(
		context.Background(),
		request,
	)

	if err != nil {
		var outstandingErr *models.OutstandingChargesError
		if errors.As(err, &outstandingErr) {
			return c.Status(fiber.StatusForbidden).JSON(
				fiber.Map{
					"error":   err.Error(),
					"code":    models.ErrCodeOutstandingCharges,
					"balance": outstandingErr.Balance,
				},
			)
		}
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.Status(fiber.StatusCreated).JSON(
		fiber.Map{
			"message":      "Ride draft created successfully",
			"ride_id":      rideID,
			"status":       "draft",
			"user_amount":  userAmount,
			"app_amount":   appAmount,
			"total_amount": totalAmount,
		},
	)
}

func (h *RideHandler) UploadDriverSelfie(c *fiber.Ctx) error {
	driverID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	rideID := c.Params("ride_id")

	if rideID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "ride_id is required",
			},
		)
	}

	file, err := c.FormFile("selfie")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Selfie image is required",
			},
		)
	}

	src, err := file.Open()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(
			fiber.Map{
				"error": "Failed to read selfie image",
			},
		)
	}
	defer src.Close()

	contentType, extension, err := SniffAndResolveContentType(file, src)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(
			fiber.Map{
				"error": "Failed to process selfie image",
			},
		)
	}

	filename := rideID + extension
	objectKey := "rides/selfies/" + filename

	var selfieURL string
	if h.Storage != nil {
		selfieURL, err = h.Storage.Upload(
			context.Background(),
			"abhishare-public",
			objectKey,
			src,
			file.Size,
			storage.UploadOptions{
				ContentType: contentType,
				IsPrivate:   false,
			},
		)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(
				fiber.Map{
					"error": "Failed to upload selfie: " + err.Error(),
				},
			)
		}
	} else {
		uploadPath := "./uploads/" + objectKey
		if err := c.SaveFile(file, uploadPath); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(
				fiber.Map{
					"error": "Failed to save selfie",
				},
			)
		}
		selfieURL = "/uploads/" + objectKey
	}

	err = h.Service.UploadDriverSelfie(
		context.Background(),
		rideID,
		driverID,
		selfieURL,
	)

	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.Status(fiber.StatusCreated).JSON(
		fiber.Map{
			"message":    "Driver selfie uploaded successfully",
			"ride_id":    rideID,
			"selfie_url": selfieURL,
			"status":     "selfie_uploaded",
		},
	)
}

func (h *RideHandler) PublishRide(c *fiber.Ctx) error {
	driverID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	rideID := c.Params("ride_id")

	if rideID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "ride_id is required",
			},
		)
	}

	err := h.Service.PublishRide(
		context.Background(),
		rideID,
		driverID,
	)

	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.JSON(
		fiber.Map{
			"message": "Ride published successfully",
			"ride_id": rideID,
			"status":  "active",
		},
	)
}

func (h *RideHandler) CompleteRide(c *fiber.Ctx) error {
	driverID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	rideID := c.Params("ride_id")

	if rideID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "ride_id is required",
			},
		)
	}

	err := h.Service.CompleteRide(
		context.Background(),
		rideID,
		driverID,
	)

	if err != nil {
		if err.Error() == "you do not have access to this ride" {
			return c.Status(fiber.StatusForbidden).JSON(
				fiber.Map{
					"error": err.Error(),
				},
			)
		}

		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.JSON(
		fiber.Map{
			// "message": "Ride completed successfully",
		},
	)
}

func (h *RideHandler) CancelRide(c *fiber.Ctx) error {
	driverID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	rideID := c.Params("ride_id")

	if rideID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "ride_id is required",
			},
		)
	}

	err := h.Service.CancelRide(
		context.Background(),
		rideID,
		driverID,
	)

	if err != nil {
		if err.Error() == "you do not have access to this ride" {
			return c.Status(fiber.StatusForbidden).JSON(
				fiber.Map{
					"error": err.Error(),
				},
			)
		}

		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.JSON(
		fiber.Map{
			"message": "Ride cancelled successfully",
		},
	)
}

func (h *RideHandler) DeleteDraft(c *fiber.Ctx) error {
	driverID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	rideID := c.Params("ride_id")

	if rideID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "ride_id is required",
			},
		)
	}

	err := h.Service.DeleteDraft(
		context.Background(),
		rideID,
		driverID,
	)

	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.JSON(
		fiber.Map{
			"message": "Draft deleted successfully",
		},
	)
}

func (h *RideHandler) UpdateDraft(c *fiber.Ctx) error {
	driverID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	rideID := c.Params("ride_id")
	if rideID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "ride_id is required",
			},
		)
	}

	var req models.CreateRideRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "invalid request body",
			},
		)
	}

	err := h.Service.UpdateDraft(
		context.Background(),
		rideID,
		driverID,
		req,
	)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.JSON(
		fiber.Map{
			"message": "Draft updated successfully",
		},
	)
}

// GetMyRides returns all rides created by the authenticated driver.
func (h *RideHandler) GetMyRides(c *fiber.Ctx) error {
	driverID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{"error": "authenticated user required"},
		)
	}

	rides, err := h.Service.GetMyRides(
		context.Background(),
		driverID,
	)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(
			fiber.Map{"error": err.Error()},
		)
	}

	return c.JSON(fiber.Map{"rides": rides})
}

// GetRideDetail returns a single ride enriched with driver and vehicle data.
func (h *RideHandler) GetRideDetail(c *fiber.Ctx) error {
	rideID := c.Params("ride_id")
	if rideID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{"error": "ride_id is required"},
		)
	}

	ride, err := h.Service.GetRideDetail(
		context.Background(),
		rideID,
	)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(
			fiber.Map{"error": err.Error()},
		)
	}

	return c.JSON(fiber.Map{"ride": ride})
}
