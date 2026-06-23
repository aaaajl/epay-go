package database

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"time"
	"unicode"

	"github.com/example/epay-go/internal/config"
	_ "github.com/jackc/pgx/v5/stdlib"
)

const (
	prepareMaxAttempts = 60
	prepareRetryDelay  = 2 * time.Second
)

// Prepare waits for PostgreSQL and ensures the target database exists.
func Prepare(ctx context.Context) error {
	cfg := config.Get().Database
	if err := validateDBName(cfg.DBName); err != nil {
		return err
	}

	adminDSN := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=postgres sslmode=%s",
		cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.SSLMode,
	)

	var lastErr error
	for attempt := 1; attempt <= prepareMaxAttempts; attempt++ {
		if ctx.Err() != nil {
			return ctx.Err()
		}

		if err := ensureDatabase(ctx, adminDSN, cfg.DBName); err == nil {
			log.Printf("Database %s is ready", cfg.DBName)
			return nil
		} else {
			lastErr = err
			log.Printf("Waiting for postgres (attempt %d/%d): %v", attempt, prepareMaxAttempts, err)
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(prepareRetryDelay):
		}
	}

	return fmt.Errorf("postgres not ready after %d attempts: %w", prepareMaxAttempts, lastErr)
}

func ensureDatabase(ctx context.Context, adminDSN, dbName string) error {
	db, err := sql.Open("pgx", adminDSN)
	if err != nil {
		return err
	}
	defer db.Close()

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		return err
	}

	var exists bool
	queryCtx, queryCancel := context.WithTimeout(ctx, 5*time.Second)
	defer queryCancel()
	if err := db.QueryRowContext(queryCtx,
		"SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname = $1)", dbName,
	).Scan(&exists); err != nil {
		return err
	}

	if exists {
		return nil
	}

	createCtx, createCancel := context.WithTimeout(ctx, 10*time.Second)
	defer createCancel()
	if _, err := db.ExecContext(createCtx, fmt.Sprintf(`CREATE DATABASE "%s"`, dbName)); err != nil {
		return err
	}

	log.Printf("Created database %s", dbName)
	return nil
}

func validateDBName(name string) error {
	if name == "" {
		return fmt.Errorf("database name is empty")
	}
	for _, r := range name {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_' {
			return fmt.Errorf("invalid database name: %s", name)
		}
	}
	return nil
}
