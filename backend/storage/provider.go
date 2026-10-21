package storage

import (
	"context"
	"fmt"
	"io"
	"time"
)

// UploadOptions defines metadata for an upload operation.
type UploadOptions struct {
	ContentType string
	IsPrivate   bool
}

// Provider defines the provider-independent object storage interface for AbhiShare.
// Implementations exist for Local filesystem and Supabase Storage (with future S3/R2 support).
type Provider interface {
	// Upload stores an object in the specified bucket at objectKey and returns the public or canonical URL.
	Upload(ctx context.Context, bucket string, objectKey string, data io.Reader, size int64, opts UploadOptions) (string, error)

	// GetURL returns the accessible URL for the object. For private objects, a signed URL is generated.
	GetURL(ctx context.Context, bucket string, objectKey string, isPrivate bool, expiry time.Duration) (string, error)

	// Download retrieves the object data stream and its content type.
	Download(ctx context.Context, bucket string, objectKey string) (io.ReadCloser, string, error)

	// Delete removes an object from storage.
	Delete(ctx context.Context, bucket string, objectKey string) error

	// Exists checks if an object exists in the storage provider.
	Exists(ctx context.Context, bucket string, objectKey string) (bool, error)
}

// Config contains parameters for configuring storage providers.
type Config struct {
	Provider      string // "local" or "supabase"
	LocalBaseDir  string // Root folder for local storage (default: "./uploads")
	SupabaseURL   string // Base URL of Supabase project
	SupabaseKey   string // Service / API key for Supabase Storage
	BucketPublic  string // Default public bucket name
	BucketPrivate string // Default private bucket name
}

// NewProvider creates a storage.Provider based on the configuration.
func NewProvider(cfg *Config) (Provider, error) {
	switch cfg.Provider {
	case "supabase":
		if cfg.SupabaseURL == "" || cfg.SupabaseKey == "" {
			return nil, fmt.Errorf("supabase URL and storage key are required when STORAGE_PROVIDER=supabase")
		}
		return NewSupabaseProvider(cfg.SupabaseURL, cfg.SupabaseKey, cfg.BucketPublic, cfg.BucketPrivate), nil
	case "local", "":
		baseDir := cfg.LocalBaseDir
		if baseDir == "" {
			baseDir = "./uploads"
		}
		return NewLocalProvider(baseDir), nil
	default:
		return nil, fmt.Errorf("unsupported storage provider: %s", cfg.Provider)
	}
}
