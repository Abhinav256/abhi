package models

import "time"

// CreatePaymentOrderRequest represents payload to create a Razorpay payment order.
type CreatePaymentOrderRequest struct {
	Purpose                  string           `json:"purpose"` // "ride_booking" or "wallet_topup"
	Amount                   float64          `json:"amount,omitempty"` // For wallet_topup
	RideID                   string           `json:"ride_id,omitempty"` // For ride_booking
	SeatsBooked              int              `json:"seats_booked,omitempty"` // For ride_booking
	Passengers               []PassengerInput `json:"passengers,omitempty"` // For ride_booking
	FromLocation             string           `json:"from_location,omitempty"`
	ToLocation               string           `json:"to_location,omitempty"`
	PickupLatitude           *float64         `json:"pickup_latitude,omitempty"`
	PickupLongitude          *float64         `json:"pickup_longitude,omitempty"`
	DestinationLatitude      *float64         `json:"destination_latitude,omitempty"`
	DestinationLongitude     *float64         `json:"destination_longitude,omitempty"`
	PickupDistanceAlongRoute *float64         `json:"pickup_distance_along_route,omitempty"`
	DropDistanceAlongRoute   *float64         `json:"drop_distance_along_route,omitempty"`
}

// PaymentOrderResponse returned when an order is created.
type PaymentOrderResponse struct {
	OrderID     string                 `json:"order_id"`
	Amount      float64                `json:"amount"` // in INR (e.g. 500.0)
	AmountPaise int64                  `json:"amount_paise"` // in paise (e.g. 50000)
	Currency    string                 `json:"currency"`
	KeyID       string                 `json:"key_id"`
	Purpose     string                 `json:"purpose"`
	Receipt     string                 `json:"receipt"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

// VerifyPaymentRequest contains client-side checkout callback signatures.
type VerifyPaymentRequest struct {
	RazorpayOrderID   string `json:"razorpay_order_id"`
	RazorpayPaymentID string `json:"razorpay_payment_id"`
	RazorpaySignature string `json:"razorpay_signature"`
}

// VerifyPaymentResponse is returned after server-side HMAC SHA256 verification.
type VerifyPaymentResponse struct {
	Success   bool               `json:"success"`
	Status    string             `json:"status"` // "verified", "already_verified"
	Purpose   string             `json:"purpose"`
	PaymentID string             `json:"payment_id"`
	OrderID   string             `json:"order_id"`
	BookingID string             `json:"booking_id,omitempty"`
	WalletTxn *WalletTransaction `json:"wallet_transaction,omitempty"`
	Message   string             `json:"message"`
}

// PaymentOrderRecord represents a row in payment_orders table.
type PaymentOrderRecord struct {
	ID        string                 `json:"id"`
	UserID    string                 `json:"user_id"`
	OrderID   string                 `json:"order_id"`
	Amount    float64                `json:"amount"`
	Currency  string                 `json:"currency"`
	Purpose   string                 `json:"purpose"`
	Status    string                 `json:"status"`
	PaymentID *string                `json:"payment_id,omitempty"`
	Signature *string                `json:"signature,omitempty"`
	Metadata  map[string]interface{} `json:"metadata"`
	CreatedAt time.Time              `json:"created_at"`
	UpdatedAt time.Time              `json:"updated_at"`
}
