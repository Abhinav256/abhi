//go:build ignore

package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

type MigrationItem struct {
	SourceFile   string
	Bucket       string
	ObjectKey    string
	ContentType  string
	IsPrivate    bool
	DBTable      string
	DBColumn     string
	RecordID     string
	SourceSize   int64
	SourceHash   string
	DestSize     int64
	DestHash     string
	DestURL      string
	Status       string
	ErrorMessage string
}

func main() {
	_ = godotenv.Load("../.env")
	_ = godotenv.Load(".env")

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgresql://abhishare_app:AbhiShare2026SecurePass!@db.uqubmnnesyvvdeiwjnag.supabase.co:5432/postgres?sslmode=require"
	}

	supabaseURL := os.Getenv("SUPABASE_URL")
	if supabaseURL == "" {
		supabaseURL = "https://uqubmnnesyvvdeiwjnag.supabase.co"
	}
	supabaseURL = strings.TrimRight(supabaseURL, "/")

	supabaseKey := os.Getenv("SUPABASE_STORAGE_KEY")
	if supabaseKey == "" {
		log.Fatal("SUPABASE_STORAGE_KEY environment variable is required")
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer pool.Close()

	log.Println("1. Creating database backup tables for safe rollback...")
	_, err = pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS vehicles_backup_urls AS 
		SELECT id, vehicle_photo_url, rc_photo_url FROM vehicles;
		
		CREATE TABLE IF NOT EXISTS rides_backup_urls AS 
		SELECT id, driver_selfie_url FROM rides;
	`)
	if err != nil {
		log.Fatalf("failed to create backup tables: %v", err)
	}
	log.Println("Backup tables verified/created.")

	// Determine uploads root path
	uploadsRoot := "./uploads"
	if _, err := os.Stat(uploadsRoot); os.IsNotExist(err) {
		uploadsRoot = "../uploads"
	}

	var items []MigrationItem

	// 1. Vehicle Photos
	vPhotosDir := filepath.Join(uploadsRoot, "vehicles/photos")
	if files, err := os.ReadDir(vPhotosDir); err == nil {
		for _, f := range files {
			if f.IsDir() || strings.HasPrefix(f.Name(), ".") {
				continue
			}
			id := strings.TrimSuffix(f.Name(), filepath.Ext(f.Name()))
			items = append(items, MigrationItem{
				SourceFile:  filepath.Join(vPhotosDir, f.Name()),
				Bucket:      "abhishare-public",
				ObjectKey:   "vehicles/photos/" + f.Name(),
				ContentType: "image/jpeg",
				IsPrivate:   false,
				DBTable:     "vehicles",
				DBColumn:    "vehicle_photo_url",
				RecordID:    id,
			})
		}
	}

	// 2. Vehicle RC Documents
	vRCDir := filepath.Join(uploadsRoot, "vehicles/rc")
	if files, err := os.ReadDir(vRCDir); err == nil {
		for _, f := range files {
			if f.IsDir() || strings.HasPrefix(f.Name(), ".") {
				continue
			}
			id := strings.TrimSuffix(f.Name(), filepath.Ext(f.Name()))
			items = append(items, MigrationItem{
				SourceFile:  filepath.Join(vRCDir, f.Name()),
				Bucket:      "abhishare-private",
				ObjectKey:   "vehicles/rc/" + f.Name(),
				ContentType: "image/jpeg",
				IsPrivate:   true,
				DBTable:     "vehicles",
				DBColumn:    "rc_photo_url",
				RecordID:    id,
			})
		}
	}

	// 3. Ride Selfies
	rSelfiesDir := filepath.Join(uploadsRoot, "rides/selfies")
	if files, err := os.ReadDir(rSelfiesDir); err == nil {
		for _, f := range files {
			if f.IsDir() || strings.HasPrefix(f.Name(), ".") {
				continue
			}
			id := strings.TrimSuffix(f.Name(), filepath.Ext(f.Name()))
			ct := "image/jpeg"
			if strings.HasSuffix(f.Name(), ".png") {
				ct = "image/png"
			}
			items = append(items, MigrationItem{
				SourceFile:  filepath.Join(rSelfiesDir, f.Name()),
				Bucket:      "abhishare-private",
				ObjectKey:   "rides/selfies/" + f.Name(),
				ContentType: ct,
				IsPrivate:   true,
				DBTable:     "rides",
				DBColumn:    "driver_selfie_url",
				RecordID:    id,
			})
		}
	}

	log.Printf("Found %d local files to migrate to Supabase Storage.\n", len(items))

	client := &http.Client{}
	successCount := 0

	for i := range items {
		item := &items[i]

		// 1. Read source and calculate hash
		fileData, err := os.ReadFile(item.SourceFile)
		if err != nil {
			item.Status = "FAILED"
			item.ErrorMessage = fmt.Sprintf("read error: %v", err)
			continue
		}
		item.SourceSize = int64(len(fileData))
		hash := sha256.Sum256(fileData)
		item.SourceHash = hex.EncodeToString(hash[:])

		// 2. Upload to Supabase Storage
		uploadURL := fmt.Sprintf("%s/storage/v1/object/%s/%s", supabaseURL, item.Bucket, item.ObjectKey)
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, uploadURL, bytes.NewReader(fileData))
		if err != nil {
			item.Status = "FAILED"
			item.ErrorMessage = fmt.Sprintf("req build error: %v", err)
			continue
		}
		req.Header.Set("apikey", supabaseKey)
		req.Header.Set("Authorization", "Bearer "+supabaseKey)
		req.Header.Set("Content-Type", item.ContentType)
		req.Header.Set("x-upsert", "true")

		resp, err := client.Do(req)
		if err != nil {
			item.Status = "FAILED"
			item.ErrorMessage = fmt.Sprintf("http error: %v", err)
			continue
		}

		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			item.Status = "FAILED"
			item.ErrorMessage = fmt.Sprintf("status %d: %s", resp.StatusCode, string(body))
			continue
		}
		resp.Body.Close()

		// 3. Verify destination by downloading and verifying size + sha256
		downloadURL := fmt.Sprintf("%s/storage/v1/object/%s/%s", supabaseURL, item.Bucket, item.ObjectKey)
		dReq, err := http.NewRequestWithContext(ctx, http.MethodGet, downloadURL, nil)
		if err != nil {
			item.Status = "FAILED"
			item.ErrorMessage = fmt.Sprintf("verify req build error: %v", err)
			continue
		}
		dReq.Header.Set("apikey", supabaseKey)
		dReq.Header.Set("Authorization", "Bearer "+supabaseKey)

		dResp, err := client.Do(dReq)
		if err != nil {
			item.Status = "FAILED"
			item.ErrorMessage = fmt.Sprintf("verify http error: %v", err)
			continue
		}

		if dResp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(dResp.Body)
			dResp.Body.Close()
			item.Status = "FAILED"
			item.ErrorMessage = fmt.Sprintf("verify status %d: %s", dResp.StatusCode, string(body))
			continue
		}

		downloadedData, err := io.ReadAll(dResp.Body)
		dResp.Body.Close()
		if err != nil {
			item.Status = "FAILED"
			item.ErrorMessage = fmt.Sprintf("verify read error: %v", err)
			continue
		}

		item.DestSize = int64(len(downloadedData))
		dHash := sha256.Sum256(downloadedData)
		item.DestHash = hex.EncodeToString(dHash[:])

		if item.DestSize != item.SourceSize || item.DestHash != item.SourceHash {
			item.Status = "CORRUPT_MISMATCH"
			item.ErrorMessage = fmt.Sprintf("checksum mismatch: source=%s, dest=%s", item.SourceHash, item.DestHash)
			continue
		}

		// 4. Construct Destination URL for Database
		if !item.IsPrivate {
			item.DestURL = fmt.Sprintf("%s/storage/v1/object/public/%s/%s", supabaseURL, item.Bucket, item.ObjectKey)
		} else {
			item.DestURL = fmt.Sprintf("%s/storage/v1/object/authenticated/%s/%s", supabaseURL, item.Bucket, item.ObjectKey)
		}

		// 5. Update Database Record
		updateSQL := fmt.Sprintf("UPDATE %s SET %s = $1, updated_at = NOW() WHERE id = $2", item.DBTable, item.DBColumn)
		_, err = pool.Exec(ctx, updateSQL, item.DestURL, item.RecordID)
		if err != nil {
			item.Status = "DB_UPDATE_FAILED"
			item.ErrorMessage = fmt.Sprintf("db update error: %v", err)
			continue
		}

		item.Status = "SUCCESS"
		successCount++
		log.Printf("[%d/%d] Verified & Migrated: %s -> %s/%s\n", successCount, len(items), item.SourceFile, item.Bucket, item.ObjectKey)
	}

	fmt.Println("\n=======================================================")
	fmt.Printf("MIGRATION COMPLETED: %d / %d SUCCESSFUL\n", successCount, len(items))
	fmt.Println("=======================================================")
}
