package handlers

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/abhishare16/Abhi-Share/backend/services"
)

type LocationHandler struct {
	Service         *services.LocationService
	RouteService    *services.RouteService
	GeoapifyAPIKey  string
	GeoapifyAPIKeys []string
	HTTPClient      *http.Client
}

func NewLocationHandler(service *services.LocationService, routeService *services.RouteService, geoapifyAPIKeys ...string) *LocationHandler {
	var keys []string
	for _, k := range geoapifyAPIKeys {
		k = strings.TrimSpace(k)
		if k != "" {
			keys = append(keys, k)
		}
	}
	primary := ""
	if len(keys) > 0 {
		primary = keys[0]
	}
	return &LocationHandler{
		Service:         service,
		RouteService:    routeService,
		GeoapifyAPIKey:  primary,
		GeoapifyAPIKeys: keys,
		HTTPClient:      &http.Client{Timeout: 12 * time.Second},
	}
}

func (h *LocationHandler) CreateLocation(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	var req models.CreateSavedLocationRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request"})
	}

	loc, err := h.Service.CreateLocation(c.Context(), userID, req)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusCreated).JSON(loc)
}

func (h *LocationHandler) GetLocations(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
	}

	locs, err := h.Service.GetLocations(c.Context(), userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	if locs == nil {
		locs = []models.SavedLocation{}
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"locations": locs,
	})
}

// Internal Geoapify GeoJSON structure
type geoapifyFeature struct {
	Properties struct {
		Name         string  `json:"name"`
		Formatted    string  `json:"formatted"`
		AddressLine1 string  `json:"address_line1"`
		AddressLine2 string  `json:"address_line2"`
		City         string  `json:"city"`
		State        string  `json:"state"`
		Country      string  `json:"country"`
		Lat          float64 `json:"lat"`
		Lon          float64 `json:"lon"`
		PlaceID      string  `json:"place_id"`
	} `json:"properties"`
	Geometry struct {
		Coordinates []float64 `json:"coordinates"`
	} `json:"geometry"`
}

type geoapifyResponse struct {
	Features []geoapifyFeature `json:"features"`
}

func (h *LocationHandler) getKeys() []string {
	keys := h.GeoapifyAPIKeys
	if len(keys) == 0 && h.GeoapifyAPIKey != "" {
		keys = []string{h.GeoapifyAPIKey}
	}
	return keys
}

// Autocomplete handles search-as-you-type queries via Geoapify
func (h *LocationHandler) Autocomplete(c *fiber.Ctx) error {
	keys := h.getKeys()
	if len(keys) == 0 {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Geoapify API key is not configured on the server. Please set GEOAPIFY_API_KEY in backend environment.",
		})
	}

	q := strings.TrimSpace(c.Query("q"))
	if q == "" {
		q = strings.TrimSpace(c.Query("text"))
	}
	if q == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Query parameter 'q' is required",
		})
	}

	var lastErr error
	var bodyBytes []byte

	for _, apiKey := range keys {
		geoapifyURL := fmt.Sprintf(
			"https://api.geoapify.com/v1/geocode/autocomplete?text=%s&filter=countrycode:in&limit=5&apiKey=%s",
			url.QueryEscape(q),
			url.QueryEscape(apiKey),
		)

		req, err := http.NewRequestWithContext(c.Context(), http.MethodGet, geoapifyURL, nil)
		if err != nil {
			lastErr = err
			continue
		}
		req.Header.Set("User-Agent", "AbhiShare-Backend/1.0")

		resp, err := h.HTTPClient.Do(req)
		if err != nil {
			lastErr = err
			continue
		}

		b, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		if readErr != nil {
			lastErr = readErr
			continue
		}

		if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
			lastErr = fmt.Errorf("Geoapify returned status %d: %s", resp.StatusCode, string(b))
			continue
		}

		if resp.StatusCode != http.StatusOK {
			return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{
				"error": fmt.Sprintf("Geoapify returned status %d: %s", resp.StatusCode, string(b)),
			})
		}

		bodyBytes = b
		lastErr = nil
		break
	}

	if lastErr != nil {
		return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{
			"error": fmt.Sprintf("All Geoapify API keys exhausted or failed: %v", lastErr),
		})
	}

	var geoResp geoapifyResponse
	if err := json.Unmarshal(bodyBytes, &geoResp); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to parse Geoapify response: %v", err),
		})
	}

	results := make([]models.AutocompleteLocation, 0, len(geoResp.Features))
	for _, feat := range geoResp.Features {
		lat := feat.Properties.Lat
		lon := feat.Properties.Lon
		if lat == 0 && lon == 0 && len(feat.Geometry.Coordinates) >= 2 {
			lon = feat.Geometry.Coordinates[0]
			lat = feat.Geometry.Coordinates[1]
		}

		name := strings.TrimSpace(feat.Properties.Name)
		if name == "" {
			name = strings.TrimSpace(feat.Properties.AddressLine1)
		}
		if name == "" && feat.Properties.Formatted != "" {
			parts := strings.Split(feat.Properties.Formatted, ",")
			if len(parts) > 0 {
				name = strings.TrimSpace(parts[0])
			}
		}

		formatted := strings.TrimSpace(feat.Properties.Formatted)
		if formatted == "" {
			var parts []string
			if feat.Properties.AddressLine1 != "" {
				parts = append(parts, feat.Properties.AddressLine1)
			}
			if feat.Properties.AddressLine2 != "" {
				parts = append(parts, feat.Properties.AddressLine2)
			}
			formatted = strings.Join(parts, ", ")
		}

		results = append(results, models.AutocompleteLocation{
			Name:             name,
			FormattedAddress: formatted,
			Latitude:         lat,
			Longitude:        lon,
			PlaceID:          feat.Properties.PlaceID,
		})
	}

	return c.Status(fiber.StatusOK).JSON(models.AutocompleteResponse{
		Results: results,
	})
}

