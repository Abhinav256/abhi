package storage

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// SupabaseStorageProvider implements Provider using the Supabase Storage REST API.
type SupabaseStorageProvider struct {
	baseURL       string
	apiKey        string
	bucketPublic  string
	bucketPrivate string
	httpClient    *http.Client
}

// NewSupabaseProvider creates a new Supabase storage provider.
func NewSupabaseProvider(baseURL, apiKey, bucketPublic, bucketPrivate string) *SupabaseStorageProvider {
	baseURL = strings.TrimRight(baseURL, "/")
	if bucketPublic == "" {
		bucketPublic = "abhishare-public"
	}
	if bucketPrivate == "" {
		bucketPrivate = "abhishare-private"
	}

	return &SupabaseStorageProvider{
		baseURL:       baseURL,
		apiKey:        apiKey,
		bucketPublic:  bucketPublic,
		bucketPrivate: bucketPrivate,
		httpClient: &http.Client{
			Timeout: 45 * time.Second,
		},
	}
}

func (p *SupabaseStorageProvider) cleanObjectKey(objectKey string) string {
	clean := strings.TrimPrefix(objectKey, "/")
	clean = strings.TrimPrefix(clean, "uploads/")
	return clean
}

func (p *SupabaseStorageProvider) Upload(ctx context.Context, bucket string, objectKey string, data io.Reader, size int64, opts UploadOptions) (string, error) {
	if bucket == "" {
		if opts.IsPrivate {
			bucket = p.bucketPrivate
		} else {
			bucket = p.bucketPublic
		}
	}

	key := p.cleanObjectKey(objectKey)
	uploadURL := fmt.Sprintf("%s/storage/v1/object/%s/%s", p.baseURL, bucket, key)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, uploadURL, data)
	if err != nil {
		return "", fmt.Errorf("failed to create upload request: %w", err)
	}

	contentType := opts.ContentType
	if contentType == "" || contentType == "application/octet-stream" {
		lowerKey := strings.ToLower(key)
		switch {
		case strings.HasSuffix(lowerKey, ".jpg"), strings.HasSuffix(lowerKey, ".jpeg"):
			contentType = "image/jpeg"
		case strings.HasSuffix(lowerKey, ".png"):
			contentType = "image/png"
		case strings.HasSuffix(lowerKey, ".webp"):
			contentType = "image/webp"
		case strings.HasSuffix(lowerKey, ".pdf"):
			contentType = "application/pdf"
		default:
			if contentType == "" {
				contentType = "application/octet-stream"
			}
		}
	}

	req.Header.Set("apikey", p.apiKey)
	req.Header.Set("Authorization", "Bearer "+p.apiKey)
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("x-upsert", "true")
	if size > 0 {
		req.ContentLength = size
	}

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to upload object to Supabase: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("supabase upload error (status %d): %s", resp.StatusCode, string(body))
	}

	// For public buckets, return the direct public CDN URL
	if !opts.IsPrivate && bucket == p.bucketPublic {
		return fmt.Sprintf("%s/storage/v1/object/public/%s/%s", p.baseURL, bucket, key), nil
	}

	// For private objects, return the canonical URL (GetURL will sign when needed)
	return fmt.Sprintf("%s/storage/v1/object/authenticated/%s/%s", p.baseURL, bucket, key), nil
}

func (p *SupabaseStorageProvider) GetURL(ctx context.Context, bucket string, objectKey string, isPrivate bool, expiry time.Duration) (string, error) {
	if bucket == "" {
		if isPrivate {
			bucket = p.bucketPrivate
		} else {
			bucket = p.bucketPublic
		}
	}

	key := p.cleanObjectKey(objectKey)

	if !isPrivate && bucket == p.bucketPublic {
		return fmt.Sprintf("%s/storage/v1/object/public/%s/%s", p.baseURL, bucket, key), nil
	}

	// Generate signed URL for private bucket
	if expiry <= 0 {
		expiry = 1 * time.Hour
	}

	signURL := fmt.Sprintf("%s/storage/v1/object/sign/%s/%s", p.baseURL, bucket, key)
	payload := map[string]interface{}{
		"expiresIn": int(expiry.Seconds()),
	}
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, signURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return "", err
	}

	req.Header.Set("apikey", p.apiKey)
	req.Header.Set("Authorization", "Bearer "+p.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		respBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("failed to sign url (status %d): %s", resp.StatusCode, string(respBody))
	}

	var result struct {
		SignedURL string `json:"signedURL"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}

	if strings.HasPrefix(result.SignedURL, "http") {
		return result.SignedURL, nil
	}

	return fmt.Sprintf("%s/storage/v1%s", p.baseURL, result.SignedURL), nil
}

func (p *SupabaseStorageProvider) Download(ctx context.Context, bucket string, objectKey string) (io.ReadCloser, string, error) {
	if bucket == "" {
		bucket = p.bucketPublic
	}
	key := p.cleanObjectKey(objectKey)
	downloadURL := fmt.Sprintf("%s/storage/v1/object/%s/%s", p.baseURL, bucket, key)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, downloadURL, nil)
	if err != nil {
		return nil, "", err
	}

	req.Header.Set("apikey", p.apiKey)
	req.Header.Set("Authorization", "Bearer "+p.apiKey)

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return nil, "", err
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		return nil, "", fmt.Errorf("failed to download object (status %d): %s", resp.StatusCode, string(body))
	}

	contentType := resp.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "application/octet-stream"
	}

	return resp.Body, contentType, nil
}

func (p *SupabaseStorageProvider) Delete(ctx context.Context, bucket string, objectKey string) error {
	if bucket == "" {
		bucket = p.bucketPublic
	}
	key := p.cleanObjectKey(objectKey)
	deleteURL := fmt.Sprintf("%s/storage/v1/object/%s/%s", p.baseURL, bucket, key)

	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, deleteURL, nil)
	if err != nil {
		return err
	}

	req.Header.Set("apikey", p.apiKey)
	req.Header.Set("Authorization", "Bearer "+p.apiKey)

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("failed to delete object (status %d): %s", resp.StatusCode, string(body))
	}

	return nil
}

func (p *SupabaseStorageProvider) Exists(ctx context.Context, bucket string, objectKey string) (bool, error) {
	if bucket == "" {
		bucket = p.bucketPublic
	}
	key := p.cleanObjectKey(objectKey)
	infoURL := fmt.Sprintf("%s/storage/v1/object/info/%s/%s", p.baseURL, bucket, key)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, infoURL, nil)
	if err != nil {
		return false, err
	}

	req.Header.Set("apikey", p.apiKey)
	req.Header.Set("Authorization", "Bearer "+p.apiKey)

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return true, nil
	}
	if resp.StatusCode == http.StatusNotFound {
		return false, nil
	}

	body, _ := io.ReadAll(resp.Body)
	return false, fmt.Errorf("exists check failed (status %d): %s", resp.StatusCode, string(body))
}
