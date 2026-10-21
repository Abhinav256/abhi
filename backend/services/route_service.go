package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"sync"
	"time"
)

// RouteWaypoint represents an intermediate town or pickup/drop coordinate along a route.
type RouteWaypoint struct {
	Name               string  `json:"name"`
	Category           string  `json:"category,omitempty"` // "town", "village", "city", "hamlet", etc.
	Latitude           float64 `json:"latitude"`
	Longitude          float64 `json:"longitude"`
	DistanceAlongRoute float64 `json:"distance_along_route_meters"`
}

// RouteOption represents a distinct driving route calculated between origin and destination.
type RouteOption struct {
	ID                 string          `json:"id"`
	Title              string          `json:"title"`
	Summary            string          `json:"summary"`
	DistanceMeters     float64         `json:"distance_meters"`
	DistanceKm         float64         `json:"distance_km"`
	DurationSeconds    float64         `json:"duration_seconds"`
	DurationMinutes    int             `json:"duration_minutes"`
	DurationFormatted  string          `json:"duration_formatted"`
	HasTolls           bool            `json:"has_tolls"`
	IntermediatePoints []RouteWaypoint `json:"intermediate_points"`
	Coordinates        [][]float64     `json:"coordinates"` // Array of [lon, lat]
}

// RouteCalculationResult is the response sent to the mobile client during ride creation.
type RouteCalculationResult struct {
	Routes        []RouteOption `json:"routes"`
	DefaultRoute  *RouteOption  `json:"default_route"`
	StaticMapURL  string        `json:"static_map_url,omitempty"`
}

// RouteMatchResult holds the outcome of matching a passenger's segment against a driver's route.
type RouteMatchResult struct {
	IsMatched               bool    `json:"is_matched"`
	PickupDistanceMeters    float64 `json:"pickup_distance_meters"`
	DropDistanceMeters      float64 `json:"drop_distance_meters"`
	SegmentDistanceMeters   float64 `json:"segment_distance_meters"`
	SegmentDistanceKm       float64 `json:"segment_distance_km"`
	TotalRouteDistanceKm    float64 `json:"total_route_distance_km"`
	SegmentRatio            float64 `json:"segment_ratio"`
	PickupPerpendicularDist float64 `json:"pickup_perpendicular_dist_meters"`
	DropPerpendicularDist   float64 `json:"drop_perpendicular_dist_meters"`
	Reason                  string  `json:"reason,omitempty"`
}

// BookingSegment represents an existing confirmed booking's interval along the route.
type BookingSegment struct {
	BookingID          string
	SeatsBooked        int
	PickupDistanceAlong float64
	DropDistanceAlong   float64
}

// cacheEntry stores cached route calculations.
type routeCacheEntry struct {
	result    RouteCalculationResult
	expiresAt time.Time
}

type settlementCacheEntry struct {
	waypoints []RouteWaypoint
	expiresAt time.Time
}

type RouteService struct {
	GeoapifyAPIKey   string
	GeoapifyAPIKeys  []string
	HTTPClient       *http.Client
	cache            map[string]routeCacheEntry
	cacheMu          sync.RWMutex
	settlementsCache map[string]settlementCacheEntry
	settlementsMu    sync.RWMutex
}

func NewRouteService(geoapifyAPIKeys ...string) *RouteService {
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
	return &RouteService{
		GeoapifyAPIKey:   primary,
		GeoapifyAPIKeys:  keys,
		HTTPClient:       &http.Client{Timeout: 12 * time.Second},
		cache:            make(map[string]routeCacheEntry),
		settlementsCache: make(map[string]settlementCacheEntry),
	}
}

// cacheKey creates a coarse spatial key (rounded to 3 decimal places ~110m) to cache routes.
func cacheKey(fromLat, fromLon, toLat, toLon float64) string {
	return fmt.Sprintf("%.3f,%.3f->%.3f,%.3f", fromLat, fromLon, toLat, toLon)
}

