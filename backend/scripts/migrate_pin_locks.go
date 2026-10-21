//go:build ignore

package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load("../.env")
	_ = godotenv.Load(".env")

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL must be set in .env")
	}

	conn, err := pgx.Connect(context.Background(), dbURL)
	if err != nil {
		log.Fatalf("failed to connect to db: %v", err)
	}
	defer conn.Close(context.Background())

	// 1. Add pin attempt and lockout columns to users table
	query := `
		ALTER TABLE users 
			ADD COLUMN IF NOT EXISTS pin_hash VARCHAR(255),
			ADD COLUMN IF NOT EXISTS pin_failed_attempts INT DEFAULT 0,
			ADD COLUMN IF NOT EXISTS pin_locked_until TIMESTAMP WITH TIME ZONE,
			ADD COLUMN IF NOT EXISTS pin_account_locked BOOLEAN DEFAULT FALSE;
	`
	_, err = conn.Exec(context.Background(), query)
	if err != nil {
		log.Fatalf("failed to alter users table: %v", err)
	}
	fmt.Println("Successfully added pin_failed_attempts, pin_locked_until, pin_account_locked columns to users table.")

	// 2. Clear any stale blocks in rate_limits table so user isn't stuck on the previous 900s timeout
	res, err := conn.Exec(context.Background(), `DELETE FROM rate_limits WHERE blocked_until IS NOT NULL;`)
	if err != nil {
		fmt.Printf("warning clearing rate limits: %v\n", err)
	} else {
		fmt.Printf("Cleared %d blocked entries in rate_limits table.\n", res.RowsAffected())
	}

	fmt.Println("Migration complete!")
}
