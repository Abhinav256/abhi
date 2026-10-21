package models

import "time"

type AuthStartRequest struct {
	Identifier string `json:"identifier"`
}

type AuthStartResponse struct {
	Exists        bool   `json:"exists"`
	Type          string `json:"type"`
	HasPIN        bool   `json:"has_pin"`
	AccountLocked bool   `json:"account_locked,omitempty"`
}

type LoginWithPINRequest struct {
	Identifier string `json:"identifier"`
	PIN        string `json:"pin"`
}

type AuthCheckResponse struct {
	Exists       bool          `json:"exists"`
	Type         string        `json:"type"`
	Identifier   string        `json:"identifier"`
	User         *UserResponse `json:"user,omitempty"`
	SessionToken string        `json:"session_token,omitempty"`
}

type SignupRequest struct {
	FullName     string  `json:"full_name"`
	Nickname     *string `json:"nickname"`
	Phone        string  `json:"phone"`
	Email        string  `json:"email"`
	DateOfBirth  string  `json:"date_of_birth"`
	Gender       string  `json:"gender"`
	ReferralCode *string `json:"referral_code,omitempty"`
}

type NewSignupRequest struct {
	FullName            string  `json:"full_name"`
	Nickname            *string `json:"nickname"`
	Phone               string  `json:"phone"`
	Email               string  `json:"email"`
	DateOfBirth         string  `json:"date_of_birth"`
	Gender              string  `json:"gender"`
	SecondaryIdentifier string  `json:"secondary_identifier"`
	SecondaryOTP        string  `json:"secondary_otp"`
	ReferralCode        *string `json:"referral_code,omitempty"`
}

type CheckSecondaryRequest struct {
	Identifier string `json:"identifier"`
	Type       string `json:"type"`
}

type UpdateProfileRequest struct {
	FullName    string  `json:"full_name"`
	Nickname    *string `json:"nickname"`
	DateOfBirth string  `json:"date_of_birth"`
	Gender      string  `json:"gender"`
}

type VerifyOTPRequest struct {
	Identifier string `json:"identifier"`
	OTP        string `json:"otp"`
	Purpose    string `json:"purpose"`
}

type AuthResponse struct {
	User         UserResponse `json:"user"`
	SessionToken string       `json:"session_token"`
}

type UserResponse struct {
	ID              string     `json:"id"`
	FullName        string     `json:"full_name"`
	Nickname        *string    `json:"nickname"`
	Phone           string     `json:"phone"`
	Email           string     `json:"email"`
	DateOfBirth     time.Time  `json:"date_of_birth"`
	Gender          string     `json:"gender"`
	HasPIN          bool       `json:"has_pin"`
	PhoneVerifiedAt *time.Time `json:"phone_verified_at,omitempty"`
	EmailVerifiedAt *time.Time `json:"email_verified_at,omitempty"`
	ReferralCode    *string    `json:"referral_code,omitempty"`
	AverageRating   *float64   `json:"average_rating,omitempty"`
	TotalRatings    int        `json:"total_ratings"`
	TotalRidesTaken int        `json:"total_rides_taken"`
	MoneyEarned     float64    `json:"money_earned"`
}

type SetPINRequest struct {
	PIN string `json:"pin"`
}

type VerifyPINRequest struct {
	PIN string `json:"pin"`
}

type ChangePINRequest struct {
	OldPIN string `json:"old_pin"`
	NewPIN string `json:"new_pin"`
}

type SendOTPResponse struct {
	Type                string     `json:"type"`
	SessionID           string     `json:"session_id"`
	ExpiresAt           time.Time  `json:"expires_at"`
	ResendCount         int        `json:"resend_count"`
	NextResendAllowedAt *time.Time `json:"next_resend_allowed_at"`
}
