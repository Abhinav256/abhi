package services

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"golang.org/x/crypto/argon2"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/models"
)

type AuthService struct {
	DB              *pgxpool.Pool
	EmailService    *EmailService
	ReferralService *ReferralService
}

func NewAuthService(
	db *pgxpool.Pool,
	emailService *EmailService,
) *AuthService {
	return &AuthService{
		DB:           db,
		EmailService: emailService,
	}
}

// StartAuth checks if an identifier (phone/email) exists and returns whether a PIN is set and if account is locked.
func (s *AuthService) StartAuth(
	ctx context.Context,
	identifier string,
) (*models.AuthStartResponse, error) {
	identifier = strings.TrimSpace(identifier)

	identifierType := detectIdentifierType(identifier)
	if identifierType == "" {
		return nil, errors.New(
			"identifier must be a valid mobile number or email",
		)
	}

	var (
		exists         bool
		hasPin         bool
		pinHash        *string
		failedAttempts int
		isLocked       bool
	)

	if identifierType == "email" {
		err := s.DB.QueryRow(
			ctx,
			`SELECT pin_hash, COALESCE(pin_failed_attempts, 0), COALESCE(pin_account_locked, FALSE)
			 FROM users
			 WHERE LOWER(email) = LOWER($1)
			 LIMIT 1`,
			identifier,
		).Scan(&pinHash, &failedAttempts, &isLocked)

		if err == nil {
			exists = true
			hasPin = pinHash != nil && *pinHash != ""
		} else if errors.Is(err, pgx.ErrNoRows) {
			exists = false
			hasPin = false
		} else {
			return nil, err
		}
	} else {
		err := s.DB.QueryRow(
			ctx,
			`SELECT pin_hash, COALESCE(pin_failed_attempts, 0), COALESCE(pin_account_locked, FALSE)
			 FROM users
			 WHERE phone = $1
			 LIMIT 1`,
			identifier,
		).Scan(&pinHash, &failedAttempts, &isLocked)

		if err == nil {
			exists = true
			hasPin = pinHash != nil && *pinHash != ""
		} else if errors.Is(err, pgx.ErrNoRows) {
			exists = false
			hasPin = false
		} else {
			return nil, err
		}
	}

	return &models.AuthStartResponse{
		Exists:        exists,
		Type:          identifierType,
		HasPIN:        hasPin,
		AccountLocked: isLocked || failedAttempts >= 15,
	}, nil
}

// SendOTPUniversal sends an OTP to any identifier (phone or email)
// regardless of whether the user exists or not. Used for the new
// unified login flow.
func (s *AuthService) SendOTPUniversal(
	ctx context.Context,
	identifier string,
) (*models.SendOTPResponse, error) {
	return s.GenerateOrResendOTP(ctx, identifier, "login")
}

// VerifyOTPAndCheck verifies the OTP and then checks if the user exists.
// If the user exists, creates a session and returns it.
// If not, returns exists=false so the client can redirect to signup.
func (s *AuthService) VerifyOTPAndCheck(
	ctx context.Context,
	identifier string,
	otp string,
) (*models.AuthCheckResponse, error) {
	identifier = strings.TrimSpace(identifier)
	otp = strings.TrimSpace(otp)

	if identifier == "" {
		return nil, errors.New("identifier is required")
	}
	if otp == "" {
		return nil, errors.New("OTP is required")
	}

	identifierType := detectIdentifierType(identifier)
	if identifierType == "" {
		return nil, errors.New("invalid identifier")
	}

	var (
		otpID          string
		otpHash        string
		idType         string
		expiresAt      time.Time
		failedAttempts int
		lockedUntil    *time.Time
	)

	err := s.DB.QueryRow(
		ctx,
		`SELECT id, otp_hash, identifier_type, original_expires_at, failed_attempts, locked_until
		 FROM otp_verifications
		 WHERE identifier = $1
		   AND purpose = 'login'
		   AND verified_at IS NULL
		 ORDER BY created_at DESC
		 LIMIT 1`,
		identifier,
	).Scan(&otpID, &otpHash, &idType, &expiresAt, &failedAttempts, &lockedUntil)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("OTP not found or already used")
		}
		return nil, err
	}

	// Check brute-force lock
	if lockedUntil != nil && time.Now().Before(*lockedUntil) {
		retryAfter := int(time.Until(*lockedUntil).Seconds()) + 1
		return nil, fmt.Errorf("too many failed attempts. Please try again in %d seconds", retryAfter)
	}

	if time.Now().After(expiresAt) {
		return nil, errors.New("OTP has expired")
	}

	if !s.isOTPValid(identifier, idType, otp, otpHash) {
		// Record failure and optionally lock
		newCount := failedAttempts + 1
		if newCount >= 5 {
			duration := s.getLockDurationForIdentifier(ctx, identifier)
			lockTime := time.Now().Add(duration)
			_, _ = s.DB.Exec(ctx,
				`UPDATE otp_verifications SET failed_attempts = $1, locked_until = $2 WHERE id = $3`,
				newCount, lockTime, otpID)
			return nil, fmt.Errorf("Account is temporarily locked. Please try again in %d minutes", int(duration.Minutes()))
		}
		_, _ = s.DB.Exec(ctx,
			`UPDATE otp_verifications SET failed_attempts = $1 WHERE id = $2`,
			newCount, otpID)
		return nil, errors.New("invalid OTP")
	}

	// OTP valid — mark as verified and reset failures
	_, err = s.DB.Exec(
		ctx,
		`UPDATE otp_verifications
		 SET verified_at = NOW(), failed_attempts = 0, locked_until = NULL
		 WHERE id = $1`,
		otpID,
	)
	if err != nil {
		return nil, err
	}

	// Check if user exists
	var exists bool
	if identifierType == "email" {
		err = s.DB.QueryRow(
			ctx,
			`SELECT EXISTS(SELECT 1 FROM users WHERE LOWER(email) = LOWER($1))`,
			identifier,
		).Scan(&exists)
	} else {
		err = s.DB.QueryRow(
			ctx,
			`SELECT EXISTS(SELECT 1 FROM users WHERE phone = $1)`,
			identifier,
		).Scan(&exists)
	}
	if err != nil {
		return nil, err
	}

	if exists {
		// User exists — unlock account and reset PIN failed attempts upon successful OTP verification
		_, _ = s.DB.Exec(ctx,
			`UPDATE users
			 SET pin_failed_attempts = 0, pin_locked_until = NULL, pin_account_locked = FALSE, updated_at = NOW()
			 WHERE phone = $1 OR LOWER(email) = LOWER($1)`,
			identifier,
		)

		// User exists — create session and return
		authResp, err := s.loginExistingUser(ctx, identifier)
		if err != nil {
			return nil, err
		}
		return &models.AuthCheckResponse{
			Exists:       true,
			Type:         identifierType,
			Identifier:   identifier,
			User:         &authResp.User,
			SessionToken: authResp.SessionToken,
		}, nil
	}

	// User does not exist — return so client can redirect to signup
	return &models.AuthCheckResponse{
		Exists:     false,
		Type:       identifierType,
		Identifier: identifier,
	}, nil
}

