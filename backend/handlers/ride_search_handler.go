package handlers

import (
	"strconv"

	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/services"
)

type RideSearchHandler struct {
	Service *services.RideSearchService
}

func NewRideSearchHandler(
	service *services.RideSearchService,
) *RideSearchHandler {
	return &RideSearchHandler{
		Service: service,
	}
}

func (h *RideSearchHandler) SearchRides(c *fiber.Ctx) error {
	fromLocation := c.Query("from")
	toLocation := c.Query("to")
	journeyDate := c.Query("date")

	if fromLocation == "" ||
		toLocation == "" ||
		journeyDate == "" {
		return c.Status(fiber.StatusBadRequest).JSON(
			fiber.Map{
				"error": "from, to and date are required",
			},
		)
	}

	fromLatStr := c.Query("from_lat")
	fromLonStr := c.Query("from_lon")
	toLatStr := c.Query("to_lat")
	toLonStr := c.Query("to_lon")

	var fromLat, fromLon, toLat, toLon *float64
	if fLat, err := strconv.ParseFloat(fromLatStr, 64); err == nil {
		fromLat = &fLat
	}
	if fLon, err := strconv.ParseFloat(fromLonStr, 64); err == nil {
		fromLon = &fLon
	}
	if tLat, err := strconv.ParseFloat(toLatStr, 64); err == nil {
		toLat = &tLat
	}
	if tLon, err := strconv.ParseFloat(toLonStr, 64); err == nil {
		toLon = &tLon
	}

	rides, err := h.Service.SearchRides(
		c.Context(),
		fromLocation,
		toLocation,
		journeyDate,
		fromLat,
		fromLon,
		toLat,
		toLon,
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
			"rides": rides,
		},
	)
}
