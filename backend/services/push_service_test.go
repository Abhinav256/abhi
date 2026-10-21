package services

import (
	"context"
	"os"
	"testing"

	"github.com/joho/godotenv"
)

func TestFCMInitializationFromEnv(t *testing.T) {
	_ = godotenv.Load("../.env")
	key := os.Getenv("FIREBASE_SERVICE_ACCOUNT_KEY")
	if key == "" {
		t.Skip("FIREBASE_SERVICE_ACCOUNT_KEY is not set")
	}

	svc := NewPushService(nil)
	svc.mu.RLock()
	defer svc.mu.RUnlock()

	if svc.fcmClient == nil {
		t.Fatalf("Expected fcmClient to be initialized with credentials from .env, but was nil")
	}
	t.Log("FCM Client successfully initialized from FIREBASE_SERVICE_ACCOUNT_KEY in .env!")
	_ = context.Background()
}