// CheckSecondaryIdentifier checks if a secondary identifier (the one NOT
// used for login) already exists in the database. If it does, returns an
// error. If not, sends an OTP to it.
func (s *AuthService) CheckSecondaryIdentifier(
	ctx context.Context,
	secondaryIdentifier string,
	secondaryType string,
) (*models.SendOTPResponse, error) {
	secondaryIdentifier = strings.TrimSpace(secondaryIdentifier)

	if secondaryIdentifier == "" {
		return nil, errors.New("identifier is required")
	}

	// Check if the secondary identifier is already registered
	var exists bool
	if secondaryType == "email" {
		err := s.DB.QueryRow(
			ctx,
			`SELECT EXISTS(SELECT 1 FROM users WHERE LOWER(email) = LOWER($1))`,
			secondaryIdentifier,
		).Scan(&exists)
		if err != nil {
			return nil, err
		}
		if exists {
			return nil, errors.New("Account already exists with this email. Try logging in with this email ID.")
		}
	} else {
		err := s.DB.QueryRow(
			ctx,
			`SELECT EXISTS(SELECT 1 FROM users WHERE phone = $1)`,
			secondaryIdentifier,
		).Scan(&exists)
		if err != nil {
			return nil, err
		}
		if exists {
			return nil, errors.New("Account already exists with this mobile number. Try logging in with this mobile number.")
		}
	}

	return s.GenerateOrResendOTP(ctx, secondaryIdentifier, "signup")
}

