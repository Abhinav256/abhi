package models

import (
	"encoding/json"
	"time"
)

const (
	MaxNegativeWalletBalance   = -100.00
	ErrCodeOutstandingCharges = "OUTSTANDING_PLATFORM_CHARGES"
	ErrOutstandingChargesMsg  = "You have reached your ₹100 negative wallet limit. Please pay the outstanding platform charges from your previous rides before creating a new ride."
)

type OutstandingChargesError struct {
	Balance float64
}

func (e *OutstandingChargesError) Error() string {
	return ErrOutstandingChargesMsg
}

type Wallet struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Balance   float64   `json:"balance"`
	Currency  string    `json:"currency"`
	IsLocked  bool      `json:"is_locked"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type WalletTransaction struct {
	ID                 string          `json:"id"`
	WalletID           string          `json:"wallet_id"`
	UserID             string          `json:"user_id"`
	ReferenceID        string          `json:"reference_id"`
	Type               string          `json:"type"` // money_added, withdrawal, ride_payment, refund
	Status             string          `json:"status"` // completed, pending, failed
	Amount             float64         `json:"amount"`
	OpeningBalance     float64         `json:"opening_balance"`
	ClosingBalance     float64         `json:"closing_balance"`
	Title              string          `json:"title"`
	Subtitle           string          `json:"subtitle"`
	Category           string          `json:"category"`
	PaymentMethod      string          `json:"payment_method"`
	PaymentMethodType  string          `json:"payment_method_type"`
	DestinationInfo    *string         `json:"destination_info,omitempty"`
	FailureReason      *string         `json:"failure_reason,omitempty"`
	Metadata           json.RawMessage `json:"metadata,omitempty"`
	CreatedAt          time.Time       `json:"created_at"`
	UpdatedAt          time.Time       `json:"updated_at"`
}

type SavedBankAccount struct {
	ID                string    `json:"id"`
	UserID            string    `json:"user_id"`
	AccountHolderName string    `json:"account_holder_name"`
	AccountNumber     string    `json:"account_number"`
	IFSCCode          string    `json:"ifsc_code"`
	BankName          string    `json:"bank_name"`
	Branch            *string   `json:"branch,omitempty"`
	IsPrimary         bool      `json:"is_primary"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

type SavedUPIID struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	UPIID     string    `json:"upi_id"`
	Label     string    `json:"label"`
	IsPrimary bool      `json:"is_primary"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type SavedCard struct {
	ID             string    `json:"id"`
	UserID         string    `json:"user_id"`
	LastFourDigits string    `json:"last_four_digits"`
	CardHolderName string    `json:"card_holder_name"`
	ExpiryDate     string    `json:"expiry_date"`
	CardNetwork    string    `json:"card_network"`
	IsCredit       bool      `json:"is_credit"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// Request and Response DTOs

type AddMoneyRequest struct {
	Amount            float64 `json:"amount"`
	PaymentMethod     string  `json:"payment_method"`
	PaymentMethodType string  `json:"payment_method_type"` // upi, card, netbanking, wallet, giftcard
	ReferenceID       string  `json:"reference_id,omitempty"`
	Status            string  `json:"status,omitempty"` // completed, pending, failed
	FailureReason     string  `json:"failure_reason,omitempty"`
}

type WithdrawMoneyRequest struct {
	Amount            float64 `json:"amount"`
	DestinationMode   string  `json:"destination_mode"` // bank, upi
	DestinationID     string  `json:"destination_id,omitempty"`
	DestinationTitle  string  `json:"destination_title"`
	DestinationDetail string  `json:"destination_detail"`
	ReferenceID       string  `json:"reference_id,omitempty"`
	Status            string  `json:"status,omitempty"` // completed, pending, failed
	FailureReason     string  `json:"failure_reason,omitempty"`
}

type AddBankAccountRequest struct {
	AccountHolderName string `json:"account_holder_name"`
	AccountNumber     string `json:"account_number"`
	IFSCCode          string `json:"ifsc_code"`
	BankName          string `json:"bank_name"`
	Branch            string `json:"branch,omitempty"`
	IsPrimary         bool   `json:"is_primary,omitempty"`
}

type AddUPIIDRequest struct {
	UPIID     string `json:"upi_id"`
	Label     string `json:"label,omitempty"`
	IsPrimary bool   `json:"is_primary,omitempty"`
}

type AddCardRequest struct {
	LastFourDigits string `json:"last_four_digits"`
	CardHolderName string `json:"card_holder_name"`
	ExpiryDate     string `json:"expiry_date"`
	CardNetwork    string `json:"card_network"`
	IsCredit       bool   `json:"is_credit,omitempty"`
}

type WalletSummaryResponse struct {
	Wallet             Wallet              `json:"wallet"`
	RecentTransactions []WalletTransaction `json:"recent_transactions"`
	SavedBankAccounts  []SavedBankAccount  `json:"saved_bank_accounts"`
	SavedUPIIDs        []SavedUPIID        `json:"saved_upi_ids"`
	SavedCards         []SavedCard         `json:"saved_cards"`
}
