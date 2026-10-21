package handlers_test

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/handlers"
	"github.com/abhishare16/Abhi-Share/backend/models"
)

// RoundTripFunc allows creating custom http.RoundTripper for mocking HTTP client calls
type roundTripFunc func(req *http.Request) *http.Response

func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req), nil
}

func TestLocationHandler_Autocomplete_MissingAPIKey(t *testing.T) {
	h := handlers.NewLocationHandler(nil, nil, "")
	app := fiber.New()
	app.Get("/locations/autocomplete", h.Autocomplete)

	req := httptest.NewRequest(http.MethodGet, "/locations/autocomplete?q=Hyde", nil)
	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if resp.StatusCode != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", resp.StatusCode)
	}
}

func TestLocationHandler_Autocomplete_MissingQuery(t *testing.T) {
	h := handlers.NewLocationHandler(nil, nil, "test-api-key")
	app := fiber.New()
	app.Get("/locations/autocomplete", h.Autocomplete)

	req := httptest.NewRequest(http.MethodGet, "/locations/autocomplete?q=", nil)
	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", resp.StatusCode)
	}
}

func TestLocationHandler_Autocomplete_Success(t *testing.T) {
	mockGeoapifyJSON := `{
		"type": "FeatureCollection",
		"features": [
			{
				"type": "Feature",
				"properties": {
					"name": "Hyderabad",
					"formatted": "Hyderabad, Telangana, India",
					"address_line1": "Hyderabad",
					"address_line2": "Telangana, India",
					"lat": 17.360589,
					"lon": 78.4740613,
					"place_id": "test-place-123"
				},
				"geometry": {
					"type": "Point",
					"coordinates": [78.4740613, 17.360589]
				}
			}
		]
	}`

	h := handlers.NewLocationHandler(nil, nil, "test-api-key")
	h.HTTPClient = &http.Client{
		Transport: roundTripFunc(func(req *http.Request) *http.Response {
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(stringsReader(mockGeoapifyJSON)),
				Header:     make(http.Header),
			}
		}),
	}

	app := fiber.New()
	app.Get("/locations/autocomplete", h.Autocomplete)

	req := httptest.NewRequest(http.MethodGet, "/locations/autocomplete?q=Hyde", nil)
	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var result models.AutocompleteResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if len(result.Results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(result.Results))
	}

	loc := result.Results[0]
	if loc.Name != "Hyderabad" {
		t.Errorf("expected name 'Hyderabad', got %q", loc.Name)
	}
	if loc.FormattedAddress != "Hyderabad, Telangana, India" {
		t.Errorf("expected formatted 'Hyderabad, Telangana, India', got %q", loc.FormattedAddress)
	}
	if loc.Latitude != 17.360589 || loc.Longitude != 78.4740613 {
		t.Errorf("expected lat 17.360589, lon 78.4740613, got %f, %f", loc.Latitude, loc.Longitude)
	}
	if loc.PlaceID != "test-place-123" {
		t.Errorf("expected place_id 'test-place-123', got %q", loc.PlaceID)
	}
}

func stringsReader(s string) io.Reader {
	return &testStringReader{s: s, i: 0}
}

type testStringReader struct {
	s string
	i int
}

func (r *testStringReader) Read(b []byte) (int, error) {
	if r.i >= len(r.s) {
		return 0, io.EOF
	}
	n := copy(b, r.s[r.i:])
	r.i += n
	return n, nil
}
