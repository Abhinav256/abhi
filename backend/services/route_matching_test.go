package services

import (
	"encoding/json"
	"testing"
)

func sampleMiryalagudaToHyderabadPolyline() [][]float64 {
	// Polyline [lon, lat] from Miryalaguda -> Nalgonda -> Choutuppal -> Hyderabad
	return [][]float64{
		{79.5647, 16.7454}, // Miryalaguda
		{79.4500, 16.8500}, // intermediate
		{79.2700, 17.0500}, // Nalgonda
		{79.1000, 17.1500}, // intermediate
		{78.9000, 17.2400}, // Choutuppal
		{78.6500, 17.3200}, // Hayathnagar
		{78.4867, 17.3850}, // Hyderabad (LB Nagar/City)
	}
}

func TestHaversineDistance(t *testing.T) {
	// Distance between Hyderabad (17.3850, 78.4867) and Nalgonda (17.0500, 79.2700) is ~91 km
	d := HaversineDistance(17.3850, 78.4867, 17.0500, 79.2700)
	km := d / 1000.0
	if km < 80.0 || km > 105.0 {
		t.Errorf("expected ~91 km, got %.2f km", km)
	}
}

func TestRouteMatching_CompatibleIntermediateJourney(t *testing.T) {
	coords := sampleMiryalagudaToHyderabadPolyline()

	// Passenger searches: Nalgonda (17.0500, 79.2700) -> Hyderabad (17.3850, 78.4867)
	match := MatchRouteSegment(coords, 17.0500, 79.2700, 17.3850, 78.4867, 10000.0)

	if !match.IsMatched {
		t.Fatalf("expected route match for Nalgonda -> Hyderabad, got un-matched: %s", match.Reason)
	}

	if match.PickupDistanceMeters >= match.DropDistanceMeters {
		t.Errorf("expected drop distance (%.1f) > pickup distance (%.1f)", match.DropDistanceMeters, match.PickupDistanceMeters)
	}

	if match.SegmentRatio <= 0.0 || match.SegmentRatio >= 1.0 {
		t.Errorf("expected segment ratio strictly between 0 and 1, got %.3f", match.SegmentRatio)
	}
}

func TestRouteMatching_ReverseDirectionRejected(t *testing.T) {
	coords := sampleMiryalagudaToHyderabadPolyline()

	// Passenger searches: Hyderabad (17.3850, 78.4867) -> Nalgonda (17.0500, 79.2700)
	// (Driver is traveling Miryalaguda -> Hyderabad)
	match := MatchRouteSegment(coords, 17.3850, 78.4867, 17.0500, 79.2700, 10000.0)

	if match.IsMatched {
		t.Fatalf("expected reverse-direction journey to be rejected, but got matched")
	}
	if match.Reason == "" {
		t.Errorf("expected clear reason for rejection")
	}
}

func TestRouteMatching_OffRouteRejected(t *testing.T) {
	coords := sampleMiryalagudaToHyderabadPolyline()

	// Passenger searches: Warangal (17.9689, 79.5941) -> Hyderabad
	// Warangal is >80 km away from Miryalaguda->Hyderabad corridor
	match := MatchRouteSegment(coords, 17.9689, 79.5941, 17.3850, 78.4867, 10000.0)

	if match.IsMatched {
		t.Fatalf("expected off-route location to be rejected, but got matched")
	}
}

func TestSegmentCapacity_OverlappingBookings(t *testing.T) {
	vehicleCapacity := 4

	// Miryalaguda (0 km) -> Nalgonda (50 km) -> Hyderabad (150 km)
	// Booking 1: Passenger travels Miryalaguda (0 km) to Nalgonda (50 km), takes 2 seats
	existing := []BookingSegment{
		{
			BookingID:           "b1",
			SeatsBooked:         2,
			PickupDistanceAlong: 0.0,
			DropDistanceAlong:   50000.0,
		},
	}

	// Case 1: Passenger 2 wants 3 seats from Nalgonda (50 km) to Hyderabad (150 km).
	// Because Passenger 1 gets off at Nalgonda, seats 2 are freed up! Overlap is 0 seats!
	available, seats, peak := CheckSegmentCapacity(vehicleCapacity, existing, 50000.0, 150000.0, 3)
	if !available {
		t.Errorf("expected 3 seats to be available on Nalgonda->Hyderabad segment, peak=%d, avail=%d", peak, seats)
	}
	if seats != 4 {
		t.Errorf("expected 4 seats available on non-overlapping segment, got %d", seats)
	}

	// Case 2: Passenger 3 wants 3 seats from Miryalaguda (0 km) to Hyderabad (150 km).
	// Overlaps with Booking 1 on [0, 50km]. 2 existing + 3 requested = 5 > 4. Must REJECT.
	availableOverlap, _, peakOverlap := CheckSegmentCapacity(vehicleCapacity, existing, 0.0, 150000.0, 3)
	if availableOverlap {
		t.Errorf("expected overlapping 3 seats to exceed capacity 4 (peak=%d)", peakOverlap)
	}
}

func TestSegmentPricing_ProportionalCalculation(t *testing.T) {
	fullUserAmount := 300.0
	extraPayPercent := 4.0

	// 1. Full trip (ratio 1.0)
	user, app, total := ComputeSegmentPricing(fullUserAmount, 1.0, extraPayPercent)
	if user != 300.0 || app != 12.0 || total != 312.0 {
		t.Errorf("expected 300/12/312 for full trip, got %.1f/%.1f/%.1f", user, app, total)
	}

	// 2. Half trip (ratio 0.5)
	userHalf, appHalf, totalHalf := ComputeSegmentPricing(fullUserAmount, 0.5, extraPayPercent)
	if userHalf != 150.0 || appHalf != 6.0 || totalHalf != 156.0 {
		t.Errorf("expected 150/6/156 for half trip, got %.1f/%.1f/%.1f", userHalf, appHalf, totalHalf)
	}

	// 3. Very short segment - should not be less than min ₹50 floor
	userShort, _, _ := ComputeSegmentPricing(fullUserAmount, 0.05, extraPayPercent)
	if userShort < 50.0 {
		t.Errorf("expected min floor of ₹50, got %.1f", userShort)
	}
}

func TestSettlementCategoryRank(t *testing.T) {
	if settlementCategoryRank("city") <= settlementCategoryRank("town") {
		t.Errorf("expected city to rank higher than town")
	}
	if settlementCategoryRank("town") <= settlementCategoryRank("village") {
		t.Errorf("expected town to rank higher than village")
	}
	if settlementCategoryRank("village") <= settlementCategoryRank("hamlet") {
		t.Errorf("expected village to rank higher than hamlet")
	}
	if settlementCategoryRank("unknown") != 0 {
		t.Errorf("expected unknown to rank 0")
	}
}

func TestRouteWaypointSerialization(t *testing.T) {
	wp := RouteWaypoint{
		Name:               "Nalgonda",
		Category:           "city",
		Latitude:           17.0504,
		Longitude:          79.2669,
		DistanceAlongRoute: 52000.0,
	}

	data, err := json.Marshal(wp)
	if err != nil {
		t.Fatalf("failed to marshal RouteWaypoint: %v", err)
	}

	var decoded RouteWaypoint
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("failed to unmarshal RouteWaypoint: %v", err)
	}

	if decoded.Name != "Nalgonda" || decoded.Category != "city" {
		t.Errorf("unexpected decoded values: %+v", decoded)
	}
}

