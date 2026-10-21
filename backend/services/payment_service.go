package services

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/abhishare16/Abhi-Share/backend/config"
	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PaymentService handles Razorpay order creation, signature verification, and settlement.
type PaymentService struct {
	DB             *pgxpool.Pool
	Config         *config.Config
	BookingService *BookingService
	WalletService  *WalletService
	HTTPClient     *http.Client
}

func NewPaymentService(
	db *pgxpool.Pool,
	cfg *config.Config,
	bookingService *BookingService,
	walletService *WalletService,
) *PaymentService {
	return &PaymentService{
		DB:             db,
		Config:         cfg,
		BookingService: bookingService,
		WalletService:  walletService,
		HTTPClient: &http.Client{
			Timeout: 15 * time.Second,
		},
	}
}

// razorpayOrderAPIResponse models the JSON returned by Razorpay Orders API.
type razorpayOrderAPIResponse struct {
	ID       string `json:"id"`
	Entity   string `json:"entity"`
	Amount   int64  `json:"amount"`
	Currency string `json:"currency"`
	Receipt  string `json:"receipt"`
	Status   string `json:"status"`
	Error    *struct {
		Code        string `json:"code"`
		Description string `json:"description"`
	} `json:"error,omitempty"`
}

// callRazorpayCreateOrder invokes the official Razorpay v1/orders REST API.
func (s *PaymentService) callRazorpayCreateOrder(ctx context.Context, amountPaise int64, currency, receipt string, notes map[string]interface{}) (string, error) {
	keyID := strings.TrimSpace(s.Config.RazorpayKeyID)
	keySecret := strings.TrimSpace(s.Config.RazorpayKeySecret)
	if keyID == "" || keySecret == "" {
		return "", errors.New("razorpay credentials not configured on backend")
	}

	payload := map[string]interface{}{
		"amount":   amountPaise,
		"currency": currency,
		"receipt":  receipt,
		"notes":    notes,
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.razorpay.com/v1/orders", bytes.NewReader(bodyBytes))
	if err != nil {
		return "", err
	}
	req.SetBasicAuth(keyID, keySecret)
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.HTTPClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to connect to razorpay: %w", err)
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	var rzpResp razorpayOrderAPIResponse
	if err := json.Unmarshal(respBytes, &rzpResp); err != nil {
		return "", fmt.Errorf("invalid razorpay response: %w", err)
	}

	if resp.StatusCode >= 400 || rzpResp.ID == "" {
		if rzpResp.Error != nil && rzpResp.Error.Description != "" {
			return "", fmt.Errorf("razorpay order creation failed: %s", rzpResp.Error.Description)
		}
		return "", fmt.Errorf("razorpay order creation failed (status %d): %s", resp.StatusCode, string(respBytes))
	}

	return rzpResp.ID, nil
}

// CreateOrder validates request, calculates actual payable amounts dynamically, creates Razorpay order,
// and records the payment order in database.
func (s *PaymentService) CreateOrder(ctx context.Context, userID string, req models.CreatePaymentOrderRequest) (*models.PaymentOrderResponse, error) {
	var payableAmount float64
	var receipt string
	metadata := make(map[string]interface{})

	switch req.Purpose {
	case "ride_booking":
		if strings.TrimSpace(req.RideID) == "" {
			return nil, errors.New("ride_id is required for ride booking payment")
		}
		if req.SeatsBooked <= 0 {
			req.SeatsBooked = 1
		}

		// Dynamically verify ride pricing and availability from database
		var driverID string
		var availableSeats int
		var pricePerSeat float64
		var rideTotalAmount float64
		var rideStatus string
		var isWomenOnly bool
		err := s.DB.QueryRow(
			ctx,
			`SELECT driver_id, available_seats, price_per_seat, total_amount, status, is_women_only
			 FROM rides
			 WHERE id = $1`,
			req.RideID,
		).Scan(&driverID, &availableSeats, &pricePerSeat, &rideTotalAmount, &rideStatus, &isWomenOnly)

		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return nil, errors.New("ride not found")
			}
			return nil, err
		}

		if rideStatus != "active" {
			return nil, errors.New("ride is not active")
		}
		if driverID == userID {
			return nil, errors.New("driver cannot book their own ride")
		}
		if availableSeats < req.SeatsBooked {
			return nil, fmt.Errorf("only %d seat(s) available, cannot book %d seats", availableSeats, req.SeatsBooked)
		}

		passengerPrice := rideTotalAmount
		if passengerPrice <= 0 {
			passengerPrice = pricePerSeat
		}

		// Handle segment booking pricing if distance parameters are provided
		if req.PickupDistanceAlongRoute != nil && req.DropDistanceAlongRoute != nil && *req.DropDistanceAlongRoute > *req.PickupDistanceAlongRoute {
			var routeDistance float64
			var userAmt float64
			_ = s.DB.QueryRow(ctx, `SELECT COALESCE(route_distance, 0), COALESCE(user_amount, price_per_seat) FROM rides WHERE id = $1`, req.RideID).Scan(&routeDistance, &userAmt)
			if routeDistance > 0 {
				segRatio := (*req.DropDistanceAlongRoute - *req.PickupDistanceAlongRoute) / routeDistance
				if segRatio > 1.0 {
					segRatio = 1.0
				}
				extraPayPct := 10.0
				if s.Config != nil && s.Config.ExtraPayPercent > 0 {
					extraPayPct = s.Config.ExtraPayPercent
				}
				_, _, segTotal := ComputeSegmentPricing(userAmt, segRatio, extraPayPct)
				if segTotal > 0 {
					passengerPrice = segTotal
				}
			}
			metadata["from_location"] = req.FromLocation
			metadata["to_location"] = req.ToLocation
			if req.PickupLatitude != nil {
				metadata["pickup_latitude"] = *req.PickupLatitude
			}
			if req.PickupLongitude != nil {
				metadata["pickup_longitude"] = *req.PickupLongitude
			}
			if req.DestinationLatitude != nil {
				metadata["destination_latitude"] = *req.DestinationLatitude
			}
			if req.DestinationLongitude != nil {
				metadata["destination_longitude"] = *req.DestinationLongitude
			}
			metadata["pickup_distance_along_route"] = *req.PickupDistanceAlongRoute
			metadata["drop_distance_along_route"] = *req.DropDistanceAlongRoute
		}

		// Calculate exact payable amount dynamically (passengerPrice * seats_booked)
		payableAmount = passengerPrice * float64(req.SeatsBooked)
		if payableAmount <= 0 {
			return nil, errors.New("payable amount must be greater than zero")
		}

		receipt = fmt.Sprintf("rcpt_ride_%d", time.Now().UnixNano()/1e6)
		metadata["ride_id"] = req.RideID
		metadata["seats_booked"] = req.SeatsBooked
		metadata["price_per_seat"] = passengerPrice
		metadata["is_women_only"] = isWomenOnly

		// Serialize passengers
		if len(req.Passengers) > 0 {
			metadata["passengers"] = req.Passengers
		}

	case "wallet_topup":
		if req.Amount < 10 {
			return nil, errors.New("minimum wallet top-up amount is ₹10")
		}
		if req.Amount > 50000 {
			return nil, errors.New("maximum top-up limit per transaction is ₹50,000")
		}
		payableAmount = req.Amount
		receipt = fmt.Sprintf("rcpt_wal_%d", time.Now().UnixNano()/1e6)
		metadata["amount"] = req.Amount

	default:
		return nil, errors.New("invalid purpose. Use 'ride_booking' or 'wallet_topup'")
	}

	amountPaise := int64(math.Round(payableAmount * 100))
	notes := map[string]interface{}{
		"purpose": req.Purpose,
		"user_id": userID,
	}

	// 1. Create order on Razorpay
	rzpOrderID, err := s.callRazorpayCreateOrder(ctx, amountPaise, "INR", receipt, notes)
	if err != nil {
		return nil, err
	}

	// 2. Persist order in local database
	metadataJSON, err := json.Marshal(metadata)
	if err != nil {
		metadataJSON = []byte("{}")
	}

	_, err = s.DB.Exec(
		ctx,
		`INSERT INTO payment_orders (
			user_id, order_id, amount, currency, purpose, status, metadata, created_at, updated_at
		) VALUES ($1, $2, $3, 'INR', $4, 'created', $5, NOW(), NOW())`,
		userID, rzpOrderID, payableAmount, req.Purpose, metadataJSON,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to save payment order: %w", err)
	}

	return &models.PaymentOrderResponse{
		OrderID:     rzpOrderID,
		Amount:      payableAmount,
		AmountPaise: amountPaise,
		Currency:    "INR",
		KeyID:       s.Config.RazorpayKeyID,
		Purpose:     req.Purpose,
		Receipt:     receipt,
		Metadata:    metadata,
	}, nil
}