// CalculateRoutes queries Geoapify Routing API with different preferences (fastest, avoid tolls, short)
// to produce distinct driving route candidates, deduplicating very similar paths.
func (s *RouteService) CalculateRoutes(
	ctx context.Context,
	fromLat, fromLon, toLat, toLon float64,
) (*RouteCalculationResult, error) {
	if len(s.GeoapifyAPIKeys) == 0 && s.GeoapifyAPIKey == "" {
		return nil, fmt.Errorf("GEOAPIFY_API_KEY is not configured on the backend")
	}

	key := cacheKey(fromLat, fromLon, toLat, toLon)
	s.cacheMu.RLock()
	entry, exists := s.cache[key]
	s.cacheMu.RUnlock()
	if exists && time.Now().Before(entry.expiresAt) {
		return &entry.result, nil
	}

	type variantSpec struct {
		id       string
		title    string
		urlQuery string
	}

	variants := []variantSpec{
		{
			id:       "fastest",
			title:    "Fastest Route",
			urlQuery: "", // default drive
		},
		{
			id:       "toll_free",
			title:    "Toll-Free Route",
			urlQuery: "&avoid=tolls",
		},
		{
			id:       "shortest",
			title:    "Shortest Distance",
			urlQuery: "&type=short",
		},
	}

	var candidates []RouteOption

	for _, v := range variants {
		opt, err := s.fetchGeoapifyRoute(ctx, fromLat, fromLon, toLat, toLon, v.id, v.title, v.urlQuery)
		if err != nil {
			continue
		}
		if opt == nil || len(opt.Coordinates) < 2 {
			continue
		}

		// Check for near-duplicates among already accepted candidates
		isDuplicate := false
		for _, existing := range candidates {
			distDiffPct := math.Abs(existing.DistanceMeters-opt.DistanceMeters) / math.Max(existing.DistanceMeters, 1) * 100
			timeDiffPct := math.Abs(existing.DurationSeconds-opt.DurationSeconds) / math.Max(existing.DurationSeconds, 1) * 100
			if distDiffPct < 2.0 && timeDiffPct < 2.0 {
				isDuplicate = true
				break
			}
		}

		if !isDuplicate {
			candidates = append(candidates, *opt)
		}
	}

	// Fallback if variants failed but at least one basic route is needed
	if len(candidates) == 0 {
		opt, err := s.fetchGeoapifyRoute(ctx, fromLat, fromLon, toLat, toLon, "default", "Recommended Route", "")
		if err != nil {
			return nil, fmt.Errorf("failed to calculate routes: %w", err)
		}
		if opt != nil {
			candidates = append(candidates, *opt)
		}
	}

	if len(candidates) == 0 {
		return nil, fmt.Errorf("no driving route available between these locations")
	}

	// Concurrently discover settlements (towns, villages, hamlets, cities) along each route candidate
	var wg sync.WaitGroup
	for i := range candidates {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			settlements, err := s.DiscoverSettlementsAlongRoute(ctx, candidates[idx].Coordinates, 5000.0)
			if err == nil && len(settlements) > 0 {
				candidates[idx].IntermediatePoints = settlements

				// Enhance route summary with top prominent towns
				var townNames []string
				for _, st := range settlements {
					cat := strings.ToLower(st.Category)
					if cat == "town" || cat == "city" {
						townNames = append(townNames, st.Name)
					}
					if len(townNames) >= 3 {
						break
					}
				}
				if len(townNames) > 0 {
					existingRoads := candidates[idx].Summary
					if existingRoads != "" && existingRoads != candidates[idx].Title {
						candidates[idx].Summary = fmt.Sprintf("via %s (%s)", strings.Join(townNames, ", "), existingRoads)
					} else {
						candidates[idx].Summary = fmt.Sprintf("via %s", strings.Join(townNames, ", "))
					}
				}
			}
		}(i)
	}
	wg.Wait()

	res := RouteCalculationResult{
		Routes:       candidates,
		DefaultRoute: &candidates[0],
	}

	// Store in cache for 1 hour
	s.cacheMu.Lock()
	s.cache[key] = routeCacheEntry{
		result:    res,
		expiresAt: time.Now().Add(1 * time.Hour),
	}
	s.cacheMu.Unlock()

	return &res, nil
}