// ReverseGeocode resolves lat & lon to a human-readable location
func (h *LocationHandler) ReverseGeocode(c *fiber.Ctx) error {
	keys := h.getKeys()
	if len(keys) == 0 {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Geoapify API key is not configured on the server. Please set GEOAPIFY_API_KEY in backend environment.",
		})
	}

	latStr := strings.TrimSpace(c.Query("lat"))
	if latStr == "" {
		latStr = strings.TrimSpace(c.Query("latitude"))
	}
	lonStr := strings.TrimSpace(c.Query("lon"))
	if lonStr == "" {
		lonStr = strings.TrimSpace(c.Query("longitude"))
	}

	if latStr == "" || lonStr == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Parameters 'lat' and 'lon' are required",
		})
	}

	lat, err1 := strconv.ParseFloat(latStr, 64)
	lon, err2 := strconv.ParseFloat(lonStr, 64)
	if err1 != nil || err2 != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid latitude or longitude value",
		})
	}

	var lastErr error
	var bodyBytes []byte

	for _, apiKey := range keys {
		geoapifyURL := fmt.Sprintf(
			"https://api.geoapify.com/v1/geocode/reverse?lat=%f&lon=%f&apiKey=%s",
			lat,
			lon,
			url.QueryEscape(apiKey),
		)

		req, err := http.NewRequestWithContext(c.Context(), http.MethodGet, geoapifyURL, nil)
		if err != nil {
			lastErr = err
			continue
		}
		req.Header.Set("User-Agent", "AbhiShare-Backend/1.0")

		resp, err := h.HTTPClient.Do(req)
		if err != nil {
			lastErr = err
			continue
		}

		b, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		if readErr != nil {
			lastErr = readErr
			continue
		}

		if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
			lastErr = fmt.Errorf("Geoapify returned status %d: %s", resp.StatusCode, string(b))
			continue
		}

		if resp.StatusCode != http.StatusOK {
			return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{
				"error": fmt.Sprintf("Geoapify returned status %d: %s", resp.StatusCode, string(b)),
			})
		}

		bodyBytes = b
		lastErr = nil
		break
	}

	if lastErr != nil {
		return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{
			"error": fmt.Sprintf("All Geoapify API keys exhausted or failed: %v", lastErr),
		})
	}

	var geoResp geoapifyResponse
	if err := json.Unmarshal(bodyBytes, &geoResp); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to parse Geoapify response: %v", err),
		})
	}

	if len(geoResp.Features) == 0 {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "No address found for the given coordinates",
		})
	}

	feat := geoResp.Features[0]
	rLat := feat.Properties.Lat
	rLon := feat.Properties.Lon
	if rLat == 0 && rLon == 0 && len(feat.Geometry.Coordinates) >= 2 {
		rLon = feat.Geometry.Coordinates[0]
		rLat = feat.Geometry.Coordinates[1]
	}
	if rLat == 0 {
		rLat = lat
	}
	if rLon == 0 {
		rLon = lon
	}

	name := strings.TrimSpace(feat.Properties.Name)
	if name == "" {
		name = strings.TrimSpace(feat.Properties.AddressLine1)
	}
	if name == "" && feat.Properties.Formatted != "" {
		parts := strings.Split(feat.Properties.Formatted, ",")
		if len(parts) > 0 {
			name = strings.TrimSpace(parts[0])
		}
	}

	formatted := strings.TrimSpace(feat.Properties.Formatted)
	if formatted == "" {
		var parts []string
		if feat.Properties.AddressLine1 != "" {
			parts = append(parts, feat.Properties.AddressLine1)
		}
		if feat.Properties.AddressLine2 != "" {
			parts = append(parts, feat.Properties.AddressLine2)
		}
		formatted = strings.Join(parts, ", ")
	}

	return c.Status(fiber.StatusOK).JSON(models.AutocompleteLocation{
		Name:             name,
		FormattedAddress: formatted,
		Latitude:         rLat,
		Longitude:        rLon,
		PlaceID:          feat.Properties.PlaceID,
	})
}