// CompleteSignup verifies the secondary OTP and creates the user account.
func (s *AuthService) CompleteSignup(
	ctx context.Context,
	request models.NewSignupRequest,
) (*models.AuthResponse, error) {
	// Validate all required fields
	request.FullName = strings.TrimSpace(request.FullName)
	request.Phone = strings.TrimSpace(request.Phone)
	request.Email = strings.TrimSpace(strings.ToLower(request.Email))
	request.DateOfBirth = strings.TrimSpace(request.DateOfBirth)
	request.Gender = strings.TrimSpace(strings.ToLower(request.Gender))
	request.SecondaryIdentifier = strings.TrimSpace(request.SecondaryIdentifier)
	request.SecondaryOTP = strings.TrimSpace(request.SecondaryOTP)

	if request.FullName == "" {
		return nil, errors.New("full name is required")
	}
	if request.Phone == "" {
		return nil, errors.New("phone is required")
	}
	if request.Email == "" {
		return nil, errors.New("email is required")
	}
	if request.DateOfBirth == "" {
		return nil, errors.New("date of birth is required")
	}
	if request.Gender != "male" && request.Gender != "female" && request.Gender != "other" {
		return nil, errors.New("invalid gender")
	}
	if request.SecondaryIdentifier == "" {
		return nil, errors.New("secondary identifier is required")
	}
	if request.SecondaryOTP == "" {
		return nil, errors.New("secondary OTP is required")
	}

	dateOfBirth, err := time.Parse("2006-01-02", request.DateOfBirth)
	if err != nil {
		return nil, errors.New("date of birth must be in YYYY-MM-DD format")
	}

	secondaryType := detectIdentifierType(request.SecondaryIdentifier)
	if secondaryType == "" {
		return nil, errors.New("invalid secondary identifier")
	}

	// Verify the secondary OTP
	var (
		otpID     string
		otpHash   string
		idType    string
		expiresAt time.Time
	)

	err = s.DB.QueryRow(
		ctx,
		`SELECT id, otp_hash, identifier_type, original_expires_at
		 FROM otp_verifications
		 WHERE identifier = $1
		   AND purpose = 'signup'
		   AND verified_at IS NULL
		 ORDER BY created_at DESC
		 LIMIT 1`,
		request.SecondaryIdentifier,
	).Scan(&otpID, &otpHash, &idType, &expiresAt)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("OTP not found or already used")
		}
		return nil, err
	}

	if time.Now().After(expiresAt) {
		return nil, errors.New("OTP has expired")
	}

	if !s.isOTPValid(request.SecondaryIdentifier, idType, request.SecondaryOTP, otpHash) {
		return nil, errors.New("invalid OTP")
	}

	// Mark OTP as verified
	_, err = s.DB.Exec(
		ctx,
		`UPDATE otp_verifications SET verified_at = NOW() WHERE id = $1`,
		otpID,
	)
	if err != nil {
		return nil, err
	}

	// Final duplicate check before creation
	var phoneExists, emailExists bool
	err = s.DB.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM users WHERE phone = $1)`,
		request.Phone,
	).Scan(&phoneExists)
	if err != nil {
		return nil, err
	}

	err = s.DB.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM users WHERE LOWER(email) = LOWER($1))`,
		request.Email,
	).Scan(&emailExists)
	if err != nil {
		return nil, err
	}

	if phoneExists {
		return nil, errors.New("Account already exists with this mobile number. Try logging in with this mobile number.")
	}
	if emailExists {
		return nil, errors.New("Account already exists with this email. Try logging in with this email ID.")
	}

	// Create the user — both phone and email are verified
	userID := uuid.New()
	now := time.Now()

	var user models.UserResponse

	err = s.DB.QueryRow(
		ctx,
		`INSERT INTO users (
			id, full_name, nickname, phone, email, date_of_birth, gender,
			phone_verified_at, email_verified_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING
			id, full_name, nickname, phone, email, date_of_birth, gender,
			phone_verified_at, email_verified_at`,
		userID,
		request.FullName,
		request.Nickname,
		request.Phone,
		request.Email,
		dateOfBirth,
		request.Gender,
		&now, // both verified
		&now, // both verified
	).Scan(
		&user.ID,
		&user.FullName,
		&user.Nickname,
		&user.Phone,
		&user.Email,
		&user.DateOfBirth,
		&user.Gender,
		&user.PhoneVerifiedAt,
		&user.EmailVerifiedAt,
	)

	if err != nil {
		return nil, err
	}

	// Generate unique referral code for the new user and process applied referral
	if s.ReferralService != nil {
		code, err := s.ReferralService.EnsureReferralCode(ctx, user.ID, user.FullName)
		if err == nil {
			user.ReferralCode = &code
		}

		if request.ReferralCode != nil && strings.TrimSpace(*request.ReferralCode) != "" {
			tx, txErr := s.DB.Begin(ctx)
			if txErr == nil {
				if refErr := s.ReferralService.ProcessReferralOnSignup(ctx, tx, user.ID, *request.ReferralCode); refErr == nil {
					_ = tx.Commit(ctx)
				} else {
					_ = tx.Rollback(ctx)
					return nil, refErr
				}
			}
		}
	}

	return s.createSession(ctx, user)
}

// ---- Legacy methods kept for backward compatibility ----

func (s *AuthService) StartSignup(
	ctx context.Context,
	request models.SignupRequest,
) error {
	request.FullName = strings.TrimSpace(request.FullName)
	request.Phone = strings.TrimSpace(request.Phone)
	request.Email = strings.TrimSpace(
		strings.ToLower(request.Email),
	)
	request.DateOfBirth = strings.TrimSpace(request.DateOfBirth)
	request.Gender = strings.TrimSpace(
		strings.ToLower(request.Gender),
	)

	if request.FullName == "" {
		return errors.New("full name is required")
	}

	if request.Phone == "" {
		return errors.New("phone is required")
	}

	if request.Email == "" {
		return errors.New("email is required")
	}

	if request.DateOfBirth == "" {
		return errors.New("date of birth is required")
	}

	if request.Gender != "male" &&
		request.Gender != "female" &&
		request.Gender != "other" {
		return errors.New("invalid gender")
	}

	_, err := time.Parse(
		"2006-01-02",
		request.DateOfBirth,
	)
	if err != nil {
		return errors.New(
			"date of birth must be in YYYY-MM-DD format",
		)
	}

	var phoneExists bool
	var emailExists bool

	err = s.DB.QueryRow(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM users
			WHERE phone = $1
		)`,
		request.Phone,
	).Scan(&phoneExists)

	if err != nil {
		return err
	}

	err = s.DB.QueryRow(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM users
			WHERE LOWER(email) = LOWER($1)
		)`,
		request.Email,
	).Scan(&emailExists)

	if err != nil {
		return err
	}

	if phoneExists {
		return errors.New(
			"phone number already registered",
		)
	}

	if emailExists {
		return errors.New(
			"email already registered",
		)
	}

	signupData, err := json.Marshal(request)
	if err != nil {
		return err
	}

	otp, err := s.generateOTP()
	if err != nil {
		return err
	}

	otpHash := hashValue(otp)
	expiresAt := time.Now().Add(5 * time.Minute)

	// Development default:
	// signup starts with mobile number.
	identifier := request.Phone
	identifierType := "phone"

	_, err = s.DB.Exec(
		ctx,
		`INSERT INTO otp_verifications (
			identifier,
			identifier_type,
			otp_hash,
			purpose,
			expires_at,
			signup_data
		)
		VALUES ($1, $2, $3, 'signup', $4, $5)`,
		identifier,
		identifierType,
		otpHash,
		expiresAt,
		signupData,
	)

	if err != nil {
		return err
	}

	return s.deliverOTP(
		identifier,
		identifierType,
		request.Email,
		otp,
	)
}

