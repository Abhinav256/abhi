package services

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/abhishare16/Abhi-Share/backend/models"
)

func (s *AuthService) GenerateOrResendOTP(
	ctx context.Context,
	identifier string,
	purpose string,
) (*models.SendOTPResponse, error) {
	identifier = strings.TrimSpace(identifier)

	identifierType := detectIdentifierType(identifier)
	if identifierType == "" {
		return nil, errors.New("invalid identifier")
	}

	var (
		sessionID           string
		otpHash             string
		otpCode             *string
		resendCount         int
		nextResendAllowedAt *time.Time
		originalExpiresAt   time.Time
	)

	err := s.DB.QueryRow(
		ctx,
		`SELECT id, otp_hash, otp_code, resend_count, next_resend_allowed_at, original_expires_at
		 FROM otp_verifications
		 WHERE identifier = $1 AND purpose = $2 AND verified_at IS NULL AND original_expires_at > NOW()
		 ORDER BY created_at DESC LIMIT 1`,
		identifier, purpose,
	).Scan(&sessionID, &otpHash, &otpCode, &resendCount, &nextResendAllowedAt, &originalExpiresAt)

	var otp string

	if err == nil {
		if nextResendAllowedAt != nil && time.Now().Before(*nextResendAllowedAt) {
			return nil, errors.New("please wait before requesting another OTP")
		}

		if otpCode != nil {
			otp = *otpCode
		} else {
			newOtp, _ := s.generateOTP()
			otp = newOtp
			otpHash = hashValue(otp)
		}

		var nextCooldown time.Duration
		switch resendCount {
		case 0:
			nextCooldown = 30 * time.Second
		case 1:
			nextCooldown = 1 * time.Minute
		default:
			nextCooldown = 2 * time.Minute
		}
		
		resendCount++
		nextAllowed := time.Now().Add(nextCooldown)
		nextResendAllowedAt = &nextAllowed

		_, err = s.DB.Exec(
			ctx,
			`UPDATE otp_verifications
			 SET resend_count = $1, next_resend_allowed_at = $2, otp_hash = $3, otp_code = $4
			 WHERE id = $5`,
			resendCount, nextResendAllowedAt, otpHash, otp, sessionID,
		)
		if err != nil {
			return nil, err
		}

	} else if err == pgx.ErrNoRows {
		otp, err = s.generateOTP()
		if err != nil {
			return nil, err
		}
		otpHash = hashValue(otp)
		originalExpiresAt = time.Now().Add(10 * time.Minute)
		nextAllowed := time.Now().Add(30 * time.Second)
		nextResendAllowedAt = &nextAllowed

		err = s.DB.QueryRow(
			ctx,
			`INSERT INTO otp_verifications (
				identifier, identifier_type, otp_hash, otp_code, purpose, expires_at, original_expires_at, resend_count, next_resend_allowed_at
			) VALUES ($1, $2, $3, $4, $5, $6, $7, 0, $8) RETURNING id`,
			identifier, identifierType, otpHash, otp, purpose, originalExpiresAt, originalExpiresAt, nextResendAllowedAt,
		).Scan(&sessionID)

		if err != nil {
			return nil, err
		}
		resendCount = 0
	} else {
		return nil, err
	}

	if identifierType == "email" {
		if s.EmailService == nil {
			return nil, errors.New("email service is not configured")
		}
		if err := s.EmailService.SendOTP(identifier, otp); err != nil {
			return nil, err
		}
	}

	return &models.SendOTPResponse{
		Type:                identifierType,
		SessionID:           sessionID,
		ExpiresAt:           originalExpiresAt,
		ResendCount:         resendCount,
		NextResendAllowedAt: nextResendAllowedAt,
	}, nil
}
