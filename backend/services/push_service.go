package services

import (
	"context"
	"encoding/base64"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/jackc/pgx/v5/pgxpool"
	"google.golang.org/api/option"
)

type PushService struct {
	DB         *pgxpool.Pool
	fcmClient  *messaging.Client
	projectID  string
	mu         sync.RWMutex
	recentSent sync.Map // notificationID -> timestamp (deduplication)
}

func NewPushService(db *pgxpool.Pool) *PushService {
	projectID := os.Getenv("FIREBASE_PROJECT_ID")
	if projectID == "" {
		projectID = "abhishare-d40ae"
	}

	service := &PushService{
		DB:        db,
		projectID: projectID,
	}

	service.initFCMClient()
	return service
}

// initFCMClient initializes the Firebase Admin Messaging client.
func (s *PushService) initFCMClient() {
	s.mu.Lock()
	defer s.mu.Unlock()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var opt option.ClientOption

	// 1. Raw JSON string or Base64 string from environment variable
	if keyEnv := strings.TrimSpace(os.Getenv("FIREBASE_SERVICE_ACCOUNT_KEY")); keyEnv != "" {
		keyBytes := []byte(keyEnv)
		if !strings.HasPrefix(keyEnv, "{") {
			// Might be base64-encoded
			if decoded, err := base64.StdEncoding.DecodeString(keyEnv); err == nil {
				keyBytes = decoded
			}
		}
		opt = option.WithCredentialsJSON(keyBytes)
	} else if filePath := strings.TrimSpace(os.Getenv("FIREBASE_SERVICE_ACCOUNT_FILE")); filePath != "" {
		// 2. Direct file path
		opt = option.WithCredentialsFile(filePath)
	} else if _, err := os.Stat("service-account.json"); err == nil {
		// 3. Local service-account.json file
		opt = option.WithCredentialsFile("service-account.json")
	} else if _, err := os.Stat("config/firebase-service-account.json"); err == nil {
		// 4. Local config/firebase-service-account.json file
		opt = option.WithCredentialsFile("config/firebase-service-account.json")
	} else if os.Getenv("GOOGLE_APPLICATION_CREDENTIALS") != "" {
		// 5. Standard Google Cloud SDK credentials variable
		opt = option.WithCredentialsFile(os.Getenv("GOOGLE_APPLICATION_CREDENTIALS"))
	}

	if opt == nil {
		log.Printf("[PushService] Notice: Firebase service account credentials not configured yet. " +
			"Tokens will be registered in DB. To enable live push delivery, set FIREBASE_SERVICE_ACCOUNT_KEY or FIREBASE_SERVICE_ACCOUNT_FILE.")
		return
	}

	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: s.projectID}, opt)
	if err != nil {
		log.Printf("[PushService] Error initializing Firebase App: %v", err)
		return
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		log.Printf("[PushService] Error initializing Firebase Messaging client: %v", err)
		return
	}

	s.fcmClient = client
	log.Printf("[PushService] Successfully initialized Firebase Cloud Messaging client for project: %s", s.projectID)
}

// IsReady returns true if Firebase Admin SDK is ready to send notifications.
func (s *PushService) IsReady() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.fcmClient != nil
}

// RegisterDeviceToken records or updates an FCM device token for a user.
func (s *PushService) RegisterDeviceToken(ctx context.Context, userID, token, platform string) error {
	token = strings.TrimSpace(token)
	if token == "" {
		return fmt.Errorf("token cannot be empty")
	}

	platform = strings.ToLower(strings.TrimSpace(platform))
	if platform != "ios" && platform != "android" && platform != "web" {
		platform = "android"
	}

	_, err := s.DB.Exec(
		ctx,
		`INSERT INTO user_device_tokens (user_id, device_token, platform, updated_at)
		 VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
		 ON CONFLICT (user_id, device_token)
		 DO UPDATE SET platform = EXCLUDED.platform, updated_at = CURRENT_TIMESTAMP`,
		userID, token, platform,
	)
	if err != nil {
		return fmt.Errorf("failed to register device token: %w", err)
	}

	log.Printf("[PushService] Registered %s device token for user %s (prefix: %s...)", platform, userID, token[:min(10, len(token))])
	return nil
}

// UnregisterDeviceToken removes an FCM device token (e.g. on logout).
func (s *PushService) UnregisterDeviceToken(ctx context.Context, userID, token string) error {
	token = strings.TrimSpace(token)
	if token == "" {
		return nil
	}

	_, err := s.DB.Exec(
		ctx,
		`DELETE FROM user_device_tokens WHERE user_id = $1 AND device_token = $2`,
		userID, token,
	)
	if err != nil {
		return fmt.Errorf("failed to unregister device token: %w", err)
	}

	log.Printf("[PushService] Unregistered device token for user %s", userID)
	return nil
}

