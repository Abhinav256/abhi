package storage

import (
	"context"
	"fmt"
	"io"
	"mime"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// LocalStorageProvider implements Provider using the local host filesystem.
type LocalStorageProvider struct {
	baseDir string
}

// NewLocalProvider creates a new local filesystem storage provider.
func NewLocalProvider(baseDir string) *LocalStorageProvider {
	return &LocalStorageProvider{
		baseDir: baseDir,
	}
}

func (p *LocalStorageProvider) resolvePath(objectKey string) string {
	cleanKey := strings.TrimPrefix(objectKey, "/")
	cleanKey = strings.TrimPrefix(cleanKey, "uploads/")
	return filepath.Join(p.baseDir, cleanKey)
}

func (p *LocalStorageProvider) Upload(ctx context.Context, bucket string, objectKey string, data io.Reader, size int64, opts UploadOptions) (string, error) {
	targetPath := p.resolvePath(objectKey)

	// Ensure parent directory exists
	dir := filepath.Dir(targetPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("failed to create directory %s: %w", dir, err)
	}

	outFile, err := os.Create(targetPath)
	if err != nil {
		return "", fmt.Errorf("failed to create file %s: %w", targetPath, err)
	}
	defer outFile.Close()

	if _, err := io.Copy(outFile, data); err != nil {
		return "", fmt.Errorf("failed to write file %s: %w", targetPath, err)
	}

	cleanKey := strings.TrimPrefix(objectKey, "/")
	cleanKey = strings.TrimPrefix(cleanKey, "uploads/")
	return "/uploads/" + cleanKey, nil
}

func (p *LocalStorageProvider) GetURL(ctx context.Context, bucket string, objectKey string, isPrivate bool, expiry time.Duration) (string, error) {
	cleanKey := strings.TrimPrefix(objectKey, "/")
	cleanKey = strings.TrimPrefix(cleanKey, "uploads/")
	return "/uploads/" + cleanKey, nil
}

func (p *LocalStorageProvider) Download(ctx context.Context, bucket string, objectKey string) (io.ReadCloser, string, error) {
	targetPath := p.resolvePath(objectKey)
	file, err := os.Open(targetPath)
	if err != nil {
		return nil, "", err
	}

	ext := filepath.Ext(targetPath)
	contentType := mime.TypeByExtension(ext)
	if contentType == "" {
		contentType = "application/octet-stream"
	}

	return file, contentType, nil
}

func (p *LocalStorageProvider) Delete(ctx context.Context, bucket string, objectKey string) error {
	targetPath := p.resolvePath(objectKey)
	if err := os.Remove(targetPath); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func (p *LocalStorageProvider) Exists(ctx context.Context, bucket string, objectKey string) (bool, error) {
	targetPath := p.resolvePath(objectKey)
	_, err := os.Stat(targetPath)
	if err == nil {
		return true, nil
	}
	if os.IsNotExist(err) {
		return false, nil
	}
	return false, err
}
