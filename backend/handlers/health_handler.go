package handlers

import (
	"context"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/config"
)

type HealthHandler struct {
	Cfg *config.Config
	DB  *pgxpool.Pool
}

func NewHealthHandler(cfg *config.Config, db *pgxpool.Pool) *HealthHandler {
	return &HealthHandler{
		Cfg: cfg,
		DB:  db,
	}
}

func (h *HealthHandler) Check(c *fiber.Ctx) error {
	ctx, cancel := context.WithTimeout(c.Context(), 3*time.Second)
	defer cancel()

	dbStatus := "connected"
	if h.DB != nil {
		if err := h.DB.Ping(ctx); err != nil {
			dbStatus = "disconnected"
			return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
				"status":      "degraded",
				"service":     "abhishare-api",
				"environment": h.Cfg.AppEnv,
				"database":    dbStatus,
			})
		}
	}

	return c.JSON(fiber.Map{
		"status":      "ok",
		"service":     "abhishare-api",
		"environment": h.Cfg.AppEnv,
		"database":    dbStatus,
	})
}