// geoapifyRoutingResponse models the Geoapify Routing GeoJSON response.
type geoapifyRoutingResponse struct {
	Features []struct {
		Properties struct {
			Distance float64 `json:"distance"`
			Time     float64 `json:"time"`
			Toll     any     `json:"toll"`
			Legs     []struct {
				Steps []struct {
					Instruction struct {
						Text string `json:"text"`
					} `json:"instruction"`
					Distance float64 `json:"distance"`
					Time     float64 `json:"time"`
					Street   string  `json:"street"`
					Name     string  `json:"name"`
					FromIndex int    `json:"from_index"`
					ToIndex   int    `json:"to_index"`
				} `json:"steps"`
			} `json:"legs"`
		} `json:"properties"`
		Geometry struct {
			Type        string `json:"type"`
			Coordinates any    `json:"coordinates"` // Can be [][]float64 (LineString) or [][][]float64 (MultiLineString)
		} `json:"geometry"`
	} `json:"features"`
}

func (s *RouteService) fetchGeoapifyRoute(
	ctx context.Context,
	fromLat, fromLon, toLat, toLon float64,
	id, title, extraParams string,
) (*RouteOption, error) {
	keys := s.GeoapifyAPIKeys
	if len(keys) == 0 && s.GeoapifyAPIKey != "" {
		keys = []string{s.GeoapifyAPIKey}
	}
	if len(keys) == 0 {
		return nil, fmt.Errorf("no geoapify api key configured")
	}

	var lastErr error
	var bodyBytes []byte

	for _, apiKey := range keys {
		reqURL := fmt.Sprintf(
			"https://api.geoapify.com/v1/routing?waypoints=%f,%f|%f,%f&mode=drive%s&apiKey=%s",
			fromLat, fromLon, toLat, toLon,
			extraParams,
			url.QueryEscape(apiKey),
		)

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
		if err != nil {
			lastErr = err
			continue
		}
		req.Header.Set("User-Agent", "AbhiShare-Backend/1.0")

		resp, err := s.HTTPClient.Do(req)
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

		// If hit rate limit or auth error on free tier, failover to next key
		if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
			lastErr = fmt.Errorf("geoapify routing status %d: %s", resp.StatusCode, string(b))
			continue
		}

		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("geoapify routing status %d: %s", resp.StatusCode, string(b))
		}

		bodyBytes = b
		lastErr = nil
		break
	}

	if lastErr != nil {
		return nil, fmt.Errorf("all geoapify api keys failed: %w", lastErr)
	}

	var geoResp geoapifyRoutingResponse
	if err := json.Unmarshal(bodyBytes, &geoResp); err != nil {
		return nil, err
	}

	if len(geoResp.Features) == 0 {
		return nil, fmt.Errorf("no route found in response")
	}

	feat := geoResp.Features[0]
	props := feat.Properties

	// Parse coordinates (supports both LineString and MultiLineString)
	var coords [][]float64
	coordsBytes, _ := json.Marshal(feat.Geometry.Coordinates)

	var lineCoords [][]float64
	if err := json.Unmarshal(coordsBytes, &lineCoords); err == nil && len(lineCoords) > 0 {
		coords = lineCoords
	} else {
		var multiCoords [][][]float64
		if err := json.Unmarshal(coordsBytes, &multiCoords); err == nil && len(multiCoords) > 0 {
			coords = multiCoords[0]
		}
	}

	if len(coords) < 2 {
		return nil, fmt.Errorf("empty geometry received")
	}

	// Extract road names / highways for summary
	var roadNames []string
	seenRoads := make(map[string]bool)

	var waypoints []RouteWaypoint
	cumulativeMeters := 0.0

	if len(props.Legs) > 0 {
		for _, step := range props.Legs[0].Steps {
			cumulativeMeters += step.Distance

			road := strings.TrimSpace(step.Street)
			if road == "" {
				road = strings.TrimSpace(step.Name)
			}
			if road == "" && strings.Contains(step.Instruction.Text, "onto ") {
				parts := strings.Split(step.Instruction.Text, "onto ")
				if len(parts) > 1 {
					road = strings.Trim(parts[1], " .")
				}
			}

			if road != "" && !seenRoads[road] {
				seenRoads[road] = true
				roadNames = append(roadNames, road)

				// Record major road waypoint with approximate coordinate
				if step.FromIndex >= 0 && step.FromIndex < len(coords) {
					pt := coords[step.FromIndex]
					waypoints = append(waypoints, RouteWaypoint{
						Name:               road,
						Longitude:          pt[0],
						Latitude:           pt[1],
						DistanceAlongRoute: cumulativeMeters,
					})
				}
			}
		}
	}

	var summary string
	if len(roadNames) > 0 {
		maxRoads := 3
		if len(roadNames) < maxRoads {
			maxRoads = len(roadNames)
		}
		summary = "via " + strings.Join(roadNames[:maxRoads], ", ")
	} else {
		summary = fmt.Sprintf("Direct route (%.1f km)", props.Distance/1000.0)
	}

	hasTolls := false
	if props.Toll != nil {
		if b, ok := props.Toll.(bool); ok && b {
			hasTolls = true
		} else if s, ok := props.Toll.(string); ok && s != "" && s != "false" {
			hasTolls = true
		}
	}

	durationMin := int(math.Round(props.Time / 60.0))
	hrs := durationMin / 60
	mins := durationMin % 60
	durationFormatted := ""
	if hrs > 0 {
		durationFormatted = fmt.Sprintf("%dh %02dm", hrs, mins)
	} else {
		durationFormatted = fmt.Sprintf("%d mins", mins)
	}

	return &RouteOption{
		ID:                 id,
		Title:              title,
		Summary:            summary,
		DistanceMeters:     props.Distance,
		DistanceKm:         math.Round((props.Distance/1000.0)*10) / 10,
		DurationSeconds:    props.Time,
		DurationMinutes:    durationMin,
		DurationFormatted:  durationFormatted,
		HasTolls:           hasTolls,
		IntermediatePoints: waypoints,
		Coordinates:        coords,
	}, nil
}

