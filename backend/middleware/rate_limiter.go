package middleware

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// RateLimitTier defines the rate limit parameters for a category of endpoints.
type RateLimitTier struct {
	MaxRequests int           // Maximum requests allowed in the window
	Window      time.Duration // Sliding window duration
	BlockFor    time.Duration // How long to block after exceeding the limit
}

// Centralized rate limit tiers — single source of truth.
var (
	// OTP generation: strict to prevent SMS/email abuse
	TierOTPGeneration = RateLimitTier{MaxRequests: 8, Window: 10 * time.Minute, BlockFor: 5 * time.Minute}

	// OTP verification: very strict to prevent brute-force
	TierOTPVerification = RateLimitTier{MaxRequests: 6, Window: 5 * time.Minute, BlockFor: 10 * time.Minute}

	// PIN verification: strict to prevent brute-force (30s timeout, not 900s)
	TierPINVerification = RateLimitTier{MaxRequests: 30, Window: 5 * time.Minute, BlockFor: 30 * time.Second}

	// Account creation: prevent mass account creation
	TierAccountCreation = RateLimitTier{MaxRequests: 3, Window: 30 * time.Minute, BlockFor: 30 * time.Minute}

	// Auth check (start-auth, check-secondary): moderate
	TierAuthCheck = RateLimitTier{MaxRequests: 20, Window: 5 * time.Minute, BlockFor: 2 * time.Minute}

	// General authenticated endpoints: lenient
	TierGeneral = RateLimitTier{MaxRequests: 60, Window: 1 * time.Minute, BlockFor: 1 * time.Minute}
)

// RateLimiter provides database-backed rate limiting.
type RateLimiter struct {
	DB *pgxpool.Pool
}

// NewRateLimiter creates a new rate limiter backed by PostgreSQL.
func NewRateLimiter(db *pgxpool.Pool) *RateLimiter {
	return &RateLimiter{DB: db}
}

// hashKey produces a SHA-256 hash of the rate limit key to avoid storing
// raw identifiers (emails, phone numbers) in the rate_limits table.
func hashKey(parts ...string) string {
	combined := strings.Join(parts, "|")
	h := sha256.Sum256([]byte(combined))
	return hex.EncodeToString(h[:])
}

// extractClientIP extracts the real client IP from the Fiber context,
// respecting X-Forwarded-For and X-Real-IP headers.
func extractClientIP(c *fiber.Ctx) string {
	if xff := c.Get("X-Forwarded-For"); xff != "" {
		// Take the first (leftmost) IP, which is the original client
		parts := strings.SplitN(xff, ",", 2)
		ip := strings.TrimSpace(parts[0])
		if ip != "" {
			return ip
		}
	}
	if xri := c.Get("X-Real-IP"); xri != "" {
		return strings.TrimSpace(xri)
	}
	return c.IP()
}

// checkResult holds the result of a rate limit check.
type checkResult struct {
	Allowed    bool
	RetryAfter time.Duration
}

