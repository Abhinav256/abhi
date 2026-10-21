package services

import (
	"strings"
	"testing"
)

func TestMaskPhoneNumber(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"+919876543210", "+91 ••••• ••10"},
		{"9876543210", "•••• ••• 3210"},
		{"1234", "1234"},
		{"", ""},
	}

	for _, tt := range tests {
		result := maskPhoneNumber(tt.input)
		if result != tt.expected {
			t.Errorf("maskPhoneNumber(%q) = %q, expected %q", tt.input, result, tt.expected)
		}
	}
}

func TestReferralCodeSanitization(t *testing.T) {
	code := " abhi1234 "
	clean := strings.ToUpper(strings.TrimSpace(code))
	if clean != "ABHI1234" {
		t.Errorf("expected clean code to be ABHI1234, got %q", clean)
	}
}
