package handlers

import (
	"context"

	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/services"
)

type BookingQueryHandler struct {
	Service *services.BookingQueryService
}

func NewBookingQueryHandler(
	service *services.BookingQueryService,
) *BookingQueryHandler {
	return &BookingQueryHandler{
		Service: service,
	}
}

func (h *BookingQueryHandler) GetBookingsForRide(
	c *fiber.Ctx,
) error {
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

	bookings, err := h.Service.GetBookingsForRide(
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

		return c.Status(fiber.StatusInternalServerError).JSON(
			fiber.Map{
				"error": err.Error(),
			},
		)
	}

	return c.JSON(
		fiber.Map{
			"bookings": bookings,
		},
	)
}

func (h *BookingQueryHandler) GetBookingsForPassenger(
	c *fiber.Ctx,
) error {
	passengerID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	bookings, err := h.Service.GetBookingsForPassenger(
		context.Background(),
		passengerID,
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
			"bookings": bookings,
		},
	)
}

func (h *BookingQueryHandler) GetBookingByID(
	c *fiber.Ctx,
) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	bookingID := c.Params("booking_id")

	if bookingID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "booking_id is required",
			},
		)
	}

	booking, err := h.Service.GetBookingByID(
		context.Background(),
		bookingID,
		userID,
	)

	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(
			fiber.Map{
				"error": "booking not found or access denied",
			},
		)
	}

	return c.JSON(
		fiber.Map{
			"booking": booking,
		},
	)
}

func (h *BookingQueryHandler) GetBookingContact(
	c *fiber.Ctx,
) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	bookingID := c.Params("booking_id")
	if bookingID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "booking_id is required",
			},
		)
	}

	contact, err := h.Service.GetBookingContact(
		c.Context(),
		bookingID,
		userID,
	)

	if err != nil {
		if err.Error() == "booking not found or access denied" {
			return c.Status(fiber.StatusNotFound).JSON(
				fiber.Map{
					"error": err.Error(),
				},
			)
		}
		if err.Error() == "phone contact is only available for confirmed bookings" {
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
			"contact": contact,
		},
	)
}