// check performs a single atomic rate-limit check-and-increment in the database.
// It uses an UPSERT to handle concurrent requests safely.
func (rl *RateLimiter) check(ctx context.Context, key string, tier RateLimitTier) (*checkResult, error) {
	now := time.Now()

	// Step 1: Check if the key is currently blocked.
	var blockedUntil *time.Time
	err := rl.DB.QueryRow(ctx,
		`SELECT blocked_until FROM rate_limits WHERE rate_key = $1 AND blocked_until > $2`,
		key, now.Format(time.RFC3339),
	).Scan(&blockedUntil)

	if err == nil && blockedUntil != nil {
		// Currently blocked
		return &checkResult{
			Allowed:    false,
			RetryAfter: time.Until(*blockedUntil),
		}, nil
	}

	// Step 2: Upsert the rate limit counter.
	// If the row exists and the window has not expired, increment the counter.
	// If the row exists but the window expired, reset the counter.
	// If the row doesn't exist, create it.
	windowStart := now.Add(-tier.Window)

	var requestCount int
	err = rl.DB.QueryRow(ctx,
		`INSERT INTO rate_limits (rate_key, window_start, request_count, updated_at)
		 VALUES ($1, $2, 1, $2)
		 ON CONFLICT (rate_key) DO UPDATE SET
		   request_count = CASE
		     WHEN rate_limits.window_start < $3 THEN 1
		     ELSE rate_limits.request_count + 1
		   END,
		   window_start = CASE
		     WHEN rate_limits.window_start < $3 THEN $2
		     ELSE rate_limits.window_start
		   END,
		   blocked_until = CAST(
		     CASE
		       WHEN rate_limits.window_start >= $3 AND rate_limits.request_count + 1 > $4 THEN $5
		       ELSE NULL
		     END AS timestamp with time zone
		   ),
		   updated_at = $2
		 RETURNING request_count`,
		key, now.Format(time.RFC3339), windowStart.Format(time.RFC3339), tier.MaxRequests, now.Add(tier.BlockFor).Format(time.RFC3339),
	).Scan(&requestCount)

	if err != nil {
		return nil, fmt.Errorf("rate limit check failed: %w", err)
	}

	if requestCount > tier.MaxRequests {
		return &checkResult{
			Allowed:    false,
			RetryAfter: tier.BlockFor,
		}, nil
	}

	return &checkResult{Allowed: true}, nil
}

// Middleware returns a Fiber middleware handler that enforces rate limiting.
// It builds composite keys from IP + endpoint, and optionally from a
// request body identifier (for OTP/auth endpoints).
func (rl *RateLimiter) Middleware(tier RateLimitTier) fiber.Handler {
	return func(c *fiber.Ctx) error {
		ip := extractClientIP(c)
		endpoint := c.Method() + ":" + c.Route().Path

		// Primary key: IP + endpoint
		ipKey := hashKey("ip", ip, endpoint)

		result, err := rl.check(context.Background(), ipKey, tier)
		if err != nil {
			// On rate-limiter failure, allow the request through (fail-open)
			// but log the error. Never block legitimate users due to infra issues.
			fmt.Printf("[RateLimiter] check error: %v\n", err)
			return c.Next()
		}

		if !result.Allowed {
			retrySeconds := int(result.RetryAfter.Seconds())
			if retrySeconds < 1 {
				retrySeconds = 1
			}
			c.Set("Retry-After", fmt.Sprintf("%d", retrySeconds))
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error":       fmt.Sprintf("Too many requests. Please try again in %d seconds.", retrySeconds),
				"retry_after": retrySeconds,
			})
		}

		return c.Next()
	}
}

// IdentifierMiddleware returns a Fiber middleware that performs an additional
// rate limit check keyed on a normalized identifier extracted from the request body.
// This prevents abuse by changing IPs but targeting the same phone/email.
func (rl *RateLimiter) IdentifierMiddleware(tier RateLimitTier) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Parse the body to extract an identifier
		var body struct {
			Identifier string `json:"identifier"`
			Phone      string `json:"phone"`
			Email      string `json:"email"`
		}

		// Try to parse — if it fails, skip identifier-based limiting
		if err := c.BodyParser(&body); err == nil {
			identifier := strings.TrimSpace(body.Identifier)
			if identifier == "" {
				identifier = strings.TrimSpace(body.Phone)
			}
			if identifier == "" {
				identifier = strings.TrimSpace(strings.ToLower(body.Email))
			}

			if identifier != "" {
				endpoint := c.Method() + ":" + c.Route().Path
				identifierKey := hashKey("id", strings.ToLower(identifier), endpoint)

				result, err := rl.check(context.Background(), identifierKey, tier)
				if err != nil {
					fmt.Printf("[RateLimiter] identifier check error: %v\n", err)
					return c.Next()
				}

				if !result.Allowed {
					retrySeconds := int(result.RetryAfter.Seconds())
					if retrySeconds < 1 {
						retrySeconds = 1
					}
					c.Set("Retry-After", fmt.Sprintf("%d", retrySeconds))
					return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
						"error":       fmt.Sprintf("Too many requests. Please try again in %d seconds.", retrySeconds),
						"retry_after": retrySeconds,
					})
				}
			}
		}

		// Reset body so downstream handlers can parse it again
		c.Request().SetBody(c.Body())

		return c.Next()
	}
}

