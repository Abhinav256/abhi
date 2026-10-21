package handlers

import (
	"strings"

	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/abhishare16/Abhi-Share/backend/services"
)

type AuthHandler struct {
	Service *services.AuthService
}

func NewAuthHandler(
	service *services.AuthService,
) *AuthHandler {
	return &AuthHandler{
		Service: service,
	}
}

func (h *AuthHandler) StartAuth(
	c *fiber.Ctx,
) error {

	var request models.AuthStartRequest

	if err := c.BodyParser(&request); err != nil {
		return c.Status(
			fiber.StatusBadRequest,
		).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	result, err := h.Service.StartAuth(
		c.Context(),
		request.Identifier,
	)

	if err != nil {
		return c.Status(
			fiber.StatusBadRequest,
		).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(
		fiber.StatusOK,
	).JSON(result)
}

// New: SendOTPUniversal
func (h *AuthHandler) SendOTPUniversal(c *fiber.Ctx) error {
	var request models.AuthStartRequest

	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	result, err := h.Service.SendOTPUniversal(c.Context(), request.Identifier)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(result)
}

// New: VerifyOTPAndCheck
func (h *AuthHandler) VerifyOTPAndCheck(c *fiber.Ctx) error {
	var request models.VerifyOTPRequest

	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	result, err := h.Service.VerifyOTPAndCheck(c.Context(), request.Identifier, request.OTP)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(result)
}

// New: CheckSecondary
func (h *AuthHandler) CheckSecondary(c *fiber.Ctx) error {
	var request models.CheckSecondaryRequest
	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	result, err := h.Service.CheckSecondaryIdentifier(c.Context(), request.Identifier, request.Type)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(result)
}

// New: CompleteSignup
func (h *AuthHandler) CompleteSignup(c *fiber.Ctx) error {
	var request models.NewSignupRequest
	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	result, err := h.Service.CompleteSignup(c.Context(), request)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(fiber.StatusOK).JSON(result)
}

// Legacy kept for backwards compatibility
func (h *AuthHandler) StartSignup(
	c *fiber.Ctx,
) error {

	var request models.SignupRequest

	if err := c.BodyParser(&request); err != nil {
		return c.Status(
			fiber.StatusBadRequest,
		).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	err := h.Service.StartSignup(
		c.Context(),
		request,
	)

	if err != nil {
		return c.Status(
			fiber.StatusBadRequest,
		).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(
		fiber.StatusOK,
	).JSON(fiber.Map{
		"message": "OTP sent successfully",
	})
}

// Legacy kept for backwards compatibility
func (h *AuthHandler) VerifyOTP(
	c *fiber.Ctx,
) error {

	var request models.VerifyOTPRequest

	if err := c.BodyParser(&request); err != nil {
		return c.Status(
			fiber.StatusBadRequest,
		).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	result, err := h.Service.VerifyOTP(
		c.Context(),
		request,
	)

	if err != nil {
		return c.Status(
			fiber.StatusBadRequest,
		).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(
		fiber.StatusOK,
	).JSON(result)
}

// Legacy kept for backwards compatibility
func (h *AuthHandler) SendLoginOTP(
	c *fiber.Ctx,
) error {

	var request models.AuthStartRequest

	if err := c.BodyParser(&request); err != nil {
		return c.Status(
			fiber.StatusBadRequest,
		).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	result, err := h.Service.SendOTPUniversal(
		c.Context(),
		request.Identifier,
	)

	if err != nil {
		return c.Status(
			fiber.StatusBadRequest,
		).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(
		fiber.StatusOK,
	).JSON(result)
}

func (h *AuthHandler) Me(
	c *fiber.Ctx,
) error {

	userID, ok := middleware.UserID(c)

	if !ok {
		return c.Status(
			fiber.StatusUnauthorized,
		).JSON(fiber.Map{
			"error": "authentication required",
		})
	}

	user, err := h.Service.GetUserByID(
		c.Context(),
		userID,
	)

	if err != nil {
		return c.Status(
			fiber.StatusNotFound,
		).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(
		fiber.StatusOK,
	).JSON(fiber.Map{
		"user": user,
	})
}

func (h *AuthHandler) Logout(
	c *fiber.Ctx,
) error {

	authHeader := strings.TrimSpace(
		c.Get("Authorization"),
	)

	parts := strings.Fields(authHeader)

	if len(parts) != 2 ||
		!strings.EqualFold(parts[0], "Bearer") {
		return c.Status(
			fiber.StatusUnauthorized,
		).JSON(fiber.Map{
			"error": "invalid authorization header",
		})
	}

	err := h.Service.DeleteSession(
		c.Context(),
		parts[1],
	)

	if err != nil {
		return c.Status(
			fiber.StatusInternalServerError,
		).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.Status(
		fiber.StatusOK,
	).JSON(fiber.Map{
		"message": "logged out successfully",
	})
}

func (h *AuthHandler) UpdateMe(
	c *fiber.Ctx,
) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authentication required"})
	}

	var request models.UpdateProfileRequest
	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	user, err := h.Service.UpdateProfile(c.Context(), userID, request)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusOK).JSON(user)
}

func (h *AuthHandler) SetPIN(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authentication required"})
	}

	var request models.SetPINRequest
	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.Service.SetUserPIN(c.Context(), userID, request.PIN); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message": "PIN set successfully",
		"has_pin": true,
	})
}

func (h *AuthHandler) VerifyPIN(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authentication required"})
	}

	var request models.VerifyPINRequest
	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	valid, err := h.Service.VerifyUserPIN(c.Context(), userID, request.PIN)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	if !valid {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"valid": false,
			"error": "Incorrect PIN",
		})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"valid":   true,
		"message": "PIN verified successfully",
	})
}

func (h *AuthHandler) ChangePIN(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authentication required"})
	}

	var request models.ChangePINRequest
	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.Service.ChangeUserPIN(c.Context(), userID, request.OldPIN, request.NewPIN); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message": "PIN changed successfully",
		"has_pin": true,
	})
}

func (h *AuthHandler) LoginWithPIN(c *fiber.Ctx) error {
	var request models.LoginWithPINRequest
	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	result, err := h.Service.LoginWithPIN(c.Context(), request.Identifier, request.PIN)
	if err != nil {
		errMsg := err.Error()
		if strings.Contains(strings.ToLower(errMsg), "locked") {
			return c.Status(fiber.StatusLocked).JSON(fiber.Map{
				"error":          errMsg,
				"account_locked": true,
			})
		}
		if strings.Contains(errMsg, "seconds") {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error":        errMsg,
				"retry_after":  30,
				"rate_limited": true,
			})
		}
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": errMsg,
		})
	}

	return c.Status(fiber.StatusOK).JSON(result)
}
