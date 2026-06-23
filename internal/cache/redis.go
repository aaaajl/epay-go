// internal/cache/redis.go
package cache

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/example/epay-go/internal/config"
	"github.com/redis/go-redis/v9"
)

var RDB *redis.Client

func Init() error {
	cfg := config.Get().Redis

	RDB = redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
		Password: cfg.Password,
		DB:       cfg.DB,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := RDB.Ping(ctx).Err(); err != nil {
		return fmt.Errorf("failed to connect redis: %w", err)
	}

	log.Println("Redis connected successfully")
	return nil
}

// Prepare waits for Redis to become available.
func Prepare(ctx context.Context) error {
	const maxAttempts = 60
	const retryDelay = 2 * time.Second

	var lastErr error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		if ctx.Err() != nil {
			return ctx.Err()
		}

		if err := Init(); err == nil {
			return nil
		} else {
			lastErr = err
			if RDB != nil {
				_ = RDB.Close()
				RDB = nil
			}
			log.Printf("Waiting for redis (attempt %d/%d): %v", attempt, maxAttempts, err)
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(retryDelay):
		}
	}

	return fmt.Errorf("redis not ready after %d attempts: %w", maxAttempts, lastErr)
}

func Get() *redis.Client {
	return RDB
}

func Close() error {
	return RDB.Close()
}
