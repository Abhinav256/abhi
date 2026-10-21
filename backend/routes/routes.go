package routes

import (
	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/handlers"
	"github.com/abhishare16/Abhi-Share/backend/middleware"
)

func Register(
	app *fiber.App,
	healthHandler func(*fiber.Ctx) error,
	authHandler *handlers.AuthHandler,
	authMiddleware *middleware.AuthMiddleware,
	rateLimiter *middleware.RateLimiter,
	vehicleHandler *handlers.VehicleHandler,
	rideHandler *handlers.RideHandler,
	rideSearchHandler *handlers.RideSearchHandler,
	bookingHandler *handlers.BookingHandler,
	bookingQueryHandler *handlers.BookingQueryHandler,
	locationHandler *handlers.LocationHandler,
	notificationHandler *handlers.NotificationHandler,
	recurringScheduleHandler *handlers.RecurringScheduleHandler,
	ratingHandler *handlers.RatingHandler,
	walletHandler *handlers.WalletHandler,
	referralHandler *handlers.ReferralHandler,
	paymentHandler *handlers.PaymentHandler,
	chatHandler *handlers.ChatHandler,
) {
	app.Get("/health", healthHandler)
	app.Get("/api/health", healthHandler)

	// ── Public authentication APIs ──────────────────────────────────────

	// OTP generation endpoints: IP rate limit + identifier rate limit
	otpGenIP := rateLimiter.Middleware(middleware.TierOTPGeneration)
	otpGenID := rateLimiter.IdentifierMiddleware(middleware.TierOTPGeneration)

	// OTP verification endpoints: IP rate limit + identifier rate limit
	otpVerifyIP := rateLimiter.Middleware(middleware.TierOTPVerification)
	otpVerifyID := rateLimiter.IdentifierMiddleware(middleware.TierOTPVerification)

	// Auth check endpoints: IP rate limit + identifier rate limit
	authCheckIP := rateLimiter.Middleware(middleware.TierAuthCheck)
	authCheckID := rateLimiter.IdentifierMiddleware(middleware.TierAuthCheck)

	// Account creation: IP rate limit + identifier rate limit
	acctCreateIP := rateLimiter.Middleware(middleware.TierAccountCreation)
	acctCreateID := rateLimiter.IdentifierMiddleware(middleware.TierAccountCreation)

	// PIN login endpoints: IP rate limit + identifier rate limit
	pinLoginIP := rateLimiter.Middleware(middleware.TierPINVerification)
	pinLoginID := rateLimiter.IdentifierMiddleware(middleware.TierPINVerification)

	// New Unified Auth Flow
	app.Post("/auth/unified/send-otp", otpGenIP, otpGenID, authHandler.SendOTPUniversal)
	app.Post("/auth/unified/verify-check", otpVerifyIP, otpVerifyID, authHandler.VerifyOTPAndCheck)
	app.Post("/auth/unified/check-secondary", authCheckIP, authCheckID, authHandler.CheckSecondary)
	app.Post("/auth/unified/complete-signup", acctCreateIP, acctCreateID, authHandler.CompleteSignup)
	app.Post("/auth/login/passcode", pinLoginIP, pinLoginID, authHandler.LoginWithPIN)

	// Legacy auth flow
	app.Post("/auth/start", authCheckIP, authCheckID, authHandler.StartAuth)
	app.Post("/auth/login/send-otp", otpGenIP, otpGenID, authHandler.SendLoginOTP)
	app.Post("/auth/signup/send-otp", otpGenIP, otpGenID, authHandler.StartSignup)
	app.Post("/auth/verify", otpVerifyIP, otpVerifyID, authHandler.VerifyOTP)

	// ── Protected authentication APIs ───────────────────────────────────

	// PIN endpoints: user-scoped rate limiting
	pinVerifyUser := rateLimiter.UserMiddleware(middleware.TierPINVerification)
	generalUser := rateLimiter.UserMiddleware(middleware.TierGeneral)

	app.Get(
		"/auth/me",
		authMiddleware.RequireAuth,
		generalUser,
		authHandler.Me,
	)

	app.Put(
		"/auth/me",
		authMiddleware.RequireAuth,
		generalUser,
		authHandler.UpdateMe,
	)

	app.Post(
		"/auth/logout",
		authMiddleware.RequireAuth,
		generalUser,
		authHandler.Logout,
	)

	// PIN management: strict rate limiting
	app.Post(
		"/auth/pin/set",
		authMiddleware.RequireAuth,
		generalUser,
		authHandler.SetPIN,
	)

	app.Post(
		"/auth/pin/verify",
		authMiddleware.RequireAuth,
		pinVerifyUser,
		authHandler.VerifyPIN,
	)

	app.Post(
		"/auth/pin/change",
		authMiddleware.RequireAuth,
		pinVerifyUser,
		authHandler.ChangePIN,
	)

	// ── Protected vehicle APIs ──────────────────────────────────────────

	app.Post(
		"/vehicles",
		authMiddleware.RequireAuth,
		generalUser,
		vehicleHandler.CreateVehicle,
	)

	app.Get(
		"/vehicles",
		authMiddleware.RequireAuth,
		generalUser,
		vehicleHandler.GetVehicles,
	)

	app.Get(
		"/vehicles/:id",
		authMiddleware.RequireAuth,
		generalUser,
		vehicleHandler.GetVehicle,
	)

	app.Delete(
		"/vehicles/:id",
		authMiddleware.RequireAuth,
		generalUser,
		vehicleHandler.DeleteVehicle,
	)

	app.Post(
		"/upload/vehicle-image",
		authMiddleware.RequireAuth,
		generalUser,
		vehicleHandler.UploadVehicleImage,
	)

	// ── Protected ride APIs ─────────────────────────────────────────────

	app.Post(
		"/rides",
		authMiddleware.RequireAuth,
		generalUser,
		rideHandler.CreateRide,
	)

	// Must be registered BEFORE /rides/:ride_id.
	app.Get(
		"/rides/me",
		authMiddleware.RequireAuth,
		generalUser,
		rideHandler.GetMyRides,
	)

	app.Get(
		"/rides/:ride_id",
		rideHandler.GetRideDetail,
	)

	app.Get(
		"/rides",
		rideSearchHandler.SearchRides,
	)

	app.Post(
		"/rides/:ride_id/complete",
		authMiddleware.RequireAuth,
		generalUser,
		rideHandler.CompleteRide,
	)

	app.Post(
		"/rides/:ride_id/cancel",
		authMiddleware.RequireAuth,
		generalUser,
		rideHandler.CancelRide,
	)

	app.Delete(
		"/rides/:ride_id/draft",
		authMiddleware.RequireAuth,
		generalUser,
		rideHandler.DeleteDraft,
	)

	app.Put(
		"/rides/:ride_id/draft",
		authMiddleware.RequireAuth,
		generalUser,
		rideHandler.UpdateDraft,
	)

	// ── Protected booking APIs ──────────────────────────────────────────

	app.Post(
		"/bookings",
		authMiddleware.RequireAuth,
		generalUser,
		bookingHandler.CreateBooking,
	)

	// Driver can see bookings for their own ride.
	app.Get(
		"/bookings/ride/:ride_id",
		authMiddleware.RequireAuth,
		generalUser,
		bookingQueryHandler.GetBookingsForRide,
	)

	// Authenticated passenger can see their own bookings.
	app.Get(
		"/bookings/me",
		authMiddleware.RequireAuth,
		generalUser,
		bookingQueryHandler.GetBookingsForPassenger,
	)

	// Passenger or ride driver can see an individual booking.
	app.Get(
		"/bookings/:booking_id",
		authMiddleware.RequireAuth,
		generalUser,
		bookingQueryHandler.GetBookingByID,
	)

	// Only the passenger who owns the booking can cancel it.
	app.Post(
		"/bookings/:booking_id/cancel",
		authMiddleware.RequireAuth,
		generalUser,
		bookingHandler.CancelBooking,
	)
	app.Post(
		"/rides/:ride_id/selfie",
		authMiddleware.RequireAuth,
		generalUser,
		rideHandler.UploadDriverSelfie,
	)

	app.Post(
		"/rides/:ride_id/publish",
		authMiddleware.RequireAuth,
		generalUser,
		rideHandler.PublishRide,
	)

	// ── Protected Location APIs ─────────────────────────────────────────

	app.Post(
		"/locations",
		authMiddleware.RequireAuth,
		generalUser,
		locationHandler.CreateLocation,
	)

	app.Get(
		"/locations",
		authMiddleware.RequireAuth,
		generalUser,
		locationHandler.GetLocations,
	)

	// ── Location Autocomplete & Geocoding (Geoapify) ───────────────────
	app.Get("/locations/autocomplete", locationHandler.Autocomplete)
	app.Get("/api/locations/autocomplete", locationHandler.Autocomplete)
	app.Get("/locations/reverse", locationHandler.ReverseGeocode)
	app.Get("/api/locations/reverse", locationHandler.ReverseGeocode)

	// ── Route Calculation & Map Preview (Geoapify) ───────────────────
	app.Get("/locations/routes", locationHandler.CalculateRoutes)
	app.Post("/locations/routes", locationHandler.CalculateRoutes)
	app.Get("/api/locations/routes", locationHandler.CalculateRoutes)
	app.Post("/api/locations/routes", locationHandler.CalculateRoutes)
	app.Get("/locations/route-map", locationHandler.GetRouteMap)
	app.Get("/api/locations/route-map", locationHandler.GetRouteMap)

	// ── Protected Notification APIs ─────────────────────────────────────

	app.Get(
		"/notifications",
		authMiddleware.RequireAuth,
		generalUser,
		notificationHandler.GetNotifications,
	)

	app.Get(
		"/notifications/:id",
		authMiddleware.RequireAuth,
		generalUser,
		notificationHandler.GetNotificationDetail,
	)

	app.Put(
		"/notifications/:id/read",
		authMiddleware.RequireAuth,
		generalUser,
		notificationHandler.MarkRead,
	)

	// Device token management for push notifications
	app.Post(
		"/notifications/device-token",
		authMiddleware.RequireAuth,
		generalUser,
		notificationHandler.RegisterDeviceToken,
	)
	app.Post(
		"/api/notifications/device-token",
		authMiddleware.RequireAuth,
		generalUser,
		notificationHandler.RegisterDeviceToken,
	)

	app.Delete(
		"/notifications/device-token",
		authMiddleware.RequireAuth,
		generalUser,
		notificationHandler.UnregisterDeviceToken,
	)
	app.Delete(
		"/api/notifications/device-token",
		authMiddleware.RequireAuth,
		generalUser,
		notificationHandler.UnregisterDeviceToken,
	)

	app.Post(
		"/notifications/test-push",
		authMiddleware.RequireAuth,
		generalUser,
		notificationHandler.TestPush,
	)
	app.Post(
		"/api/notifications/test-push",
		authMiddleware.RequireAuth,
		generalUser,
		notificationHandler.TestPush,
	)

	// ── Protected Recurring Schedule APIs ───────────────────────────────

	app.Post(
		"/recurring-schedules",
		authMiddleware.RequireAuth,
		generalUser,
		recurringScheduleHandler.CreateRecurringSchedule,
	)

	app.Post(
		"/recurring-schedules/:id/selfie",
		authMiddleware.RequireAuth,
		generalUser,
		recurringScheduleHandler.UploadSelfie,
	)

	app.Post(
		"/recurring-schedules/:id/publish",
		authMiddleware.RequireAuth,
		generalUser,
		recurringScheduleHandler.PublishRecurringSchedule,
	)

	app.Get(
		"/recurring-schedules",
		authMiddleware.RequireAuth,
		generalUser,
		recurringScheduleHandler.GetUserRecurringSchedules,
	)

	app.Get(
		"/recurring-schedules/:id",
		authMiddleware.RequireAuth,
		generalUser,
		recurringScheduleHandler.GetRecurringScheduleDetail,
	)

	app.Put(
		"/recurring-schedules/:id/pause",
		authMiddleware.RequireAuth,
		generalUser,
		recurringScheduleHandler.PauseRecurringSchedule,
	)

	app.Put(
		"/recurring-schedules/:id/resume",
		authMiddleware.RequireAuth,
		generalUser,
		recurringScheduleHandler.ResumeRecurringSchedule,
	)

	app.Put(
		"/recurring-schedules/:id/cancel",
		authMiddleware.RequireAuth,
		generalUser,
		recurringScheduleHandler.CancelRecurringSchedule,
	)

	app.Put(
		"/recurring-schedules/:id",
		authMiddleware.RequireAuth,
		generalUser,
		recurringScheduleHandler.UpdateRecurringSchedule,
	)

	// ── Ratings APIs ────────────────────────────────────────────────────

	app.Post(
		"/ratings",
		authMiddleware.RequireAuth,
		generalUser,
		ratingHandler.SubmitRatings,
	)

	app.Get(
		"/ratings/pending",
		authMiddleware.RequireAuth,
		generalUser,
		ratingHandler.GetPendingRating,
	)

	app.Get(
		"/ratings/rides/:ride_id",
		authMiddleware.RequireAuth,
		generalUser,
		ratingHandler.GetRideRatingParticipants,
	)

	app.Get(
		"/ratings/me",
		authMiddleware.RequireAuth,
		generalUser,
		ratingHandler.GetMyRatingSummary,
	)

	app.Get(
		"/ratings/users/:user_id",
		authMiddleware.RequireAuth,
		generalUser,
		ratingHandler.GetUserRatingSummary,
	)

	// ── Protected Wallet APIs ───────────────────────────────────────────

	app.Get(
		"/wallet",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.GetWalletSummary,
	)

	app.Get(
		"/wallet/transactions",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.GetTransactions,
	)

	app.Get(
		"/wallet/transactions/:id",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.GetTransactionByID,
	)

	app.Post(
		"/wallet/add-money",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.AddMoney,
	)

	app.Post(
		"/wallet/withdraw",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.WithdrawMoney,
	)

	app.Get(
		"/wallet/bank-accounts",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.GetBankAccounts,
	)

	app.Post(
		"/wallet/bank-accounts",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.AddBankAccount,
	)

	app.Delete(
		"/wallet/bank-accounts/:id",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.DeleteBankAccount,
	)

	app.Get(
		"/wallet/upi-ids",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.GetUPIIDs,
	)

	app.Post(
		"/wallet/upi-ids",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.AddUPIID,
	)

	app.Delete(
		"/wallet/upi-ids/:id",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.DeleteUPIID,
	)

	app.Get(
		"/wallet/cards",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.GetCards,
	)

	app.Post(
		"/wallet/cards",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.AddCard,
	)

	app.Delete(
		"/wallet/cards/:id",
		authMiddleware.RequireAuth,
		generalUser,
		walletHandler.DeleteCard,
	)

	// ── Refer & Earn APIs ───────────────────────────────────────────────

	app.Post(
		"/referrals/validate",
		generalUser,
		referralHandler.ValidateCode,
	)
	app.Post(
		"/api/referrals/validate",
		generalUser,
		referralHandler.ValidateCode,
	)

	app.Get(
		"/referrals/summary",
		authMiddleware.RequireAuth,
		generalUser,
		referralHandler.GetSummary,
	)
	app.Get(
		"/api/referrals/summary",
		authMiddleware.RequireAuth,
		generalUser,
		referralHandler.GetSummary,
	)

	// ── Razorpay Payment APIs ───────────────────────────────────────────

	// Public config (Key ID only)
	app.Get("/payments/config", paymentHandler.GetConfig)
	app.Get("/api/payments/config", paymentHandler.GetConfig)

	// Protected order creation & verification
	app.Post(
		"/payments/create-order",
		authMiddleware.RequireAuth,
		generalUser,
		paymentHandler.CreateOrder,
	)
	app.Post(
		"/api/payments/create-order",
		authMiddleware.RequireAuth,
		generalUser,
		paymentHandler.CreateOrder,
	)

	app.Post(
		"/payments/verify",
		authMiddleware.RequireAuth,
		generalUser,
		paymentHandler.VerifyPayment,
	)
	app.Post(
		"/api/payments/verify",
		authMiddleware.RequireAuth,
		generalUser,
		paymentHandler.VerifyPayment,
	)

	app.Post(
		"/payments/cancel",
		authMiddleware.RequireAuth,
		generalUser,
		paymentHandler.CancelOrder,
	)
	app.Post(
		"/api/payments/cancel",
		authMiddleware.RequireAuth,
		generalUser,
		paymentHandler.CancelOrder,
	)

	// Status retrieval
	app.Get(
		"/payments/status/:orderId",
		authMiddleware.RequireAuth,
		generalUser,
		paymentHandler.GetStatus,
	)
	app.Get(
		"/api/payments/status/:orderId",
		authMiddleware.RequireAuth,
		generalUser,
		paymentHandler.GetStatus,
	)

	// Razorpay Webhook endpoint
	app.Post("/payments/webhook", paymentHandler.HandleWebhook)
	app.Post("/api/payments/webhook", paymentHandler.HandleWebhook)

	// ── Protected In-App Chat APIs ──────────────────────────────────────
	app.Post("/chat/conversations/get-or-create", authMiddleware.RequireAuth, generalUser, chatHandler.GetOrCreateConversation)
	app.Post("/api/chat/conversations/get-or-create", authMiddleware.RequireAuth, generalUser, chatHandler.GetOrCreateConversation)

	app.Get("/chat/conversations", authMiddleware.RequireAuth, generalUser, chatHandler.ListConversations)
	app.Get("/api/chat/conversations", authMiddleware.RequireAuth, generalUser, chatHandler.ListConversations)

	app.Get("/chat/conversations/:id", authMiddleware.RequireAuth, generalUser, chatHandler.GetConversation)
	app.Get("/api/chat/conversations/:id", authMiddleware.RequireAuth, generalUser, chatHandler.GetConversation)

	app.Get("/chat/conversations/:id/messages", authMiddleware.RequireAuth, generalUser, chatHandler.GetMessages)
	app.Get("/api/chat/conversations/:id/messages", authMiddleware.RequireAuth, generalUser, chatHandler.GetMessages)

	app.Post("/chat/conversations/:id/messages", authMiddleware.RequireAuth, generalUser, chatHandler.SendMessage)
	app.Post("/api/chat/conversations/:id/messages", authMiddleware.RequireAuth, generalUser, chatHandler.SendMessage)

	app.Post("/chat/conversations/:id/read", authMiddleware.RequireAuth, generalUser, chatHandler.MarkMessagesAsRead)
	app.Post("/api/chat/conversations/:id/read", authMiddleware.RequireAuth, generalUser, chatHandler.MarkMessagesAsRead)

	app.Get("/chat/unread-count", authMiddleware.RequireAuth, generalUser, chatHandler.GetUnreadCount)
	app.Get("/api/chat/unread-count", authMiddleware.RequireAuth, generalUser, chatHandler.GetUnreadCount)

	app.Post("/chat/block", authMiddleware.RequireAuth, generalUser, chatHandler.BlockUser)
	app.Post("/api/chat/block", authMiddleware.RequireAuth, generalUser, chatHandler.BlockUser)

	app.Post("/chat/report", authMiddleware.RequireAuth, generalUser, chatHandler.ReportUser)
	app.Post("/api/chat/report", authMiddleware.RequireAuth, generalUser, chatHandler.ReportUser)

	// ── Direct Phone Calling Contact Info (Confirmed booking participants only) ──
	app.Get("/bookings/:booking_id/contact", authMiddleware.RequireAuth, generalUser, bookingQueryHandler.GetBookingContact)
	app.Get("/api/bookings/:booking_id/contact", authMiddleware.RequireAuth, generalUser, bookingQueryHandler.GetBookingContact)
}

