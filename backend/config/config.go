package config

import (
	"log"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	AppEnv       string
	DatabaseURL  string
	Port         string
	SMTPHost     string
	SMTPPort     string
	SMTPUsername string
	SMTPPassword string
	SMTPFrom              string
	StorageProvider       string
	SupabaseURL           string
	SupabaseStorageKey    string
	SupabaseBucketPublic  string
	SupabaseBucketPrivate string
	RazorpayKeyID         string
	RazorpayKeySecret     string
	RazorpayWebhookSecret string
	ExtraPayPercent       float64
	AllowedOrigins        string
	GeoapifyAPIKey        string
	GeoapifyAPIKeys       []string
}

func Load() *Config {
	_ = godotenv.Load()

	rawPort := getEnv("PORT", "8080")
	if !strings.HasPrefix(rawPort, ":") {
		rawPort = ":" + rawPort
	}

	appEnv := strings.ToLower(strings.TrimSpace(os.Getenv("APP_ENV")))
	if appEnv == "" {
		appEnv = strings.ToLower(strings.TrimSpace(os.Getenv("ENVIRONMENT")))
	}
	if appEnv == "" {
		appEnv = strings.ToLower(strings.TrimSpace(os.Getenv("ENV")))
	}
	if appEnv == "" {
		appEnv = "development"
	}

	cfg := &Config{
		AppEnv:                appEnv,
		DatabaseURL:           getEnv("DATABASE_URL", "postgresql://abhishare_app:AbhiShare2026SecurePass!@db.uqubmnnesyvvdeiwjnag.supabase.co:5432/postgres?sslmode=require"),
		Port:                  rawPort,
		SMTPHost:              os.Getenv("SMTP_HOST"),
		SMTPPort:              getEnv("SMTP_PORT", "587"),
		SMTPUsername:          os.Getenv("SMTP_USERNAME"),
		SMTPPassword:          os.Getenv("SMTP_PASSWORD"),
		SMTPFrom:              os.Getenv("SMTP_FROM"),
		StorageProvider:       getEnv("STORAGE_PROVIDER", "supabase"),
		SupabaseURL:           getEnv("SUPABASE_URL", "https://uqubmnnesyvvdeiwjnag.supabase.co"),
		SupabaseStorageKey:    os.Getenv("SUPABASE_STORAGE_KEY"),
		SupabaseBucketPublic:  getEnv("SUPABASE_BUCKET_PUBLIC", "abhishare-public"),
		SupabaseBucketPrivate: getEnv("SUPABASE_BUCKET_PRIVATE", "abhishare-private"),
		RazorpayKeyID:         getEnv("RAZORPAY_KEY_ID", "rzp_test_TlUKfo2Pi9FVYU"),
		RazorpayKeySecret:     os.Getenv("RAZORPAY_KEY_SECRET"),
		RazorpayWebhookSecret: getEnv("RAZORPAY_WEBHOOK_SECRET", os.Getenv("RAZORPAY_KEY_SECRET")),
		AllowedOrigins:        getEnv("ALLOWED_ORIGINS", ""),
		GeoapifyAPIKey:        os.Getenv("GEOAPIFY_API_KEY"),
	}

	// Collect all Geoapify keys from GEOAPIFY_API_KEY and GEOAPIFY_API_KEYS (comma-separated or fallback envs)
	keySet := make(map[string]bool)
	var allKeys []string
	addKey := func(k string) {
		k = strings.TrimSpace(k)
		if k != "" && !keySet[k] {
			keySet[k] = true
			allKeys = append(allKeys, k)
		}
	}

	// 1. Primary key
	if cfg.GeoapifyAPIKey != "" {
		for _, part := range strings.Split(cfg.GeoapifyAPIKey, ",") {
			addKey(part)
		}
	}
	// 2. Extra keys env variable GEOAPIFY_API_KEYS
	extraKeys := os.Getenv("GEOAPIFY_API_KEYS")
	if extraKeys != "" {
		for _, part := range strings.Split(extraKeys, ",") {
			addKey(part)
		}
	}
	cfg.GeoapifyAPIKeys = allKeys
	if len(allKeys) > 0 {
		cfg.GeoapifyAPIKey = allKeys[0]
	}
	log.Printf("[Config] Loaded %d Geoapify API key(s) with automatic failover", len(cfg.GeoapifyAPIKeys))

	// Parse and validate EXTRA_PAY_PERCENT.
	extraPayStr := getEnv("EXTRA_PAY_PERCENT", "4")
	extraPay, err := strconv.ParseFloat(extraPayStr, 64)
	if err != nil || extraPay < 0 {
		log.Printf("[Config] WARNING: invalid EXTRA_PAY_PERCENT=%q, defaulting to 4%%", extraPayStr)
		extraPay = 4.0
	}
	cfg.ExtraPayPercent = extraPay
	log.Printf("[Config] EXTRA_PAY_PERCENT = %.2f%%", cfg.ExtraPayPercent)

	return cfg
}

func getEnv(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	return value
}