// GetDeviceTokensForUser retrieves all active device tokens registered for a user.
func (s *PushService) GetDeviceTokensForUser(ctx context.Context, userID string) ([]string, error) {
	rows, err := s.DB.Query(
		ctx,
		`SELECT device_token FROM user_device_tokens WHERE user_id = $1 ORDER BY updated_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var tok string
		if err := rows.Scan(&tok); err == nil && tok != "" {
			tokens = append(tokens, tok)
		}
	}
	return tokens, nil
}

// SendPushToUser sends a push notification with data payload to all registered devices of a user.
func (s *PushService) SendPushToUser(ctx context.Context, userID, title, body string, data map[string]string) error {
	s.mu.RLock()
	client := s.fcmClient
	s.mu.RUnlock()

	if client == nil {
		// Try lazy re-init in case credentials were just added
		s.initFCMClient()
		s.mu.RLock()
		client = s.fcmClient
		s.mu.RUnlock()
		if client == nil {
			log.Printf("[PushService] Cannot send push: FCM client not configured yet")
			return nil
		}
	}

	tokens, err := s.GetDeviceTokensForUser(ctx, userID)
	if err != nil {
		return fmt.Errorf("failed to fetch user device tokens: %w", err)
	}

	if len(tokens) == 0 {
		return nil
	}

	// Clean data payload
	if data == nil {
		data = make(map[string]string)
	}
	data["title"] = title
	data["message"] = body
	data["click_action"] = "FLUTTER_NOTIFICATION_CLICK"

	var staleTokens []string

	for _, token := range tokens {
		msg := &messaging.Message{
			Token: token,
			Notification: &messaging.Notification{
				Title: title,
				Body:  body,
			},
			Data: data,
			Android: &messaging.AndroidConfig{
				Priority: "high",
				Notification: &messaging.AndroidNotification{
					ChannelID:             "abhishare_notifications",
					Priority:              messaging.PriorityHigh,
					DefaultSound:          true,
					DefaultVibrateTimings: true,
					Visibility:            messaging.VisibilityPublic,
				},
			},
			APNS: &messaging.APNSConfig{
				Headers: map[string]string{
					"apns-priority": "10",
				},
				Payload: &messaging.APNSPayload{
					Aps: &messaging.Aps{
						Alert: &messaging.ApsAlert{
							Title: title,
							Body:  body,
						},
						Sound:            "default",
						ContentAvailable: true,
					},
				},
			},
		}

		sendCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		_, err := client.Send(sendCtx, msg)
		cancel()

		if err != nil {
			log.Printf("[PushService] Failed sending to token %s...: %v", token[:min(10, len(token))], err)
			if messaging.IsUnregistered(err) || messaging.IsInvalidArgument(err) {
				staleTokens = append(staleTokens, token)
			}
		} else {
			log.Printf("[PushService] Push successfully dispatched to user %s (token prefix %s...)", userID, token[:min(10, len(token))])
		}
	}

	// Purge stale/unregistered tokens
	if len(staleTokens) > 0 {
		go func(badTokens []string) {
			for _, badTok := range badTokens {
				_, _ = s.DB.Exec(context.Background(), `DELETE FROM user_device_tokens WHERE device_token = $1`, badTok)
			}
		}(staleTokens)
	}

	return nil
}

// StartBackgroundWorker continuously scans for unsent notifications and dispatches them.
func (s *PushService) StartBackgroundWorker(ctx context.Context) {
	ticker := time.NewTicker(3 * time.Second)
	cleanupTicker := time.NewTicker(10 * time.Minute)

	go func() {
		defer ticker.Stop()
		defer cleanupTicker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-cleanupTicker.C:
				// Clean deduplication map
				now := time.Now()
				s.recentSent.Range(func(key, val any) bool {
					if t, ok := val.(time.Time); ok && now.Sub(t) > 5*time.Minute {
						s.recentSent.Delete(key)
					}
					return true
				})
			case <-ticker.C:
				s.processUnsentNotifications(ctx)
			}
		}
	}()
}

// processUnsentNotifications queries rows with push_sent = FALSE and sends pushes.
func (s *PushService) processUnsentNotifications(ctx context.Context) {
	rows, err := s.DB.Query(
		ctx,
		`SELECT id, user_id, type, title, message, COALESCE(ride_id::text, ''), COALESCE(booking_id::text, '')
		 FROM notifications
		 WHERE push_sent = FALSE AND created_at >= NOW() - INTERVAL '1 hour'
		 ORDER BY created_at ASC
		 LIMIT 50`,
	)
	if err != nil {
		log.Printf("[PushService] processUnsentNotifications query error: %v", err)
		return
	}
	defer rows.Close()

	type pendingNotif struct {
		id        string
		userID    string
		notifType string
		title     string
		message   string
		rideID    string
		bookingID string
	}

	var pending []pendingNotif
	for rows.Next() {
		var p pendingNotif
		if err := rows.Scan(&p.id, &p.userID, &p.notifType, &p.title, &p.message, &p.rideID, &p.bookingID); err == nil {
			pending = append(pending, p)
		}
	}

	for _, n := range pending {
		// Deduplication check
		if _, exists := s.recentSent.Load(n.id); exists {
			_, _ = s.DB.Exec(ctx, `UPDATE notifications SET push_sent = TRUE WHERE id = $1`, n.id)
			continue
		}

		s.recentSent.Store(n.id, time.Now())

		data := map[string]string{
			"notification_id": n.id,
			"type":            n.notifType,
		}
		if n.rideID != "" {
			data["ride_id"] = n.rideID
		}
		if n.bookingID != "" {
			data["booking_id"] = n.bookingID
		}

		// Send push
		_ = s.SendPushToUser(ctx, n.userID, n.title, n.message, data)

		// Mark processed in DB
		_, _ = s.DB.Exec(ctx, `UPDATE notifications SET push_sent = TRUE WHERE id = $1`, n.id)
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
