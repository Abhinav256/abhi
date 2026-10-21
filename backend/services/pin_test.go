package services

import (
	"testing"
)

func TestPinArgon2HashingAndVerification(t *testing.T) {
	pin := "1234"
	wrongPin := "4321"

	hashed, err := hashPinArgon2(pin)
	if err != nil {
		t.Fatalf("expected no error hashing PIN, got: %v", err)
	}

	if hashed == "" {
		t.Fatalf("expected non-empty hash")
	}

	// Verify with correct PIN
	valid, err := verifyPinArgon2(pin, hashed)
	if err != nil {
		t.Fatalf("expected no error verifying PIN, got: %v", err)
	}
	if !valid {
		t.Errorf("expected PIN %s to match hash", pin)
	}

	// Verify with wrong PIN
	valid, err = verifyPinArgon2(wrongPin, hashed)
	if err != nil {
		t.Fatalf("expected no error verifying wrong PIN, got: %v", err)
	}
	if valid {
		t.Errorf("expected wrong PIN %s to not match hash", wrongPin)
	}
}

func TestDetectIdentifierType(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"user@example.com", "email"},
		{"user.name+tag@domain.co.in", "email"},
		{"9876543210", "phone"},
		{"987654321000", "phone"},
		{"invalid_text", ""},
		{"1234", ""},
	}

	for _, tt := range tests {
		result := detectIdentifierType(tt.input)
		if result != tt.expected {
			t.Errorf("detectIdentifierType(%q) = %q, expected %q", tt.input, result, tt.expected)
		}
	}
}
