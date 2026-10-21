//go:build ignore

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	"github.com/jackc/pgx/v5"
	"github.com/joho/godotenv"
)

type CopyRequest struct {
	BucketID          string `json:"bucketId"`
	SourceKey         string `json:"sourceKey"`
	DestinationBucket string `json:"destinationBucket"`
	DestinationKey    string `json:"destinationKey"`
}

func main() {
	_ = godotenv.Load()

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgresql://abhishare_app:AbhiShare2026SecurePass!@db.uqubmnnesyvvdeiwjnag.supabase.co:5432/postgres?sslmode=require"
	}

	supabaseURL := os.Getenv("SUPABASE_URL")
	supabaseKey := os.Getenv("SUPABASE_STORAGE_KEY")
	if supabaseURL == "" || supabaseKey == "" {
		log.Fatal("SUPABASE_URL and SUPABASE_STORAGE_KEY must be set in .env")
	}

	conn, err := pgx.Connect(context.Background(), dbURL)
	if err != nil {
		log.Fatalf("Database connection error: %v", err)
	}
	defer conn.Close(context.Background())

	rows, err := conn.Query(context.Background(), `
		SELECT id, driver_selfie_url 
		FROM rides 
		WHERE driver_selfie_url LIKE '%rides/selfies/%';
	`)
	if err != nil {
		log.Fatalf("Failed to query rides: %v", err)
	}
	defer rows.Close()

	client := &http.Client{}

	type RideSelfie struct {
		ID  string
		URL string
	}
	var list []RideSelfie
	for rows.Next() {
		var r RideSelfie
		if err := rows.Scan(&r.ID, &r.URL); err == nil {
			list = append(list, r)
		}
	}

	log.Printf("Found %d rides with selfies to verify/sync to public bucket...", len(list))

	for _, item := range list {
		objectKey := fmt.Sprintf("rides/selfies/%s.jpg", item.ID)
		if bytes.Contains([]byte(item.URL), []byte(".png")) {
			objectKey = fmt.Sprintf("rides/selfies/%s.png", item.ID)
		}

		copyReq := CopyRequest{
			BucketID:          "abhishare-private",
			SourceKey:         objectKey,
			DestinationBucket: "abhishare-public",
			DestinationKey:    objectKey,
		}
		data, _ := json.Marshal(copyReq)

		req, err := http.NewRequest(
			http.MethodPost,
			fmt.Sprintf("%s/storage/v1/object/copy", supabaseURL),
			bytes.NewReader(data),
		)
		if err == nil {
			req.Header.Set("apikey", supabaseKey)
			req.Header.Set("Authorization", "Bearer "+supabaseKey)
			req.Header.Set("Content-Type", "application/json")

			resp, err := client.Do(req)
			if err == nil {
				respBody, _ := io.ReadAll(resp.Body)
				resp.Body.Close()
				if resp.StatusCode == 200 || resp.StatusCode == 201 {
					log.Printf("Copied %s to abhishare-public", objectKey)
				} else {
					log.Printf("Copy response for %s: %d (%s)", objectKey, resp.StatusCode, string(respBody))
				}
			}
		}
	}

	// Update PostgreSQL database URLs to point to public bucket
	tag, err := conn.Exec(context.Background(), `
		UPDATE rides 
		SET driver_selfie_url = REPLACE(driver_selfie_url, 'authenticated/abhishare-private', 'public/abhishare-public')
		WHERE driver_selfie_url LIKE '%authenticated/abhishare-private%';
	`)
	if err != nil {
		log.Fatalf("Failed to update database URLs: %v", err)
	}

	log.Printf("Successfully updated %d ride records to public Supabase URLs in database!", tag.RowsAffected())
}