// VerifyRazorpaySignature verifies Razorpay HMAC SHA256 signature according to official specification:
// HMAC_SHA256(order_id + "|" + payment_id, key_secret) == signature
func VerifyRazorpaySignature(orderID, paymentID, signature, secret string) bool {
	if orderID == "" || paymentID == "" || signature == "" || secret == "" {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(orderID + "|" + paymentID))
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(strings.ToLower(expected)), []byte(strings.ToLower(signature)))
}

// VerifyPayment performs server-side signature verification and atomic settlement.
func (s *PaymentService) VerifyPayment(ctx context.Context, userID string, req models.VerifyPaymentRequest) (*models.VerifyPaymentResponse, error) {
	req.RazorpayOrderID = strings.TrimSpace(req.RazorpayOrderID)
	req.RazorpayPaymentID = strings.TrimSpace(req.RazorpayPaymentID)
	req.RazorpaySignature = strings.TrimSpace(req.RazorpaySignature)

	if req.RazorpayOrderID == "" || req.RazorpayPaymentID == "" || req.RazorpaySignature == "" {
		return nil, errors.New("razorpay_order_id, razorpay_payment_id, and razorpay_signature are required")
	}

	// 1. Verify cryptographic signature
	secret := strings.TrimSpace(s.Config.RazorpayKeySecret)
	if !VerifyRazorpaySignature(req.RazorpayOrderID, req.RazorpayPaymentID, req.RazorpaySignature, secret) {
		return nil, errors.New("invalid payment signature: payment verification failed")
	}

	// 2. Fetch payment order
	var orderID string
	var orderUserID string
	var amount float64
	var purpose string
	var status string
	var metadataBytes []byte

	err := s.DB.QueryRow(
		ctx,
		`SELECT id, user_id, amount, purpose, status, metadata
		 FROM payment_orders
		 WHERE order_id = $1`,
		req.RazorpayOrderID,
	).Scan(&orderID, &orderUserID, &amount, &purpose, &status, &metadataBytes)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("payment order not found")
		}
		return nil, err
	}

	if orderUserID != userID {
		return nil, errors.New("unauthorized: order belongs to another user")
	}

	var metadata map[string]interface{}
	if len(metadataBytes) > 0 {
		_ = json.Unmarshal(metadataBytes, &metadata)
	}
	if metadata == nil {
		metadata = make(map[string]interface{})
	}

	// 3. Idempotency Check: if order is already paid, return existing result without duplicate actions
	if status == "paid" {
		existingBookingID, _ := metadata["booking_id"].(string)
		return &models.VerifyPaymentResponse{
			Success:   true,
			Status:    "already_verified",
			Purpose:   purpose,
			PaymentID: req.RazorpayPaymentID,
			OrderID:   req.RazorpayOrderID,
			BookingID: existingBookingID,
			Message:   "Payment was already verified successfully.",
		}, nil
	}

	// 4. Atomic Execution based on purpose
	switch purpose {
	case "ride_booking":
		rideID, _ := metadata["ride_id"].(string)
		seatsBookedRaw := metadata["seats_booked"]
		seatsBooked := 1
		if sb, ok := seatsBookedRaw.(float64); ok {
			seatsBooked = int(sb)
		} else if sb, ok := seatsBookedRaw.(int); ok {
			seatsBooked = sb
		}

		var passengers []models.PassengerInput
		if rawPass, ok := metadata["passengers"].([]interface{}); ok {
			for _, p := range rawPass {
				if pMap, ok := p.(map[string]interface{}); ok {
					name, _ := pMap["name"].(string)
					gender, _ := pMap["gender"].(string)
					age := 18
					if rawAge, ok := pMap["age"].(float64); ok {
						age = int(rawAge)
					}
					passengers = append(passengers, models.PassengerInput{
						Name:   name,
						Age:    age,
						Gender: gender,
					})
				}
			}
		}

		var fromLoc, toLoc string
		if fl, ok := metadata["from_location"].(string); ok {
			fromLoc = fl
		}
		if tl, ok := metadata["to_location"].(string); ok {
			toLoc = tl
		}
		var pickLat, pickLon, destLat, destLon, pickDist, dropDist *float64
		if pl, ok := metadata["pickup_latitude"].(float64); ok {
			pickLat = &pl
		}
		if pl, ok := metadata["pickup_longitude"].(float64); ok {
			pickLon = &pl
		}
		if dl, ok := metadata["destination_latitude"].(float64); ok {
			destLat = &dl
		}
		if dl, ok := metadata["destination_longitude"].(float64); ok {
			destLon = &dl
		}
		if pd, ok := metadata["pickup_distance_along_route"].(float64); ok {
			pickDist = &pd
		}
		if dd, ok := metadata["drop_distance_along_route"].(float64); ok {
			dropDist = &dd
		}

		// Call BookingService to atomically create booking and reserve seats
		bookingID, err := s.BookingService.CreateBooking(ctx, models.CreateBookingRequest{
			RideID:                   rideID,
			PassengerID:              userID,
			SeatsBooked:              seatsBooked,
			PaymentMode:              "upi",
			Passengers:               passengers,
			FromLocation:             fromLoc,
			ToLocation:               toLoc,
			PickupLatitude:           pickLat,
			PickupLongitude:          pickLon,
			DestinationLatitude:      destLat,
			DestinationLongitude:     destLon,
			PickupDistanceAlongRoute: pickDist,
			DropDistanceAlongRoute:   dropDist,
		})
		if err != nil {
			return nil, fmt.Errorf("payment verified but booking creation failed: %w", err)
		}

		// Update payment_order to 'paid' and store booking_id
		metadata["booking_id"] = bookingID
		updatedMetaBytes, _ := json.Marshal(metadata)

		_, _ = s.DB.Exec(
			ctx,
			`UPDATE payment_orders
			 SET status = 'paid', payment_id = $1, signature = $2, metadata = $3, updated_at = NOW()
			 WHERE id = $4`,
			req.RazorpayPaymentID, req.RazorpaySignature, updatedMetaBytes, orderID,
		)

		return &models.VerifyPaymentResponse{
			Success:   true,
			Status:    "verified",
			Purpose:   "ride_booking",
			PaymentID: req.RazorpayPaymentID,
			OrderID:   req.RazorpayOrderID,
			BookingID: bookingID,
			Message:   "Payment verified and ride booking confirmed successfully.",
		}, nil

	case "wallet_topup":
		// Call WalletService to atomically credit the wallet with ACID protection
		txn, err := s.WalletService.AddMoney(ctx, userID, models.AddMoneyRequest{
			Amount:            amount,
			PaymentMethod:     "Razorpay (UPI / Cards)",
			PaymentMethodType: "upi",
			ReferenceID:       req.RazorpayPaymentID,
			Status:            "completed",
		})
		if err != nil {
			return nil, fmt.Errorf("payment verified but wallet credit failed: %w", err)
		}

		metadata["transaction_id"] = txn.ID
		updatedMetaBytes, _ := json.Marshal(metadata)

		_, _ = s.DB.Exec(
			ctx,
			`UPDATE payment_orders
			 SET status = 'paid', payment_id = $1, signature = $2, metadata = $3, updated_at = NOW()
			 WHERE id = $4`,
			req.RazorpayPaymentID, req.RazorpaySignature, updatedMetaBytes, orderID,
		)

		return &models.VerifyPaymentResponse{
			Success:   true,
			Status:    "verified",
			Purpose:   "wallet_topup",
			PaymentID: req.RazorpayPaymentID,
			OrderID:   req.RazorpayOrderID,
			WalletTxn: txn,
			Message:   "Payment verified and wallet credited successfully.",
		}, nil

	default:
		return nil, fmt.Errorf("unrecognized payment purpose: %s", purpose)
	}
}