// settlementCategoryRank assigns precedence for deduplication (higher rank preferred).
func settlementCategoryRank(cat string) int {
	switch strings.ToLower(cat) {
	case "city":
		return 5
	case "town":
		return 4
	case "village":
		return 3
	case "hamlet":
		return 2
	case "suburb", "neighbourhood":
		return 1
	default:
		return 0
	}
}

// DiscoverSettlementsAlongRoute queries Geoapify Places API for populated places (cities, towns, villages, hamlets)
// along the route's polyline with a configurable corridor buffer (default ~5 km).
// It projects discovered settlements onto the route, sorts them in travel order, removes duplicates, and caches results.
func (s *RouteService) DiscoverSettlementsAlongRoute(
	ctx context.Context,
	coords [][]float64,
	bufferMeters float64,
) ([]RouteWaypoint, error) {
	if len(coords) < 2 {
		return nil, nil
	}
	if bufferMeters <= 0 {
		bufferMeters = 5000.0 // 5 km default
	}

	keys := s.GeoapifyAPIKeys
	if len(keys) == 0 && s.GeoapifyAPIKey != "" {
		keys = []string{s.GeoapifyAPIKey}
	}
	if len(keys) == 0 {
		return nil, fmt.Errorf("no geoapify api key configured")
	}

	totalDist := ComputeTotalPolylineDistance(coords)

	// Check cache
	cacheKey := fmt.Sprintf("%.4f,%.4f->%.4f,%.4f:%.0f:buf=%.0f",
		coords[0][1], coords[0][0],
		coords[len(coords)-1][1], coords[len(coords)-1][0],
		totalDist, bufferMeters,
	)

	s.settlementsMu.RLock()
	entry, exists := s.settlementsCache[cacheKey]
	s.settlementsMu.RUnlock()
	if exists && time.Now().Before(entry.expiresAt) {
		res := make([]RouteWaypoint, len(entry.waypoints))
		copy(res, entry.waypoints)
		return res, nil
	}

	// Sample coordinates if route polyline has many points (> 500)
	// Geoapify polyline filter accepts a GeoJSON LineString.
	sampledCoords := coords
	if len(coords) > 500 {
		step := (len(coords) / 400) + 1
		sampledCoords = make([][]float64, 0, (len(coords)/step)+2)
		sampledCoords = append(sampledCoords, coords[0])
		for i := 1; i < len(coords)-1; i += step {
			sampledCoords = append(sampledCoords, coords[i])
		}
		sampledCoords = append(sampledCoords, coords[len(coords)-1])
	}

	placesReq := map[string]interface{}{
		"categories": []string{
			"populated_place.city",
			"populated_place.town",
			"populated_place.village",
			"populated_place.hamlet",
		},
		"filter": map[string]interface{}{
			"type": "polyline",
			"geometry": map[string]interface{}{
				"type":        "LineString",
				"coordinates": sampledCoords,
			},
			"buffer": int(bufferMeters),
		},
		"limit": 100,
	}

	reqBodyBytes, err := json.Marshal(placesReq)
	if err != nil {
		return nil, err
	}

	var lastErr error
	var bodyBytes []byte

	for _, apiKey := range keys {
		reqURL := fmt.Sprintf("https://api.geoapify.com/v2/places?apiKey=%s", url.QueryEscape(apiKey))
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, reqURL, bytes.NewReader(reqBodyBytes))
		if err != nil {
			lastErr = err
			continue
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("User-Agent", "AbhiShare-Backend/1.0")

		resp, err := s.HTTPClient.Do(req)
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

		// Handle free-tier quota exhaustion or rate limits: retry with next key
		if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
			lastErr = fmt.Errorf("geoapify places status %d: %s", resp.StatusCode, string(b))
			continue
		}

		if resp.StatusCode != http.StatusOK {
			lastErr = fmt.Errorf("geoapify places status %d: %s", resp.StatusCode, string(b))
			continue
		}

		bodyBytes = b
		lastErr = nil
		break
	}

	if lastErr != nil {
		return nil, fmt.Errorf("geoapify places discovery failed: %w", lastErr)
	}

	var placesData struct {
		Features []struct {
			Properties struct {
				Name       string   `json:"name"`
				City       string   `json:"city"`
				Town       string   `json:"town"`
				Village    string   `json:"village"`
				Hamlet     string   `json:"hamlet"`
				Categories []string `json:"categories"`
				Lat        float64  `json:"lat"`
				Lon        float64  `json:"lon"`
				Datasource struct {
					Raw struct {
						Place string `json:"place"`
					} `json:"raw"`
				} `json:"datasource"`
			} `json:"properties"`
			Geometry struct {
				Coordinates []float64 `json:"coordinates"`
			} `json:"geometry"`
		} `json:"features"`
	}

	if err := json.Unmarshal(bodyBytes, &placesData); err != nil {
		return nil, err
	}

	type candidatePoint struct {
		wp       RouteWaypoint
		rank     int
		perpDist float64
	}

	var rawList []candidatePoint
	for _, f := range placesData.Features {
		name := strings.TrimSpace(f.Properties.Name)
		if name == "" {
			name = strings.TrimSpace(f.Properties.Town)
		}
		if name == "" {
			name = strings.TrimSpace(f.Properties.Village)
		}
		if name == "" {
			name = strings.TrimSpace(f.Properties.City)
		}
		if name == "" {
			name = strings.TrimSpace(f.Properties.Hamlet)
		}
		if name == "" {
			continue
		}

		lat := f.Properties.Lat
		lon := f.Properties.Lon
		if lat == 0 && lon == 0 && len(f.Geometry.Coordinates) >= 2 {
			lon = f.Geometry.Coordinates[0]
			lat = f.Geometry.Coordinates[1]
		}
		if lat == 0 && lon == 0 {
			continue
		}

		cat := strings.TrimSpace(f.Properties.Datasource.Raw.Place)
		if cat == "" {
			for _, c := range f.Properties.Categories {
				if strings.HasPrefix(c, "populated_place.") {
					cat = strings.TrimPrefix(c, "populated_place.")
					break
				}
			}
		}
		if cat == "" {
			cat = "settlement"
		}

		// Project onto the driving route polyline
		perpDist, distAlong := ProjectPointOnPolyline(coords, lat, lon)

		// Exclude points beyond our corridor buffer
		if perpDist > bufferMeters {
			continue
		}

		// Exclude points located within 1 km of origin or destination
		if distAlong < 1000.0 || distAlong > (totalDist-1000.0) {
			continue
		}

		rawList = append(rawList, candidatePoint{
			wp: RouteWaypoint{
				Name:               name,
				Category:           cat,
				Latitude:           lat,
				Longitude:          lon,
				DistanceAlongRoute: distAlong,
			},
			rank:     settlementCategoryRank(cat),
			perpDist: perpDist,
		})
	}

	// Sort candidate points in travel order along the route
	sort.Slice(rawList, func(i, j int) bool {
		return rawList[i].wp.DistanceAlongRoute < rawList[j].wp.DistanceAlongRoute
	})

	// Deduplication:
	// 1. Group / suppress identical or near-identical settlement names along the same stretch
	// 2. If two settlements are within 400m of each other, retain the higher category rank
	var deduplicated []RouteWaypoint
	type savedEntry struct {
		wp   RouteWaypoint
		rank int
	}
	var accepted []savedEntry

	for _, cand := range rawList {
		normName := strings.ToLower(cand.wp.Name)
		isDuplicate := false

		for i := len(accepted) - 1; i >= 0; i-- {
			prev := accepted[i]
			distDiff := math.Abs(cand.wp.DistanceAlongRoute - prev.wp.DistanceAlongRoute)
			if distDiff > 12000.0 {
				// No need to check further back than 12 km
				break
			}

			// Same name within 10 km corridor
			if strings.ToLower(prev.wp.Name) == normName {
				isDuplicate = true
				break
			}

			// Coordinates within 400m
			coordsDist := HaversineDistance(cand.wp.Latitude, cand.wp.Longitude, prev.wp.Latitude, prev.wp.Longitude)
			if coordsDist < 400.0 {
				// Very close to existing point: keep higher rank
				if cand.rank > prev.rank {
					accepted[i] = savedEntry{wp: cand.wp, rank: cand.rank}
				}
				isDuplicate = true
				break
			}
		}

		if !isDuplicate {
			accepted = append(accepted, savedEntry{wp: cand.wp, rank: cand.rank})
		}
	}

	for _, acc := range accepted {
		deduplicated = append(deduplicated, acc.wp)
	}

	// Save in cache (2 hours TTL)
	s.settlementsMu.Lock()
	s.settlementsCache[cacheKey] = settlementCacheEntry{
		waypoints: deduplicated,
		expiresAt: time.Now().Add(2 * time.Hour),
	}
	s.settlementsMu.Unlock()

	return deduplicated, nil
}


