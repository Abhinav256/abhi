package handlers

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/config"
)

func TestHealthHandler_Production(t *testing.T) {
	app := fiber.New()
	cfg := &config.Config{
		AppEnv: "production",
	}

	handler := NewHealthHandler(cfg, nil)
	app.Get("/health", handler.Check)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	resp, err := app.Test(req, -1)
	if err != nil {
		t.Fatalf("failed to execute test request: %v", err)
	}

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected status 200 OK, got %d", resp.StatusCode)
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("failed to read response body: %v", err)
	}

	var data map[string]interface{}
	if err := json.Unmarshal(bodyBytes, &data); err != nil {
		t.Fatalf("failed to parse JSON response: %v", err)
	}

	if data["status"] != "ok" {
		t.Errorf("expected status 'ok', got %v", data["status"])
	}
	if data["environment"] != "production" {
		t.Errorf("expected environment 'production', got %v", data["environment"])
	}
	if data["service"] != "abhishare-api" {
		t.Errorf("expected service 'abhishare-api', got %v", data["service"])
	}
	if data["database"] != "connected" {
		t.Errorf("expected database 'connected', got %v", data["database"])
	}
}

func TestHealthHandler_Development(t *testing.T) {
	app := fiber.New()
	cfg := &config.Config{
		AppEnv: "development",
	}

	handler := NewHealthHandler(cfg, nil)
	app.Get("/health", handler.Check)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	resp, err := app.Test(req, -1)
	if err != nil {
		t.Fatalf("failed to execute test request: %v", err)
	}

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected status 200 OK, got %d", resp.StatusCode)
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("failed to read response body: %v", err)
	}

	var data map[string]interface{}
	if err := json.Unmarshal(bodyBytes, &data); err != nil {
		t.Fatalf("failed to parse JSON response: %v", err)
	}

	if data["environment"] != "development" {
		t.Errorf("expected environment 'development', got %v", data["environment"])
	}
}
