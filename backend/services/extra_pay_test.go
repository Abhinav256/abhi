package services

import (
	"math"
	"testing"

	"github.com/abhishare16/Abhi-Share/backend/config"
)

func TestExtraPayPricingLogic(t *testing.T) {
	tests := []struct {
		name               string
		userAmount         float64
		percentage         float64
		expectedAppAmount  float64
		expectedTotalAmount float64
	}{
		{
			name:               "Prompt example 1: 4% on ₹200",
			userAmount:         200.0,
			percentage:         4.0,
			expectedAppAmount:  8.0,
			expectedTotalAmount: 208.0,
		},
		{
			name:               "Prompt example 2: 5% on ₹200",
			userAmount:         200.0,
			percentage:         5.0,
			expectedAppAmount:  10.0,
			expectedTotalAmount: 210.0,
		},
		{
			name:               "Zero price",
			userAmount:         0.0,
			percentage:         4.0,
			expectedAppAmount:  0.0,
			expectedTotalAmount: 0.0,
		},
		{
			name:               "Rounding up: ₹155 at 4% (6.2 -> 6)",
			userAmount:         155.0,
			percentage:         4.0,
			expectedAppAmount:  6.0,
			expectedTotalAmount: 161.0,
		},
		{
			name:               "Rounding up: ₹165 at 4% (6.6 -> 7)",
			userAmount:         165.0,
			percentage:         4.0,
			expectedAppAmount:  7.0,
			expectedTotalAmount: 172.0,
		},
		{
			name:               "Higher fare: ₹1500 at 5%",
			userAmount:         1500.0,
			percentage:         5.0,
			expectedAppAmount:  75.0,
			expectedTotalAmount: 1575.0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			svc := &RideService{
				Config: &config.Config{
					ExtraPayPercent: tc.percentage,
				},
			}

			appAmt, totalAmt := svc.computeExtraPay(tc.userAmount)

			if math.Abs(appAmt-tc.expectedAppAmount) > 1e-6 {
				t.Errorf("expected appAmount=%.2f, got %.2f", tc.expectedAppAmount, appAmt)
			}
			if math.Abs(totalAmt-tc.expectedTotalAmount) > 1e-6 {
				t.Errorf("expected totalAmount=%.2f, got %.2f", tc.expectedTotalAmount, totalAmt)
			}
		})
	}
}

func TestExtraPayConfigDefault(t *testing.T) {
	// Nil config fallback to 4%
	svc := &RideService{Config: nil}
	appAmt, totalAmt := svc.computeExtraPay(200.0)
	if appAmt != 8.0 || totalAmt != 208.0 {
		t.Errorf("expected default 4%% to give 8 and 208, got %.2f and %.2f", appAmt, totalAmt)
	}
}