// MarkOrderFailed records that a payment attempt was cancelled or failed on the client side.
func (s *PaymentService) MarkOrderFailed(ctx context.Context, userID, orderID, reason string) error {
	_, err := s.DB.Exec(
		ctx,
		`UPDATE payment_orders
		 SET status = 'failed', updated_at = NOW(),
		     metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{failure_reason}', to_jsonb($1::text))
		 WHERE order_id = $2 AND user_id = $3 AND status = 'created'`,
		reason, orderID, userID,
	)
	return err
}

// GetOrderStatus retrieves the payment order record for a user.
func (s *PaymentService) GetOrderStatus(ctx context.Context, userID, orderID string) (*models.PaymentOrderRecord, error) {
	var record models.PaymentOrderRecord
	var metadataBytes []byte

	err := s.DB.QueryRow(
		ctx,
		`SELECT id, user_id, order_id, amount, currency, purpose, status, payment_id, signature, metadata, created_at, updated_at
		 FROM payment_orders
		 WHERE order_id = $1 AND user_id = $2`,
		orderID, userID,
	).Scan(
		&record.ID,
		&record.UserID,
		&record.OrderID,
		&record.Amount,
		&record.Currency,
		&record.Purpose,
		&record.Status,
		&record.PaymentID,
		&record.Signature,
		&metadataBytes,
		&record.CreatedAt,
		&record.UpdatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("payment order not found")
		}
		return nil, err
	}

	if len(metadataBytes) > 0 {
		_ = json.Unmarshal(metadataBytes, &record.Metadata)
	}
	if record.Metadata == nil {
		record.Metadata = make(map[string]interface{})
	}

	return &record, nil
}