func (s *AuthService) SendLoginOTP(
	ctx context.Context,
	identifier string,
) error {
	identifier = strings.TrimSpace(identifier)

	identifierType := detectIdentifierType(identifier)

	if identifierType == "" {
		return errors.New(
			"invalid mobile number or email",
		)
	}

	var email string

	if identifierType == "email" {
		err := s.DB.QueryRow(
			ctx,
			`SELECT email
			 FROM users
			 WHERE LOWER(email) = LOWER($1)`,
			identifier,
		).Scan(&email)

		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return errors.New("user not found")
			}

			return err
		}
	} else {
		err := s.DB.QueryRow(
			ctx,
			`SELECT email
			 FROM users
			 WHERE phone = $1`,
			identifier,
		).Scan(&email)

		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return errors.New("user not found")
			}

			return err
		}
	}

	otp, err := s.generateOTP()
	if err != nil {
		return err
	}

	otpHash := hashValue(otp)
	expiresAt := time.Now().Add(5 * time.Minute)

	_, err = s.DB.Exec(
		ctx,
		`INSERT INTO otp_verifications (
			identifier,
			identifier_type,
			otp_hash,
			purpose,
			expires_at
		)
		VALUES ($1, $2, $3, 'login', $4)`,
		identifier,
		identifierType,
		otpHash,
		expiresAt,
	)

	if err != nil {
		return err
	}

	return s.deliverOTP(
		identifier,
		identifierType,
		email,
		otp,
	)
}

func (s *AuthService) VerifyOTP(
	ctx context.Context,
	request models.VerifyOTPRequest,
) (*models.AuthResponse, error) {
	identifier := strings.TrimSpace(
		request.Identifier,
	)

	otp := strings.TrimSpace(request.OTP)
	purpose := strings.TrimSpace(request.Purpose)

	if identifier == "" {
		return nil, errors.New(
			"identifier is required",
		)
	}

	if otp == "" {
		return nil, errors.New(
			"OTP is required",
		)
	}

	if purpose != "login" &&
		purpose != "signup" {
		return nil, errors.New(
			"invalid OTP purpose",
		)
	}

	var (
		otpID          string
		otpHash        string
		identifierType string
		expiresAt      time.Time
		signupData     []byte
		failedAttempts int
		lockedUntil    *time.Time
	)

	err := s.DB.QueryRow(
		ctx,
		`SELECT
			id,
			otp_hash,
			identifier_type,
			expires_at,
			COALESCE(signup_data, '{}'::jsonb),
			failed_attempts,
			locked_until
		FROM otp_verifications
		WHERE identifier = $1
		  AND purpose = $2
		  AND verified_at IS NULL
		ORDER BY created_at DESC
		LIMIT 1`,
		identifier,
		purpose,
	).Scan(
		&otpID,
		&otpHash,
		&identifierType,
		&expiresAt,
		&signupData,
		&failedAttempts,
		&lockedUntil,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New(
				"OTP not found or already used",
			)
		}

		return nil, err
	}

	// Check brute-force lock
	if lockedUntil != nil && time.Now().Before(*lockedUntil) {
		retryAfter := int(time.Until(*lockedUntil).Seconds()) + 1
		return nil, fmt.Errorf("too many failed attempts. Please try again in %d seconds", retryAfter)
	}

	if time.Now().After(expiresAt) {
		return nil, errors.New(
			"OTP has expired",
		)
	}

	if !s.isOTPValid(
		identifier,
		identifierType,
		otp,
		otpHash,
	) {
		// Record failure
		newCount := failedAttempts + 1
		if newCount >= 5 {
			duration := s.getLockDurationForIdentifier(ctx, identifier)
			lockTime := time.Now().Add(duration)
			_, _ = s.DB.Exec(ctx,
				`UPDATE otp_verifications SET failed_attempts = $1, locked_until = $2 WHERE id = $3`,
				newCount, lockTime, otpID)
			return nil, fmt.Errorf("Account is temporarily locked. Please try again in %d minutes", int(duration.Minutes()))
		}
		_, _ = s.DB.Exec(ctx,
			`UPDATE otp_verifications SET failed_attempts = $1 WHERE id = $2`,
			newCount, otpID)
		return nil, errors.New(
			"invalid OTP",
		)
	}

	_, err = s.DB.Exec(
		ctx,
		`UPDATE otp_verifications
		 SET verified_at = NOW(), failed_attempts = 0, locked_until = NULL
		 WHERE id = $1`,
		otpID,
	)

	if err != nil {
		return nil, err
	}

	if purpose == "signup" {
		return s.createUserFromSignup(
			ctx,
			signupData,
			identifierType,
		)
	}

	return s.loginExistingUser(
		ctx,
		identifier,
	)
}

