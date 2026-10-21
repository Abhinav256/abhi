package main

import (
	"context"
	"log"
	"os"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"

	"github.com/abhishare16/Abhi-Share/backend/config"
	"github.com/abhishare16/Abhi-Share/backend/database"
	"github.com/abhishare16/Abhi-Share/backend/handlers"
	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/routes"
	"github.com/abhishare16/Abhi-Share/backend/services"
	"github.com/abhishare16/Abhi-Share/backend/storage"
)

func main() {
	cfg := config.Load()

	conn, err := database.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}

	defer conn.Close()

	log.Printf("Connected to PostgreSQL [Env: %s]", cfg.AppEnv)

	app := fiber.New()

	corsConfig := cors.Config{
		AllowMethods: "GET,POST,PUT,DELETE,PATCH,HEAD,OPTIONS",
		AllowHeaders: "Origin,Content-Type,Accept,Authorization,X-Requested-With,client-message-id",
	}

	if cfg.AppEnv == "production" {
		origins := []string{
			"https://abhishare.netlify.app",
			"https://abhishare.onrender.com",
			"https://abhishare-api.onrender.com",
		}
		if cfg.AllowedOrigins != "" {
			for _, o := range strings.Split(cfg.AllowedOrigins, ",") {
				trimmed := strings.TrimSpace(o)
				if trimmed != "" {
					origins = append(origins, trimmed)
				}
			}
		}
		corsConfig.AllowOrigins = strings.Join(origins, ", ")
	} else {
		devOrigins := []string{
			"http://localhost:5173",
			"http://localhost:5174",
			"http://localhost:3000",
			"http://127.0.0.1:5173",
			"http://127.0.0.1:5174",
			"http://127.0.0.1:3000",
			"http://127.0.0.1:8080",
			"http://localhost:8080",
			"https://abhishare.netlify.app",
		}
		if cfg.AllowedOrigins != "" {
			for _, o := range strings.Split(cfg.AllowedOrigins, ",") {
				trimmed := strings.TrimSpace(o)
				if trimmed != "" {
					devOrigins = append(devOrigins, trimmed)
				}
			}
		}
		corsConfig.AllowOrigins = strings.Join(devOrigins, ", ")
	}

	app.Use(cors.New(corsConfig))

	// Ensure upload directories exist.
	os.MkdirAll("./uploads/vehicles/photos", 0755)
	os.MkdirAll("./uploads/vehicles/rc", 0755)
	os.MkdirAll("./uploads/rides/selfies", 0755)

	app.Static(
		"/uploads",
		"./uploads",
	)

	// Services

	emailService, err := services.NewEmailService(
		cfg.SMTPHost,
		cfg.SMTPPort,
		cfg.SMTPUsername,
		cfg.SMTPPassword,
		cfg.SMTPFrom,
	)
	if err != nil {
		log.Fatalf("failed to initialize email service: %v", err)
	}

	authService := services.NewAuthService(
		conn,
		emailService,
	)

	authMiddleware := middleware.NewAuthMiddleware(conn)

	// Rate limiter (database-backed)
	rateLimiter := middleware.NewRateLimiter(conn)

	// Background cleanup of expired rate limit entries
	go func() {
		ticker := time.NewTicker(30 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			if err := rateLimiter.CleanupExpired(context.Background()); err != nil {
				log.Printf("[RateLimiter] cleanup error: %v", err)
			}
		}
	}()

	routeService := services.NewRouteService(cfg.GeoapifyAPIKeys...)

	vehicleService := services.NewVehicleService(conn)

	rideService := services.NewRideService(conn, cfg)
	rideService.RouteService = routeService

	rideSearchService := services.NewRideSearchService(conn, cfg)

	bookingService := services.NewBookingService(conn, cfg)

	bookingQueryService := services.NewBookingQueryService(conn)

	// Handlers

	authHandler := handlers.NewAuthHandler(
		authService,
	)

	storageProvider, err := storage.NewProvider(&storage.Config{
		Provider:      cfg.StorageProvider,
		LocalBaseDir:  "./uploads",
		SupabaseURL:   cfg.SupabaseURL,
		SupabaseKey:   cfg.SupabaseStorageKey,
		BucketPublic:  cfg.SupabaseBucketPublic,
		BucketPrivate: cfg.SupabaseBucketPrivate,
	})
	if err != nil {
		log.Fatalf("failed to initialize storage provider: %v", err)
	}

	vehicleHandler := handlers.NewVehicleHandler(
		vehicleService,
		storageProvider,
	)

	rideHandler := handlers.NewRideHandler(
		rideService,
		storageProvider,
	)

	rideSearchHandler := handlers.NewRideSearchHandler(
		rideSearchService,
	)

	bookingHandler := handlers.NewBookingHandler(
		bookingService,
	)

	bookingQueryHandler := handlers.NewBookingQueryHandler(
		bookingQueryService,
	)

	locationService := services.NewLocationService(conn)
	locationHandler := handlers.NewLocationHandler(locationService, routeService, cfg.GeoapifyAPIKeys...)

	pushService := services.NewPushService(conn)
	pushService.StartBackgroundWorker(context.Background())

	notificationService := services.NewNotificationService(conn, pushService)
	notificationHandler := handlers.NewNotificationHandler(notificationService)

	recurringScheduleService := services.NewRecurringScheduleService(conn, notificationService, cfg)
	recurringScheduleHandler := handlers.NewRecurringScheduleHandler(recurringScheduleService, storageProvider)

	ratingService := services.NewRatingService(conn)
	ratingHandler := handlers.NewRatingHandler(ratingService)

	walletService := services.NewWalletService(conn)
	walletHandler := handlers.NewWalletHandler(walletService)

	referralService := services.NewReferralService(conn)
	referralHandler := handlers.NewReferralHandler(referralService)
	authService.ReferralService = referralService
	referralService.NotificationService = notificationService
	rideService.ReferralService = referralService
	rideService.WalletService = walletService
	rideService.NotificationService = notificationService
	recurringScheduleService.WalletService = walletService
	bookingService.WalletService = walletService
	bookingService.NotificationService = notificationService

	paymentService := services.NewPaymentService(conn, cfg, bookingService, walletService)
	paymentHandler := handlers.NewPaymentHandler(paymentService, cfg)

	chatService := services.NewChatService(conn, notificationService)
	chatHandler := handlers.NewChatHandler(chatService)

	// Scheduled database cleanup of expired completed ride conversations (7-day retention)
	go func() {
		// Run initial cleanup on startup
		if count, err := chatService.CleanupExpiredConversations(context.Background()); err != nil {
			log.Printf("[ChatRetention] initial cleanup error: %v", err)
		} else if count > 0 {
			log.Printf("[ChatRetention] initial cleanup purged %d expired conversations", count)
		}

		ticker := time.NewTicker(1 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			if count, err := chatService.CleanupExpiredConversations(context.Background()); err != nil {
				log.Printf("[ChatRetention] periodic cleanup error: %v", err)
			} else if count > 0 {
				log.Printf("[ChatRetention] periodic cleanup purged %d expired conversations", count)
			}
		}
	}()

	healthHandler := handlers.NewHealthHandler(cfg, conn)

	// Routes

	routes.Register(
		app,
		healthHandler.Check,
		authHandler,
		authMiddleware,
		rateLimiter,
		vehicleHandler,
		rideHandler,
		rideSearchHandler,
		bookingHandler,
		bookingQueryHandler,
		locationHandler,
		notificationHandler,
		recurringScheduleHandler,
		ratingHandler,
		walletHandler,
		referralHandler,
		paymentHandler,
		chatHandler,
	)

	log.Printf(
		"AbhiShare API running on %s",
		cfg.Port,
	)

	log.Fatal(
		app.Listen(cfg.Port),
	)
}