// CalculateRoutes calculates distinct driving route candidates for driver route selection
func (h *LocationHandler) CalculateRoutes(c *fiber.Ctx) error {
	if h.RouteService == nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Route service is not configured",
		})
	}

	fromLatStr := strings.TrimSpace(c.Query("from_lat"))
	fromLonStr := strings.TrimSpace(c.Query("from_lon"))
	toLatStr := strings.TrimSpace(c.Query("to_lat"))
	toLonStr := strings.TrimSpace(c.Query("to_lon"))

	type routeReqBody struct {
		FromLat float64 `json:"from_lat"`
		FromLon float64 `json:"from_lon"`
		ToLat   float64 `json:"to_lat"`
		ToLon   float64 `json:"to_lon"`
	}

	var reqBody routeReqBody
	if c.Method() == fiber.MethodPost {
		_ = c.BodyParser(&reqBody)
	}

	var fromLat, fromLon, toLat, toLon float64
	var err error

	if reqBody.FromLat != 0 || reqBody.FromLon != 0 {
		fromLat = reqBody.FromLat
		fromLon = reqBody.FromLon
		toLat = reqBody.ToLat
		toLon = reqBody.ToLon
	} else {
		if fromLatStr == "" || fromLonStr == "" || toLatStr == "" || toLonStr == "" {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Coordinates 'from_lat', 'from_lon', 'to_lat', and 'to_lon' are required",
			})
		}
		fromLat, err = strconv.ParseFloat(fromLatStr, 64)
		if err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid from_lat"})
		}
		fromLon, err = strconv.ParseFloat(fromLonStr, 64)
		if err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid from_lon"})
		}
		toLat, err = strconv.ParseFloat(toLatStr, 64)
		if err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid to_lat"})
		}
		toLon, err = strconv.ParseFloat(toLonStr, 64)
		if err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid to_lon"})
		}
	}

	result, err := h.RouteService.CalculateRoutes(c.Context(), fromLat, fromLon, toLat, toLon)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	// Generate static map URL pointing to our backend proxy endpoint
	result.StaticMapURL = fmt.Sprintf(
		"/locations/route-map?from_lat=%f&from_lon=%f&to_lat=%f&to_lon=%f",
		fromLat, fromLon, toLat, toLon,
	)

	return c.Status(fiber.StatusOK).JSON(result)
}

// GetRouteMap serves a static map preview keeping the API key strictly on the backend
func (h *LocationHandler) GetRouteMap(c *fiber.Ctx) error {
	fromLatStr := strings.TrimSpace(c.Query("from_lat"))
	fromLonStr := strings.TrimSpace(c.Query("from_lon"))
	toLatStr := strings.TrimSpace(c.Query("to_lat"))
	toLonStr := strings.TrimSpace(c.Query("to_lon"))

	if fromLatStr == "" || fromLonStr == "" || toLatStr == "" || toLonStr == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "from_lat, from_lon, to_lat, to_lon are required",
		})
	}

	fromLat, err1 := strconv.ParseFloat(fromLatStr, 64)
	fromLon, err2 := strconv.ParseFloat(fromLonStr, 64)
	toLat, err3 := strconv.ParseFloat(toLatStr, 64)
	toLon, err4 := strconv.ParseFloat(toLonStr, 64)
	if err1 != nil || err2 != nil || err3 != nil || err4 != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid coordinates"})
	}

	keys := h.getKeys()
	if len(keys) == 0 {
		return c.Status(fiber.StatusInternalServerError).SendString("Geoapify key not configured")
	}

	midLon := (fromLon + toLon) / 2.0
	midLat := (fromLat + toLat) / 2.0

	var lastErr error
	var imgBytes []byte
	var lastStatus int

	for _, apiKey := range keys {
		// Geoapify Static Map API request
		geoapifyURL := fmt.Sprintf(
			"https://maps.geoapify.com/v1/staticmap?style=osm-bright-smooth&width=600&height=360&center=lonlat:%f,%f&marker=lonlat:%f,%f;color:%%230b5fd1;text:A|lonlat:%f,%f;color:%%23e5484d;text:B&apiKey=%s",
			midLon, midLat,
			fromLon, fromLat,
			toLon, toLat,
			url.QueryEscape(apiKey),
		)

		req, err := http.NewRequestWithContext(c.Context(), http.MethodGet, geoapifyURL, nil)
		if err != nil {
			lastErr = err
			continue
		}
		req.Header.Set("User-Agent", "AbhiShare-Backend/1.0")

		resp, err := h.HTTPClient.Do(req)
		if err != nil {
			lastErr = err
			continue
		}

		b, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		if readErr != nil {
			lastErr = readErr
			continue
		}

		if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
			lastStatus = resp.StatusCode
			lastErr = fmt.Errorf("status %d", resp.StatusCode)
			continue
		}

		if resp.StatusCode != http.StatusOK {
			return c.Status(resp.StatusCode).SendString("Failed to render map")
		}

		imgBytes = b
		lastErr = nil
		break
	}

	if lastErr != nil {
		if lastStatus != 0 {
			return c.Status(lastStatus).SendString("Failed to render map: all keys exhausted")
		}
		return c.Status(fiber.StatusBadGateway).SendString("Failed to fetch map from provider")
	}

	c.Set("Content-Type", "image/jpeg")
	c.Set("Cache-Control", "public, max-age=86400")
	return c.Status(fiber.StatusOK).Send(imgBytes)
}