func (s *AuthService) createUserFromSignup(
	ctx context.Context,
	data []byte,
	identifierType string,
) (*models.AuthResponse, error) {
	var signup models.SignupRequest

	err := json.Unmarshal(
		data,
		&signup,
	)
	if err != nil {
		return nil, errors.New(
			"invalid signup data",
		)
	}

	dateOfBirth, err := time.Parse(
		"2006-01-02",
		signup.DateOfBirth,
	)
	if err != nil {
		return nil, errors.New(
			"invalid date of birth",
		)
	}

	userID := uuid.New()

	var user models.UserResponse

	var phoneVerifiedAt *time.Time
	var emailVerifiedAt *time.Time

	now := time.Now()

	if identifierType == "phone" {
		phoneVerifiedAt = &now
	}

	if identifierType == "email" {
		emailVerifiedAt = &now
	}

	err = s.DB.QueryRow(
		ctx,
		`INSERT INTO users (
			id,
			full_name,
			nickname,
			phone,
			email,
			date_of_birth,
			gender,
			phone_verified_at,
			email_verified_at
		)
		VALUES (
			$1,
			$2,
			$3,
			$4,
			$5,
			$6,
			$7,
			$8,
			$9
		)
		RETURNING
			id,
			full_name,
			nickname,
			phone,
			email,
			date_of_birth,
			gender,
			phone_verified_at,
			email_verified_at`,
		userID,
		signup.FullName,
		signup.Nickname,
		signup.Phone,
		signup.Email,
		dateOfBirth,
		signup.Gender,
		phoneVerifiedAt,
		emailVerifiedAt,
	).Scan(
		&user.ID,
		&user.FullName,
		&user.Nickname,
		&user.Phone,
		&user.Email,
		&user.DateOfBirth,
		&user.Gender,
		&user.PhoneVerifiedAt,
		&user.EmailVerifiedAt,
	)

	if err != nil {
		return nil, err
	}

	if s.ReferralService != nil {
		code, err := s.ReferralService.EnsureReferralCode(ctx, user.ID, user.FullName)
		if err == nil {
			user.ReferralCode = &code
		}

		if signup.ReferralCode != nil && strings.TrimSpace(*signup.ReferralCode) != "" {
			tx, txErr := s.DB.Begin(ctx)
			if txErr == nil {
				if refErr := s.ReferralService.ProcessReferralOnSignup(ctx, tx, user.ID, *signup.ReferralCode); refErr == nil {
					_ = tx.Commit(ctx)
				} else {
					_ = tx.Rollback(ctx)
					return nil, refErr
				}
			}
		}
	}

	return s.createSession(
		ctx,
		user,
	)
}

func (s *AuthService) loginExistingUser(
	ctx context.Context,
	identifier string,
) (*models.AuthResponse, error) {
	var user models.UserResponse
	var pinHash *string

	err := s.DB.QueryRow(
		ctx,
		`SELECT
			id,
			full_name,
			nickname,
			phone,
			email,
			date_of_birth,
			gender,
			phone_verified_at,
			email_verified_at,
			pin_hash,
			referral_code
		FROM users
		WHERE phone = $1
		   OR LOWER(email) = LOWER($1)
		LIMIT 1`,
		identifier,
	).Scan(
		&user.ID,
		&user.FullName,
		&user.Nickname,
		&user.Phone,
		&user.Email,
		&user.DateOfBirth,
		&user.Gender,
		&user.PhoneVerifiedAt,
		&user.EmailVerifiedAt,
		&pinHash,
		&user.ReferralCode,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New(
				"user not found",
			)
		}

		return nil, err
	}

	fullUser, err := s.GetUserByID(ctx, user.ID)
	if err != nil {
		return nil, err
	}

	return s.createSession(
		ctx,
		*fullUser,
	)
}

func (s *AuthService) createSession(
	ctx context.Context,
	user models.UserResponse,
) (*models.AuthResponse, error) {
	tokenBytes := make(
		[]byte,
		32,
	)

	_, err := rand.Read(tokenBytes)
	if err != nil {
		return nil, err
	}

	sessionToken := hex.EncodeToString(
		tokenBytes,
	)

	tokenHash := hashValue(
		sessionToken,
	)

	expiresAt := time.Now().Add(
		30 * 24 * time.Hour,
	)

	_, err = s.DB.Exec(
		ctx,
		`INSERT INTO user_sessions (
			user_id,
			session_token_hash,
			expires_at
		)
		VALUES ($1, $2, $3)`,
		user.ID,
		tokenHash,
		expiresAt,
	)

	if err != nil {
		return nil, err
	}

	return &models.AuthResponse{
		User:         user,
		SessionToken: sessionToken,
	}, nil
}

