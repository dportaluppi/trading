package main

import (
	"context"
	"github.com/dportaluppi/trading/internal/feed"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// This is a placeholder for the main function.
	// Create channel to listen for signals
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	// Start background task
	go func() {
		for {
			if err := feed.Start(ctx); err != nil {
				log.Printf("Error in background task: %v", err)
				time.Sleep(time.Second * 5) // Wait before retry
				continue
			}
		}
	}()

	// Wait for termination signal
	<-stop
	log.Println("Shutting down gracefully...")
}
