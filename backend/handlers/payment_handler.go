package handlers

import (
	"github.com/abhishare16/Abhi-Share/backend/config"
	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/abhishare16/Abhi-Share/backend/services"
	"github.com/gofiber/fiber/v2"
)

// PaymentHandler manages HTTP endpoints for Razorpay payment workflows.
type PaymentHandler struct {
	Service *services.PaymentService
	Config  *config.Config
}

func NewPaymentHandler(svc *services.PaymentService, cfg *config.Config) *PaymentHandler {
	return &PaymentHandler{
		Service: svc,
		Config:  cfg,
	}
}

// GetConfig returns public client-safe payment settings (Key ID only, NEVER the secret).
func (h *PaymentHandler) GetConfig(c *fiber.Ctx) error {
	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"key_id":   h.Config.RazorpayKeyID,
		"currency": "INR",
	})
}

// CreateOrder initiates a payment order with dynamic server-side amount calculation.
func (h *PaymentHandler) CreateOrder(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	var req models.CreatePaymentOrderRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request payload"})
	}

	res, err := h.Service.CreateOrder(c.Context(), userID, req)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusCreated).JSON(res)
}

// VerifyPayment verifies the Razorpay payment signature and performs atomic settlement.
func (h *PaymentHandler) VerifyPayment(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	var req models.VerifyPaymentRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid verification payload"})
	}

	res, err := h.Service.VerifyPayment(c.Context(), userID, req)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error":   err.Error(),
			"success": false,
		})
	}

	return c.Status(fiber.StatusOK).JSON(res)
}

// CancelOrder handles client cancellation or payment failures.
func (h *PaymentHandler) CancelOrder(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	var req struct {
		OrderID string `json:"order_id"`
		Reason  string `json:"reason"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid payload"})
	}

	_ = h.Service.MarkOrderFailed(c.Context(), userID, req.OrderID, req.Reason)
	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message": "payment order marked as cancelled",
	})
}

// GetStatus returns the current order status for polling or verification reconciliation.
func (h *PaymentHandler) GetStatus(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	orderID := c.Params("orderId")
	if orderID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "order_id is required"})
	}

	order, err := h.Service.GetOrderStatus(c.Context(), userID, orderID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusOK).JSON(order)
}

// HandleWebhook processes webhook deliveries from Razorpay.
func (h *PaymentHandler) HandleWebhook(c *fiber.Ctx) error {
	signature := c.Get("X-Razorpay-Signature")
	if signature == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "missing signature"})
	}

	body := c.Body()
	if err := h.Service.HandleWebhook(c.Context(), body, signature); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{"status": "ok"})
}