// ─────────────────────────────────────────────────────────────────────────────
// SPATIAL ROUTE MATCHING ALGORITHM
// ─────────────────────────────────────────────────────────────────────────────

// HaversineDistance calculates the great-circle distance between two points in meters.
func HaversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadiusMeters = 6371000.0
	dLat := (lat2 - lat1) * (math.Pi / 180.0)
	dLon := (lon2 - lon1) * (math.Pi / 180.0)

	rLat1 := lat1 * (math.Pi / 180.0)
	rLat2 := lat2 * (math.Pi / 180.0)

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(rLat1)*math.Cos(rLat2)*math.Sin(dLon/2)*math.Sin(dLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadiusMeters * c
}

// ProjectPointOnPolyline projects query point (lat, lon) onto a polyline of [lon, lat] coordinates.
// It returns:
// - minPerpDistMeters: minimum perpendicular distance from query point to the closest segment
// - distAlongRouteMeters: cumulative trajectory distance from route start to the projected point
func ProjectPointOnPolyline(coords [][]float64, lat, lon float64) (minPerpDistMeters float64, distAlongRouteMeters float64) {
	if len(coords) < 2 {
		return math.MaxFloat64, 0
	}

	minPerpDistMeters = math.MaxFloat64
	distAlongRouteMeters = 0.0

	cumulativeDist := 0.0
	bestCumulativeDist := 0.0

	// Pre-calculate cos(lat) approximation factor for local Cartesian projection
	degToRad := math.Pi / 180.0
	const earthRadiusMeters = 6371000.0

	for i := 0; i < len(coords)-1; i++ {
		p1Lon := coords[i][0]
		p1Lat := coords[i][1]
		p2Lon := coords[i+1][0]
		p2Lat := coords[i+1][1]

		segLength := HaversineDistance(p1Lat, p1Lon, p2Lat, p2Lon)
		if segLength < 0.1 {
			continue
		}

		// Equirectangular local projection around midpoint of segment
		midLatRad := ((p1Lat + p2Lat) / 2.0) * degToRad
		cosLat := math.Cos(midLatRad)

		// Vector P1 -> P2 in meters
		dx := (p2Lon - p1Lon) * degToRad * earthRadiusMeters * cosLat
		dy := (p2Lat - p1Lat) * degToRad * earthRadiusMeters

		// Vector P1 -> Q in meters
		qx := (lon - p1Lon) * degToRad * earthRadiusMeters * cosLat
		qy := (lat - p1Lat) * degToRad * earthRadiusMeters

		// Projection scalar u
		segLenSq := dx*dx + dy*dy
		u := 0.0
		if segLenSq > 0 {
			u = (qx*dx + qy*dy) / segLenSq
		}

		// Clamp u to segment [0, 1]
		if u < 0.0 {
			u = 0.0
		} else if u > 1.0 {
			u = 1.0
		}

		// Closest point on segment in local coordinates
		projX := dx * u
		projY := dy * u

		perpDist := math.Hypot(qx-projX, qy-projY)

		if perpDist < minPerpDistMeters {
			minPerpDistMeters = perpDist
			bestCumulativeDist = cumulativeDist + (u * segLength)
		}

		cumulativeDist += segLength
	}

	distAlongRouteMeters = bestCumulativeDist
	return minPerpDistMeters, distAlongRouteMeters
}