func (s *AuthService) generateOTP() (string, error) {
	numberBytes := make([]byte, 4)

	_, err := rand.Read(numberBytes)
	if err != nil {
		return "", err
	}

	number := uint32(numberBytes[0])<<24 |
		uint32(numberBytes[1])<<16 |
		uint32(numberBytes[2])<<8 |
		uint32(numberBytes[3])

	return fmt.Sprintf(
		"%06d",
		number%1000000,
	), nil
}

func (s *AuthService) isOTPValid(
	identifier string,
	identifierType string,
	otp string,
	storedHash string,
) bool {
	if os.Getenv("APP_ENV") == "development" &&
		identifierType == "phone" &&
		otp == "123456" {
		return true
	}

	return hashValue(otp) == storedHash
}

func (s *AuthService) deliverOTP(
	identifier string,
	identifierType string,
	email string,
	otp string,
) error {
	if identifierType == "phone" {
		return nil
	}

	if identifierType != "email" {
		return errors.New("unsupported OTP delivery type")
	}

	if s.EmailService == nil {
		return errors.New("email service is not configured")
	}

	return s.EmailService.SendOTP(email, otp)
}

func detectIdentifierType(
	identifier string,
) string {
	if strings.Contains(
		identifier,
		"@",
	) {
		return "email"
	}

	digitsOnly := true

	for _, character := range identifier {
		if character < '0' ||
			character > '9' {
			digitsOnly = false
			break
		}
	}

	if digitsOnly &&
		len(identifier) >= 10 {
		return "phone"
	}

	return ""
}

func hashValue(
	value string,
) string {
	hash := sha256.Sum256(
		[]byte(value),
	)

	return hex.EncodeToString(
		hash[:],
	)
}

func (s *AuthService) GetUserByID(
	ctx context.Context,
	userID string,
) (*models.UserResponse, error) {

	var user models.UserResponse
	var pinHash *string

	err := s.DB.QueryRow(
		ctx,
		`SELECT
			id,
			full_name,
			nickname,
			phone,
			email,
			date_of_birth,
			gender,
			phone_verified_at,
			email_verified_at,
			pin_hash,
			COALESCE(money_earned, 0.00),
			referral_code
		FROM users
		WHERE id = $1`,
		userID,
	).Scan(
		&user.ID,
		&user.FullName,
		&user.Nickname,
		&user.Phone,
		&user.Email,
		&user.DateOfBirth,
		&user.Gender,
		&user.PhoneVerifiedAt,
		&user.EmailVerifiedAt,
		&pinHash,
		&user.MoneyEarned,
		&user.ReferralCode,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("user not found")
		}

		return nil, err
	}

	user.HasPIN = pinHash != nil && *pinHash != ""

	var avgRating *float64
	var totalRatings int
	_ = s.DB.QueryRow(
		ctx,
		`SELECT ROUND(AVG(rating_value)::numeric, 1), COUNT(*) FROM ratings WHERE ratee_id = $1`,
		userID,
	).Scan(&avgRating, &totalRatings)

	user.AverageRating = avgRating
	user.TotalRatings = totalRatings

	var totalRidesTaken int
	_ = s.DB.QueryRow(
		ctx,
		`SELECT 
			(SELECT COUNT(*) FROM rides WHERE driver_id = $1 AND status = 'completed') +
			(SELECT COUNT(DISTINCT b.ride_id) FROM bookings b JOIN rides r ON r.id = b.ride_id WHERE b.passenger_id = $1 AND r.status = 'completed' AND b.status IN ('confirmed', 'completed'))`,
		userID,
	).Scan(&totalRidesTaken)

	user.TotalRidesTaken = totalRidesTaken

	return &user, nil
}

func (s *AuthService) DeleteSession(
	ctx context.Context,
	sessionToken string,
) error {

	tokenHash := hashValue(
		strings.TrimSpace(sessionToken),
	)

	_, err := s.DB.Exec(
		ctx,
		`DELETE FROM user_sessions
		 WHERE session_token_hash = $1`,
		tokenHash,
	)

	return err
}

func (s *AuthService) UpdateProfile(
	ctx context.Context,
	userID string,
	req models.UpdateProfileRequest,
) (*models.UserResponse, error) {

	_, err := s.DB.Exec(
		ctx,
		`UPDATE users
		 SET full_name = $1, nickname = $2, date_of_birth = $3, gender = $4, updated_at = NOW()
		 WHERE id = $5`,
		req.FullName, req.Nickname, req.DateOfBirth, req.Gender, userID,
	)

	if err != nil {
		return nil, err
	}

	return s.GetUserByID(ctx, userID)
}

