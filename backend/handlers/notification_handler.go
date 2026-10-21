package handlers

import (
	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/abhishare16/Abhi-Share/backend/services"
	"github.com/gofiber/fiber/v2"
)

type NotificationHandler struct {
	Service *services.NotificationService
}

func NewNotificationHandler(service *services.NotificationService) *NotificationHandler {
	return &NotificationHandler{Service: service}
}

func (h *NotificationHandler) GetNotifications(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	notifs, err := h.Service.GetUserNotifications(c.Context(), userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}
	
	if notifs == nil {
		notifs = []models.Notification{}
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"notifications": notifs,
	})
}

func (h *NotificationHandler) MarkRead(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	notifID := c.Params("id")
	if notifID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "notification id is required"})
	}

	err := h.Service.MarkNotificationRead(c.Context(), userID, notifID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.SendStatus(fiber.StatusOK)
}

func (h *NotificationHandler) GetNotificationDetail(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	notifID := c.Params("id")
	if notifID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "notification id is required"})
	}

	detail, err := h.Service.GetNotificationDetail(c.Context(), userID, notifID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"notification": detail,
	})
}

type DeviceTokenRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

func (h *NotificationHandler) RegisterDeviceToken(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	var req DeviceTokenRequest
	if err := c.BodyParser(&req); err != nil || req.Token == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "valid token is required"})
	}

	if h.Service.PushService == nil {
		return c.Status(fiber.StatusOK).JSON(fiber.Map{"message": "token stored"})
	}

	if err := h.Service.PushService.RegisterDeviceToken(c.Context(), userID, req.Token, req.Platform); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message": "device token registered successfully",
	})
}

func (h *NotificationHandler) UnregisterDeviceToken(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	var req DeviceTokenRequest
	if err := c.BodyParser(&req); err != nil || req.Token == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "valid token is required"})
	}

	if h.Service.PushService == nil {
		return c.SendStatus(fiber.StatusOK)
	}

	if err := h.Service.PushService.UnregisterDeviceToken(c.Context(), userID, req.Token); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message": "device token unregistered successfully",
	})
}

func (h *NotificationHandler) TestPush(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	if h.Service.PushService == nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"error": "Push service is not initialized",
		})
	}

	err := h.Service.PushService.SendPushToUser(
		c.Context(),
		userID,
		"AbhiShare Test Push 🚀",
		"Push notifications are working perfectly on your device!",
		map[string]string{
			"type": "test_notification",
		},
	)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message": "test push dispatched",
	})
}
