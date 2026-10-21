package services_test

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"testing"

	"github.com/abhishare16/Abhi-Share/backend/services"
)

func TestVerifyRazorpaySignature(t *testing.T) {
	orderID := "order_test_12345"
	paymentID := "pay_test_67890"
	secret := "3giLiwUWmpHDy1H2DuWUm9J2"

	// Compute valid signature
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(orderID + "|" + paymentID))
	validSignature := hex.EncodeToString(mac.Sum(nil))

	t.Run("Valid signature returns true", func(t *testing.T) {
		if !services.VerifyRazorpaySignature(orderID, paymentID, validSignature, secret) {
			t.Errorf("expected signature to be valid, got false")
		}
	})

	t.Run("Tampered payment_id returns false", func(t *testing.T) {
		if services.VerifyRazorpaySignature(orderID, "pay_tampered_00000", validSignature, secret) {
			t.Errorf("expected tampered payment_id to be invalid, got true")
		}
	})

	t.Run("Tampered order_id returns false", func(t *testing.T) {
		if services.VerifyRazorpaySignature("order_tampered_99999", paymentID, validSignature, secret) {
			t.Errorf("expected tampered order_id to be invalid, got true")
		}
	})

	t.Run("Tampered signature returns false", func(t *testing.T) {
		tamperedSig := "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
		if services.VerifyRazorpaySignature(orderID, paymentID, tamperedSig, secret) {
			t.Errorf("expected invalid signature to be false, got true")
		}
	})

	t.Run("Empty parameters return false", func(t *testing.T) {
		if services.VerifyRazorpaySignature("", paymentID, validSignature, secret) {
			t.Errorf("expected empty orderID to be invalid")
		}
		if services.VerifyRazorpaySignature(orderID, "", validSignature, secret) {
			t.Errorf("expected empty paymentID to be invalid")
		}
		if services.VerifyRazorpaySignature(orderID, paymentID, "", secret) {
			t.Errorf("expected empty signature to be invalid")
		}
		if services.VerifyRazorpaySignature(orderID, paymentID, validSignature, "") {
			t.Errorf("expected empty secret to be invalid")
		}
	})
}