// VerifyWebhookSignature validates the Razorpay webhook HMAC SHA256 signature.
func (s *PaymentService) VerifyWebhookSignature(payload []byte, signature, secret string) bool {
	if len(payload) == 0 || signature == "" || secret == "" {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(payload)
	expectedMAC := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(strings.ToLower(signature)), []byte(strings.ToLower(expectedMAC)))
}

// ComputeSignature calculates the expected Razorpay HMAC SHA256 hex string.
func (s *PaymentService) ComputeSignature(orderID, paymentID, secret string) string {
	message := orderID + "|" + paymentID
	h := hmac.New(sha256.New, []byte(secret))
	h.Write([]byte(message))
	return hex.EncodeToString(h.Sum(nil))
}

// HandleWebhook processes asynchronous webhook events from Razorpay with idempotency.
func (s *PaymentService) HandleWebhook(ctx context.Context, payload []byte, signature string) error {
	secret := s.Config.RazorpayWebhookSecret
	if secret == "" {
		secret = s.Config.RazorpayKeySecret
	}

	if !s.VerifyWebhookSignature(payload, signature, secret) {
		return errors.New("invalid webhook signature")
	}

	var event struct {
		Event   string `json:"event"`
		Payload struct {
			Payment struct {
				Entity struct {
					ID      string `json:"id"`
					OrderID string `json:"order_id"`
					Status  string `json:"status"`
				} `json:"entity"`
			} `json:"payment"`
			Order struct {
				Entity struct {
					ID     string `json:"id"`
					Status string `json:"status"`
				} `json:"entity"`
			} `json:"order"`
		} `json:"payload"`
	}

	if err := json.Unmarshal(payload, &event); err != nil {
		return fmt.Errorf("failed to parse webhook payload: %w", err)
	}

	orderID := event.Payload.Payment.Entity.OrderID
	if orderID == "" {
		orderID = event.Payload.Order.Entity.ID
	}
	paymentID := event.Payload.Payment.Entity.ID

	if orderID == "" {
		return nil
	}

	switch event.Event {
	case "payment.captured", "order.paid":
		var userID string
		err := s.DB.QueryRow(ctx, `SELECT user_id FROM payment_orders WHERE order_id = $1`, orderID).Scan(&userID)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return nil
			}
			return err
		}

		expectedSignature := s.ComputeSignature(orderID, paymentID, s.Config.RazorpayKeySecret)
		_, err = s.VerifyPayment(ctx, userID, models.VerifyPaymentRequest{
			RazorpayOrderID:   orderID,
			RazorpayPaymentID: paymentID,
			RazorpaySignature: expectedSignature,
		})
		if err != nil {
			return err
		}

	case "payment.failed":
		_, _ = s.DB.Exec(
			ctx,
			`UPDATE payment_orders
			 SET status = 'failed', updated_at = NOW(),
			     metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{failure_reason}', to_jsonb('Payment failed at gateway'::text))
			 WHERE order_id = $1 AND status = 'created'`,
			orderID,
		)
	}

	return nil
}
