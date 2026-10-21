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

type RecurringScheduleHandler struct {
	Service *services.RecurringScheduleService
	Storage storage.Provider
}

func NewRecurringScheduleHandler(
	service *services.RecurringScheduleService,
	storageProvider storage.Provider,
) *RecurringScheduleHandler {
	return &RecurringScheduleHandler{
		Service: service,
		Storage: storageProvider,
	}
}

func (h *RecurringScheduleHandler) CreateRecurringSchedule(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "authenticated user required",
		})
	}

	var req models.CreateRecurringScheduleRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	if req.VehicleID == "" || req.FromLocation == "" || req.ToLocation == "" ||
		req.DepartureTime == "" || req.EstimatedArrivalTime == "" || req.StartDate == "" ||
		req.RecurrenceType == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Missing required schedule fields",
		})
	}

	scheduleID, rideIDs, userAmount, appAmount, totalAmount, err := h.Service.CreateRecurringSchedule(c.Context(), userID, req)
	if err != nil {
		var outstandingErr *models.OutstandingChargesError
		if errors.As(err, &outstandingErr) {
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
				"error":   err.Error(),
				"code":    models.ErrCodeOutstandingCharges,
				"balance": outstandingErr.Balance,
			})
		}
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{
		"message":      "Recurring schedule draft created successfully",
		"schedule_id":  scheduleID,
		"ride_ids":     rideIDs,
		"ride_count":   len(rideIDs),
		"status":       "draft",
		"user_amount":  userAmount,
		"app_amount":   appAmount,
		"total_amount": totalAmount,
	})
}

func (h *RecurringScheduleHandler) UploadSelfie(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "authenticated user required",
		})
	}

	scheduleID := c.Params("id")
	if scheduleID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "schedule ID is required",
		})
	}

	file, err := c.FormFile("selfie")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Selfie image is required",
		})
	}

	src, err := file.Open()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to read selfie image",
		})
	}
	defer src.Close()

	contentType, extension, err := SniffAndResolveContentType(file, src)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to process selfie image",
		})
	}

	filename := "schedule_" + scheduleID + extension
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
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to upload selfie: " + err.Error(),
			})
		}
	} else {
		uploadPath := "./uploads/" + objectKey
		if err := c.SaveFile(file, uploadPath); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to save selfie",
			})
		}
		selfieURL = "/uploads/" + objectKey
	}

	err = h.Service.UploadSelfie(context.Background(), scheduleID, userID, selfieURL)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{
		"message":     "Selfie uploaded successfully for recurring schedule",
		"schedule_id": scheduleID,
		"selfie_url":  selfieURL,
		"status":      "selfie_uploaded",
	})
}

func (h *RecurringScheduleHandler) PublishRecurringSchedule(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "authenticated user required",
		})
	}

	scheduleID := c.Params("id")
	if scheduleID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "schedule ID is required",
		})
	}

	publishedCount, err := h.Service.PublishRecurringSchedule(context.Background(), scheduleID, userID)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message":         "Recurring schedule and all rides published successfully",
		"schedule_id":     scheduleID,
		"published_count": publishedCount,
		"status":          "active",
	})
}

func (h *RecurringScheduleHandler) GetUserRecurringSchedules(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "authenticated user required",
		})
	}

	schedules, err := h.Service.GetUserRecurringSchedules(context.Background(), userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to load recurring schedules: " + err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"schedules": schedules,
	})
}

func (h *RecurringScheduleHandler) GetRecurringScheduleDetail(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "authenticated user required",
		})
	}

	scheduleID := c.Params("id")
	if scheduleID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "schedule ID is required",
		})
	}

	schedule, err := h.Service.GetRecurringScheduleDetail(context.Background(), scheduleID, userID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"schedule": schedule,
	})
}

func (h *RecurringScheduleHandler) PauseRecurringSchedule(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "authenticated user required",
		})
	}

	scheduleID := c.Params("id")
	if scheduleID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "schedule ID is required",
		})
	}

	err := h.Service.PauseRecurringSchedule(context.Background(), scheduleID, userID)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message": "Recurring schedule paused successfully",
		"status":  "paused",
	})
}

func (h *RecurringScheduleHandler) ResumeRecurringSchedule(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "authenticated user required",
		})
	}

	scheduleID := c.Params("id")
	if scheduleID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "schedule ID is required",
		})
	}

	err := h.Service.ResumeRecurringSchedule(context.Background(), scheduleID, userID)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message": "Recurring schedule resumed successfully",
		"status":  "active",
	})
}

func (h *RecurringScheduleHandler) CancelRecurringSchedule(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "authenticated user required",
		})
	}

	scheduleID := c.Params("id")
	if scheduleID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "schedule ID is required",
		})
	}

	err := h.Service.CancelRecurringSchedule(context.Background(), scheduleID, userID)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message": "Recurring schedule cancelled successfully",
		"status":  "cancelled",
	})
}

func (h *RecurringScheduleHandler) UpdateRecurringSchedule(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "authenticated user required",
		})
	}

	scheduleID := c.Params("id")
	if scheduleID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "schedule ID is required",
		})
	}

	var req models.UpdateRecurringScheduleRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	err := h.Service.UpdateRecurringSchedule(context.Background(), scheduleID, userID, req)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message": "Recurring schedule updated successfully",
	})
}