// ComputeTotalPolylineDistance returns the total length of a polyline in meters.
func ComputeTotalPolylineDistance(coords [][]float64) float64 {
	total := 0.0
	for i := 0; i < len(coords)-1; i++ {
		total += HaversineDistance(coords[i][1], coords[i][0], coords[i+1][1], coords[i+1][0])
	}
	return total
}

// MatchRouteSegment evaluates whether a passenger's pickup and destination fit along a driver's route polyline.
// Tolerance: maxPerpToleranceMeters (default 10,000 meters / 10 km).
func MatchRouteSegment(
	coords [][]float64,
	pickLat, pickLon, dropLat, dropLon float64,
	maxPerpToleranceMeters float64,
) RouteMatchResult {
	if len(coords) < 2 {
		return RouteMatchResult{IsMatched: false, Reason: "route geometry is missing or too short"}
	}

	if maxPerpToleranceMeters <= 0 {
		maxPerpToleranceMeters = 10000.0 // 10 km
	}

	pickPerpDist, pickDistAlong := ProjectPointOnPolyline(coords, pickLat, pickLon)
	dropPerpDist, dropDistAlong := ProjectPointOnPolyline(coords, dropLat, dropLon)

	totalDistance := ComputeTotalPolylineDistance(coords)
	if totalDistance < 100 {
		return RouteMatchResult{IsMatched: false, Reason: "route distance is negligible"}
	}

	// 1. Verify pickup lies within tolerance of the route
	if pickPerpDist > maxPerpToleranceMeters {
		return RouteMatchResult{
			IsMatched:               false,
			PickupPerpendicularDist: pickPerpDist,
			DropPerpendicularDist:   dropPerpDist,
			Reason:                  fmt.Sprintf("pickup is %.1f km away from route (max %.1f km)", pickPerpDist/1000.0, maxPerpToleranceMeters/1000.0),
		}
	}

	// 2. Verify destination lies within tolerance of the route
	if dropPerpDist > maxPerpToleranceMeters {
		return RouteMatchResult{
			IsMatched:               false,
			PickupPerpendicularDist: pickPerpDist,
			DropPerpendicularDist:   dropPerpDist,
			Reason:                  fmt.Sprintf("destination is %.1f km away from route (max %.1f km)", dropPerpDist/1000.0, maxPerpToleranceMeters/1000.0),
		}
	}

	// 3. Verify destination occurs farther along the route than pickup (trajectory ordering)
	segmentDistance := dropDistAlong - pickDistAlong
	if segmentDistance < 1000.0 {
		// Drop is behind pickup or practically at the same location (reject reverse or zero-distance journey)
		return RouteMatchResult{
			IsMatched:               false,
			PickupDistanceMeters:    pickDistAlong,
			DropDistanceMeters:      dropDistAlong,
			PickupPerpendicularDist: pickPerpDist,
			DropPerpendicularDist:   dropPerpDist,
			Reason:                  "destination is in reverse direction or before pickup along the route",
		}
	}

	ratio := segmentDistance / totalDistance
	if ratio > 1.0 {
		ratio = 1.0
	} else if ratio < 0.15 {
		ratio = 0.15 // Minimum 15% floor to avoid near-zero fractions
	}

	return RouteMatchResult{
		IsMatched:               true,
		PickupDistanceMeters:    pickDistAlong,
		DropDistanceMeters:      dropDistAlong,
		SegmentDistanceMeters:   segmentDistance,
		SegmentDistanceKm:       math.Round((segmentDistance/1000.0)*10) / 10,
		TotalRouteDistanceKm:    math.Round((totalDistance/1000.0)*10) / 10,
		SegmentRatio:            ratio,
		PickupPerpendicularDist: pickPerpDist,
		DropPerpendicularDist:   dropPerpDist,
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// SEGMENT SEAT AVAILABILITY & CAPACITY
// ─────────────────────────────────────────────────────────────────────────────

// CheckSegmentCapacity computes the peak seat occupancy overlapping the new segment [pickDist, dropDist]
// and determines whether seatsRequested can be accommodated within vehicleCapacity.
func CheckSegmentCapacity(
	vehicleCapacity int,
	existingBookings []BookingSegment,
	newPickDist, newDropDist float64,
	seatsRequested int,
) (isAvailable bool, availableSeats int, peakOverlap int) {
	if vehicleCapacity <= 0 {
		return false, 0, 0
	}

	// Filter existing bookings that overlap with [newPickDist, newDropDist]
	// Overlap condition: max(b.Pick, newPick) < min(b.Drop, newDrop)
	type interval struct {
		start float64
		end   float64
		seats int
	}

	var overlapping []interval
	for _, b := range existingBookings {
		// If existing booking has 0/0 or equal bounds, it represents full ride
		bPick := b.PickupDistanceAlong
		bDrop := b.DropDistanceAlong
		if bDrop <= bPick {
			bPick = 0
			bDrop = math.MaxFloat64
		}

		start := math.Max(bPick, newPickDist)
		end := math.Min(bDrop, newDropDist)

		if start < end {
			overlapping = append(overlapping, interval{
				start: bPick,
				end:   bDrop,
				seats: b.SeatsBooked,
			})
		}
	}

	if len(overlapping) == 0 {
		available := vehicleCapacity
		return seatsRequested <= available, available, 0
	}

	// Find peak concurrent seats along [newPickDist, newDropDist]
	// Critical sample points are newPickDist and each booking start/end that falls inside (newPickDist, newDropDist)
	samplePoints := map[float64]bool{
		newPickDist:                true,
		(newPickDist + newDropDist) / 2: true,
	}
	for _, iv := range overlapping {
		if iv.start >= newPickDist && iv.start < newDropDist {
			samplePoints[iv.start] = true
			samplePoints[iv.start+1.0] = true
		}
		if iv.end > newPickDist && iv.end <= newDropDist {
			samplePoints[iv.end-1.0] = true
		}
	}

	maxConcurrent := 0
	for pt := range samplePoints {
		sumAtPt := 0
		for _, iv := range overlapping {
			if pt >= iv.start && pt < iv.end {
				sumAtPt += iv.seats
			}
		}
		if sumAtPt > maxConcurrent {
			maxConcurrent = sumAtPt
		}
	}

	availableSeats = vehicleCapacity - maxConcurrent
	if availableSeats < 0 {
		availableSeats = 0
	}

	isAvailable = (maxConcurrent + seatsRequested) <= vehicleCapacity
	return isAvailable, availableSeats, maxConcurrent
}

// ─────────────────────────────────────────────────────────────────────────────
// SEGMENT PRICING
// ─────────────────────────────────────────────────────────────────────────────

// ComputeSegmentPricing calculates the passenger's fare for the specific segment traveled,
// preserving the exact AbhiShare Extra Pay formula:
// user_amount = max(50.0, round(full_user_amount * segment_ratio))
// app_amount = round(user_amount * extra_pay_pct / 100.0)
// total_amount = user_amount + app_amount
func ComputeSegmentPricing(
	fullUserAmount float64,
	segmentRatio float64,
	extraPayPercent float64,
) (userAmount float64, appAmount float64, totalAmount float64) {
	if segmentRatio <= 0 {
		segmentRatio = 1.0
	}
	if segmentRatio > 1.0 {
		segmentRatio = 1.0
	}

	// Base fare proportion
	rawUser := fullUserAmount * segmentRatio
	// Minimum fare per seat is ₹50 (to cover short pickup hops fairly)
	userAmount = math.Round(rawUser)
	if userAmount < 50.0 && fullUserAmount >= 50.0 {
		userAmount = 50.0
	} else if userAmount > fullUserAmount {
		userAmount = fullUserAmount
	}

	pct := 4.0
	if extraPayPercent >= 0 {
		pct = extraPayPercent
	}

	appAmount = math.Round(userAmount * pct / 100.0)
	totalAmount = userAmount + appAmount

	return userAmount, appAmount, totalAmount
}