// -----------------------------------------------------------------------------
// SECURE PIN MANAGEMENT (Argon2id Encrypted)
// -----------------------------------------------------------------------------

const (
	argonMemory      = 64 * 1024 // 64 MB
	argonIterations  = 3
	argonParallelism = 2
	argonKeyLength   = 32
	argonSaltLength  = 16
)

func hashPinArgon2(pin string) (string, error) {
	salt := make([]byte, argonSaltLength)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}

	hash := argon2.IDKey([]byte(pin), salt, argonIterations, argonMemory, argonParallelism, argonKeyLength)

	b64Salt := base64.RawStdEncoding.EncodeToString(salt)
	b64Hash := base64.RawStdEncoding.EncodeToString(hash)

	// Format: $argon2id$v=19$m=65536,t=3,p=2$<salt>$<hash>
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s", argon2.Version, argonMemory, argonIterations, argonParallelism, b64Salt, b64Hash), nil
}

func verifyPinArgon2(pin, encodedHash string) (bool, error) {
	parts := strings.Split(encodedHash, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false, errors.New("invalid PIN hash format")
	}

	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil {
		return false, err
	}

	var memory uint32
	var iterations uint32
	var parallelism uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &iterations, &parallelism); err != nil {
		return false, err
	}

	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false, err
	}

	expectedHash, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false, err
	}

	computedHash := argon2.IDKey([]byte(pin), salt, iterations, memory, parallelism, uint32(len(expectedHash)))

	if subtle.ConstantTimeCompare(expectedHash, computedHash) == 1 {
		return true, nil
	}

	return false, nil
}

// SetUserPIN sets or updates a user's PIN using Argon2id encryption.
func (s *AuthService) SetUserPIN(
	ctx context.Context,
	userID string,
	pin string,
) error {
	pin = strings.TrimSpace(pin)
	if len(pin) != 4 {
		return errors.New("PIN must be exactly 4 digits")
	}
	for _, ch := range pin {
		if ch < '0' || ch > '9' {
			return errors.New("PIN must contain only numbers")
		}
	}

	// Fetch user details to check if this is the first PIN setup (account creation complete)
	var fullName, email string
	var existingPinHash *string
	err := s.DB.QueryRow(
		ctx,
		`SELECT full_name, email, pin_hash FROM users WHERE id = $1`,
		userID,
	).Scan(&fullName, &email, &existingPinHash)
	if err != nil {
		return fmt.Errorf("failed to fetch user details: %w", err)
	}

	hashed, err := hashPinArgon2(pin)
	if err != nil {
		return fmt.Errorf("failed to hash PIN: %w", err)
	}

	_, err = s.DB.Exec(
		ctx,
		`UPDATE users
		 SET pin_hash = $1, pin_failed_attempts = 0, pin_locked_until = NULL, pin_account_locked = FALSE, updated_at = NOW()
		 WHERE id = $2`,
		hashed, userID,
	)

	if err != nil {
		return err
	}

	// If the user did not have a PIN before, this means account creation (including PIN) is now successfully completed.
	// We send the welcome confirmation email asynchronously.
	if existingPinHash == nil && s.EmailService != nil {
		go func(to, name string) {
			err := s.EmailService.SendWelcomeEmail(to, name)
			if err != nil {
				// Log the error securely without rolling back the account
				fmt.Fprintf(os.Stderr, "[EmailService Error] Failed to send welcome email to %s: %v\n", to, err)
			}
		}(email, fullName)
	}

	return nil
}

// VerifyUserPIN verifies the provided PIN against the user's stored Argon2id hash.
func (s *AuthService) VerifyUserPIN(
	ctx context.Context,
	userID string,
	pin string,
) (bool, error) {
	pin = strings.TrimSpace(pin)
	if len(pin) != 4 {
		return false, errors.New("PIN must be 4 digits")
	}

	var storedHash *string
	err := s.DB.QueryRow(
		ctx,
		`SELECT pin_hash FROM users WHERE id = $1`,
		userID,
	).Scan(&storedHash)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return false, errors.New("user not found")
		}
		return false, err
	}

	if storedHash == nil || *storedHash == "" {
		return false, errors.New("PIN has not been set yet")
	}

	return verifyPinArgon2(pin, *storedHash)
}

// ChangeUserPIN verifies the old PIN and updates to the new PIN.
func (s *AuthService) ChangeUserPIN(
	ctx context.Context,
	userID string,
	oldPin string,
	newPin string,
) error {
	// 1. Verify the old PIN
	match, err := s.VerifyUserPIN(ctx, userID, oldPin)
	if err != nil {
		return err
	}
	if !match {
		return errors.New("incorrect old PIN")
	}

	// 2. Set the new PIN
	return s.SetUserPIN(ctx, userID, newPin)
}

