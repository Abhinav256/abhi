package database

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

func Connect(databaseURL string) (*pgxpool.Pool, error) {
	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, err
	}

	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		return nil, err
	}

	if err := pool.Ping(context.Background()); err != nil {
		pool.Close()
		return nil, err
	}

	// Auto-migrate users table to ensure pin columns exist
	_, _ = pool.Exec(
		context.Background(),
		`ALTER TABLE users 
			ADD COLUMN IF NOT EXISTS pin_hash VARCHAR(255),
			ADD COLUMN IF NOT EXISTS pin_failed_attempts INT DEFAULT 0,
			ADD COLUMN IF NOT EXISTS pin_locked_until TIMESTAMP WITH TIME ZONE,
			ADD COLUMN IF NOT EXISTS pin_account_locked BOOLEAN DEFAULT FALSE;`,
	)

	// Auto-migrate user_device_tokens table for push notifications
	_, _ = pool.Exec(
		context.Background(),
		`CREATE TABLE IF NOT EXISTS user_device_tokens (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			device_token TEXT NOT NULL,
			platform VARCHAR(20) NOT NULL DEFAULT 'android',
			created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
			CONSTRAINT uq_user_device UNIQUE (user_id, device_token)
		);
		CREATE INDEX IF NOT EXISTS idx_user_device_tokens_user ON user_device_tokens(user_id);

		ALTER TABLE notifications ADD COLUMN IF NOT EXISTS push_sent BOOLEAN DEFAULT FALSE;
		CREATE INDEX IF NOT EXISTS idx_notifications_push_sent ON notifications(push_sent) WHERE push_sent = FALSE;`,
	)

	return pool, nil
}
