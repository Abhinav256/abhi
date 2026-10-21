package handlers

import (
	"context"
	"fmt"

	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/abhishare16/Abhi-Share/backend/services"
)

type BookingHandler struct {
	Service *services.BookingService
}

func NewBookingHandler(
	service *services.BookingService,
) *BookingHandler {
	return &BookingHandler{
		Service: service,
	}
}

func (h *BookingHandler) CreateBooking(c *fiber.Ctx) error {
	passengerID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(
			fiber.Map{
				"error": "authenticated user required",
			},
		)
	}

	var request models.CreateBookingRequest

	if err := c.BodyParser(&request); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Invalid request body",
			},
		)
	}

	// Never trust passenger_id supplied by the client.
	request.PassengerID = passengerID

	if len(request.Passengers) > 0 {
		if request.PassengerName == "" {
			request.PassengerName = request.Passengers[0].Name
		}
		if request.PassengerAge == 0 {
			request.PassengerAge = request.Passengers[0].Age
		}
		if request.PassengerGender == "" {
			request.PassengerGender = request.Passengers[0].Gender
		}
		if request.SeatsBooked <= 0 {
			request.SeatsBooked = len(request.Passengers)
		}
	} else if request.PassengerName != "" {
		request.Passengers = []models.PassengerInput{
			{
				Name:   request.PassengerName,
				Age:    request.PassengerAge,
				Gender: request.PassengerGender,
			},
		}
		if request.SeatsBooked <= 0 {
			request.SeatsBooked = 1
		}
	}

	if request.RideID == "" ||
		request.PaymentMode == "" ||
		len(request.Passengers) == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "Missing required booking details",
			},
		)
	}

	for idx, p := range request.Passengers {
		if p.Name == "" || p.Gender == "" {
			return c.Status(fiber.StatusBadRequest).JSON(
				fiber.Map{
					"error": fmt.Sprintf("Missing details for passenger %d", idx+1),
				},
			)
		}
		if p.Age < 18 {
			return c.Status(fiber.StatusBadRequest).JSON(
				fiber.Map{
					"error": fmt.Sprintf("Passenger %d must be at least 18 years old", idx+1),
				},
			)
		}
	}

	bookingID, err := h.Service.CreateBooking(
		context.Background(),
		request,
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
			"message":    "Booking created successfully",
			"booking_id": bookingID,
		},
	)
}

func (h *BookingHandler) CancelBooking(c *fiber.Ctx) error {
	passengerID, ok := middleware.UserID(c)
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

	err := h.Service.CancelBooking(
		context.Background(),
		bookingID,
		passengerID,
	)

	if err != nil {
		if err.Error() == "you do not have access to this booking" {
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
			"message": "Booking cancelled successfully",
		},
	)
}