// LoginWithPIN authenticates an existing user using their identifier (email or phone) and 4-digit PIN/passcode.
func (s *AuthService) LoginWithPIN(
	ctx context.Context,
	identifier string,
	pin string,
) (*models.AuthResponse, error) {
	identifier = strings.TrimSpace(identifier)
	pin = strings.TrimSpace(pin)

	if identifier == "" {
		return nil, errors.New("identifier is required")
	}
	if len(pin) != 4 {
		return nil, errors.New("passcode must be exactly 4 digits")
	}
	for _, ch := range pin {
		if ch < '0' || ch > '9' {
			return nil, errors.New("passcode must contain only digits")
		}
	}

	identifierType := detectIdentifierType(identifier)
	if identifierType == "" {
		return nil, errors.New("invalid identifier")
	}

	var (
		user           models.UserResponse
		pinHash        *string
		failedAttempts int
		lockedUntil    *time.Time
		accountLocked  bool
	)

	var query string
	if identifierType == "email" {
		query = `SELECT
			id,
			full_name,
			nickname,
			phone,
			email,
			date_of_birth,
			gender,
			phone_verified_at,
			email_verified_at,
			pin_hash,
			COALESCE(pin_failed_attempts, 0),
			pin_locked_until,
			COALESCE(pin_account_locked, FALSE)
		FROM users
		WHERE LOWER(email) = LOWER($1)
		LIMIT 1`
	} else {
		query = `SELECT
			id,
			full_name,
			nickname,
			phone,
			email,
			date_of_birth,
			gender,
			phone_verified_at,
			email_verified_at,
			pin_hash,
			COALESCE(pin_failed_attempts, 0),
			pin_locked_until,
			COALESCE(pin_account_locked, FALSE)
		FROM users
		WHERE phone = $1
		LIMIT 1`
	}

	err := s.DB.QueryRow(ctx, query, identifier).Scan(
		&user.ID,
		&user.FullName,
		&user.Nickname,
		&user.Phone,
		&user.Email,
		&user.DateOfBirth,
		&user.Gender,
		&user.PhoneVerifiedAt,
		&user.EmailVerifiedAt,
		&pinHash,
		&failedAttempts,
		&lockedUntil,
		&accountLocked,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("user not found")
		}
		return nil, err
	}

	// 1. Total limit check: after 15 failed attempts, lock account until OTP verification is completed
	if accountLocked || failedAttempts >= 15 {
		return nil, errors.New("Account is locked due to too many failed passcode attempts. Please verify with OTP to unlock your account.")
	}

	// 2. Timeout check: for every 3 attempts, give 30 seconds timeout
	if lockedUntil != nil && time.Now().Before(*lockedUntil) {
		remaining := int(time.Until(*lockedUntil).Seconds()) + 1
		if remaining <= 0 {
			remaining = 1
		}
		return nil, fmt.Errorf("Too many failed attempts. Please try again in %d seconds.", remaining)
	}

	if pinHash == nil || *pinHash == "" {
		return nil, errors.New("passcode has not been set yet")
	}

	match, err := verifyPinArgon2(pin, *pinHash)
	if err != nil {
		return nil, err
	}
	if !match {
		newFailed := failedAttempts + 1
		if newFailed >= 15 {
			_, _ = s.DB.Exec(ctx,
				`UPDATE users
				 SET pin_failed_attempts = $1, pin_account_locked = TRUE, updated_at = NOW()
				 WHERE id = $2`,
				newFailed, user.ID,
			)
			return nil, errors.New("Account is locked due to 15 failed passcode attempts. Please verify with OTP to unlock your account.")
		} else if newFailed%3 == 0 {
			timeoutUntil := time.Now().Add(30 * time.Second)
			_, _ = s.DB.Exec(ctx,
				`UPDATE users
				 SET pin_failed_attempts = $1, pin_locked_until = $2, updated_at = NOW()
				 WHERE id = $3`,
				newFailed, timeoutUntil, user.ID,
			)
			return nil, errors.New("Incorrect passcode. Too many attempts. Please try again in 30 seconds.")
		} else {
			_, _ = s.DB.Exec(ctx,
				`UPDATE users
				 SET pin_failed_attempts = $1, updated_at = NOW()
				 WHERE id = $2`,
				newFailed, user.ID,
			)
			attemptsLeft := 3 - (newFailed % 3)
			return nil, fmt.Errorf("Incorrect passcode. %d attempt(s) remaining before 30-second timeout.", attemptsLeft)
		}
	}

	// Correct passcode -> reset failed attempts and clear locks
	_, _ = s.DB.Exec(ctx,
		`UPDATE users
		 SET pin_failed_attempts = 0, pin_locked_until = NULL, pin_account_locked = FALSE, updated_at = NOW()
		 WHERE id = $1`,
		user.ID,
	)

	fullUser, err := s.GetUserByID(ctx, user.ID)
	if err != nil {
		return nil, err
	}

	return s.createSession(ctx, *fullUser)
}

func (s *AuthService) getLockDurationForIdentifier(ctx context.Context, identifier string) time.Duration {
	var previousLocks int
	err := s.DB.QueryRow(ctx,
		`SELECT COUNT(*) FROM otp_verifications 
		 WHERE identifier = $1 
		   AND locked_until IS NOT NULL 
		   AND created_at > NOW() - INTERVAL '24 hours'`,
		identifier,
	).Scan(&previousLocks)

	if err != nil || previousLocks == 0 {
		return 1 * time.Minute
	}
	return 5 * time.Minute
}
