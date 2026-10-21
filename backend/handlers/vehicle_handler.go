package handlers

import (
	"context"

	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/abhishare16/Abhi-Share/backend/services"
	"github.com/abhishare16/Abhi-Share/backend/storage"
)

type VehicleHandler struct {
	Service *services.VehicleService
	Storage storage.Provider
}

func NewVehicleHandler(service *services.VehicleService, storageProvider storage.Provider) *VehicleHandler {
	return &VehicleHandler{
		Service: service,
		Storage: storageProvider,
	}
}

func (h *VehicleHandler) CreateVehicle(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	var request models.CreateVehicleRequest

	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Invalid request body",
			},
		)
	}

	request.UserID = userID

	if request.VehicleNumber == "" ||
		request.VehicleType == "" ||
		request.Model == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "vehicle_number, vehicle_type and model are required",
			},
		)
	}

	validVehicleTypes := map[string]bool{
		"two_wheeler":  true,
		"five_seater":  true,
		"seven_seater": true,
	}

	if !validVehicleTypes[request.VehicleType] {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Invalid vehicle type",
			},
		)
	}

	vehicleID, err := h.Service.CreateVehicle(
		context.Background(),
		request,
	)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.Status(fiber.StatusCreated).JSON(
		fiber.Map{
			"message":    "Vehicle added successfully",
			"vehicle_id": vehicleID,
		},
	)
}

func (h *VehicleHandler) GetVehicles(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	vehicles, err := h.Service.GetVehicles(
		context.Background(),
		userID,
	)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.JSON(
		fiber.Map{
			"vehicles": vehicles,
		},
	)
}

func (h *VehicleHandler) GetVehicle(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	vehicleID := c.Params("id")

	if vehicleID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "vehicle id is required",
			},
		)
	}

	vehicle, err := h.Service.GetVehicle(
		context.Background(),
		vehicleID,
	)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(
			fiber.Map{
				"error": "Vehicle not found",
			},
		)
	}

	if vehicle.UserID != userID {
		return c.Status(fiber.StatusForbidden).JSON(
			fiber.Map{
				"error": "you do not have access to this vehicle",
			},
		)
	}

	return c.JSON(vehicle)
}

func (h *VehicleHandler) UploadVehicleImage(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	vehicleID := c.FormValue("vehicle_id")
	imageType := c.FormValue("type")

	if vehicleID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "vehicle_id is required",
			},
		)
	}

	if imageType != "rc" && imageType != "vehicle" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Invalid image type. Use rc or vehicle",
			},
		)
	}

	vehicle, err := h.Service.GetVehicle(
		context.Background(),
		vehicleID,
	)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(
			fiber.Map{
				"error": "Vehicle not found",
			},
		)
	}

	if vehicle.UserID != userID {
		return c.Status(fiber.StatusForbidden).JSON(
			fiber.Map{
				"error": "you do not have access to this vehicle",
			},
		)
	}

	file, err := c.FormFile("image")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Image is required",
			},
		)
	}

	var folder string
	var column string

	if imageType == "rc" {
		folder = "rc"
		column = "rc_photo_url"
	} else {
		folder = "photos"
		column = "vehicle_photo_url"
	}

	src, err := file.Open()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(
			fiber.Map{
				"error": "Failed to read uploaded image",
			},
		)
	}
	defer src.Close()

	contentType, extension, err := SniffAndResolveContentType(file, src)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(
			fiber.Map{
				"error": "Failed to process image",
			},
		)
	}

	filename := vehicleID + extension
	objectKey := "vehicles/" + folder + "/" + filename

	isPrivate := (imageType == "rc")
	var bucket string
	if isPrivate {
		bucket = "abhishare-private"
	} else {
		bucket = "abhishare-public"
	}

	var imageURL string
	if h.Storage != nil {
		imageURL, err = h.Storage.Upload(
			context.Background(),
			bucket,
			objectKey,
			src,
			file.Size,
			storage.UploadOptions{
				ContentType: contentType,
				IsPrivate:   isPrivate,
			},
		)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(
				fiber.Map{
					"error": "Failed to upload image: " + err.Error(),
				},
			)
		}
	} else {
		uploadPath := "./uploads/" + objectKey
		if err := c.SaveFile(file, uploadPath); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(
				fiber.Map{
					"error": err.Error(),
				},
			)
		}
		imageURL = "/uploads/" + objectKey
	}

	_, err = h.Service.DB.Exec(
		context.Background(),
		"UPDATE vehicles SET "+column+
			" = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3",
		imageURL,
		vehicleID,
		userID,
	)

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.Status(fiber.StatusCreated).JSON(
		fiber.Map{
			"message": "Image uploaded successfully",
			"url":     imageURL,
		},
	)
}

func (h *VehicleHandler) DeleteVehicle(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	vehicleID := c.Params("id")
	if vehicleID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "vehicle id is required",
			},
		)
	}

	err := h.Service.DeleteVehicle(
		context.Background(),
		vehicleID,
		userID,
	)
	if err != nil {
		if err.Error() == "You cannot delete this vehicle because it has existing bookings." {
			return c.Status(fiber.StatusBadRequest).JSON(
				fiber.Map{
					"error": "You cannot delete this vehicle because it has existing bookings.",
				},
			)
		}
		if err.Error() == "vehicle not found or access denied" {
			return c.Status(fiber.StatusNotFound).JSON(
				fiber.Map{
					"error": err.Error(),
				},
			)
		}
		return c.Status(fiber.StatusInternalServerError).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.JSON(
		fiber.Map{
			"message": "Vehicle deleted successfully",
		},
	)
}

