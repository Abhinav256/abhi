package handlers

import (
	"strings"

	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/abhishare16/Abhi-Share/backend/services"

	"github.com/gofiber/fiber/v2"
)

type ReferralHandler struct {
	Service *services.ReferralService
}

func NewReferralHandler(service *services.ReferralService) *ReferralHandler {
	return &ReferralHandler{Service: service}
}

// GetSummary returns the referrer summary, eligibility, daily usage, and referral history.
func (h *ReferralHandler) GetSummary(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Unauthorized user session",
		})
	}

	summary, err := h.Service.GetReferralSummary(c.Context(), userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.JSON(summary)
}

// ValidateCode checks if a referral code is valid, active, and within the referrer's daily limit.
func (h *ReferralHandler) ValidateCode(c *fiber.Ctx) error {
	var req models.ValidateReferralCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request payload",
		})
	}

	code := strings.TrimSpace(req.ReferralCode)
	if code == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Referral code cannot be empty",
		})
	}

	res, err := h.Service.ValidateReferralCode(c.Context(), code)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.JSON(res)
}