// UserMiddleware returns a Fiber middleware that rate-limits by authenticated user ID.
// Must be placed AFTER auth middleware so user_id is available in Locals.
func (rl *RateLimiter) UserMiddleware(tier RateLimitTier) fiber.Handler {
	return func(c *fiber.Ctx) error {
		userID, ok := c.Locals("user_id").(string)
		if !ok || userID == "" {
			return c.Next()
		}

		endpoint := c.Method() + ":" + c.Route().Path
		userKey := hashKey("user", userID, endpoint)

		result, err := rl.check(context.Background(), userKey, tier)
		if err != nil {
			fmt.Printf("[RateLimiter] user check error: %v\n", err)
			return c.Next()
		}

		if !result.Allowed {
			retrySeconds := int(result.RetryAfter.Seconds())
			if retrySeconds < 1 {
				retrySeconds = 1
			}
			c.Set("Retry-After", fmt.Sprintf("%d", retrySeconds))
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error":       fmt.Sprintf("Too many requests. Please try again in %d seconds.", retrySeconds),
				"retry_after": retrySeconds,
			})
		}

		return c.Next()
	}
}

// CheckOTPBruteForce checks whether an OTP session is locked due to too many failed attempts.
// Returns (allowed bool, retryAfterSeconds int, error).
func (rl *RateLimiter) CheckOTPBruteForce(ctx context.Context, sessionID string) (bool, int, error) {
	var failedAttempts int
	var lockedUntil *time.Time

	err := rl.DB.QueryRow(ctx,
		`SELECT failed_attempts, locked_until FROM otp_verifications WHERE id = $1`,
		sessionID,
	).Scan(&failedAttempts, &lockedUntil)

	if err != nil {
		if err == pgx.ErrNoRows {
			return true, 0, nil
		}
		return false, 0, err
	}

	if lockedUntil != nil && time.Now().Before(*lockedUntil) {
		retryAfter := int(time.Until(*lockedUntil).Seconds()) + 1
		return false, retryAfter, nil
	}

	return true, 0, nil
}

// RecordOTPFailure increments the failed attempt counter on an OTP session
// and locks it if attempts exceed the threshold.
func (rl *RateLimiter) RecordOTPFailure(ctx context.Context, sessionID string) error {
	// Max 5 failed attempts, then lock for 10 minutes
	const maxAttempts = 5
	lockDuration := 10 * time.Minute

	_, err := rl.DB.Exec(ctx,
		`UPDATE otp_verifications
		 SET failed_attempts = failed_attempts + 1,
		     locked_until = CASE
		       WHEN failed_attempts + 1 >= $1 THEN $2
		       ELSE locked_until
		     END
		 WHERE id = $3`,
		maxAttempts, time.Now().Add(lockDuration), sessionID,
	)

	return err
}

// ResetOTPFailures resets the failed attempt counter after a successful verification.
func (rl *RateLimiter) ResetOTPFailures(ctx context.Context, sessionID string) error {
	_, err := rl.DB.Exec(ctx,
		`UPDATE otp_verifications SET failed_attempts = 0, locked_until = NULL WHERE id = $1`,
		sessionID,
	)
	return err
}

// CleanupExpired removes stale rate limit entries. Call periodically.
func (rl *RateLimiter) CleanupExpired(ctx context.Context) error {
	_, err := rl.DB.Exec(ctx,
		`DELETE FROM rate_limits
		 WHERE window_start < NOW() - INTERVAL '2 hours'
		   AND (blocked_until IS NULL OR blocked_until < NOW())`,
	)
	return err
}
