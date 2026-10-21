package middleware

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type AuthMiddleware struct {
	DB *pgxpool.Pool
}

func NewAuthMiddleware(db *pgxpool.Pool) *AuthMiddleware {
	return &AuthMiddleware{
		DB: db,
	}
}

func (m *AuthMiddleware) RequireAuth(
	c *fiber.Ctx,
) error {

	authHeader := strings.TrimSpace(
		c.Get("Authorization"),
	)

	if authHeader == "" {
		return c.Status(
			fiber.StatusUnauthorized,
		).JSON(fiber.Map{
			"error": "authorization required",
		})
	}

	parts := strings.Fields(authHeader)

	if len(parts) != 2 ||
		!strings.EqualFold(parts[0], "Bearer") {
		return c.Status(
			fiber.StatusUnauthorized,
		).JSON(fiber.Map{
			"error": "invalid authorization header",
		})
	}

	sessionToken := strings.TrimSpace(parts[1])

	if sessionToken == "" {
		return c.Status(
			fiber.StatusUnauthorized,
		).JSON(fiber.Map{
			"error": "invalid session token",
		})
	}

	userID, err := m.ValidateSessionToken(context.Background(), sessionToken)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return c.Status(
				fiber.StatusUnauthorized,
			).JSON(fiber.Map{
				"error": "invalid or expired session",
			})
		}
		if err.Error() == "session expired" {
			return c.Status(
				fiber.StatusUnauthorized,
			).JSON(fiber.Map{
				"error": "session expired",
			})
		}

		return c.Status(
			fiber.StatusInternalServerError,
		).JSON(fiber.Map{
			"error": "failed to validate session",
		})
	}

	c.Locals("user_id", userID)

	return c.Next()
}

// ValidateSessionToken verifies a raw bearer session token and returns the userID or error.
func (m *AuthMiddleware) ValidateSessionToken(ctx context.Context, sessionToken string) (string, error) {
	sessionToken = strings.TrimSpace(sessionToken)
	if sessionToken == "" {
		return "", errors.New("empty session token")
	}

	tokenHash := hashToken(sessionToken)

	var userID string
	var expiresAt time.Time

	err := m.DB.QueryRow(
		ctx,
		`SELECT user_id, expires_at
		 FROM user_sessions
		 WHERE session_token_hash = $1`,
		tokenHash,
	).Scan(
		&userID,
		&expiresAt,
	)
	if err != nil {
		return "", err
	}

	if time.Now().After(expiresAt) {
		return "", errors.New("session expired")
	}

	return userID, nil
}

func UserID(c *fiber.Ctx) (string, bool) {

	userID, ok := c.Locals(
		"user_id",
	).(string)

	if !ok ||
		strings.TrimSpace(userID) == "" {
		return "", false
	}

	return userID, true
}

func hashToken(token string) string {

	hash := sha256.Sum256(
		[]byte(token),
	)

	return hex.EncodeToString(
		hash[:],
	)
}
