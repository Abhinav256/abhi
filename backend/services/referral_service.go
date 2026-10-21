package services

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"regexp"
	"strings"
	"time"

	"github.com/abhishare16/Abhi-Share/backend/models"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ReferralService struct {
	DB                  *pgxpool.Pool
	NotificationService *NotificationService
}

func NewReferralService(db *pgxpool.Pool) *ReferralService {
	return &ReferralService{DB: db}
}

// EnsureReferralCode makes sure the user has a unique referral code.
func (s *ReferralService) EnsureReferralCode(ctx context.Context, userID string, fullName string) (string, error) {
	var code *string
	err := s.DB.QueryRow(ctx, `SELECT referral_code FROM users WHERE id = $1`, userID).Scan(&code)
	if err != nil {
		return "", err
	}
	if code != nil && strings.TrimSpace(*code) != "" {
		return *code, nil
	}

	// Generate clean unique code
	cleanName := regexp.MustCompile(`[^a-zA-Z]`).ReplaceAllString(fullName, "")
	if len(cleanName) < 4 {
		cleanName = (cleanName + "USER")[:4]
	} else {
		cleanName = cleanName[:4]
	}
	cleanName = strings.ToUpper(cleanName)

	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	for attempts := 0; attempts < 10; attempts++ {
		candidate := fmt.Sprintf("%s%04d", cleanName, r.Intn(9000)+1000)
		var exists bool
		err = s.DB.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE referral_code = $1)`, candidate).Scan(&exists)
		if err == nil && !exists {
			_, err = s.DB.Exec(ctx, `UPDATE users SET referral_code = $1 WHERE id = $2`, candidate, userID)
			if err == nil {
				return candidate, nil
			}
		}
	}

	// Fallback with timestamp
	fallback := fmt.Sprintf("ABHI%d", time.Now().Unix()%10000)
	_, _ = s.DB.Exec(ctx, `UPDATE users SET referral_code = $1 WHERE id = $2`, fallback, userID)
	return fallback, nil
}

// GetReferralSummary gathers eligibility, stats, usage, and referral history.
func (s *ReferralService) GetReferralSummary(ctx context.Context, userID string) (*models.ReferralSummaryResponse, error) {
	var fullName string
	var existingCode *string
	err := s.DB.QueryRow(ctx, `SELECT full_name, referral_code FROM users WHERE id = $1`, userID).Scan(&fullName, &existingCode)
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}

	referralCode := ""
	if existingCode != nil && strings.TrimSpace(*existingCode) != "" {
		referralCode = *existingCode
	} else {
		referralCode, err = s.EnsureReferralCode(ctx, userID, fullName)
		if err != nil {
			return nil, err
		}
	}

	// 1. Check eligibility: completed at least one published ride as driver
	var completedRidesAsDriver int
	err = s.DB.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM rides
		WHERE driver_id = $1 AND status = 'completed'
	`, userID).Scan(&completedRidesAsDriver)
	if err != nil {
		return nil, err
	}

	isEligible := completedRidesAsDriver >= 1
	eligibilityReason := "You are eligible to refer friends and earn ₹50 per friend!"
	if !isEligible {
		eligibilityReason = "Complete at least 1 published ride as a driver to participate in Refer & Earn."
	}

	// 2. Daily usage in IST (Asia/Kolkata timezone)
	const dailyLimit = 5
	var dailyReferralsUsed int
	err = s.DB.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM referrals
		WHERE referrer_id = $1
		  AND (created_at AT TIME ZONE 'Asia/Kolkata')::date = (NOW() AT TIME ZONE 'Asia/Kolkata')::date
	`, userID).Scan(&dailyReferralsUsed)
	if err != nil {
		return nil, err
	}

	dailyRemaining := dailyLimit - dailyReferralsUsed
	if dailyRemaining < 0 {
		dailyRemaining = 0
	}

	// 3. Total stats
	var totalSuccessfulReferrals int
	var totalRewardsEarned float64
	err = s.DB.QueryRow(ctx, `
		SELECT COUNT(*), COALESCE(SUM(reward_amount), 0)
		FROM referrals
		WHERE referrer_id = $1 AND status = 'reward_credited'
	`, userID).Scan(&totalSuccessfulReferrals, &totalRewardsEarned)
	if err != nil {
		return nil, err
	}

	// 4. Referral list
	rows, err := s.DB.Query(ctx, `
		SELECT r.id, r.referee_id, u.full_name, u.phone, r.status, r.reward_amount,
		       r.referrer_ride_completed, r.referee_ride_completed, r.reward_credited_at, r.created_at
		FROM referrals r
		JOIN users u ON u.id = r.referee_id
		WHERE r.referrer_id = $1
		ORDER BY r.created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []models.ReferralItem
	for rows.Next() {
		var item models.ReferralItem
		var rawPhone string
		err = rows.Scan(
			&item.ID,
			&item.RefereeID,
			&item.RefereeName,
			&rawPhone,
			&item.Status,
			&item.RewardAmount,
			&item.ReferrerRideCompleted,
			&item.RefereeRideCompleted,
			&item.RewardCreditedAt,
			&item.CreatedAt,
		)
		if err != nil {
			return nil, err
		}

		item.RefereePhone = maskPhoneNumber(rawPhone)
		switch item.Status {
		case "registered":
			item.StatusDisplay = "Registered"
		case "ride_pending":
			item.StatusDisplay = "Ride Pending"
		case "eligible":
			item.StatusDisplay = "Eligible"
		case "reward_credited":
			item.StatusDisplay = "Reward Credited"
		default:
			item.StatusDisplay = strings.Title(item.Status)
		}

		items = append(items, item)
	}

	if items == nil {
		items = []models.ReferralItem{}
	}

	referralLink := fmt.Sprintf("https://abhishare.com/refer?code=%s", referralCode)

	return &models.ReferralSummaryResponse{
		ReferralCode:             referralCode,
		ReferralLink:             referralLink,
		IsEligible:               isEligible,
		CompletedRidesAsDriver:   completedRidesAsDriver,
		EligibilityReason:        eligibilityReason,
		DailyReferralsUsed:       dailyReferralsUsed,
		DailyReferralsLimit:      dailyLimit,
		DailyReferralsRemaining:  dailyRemaining,
		TotalSuccessfulReferrals: totalSuccessfulReferrals,
		TotalRewardsEarned:       totalRewardsEarned,
		Referrals:                items,
	}, nil
}

// ValidateReferralCode checks whether a given referral code is valid, active, eligible, and within daily limit.
func (s *ReferralService) ValidateReferralCode(ctx context.Context, code string) (*models.ValidateReferralCodeResponse, error) {
	trimmed := strings.ToUpper(strings.TrimSpace(code))
	if trimmed == "" {
		return &models.ValidateReferralCodeResponse{
			Valid:   false,
			Message: "Referral code cannot be empty.",
		}, nil
	}

	var referrerID string
	var referrerName string
	err := s.DB.QueryRow(ctx, `
		SELECT id, full_name
		FROM users
		WHERE UPPER(referral_code) = $1
	`, trimmed).Scan(&referrerID, &referrerName)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return &models.ValidateReferralCodeResponse{
				Valid:   false,
				Message: "Invalid referral code. Please check and try again.",
			}, nil
		}
		return nil, err
	}

	// Check referrer eligibility
	var completedRides int
	err = s.DB.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM rides
		WHERE driver_id = $1 AND status = 'completed'
	`, referrerID).Scan(&completedRides)
	if err != nil {
		return nil, err
	}

	if completedRides < 1 {
		return &models.ValidateReferralCodeResponse{
			Valid:   false,
			Message: fmt.Sprintf("%s is not yet eligible to refer friends (needs at least 1 completed ride as driver).", referrerName),
		}, nil
	}

	// Check daily limit (5 per calendar day in IST)
	var dailyCount int
	err = s.DB.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM referrals
		WHERE referrer_id = $1
		  AND (created_at AT TIME ZONE 'Asia/Kolkata')::date = (NOW() AT TIME ZONE 'Asia/Kolkata')::date
	`, referrerID).Scan(&dailyCount)
	if err != nil {
		return nil, err
	}

	if dailyCount >= 5 {
		return &models.ValidateReferralCodeResponse{
			Valid:   false,
			Message: fmt.Sprintf("%s has already reached the maximum limit of 5 referrals for today.", referrerName),
		}, nil
	}

	return &models.ValidateReferralCodeResponse{
		Valid:        true,
		ReferrerName: referrerName,
		Message:      fmt.Sprintf("Referral code valid! Invited by %s. Complete your first ride as driver to get rewarded.", referrerName),
	}, nil
}

// ProcessReferralOnSignup handles referral linking inside the signup transaction.
func (s *ReferralService) ProcessReferralOnSignup(ctx context.Context, tx pgx.Tx, refereeID string, rawCode string) error {
	trimmed := strings.ToUpper(strings.TrimSpace(rawCode))
	if trimmed == "" {
		return nil
	}

	var referrerID string
	var referrerName string
	err := tx.QueryRow(ctx, `
		SELECT id, full_name
		FROM users
		WHERE UPPER(referral_code) = $1
		FOR UPDATE
	`, trimmed).Scan(&referrerID, &referrerName)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return errors.New("invalid referral code")
		}
		return err
	}

	if referrerID == refereeID {
		return errors.New("cannot refer yourself")
	}

	// Check referrer eligibility: must have completed at least 1 ride as driver
	var completedRides int
	err = tx.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM rides
		WHERE driver_id = $1 AND status = 'completed'
	`, referrerID).Scan(&completedRides)
	if err != nil {
		return err
	}

	if completedRides < 1 {
		return errors.New("referrer is not yet eligible to invite friends (requires at least 1 completed ride as driver)")
	}

	// Check daily referral limit (5 per day in IST)
	var dailyCount int
	err = tx.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM referrals
		WHERE referrer_id = $1
		  AND (created_at AT TIME ZONE 'Asia/Kolkata')::date = (NOW() AT TIME ZONE 'Asia/Kolkata')::date
	`, referrerID).Scan(&dailyCount)
	if err != nil {
		return err
	}

	if dailyCount >= 5 {
		return errors.New("referrer has reached the daily limit of 5 referrals for today")
	}

	// Check if referee was already referred
	var alreadyReferred bool
	err = tx.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM referrals WHERE referee_id = $1)
	`, refereeID).Scan(&alreadyReferred)
	if err != nil {
		return err
	}
	if alreadyReferred {
		return errors.New("this account has already been registered with a referral")
	}

	// Link user to referrer
	_, err = tx.Exec(ctx, `
		UPDATE users
		SET referred_by_id = $1, referred_by_code = $2
		WHERE id = $3
	`, referrerID, trimmed, refereeID)
	if err != nil {
		return err
	}

	// Insert referral record
	_, err = tx.Exec(ctx, `
		INSERT INTO referrals (
			referrer_id,
			referee_id,
			referral_code,
			status,
			reward_amount,
			referrer_ride_completed,
			referee_ride_completed
		)
		VALUES ($1, $2, $3, 'registered', 50.00, true, false)
	`, referrerID, refereeID, trimmed)
	if err != nil {
		return err
	}

	return nil
}

// HandleRidePublished updates any pending referral for the driver from 'registered' to 'ride_pending'.
func (s *ReferralService) HandleRidePublished(ctx context.Context, driverID string) error {
	_, err := s.DB.Exec(ctx, `
		UPDATE referrals
		SET status = 'ride_pending', updated_at = NOW()
		WHERE referee_id = $1 AND status = 'registered'
	`, driverID)
	return err
}

// HandleRideCompleted evaluates and credits referral rewards when a ride is completed.
// This handles:
// 1. If driver is a referee: referee has now completed their ride. If referrer already has completed ride, credit ₹50 to referrer!
// 2. If driver is a referrer: referrer has now completed their ride. If any referees had already completed rides and were waiting, credit ₹50!
func (s *ReferralService) HandleRideCompleted(ctx context.Context, tx pgx.Tx, driverID string) error {
	// 1. Is driver a referee with pending referral?
	var referralID string
	var referrerID string
	var refStatus string
	err := tx.QueryRow(ctx, `
		SELECT id, referrer_id, status
		FROM referrals
		WHERE referee_id = $1 AND status != 'reward_credited'
		FOR UPDATE
	`, driverID).Scan(&referralID, &referrerID, &refStatus)

	if err == nil {
		// Mark referee_ride_completed = true
		_, err = tx.Exec(ctx, `
			UPDATE referrals
			SET referee_ride_completed = true, updated_at = NOW()
			WHERE id = $1
		`, referralID)
		if err != nil {
			return err
		}

		// Check if referrer has completed at least 1 ride as driver
		var referrerRides int
		err = tx.QueryRow(ctx, `
			SELECT COUNT(*)
			FROM rides
			WHERE driver_id = $1 AND status = 'completed'
		`, referrerID).Scan(&referrerRides)
		if err != nil {
			return err
		}

		if referrerRides >= 1 {
			// Both users have completed rides! Credit ₹50 to referrer.
			var refereeName string
			_ = tx.QueryRow(ctx, `SELECT full_name FROM users WHERE id = $1`, driverID).Scan(&refereeName)
			if refereeName == "" {
				refereeName = "Referred Friend"
			}

			err = s.creditReferralReward(ctx, tx, referralID, referrerID, refereeName)
			if err != nil {
				return err
			}
		} else {
			// Referrer hasn't completed a ride yet; mark status as 'eligible'
			_, err = tx.Exec(ctx, `
				UPDATE referrals
				SET status = 'eligible', updated_at = NOW()
				WHERE id = $1
			`, referralID)
			if err != nil {
				return err
			}
		}
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	// 2. Is driver a referrer with waiting referrals in 'eligible' status?
	rows, err := tx.Query(ctx, `
		SELECT r.id, r.referee_id, u.full_name
		FROM referrals r
		JOIN users u ON u.id = r.referee_id
		WHERE r.referrer_id = $1
		  AND r.status = 'eligible'
		  AND r.referee_ride_completed = true
		FOR UPDATE
	`, driverID)
	if err != nil {
		return err
	}
	defer rows.Close()

	type pendingReward struct {
		id          string
		refereeName string
	}
	var pendingList []pendingReward
	for rows.Next() {
		var pr pendingReward
		var refereeID string
		if err := rows.Scan(&pr.id, &refereeID, &pr.refereeName); err == nil {
			pendingList = append(pendingList, pr)
		}
	}
	rows.Close()

	for _, pr := range pendingList {
		err = s.creditReferralReward(ctx, tx, pr.id, driverID, pr.refereeName)
		if err != nil {
			return err
		}
	}

	return nil
}

// creditReferralReward atomically credits ₹50 to referrer's wallet and records transaction.
func (s *ReferralService) creditReferralReward(ctx context.Context, tx pgx.Tx, referralID string, referrerID string, refereeName string) error {
	const rewardAmount = 50.00
	refTxnID := fmt.Sprintf("REF-REWARD-%s", referralID)

	// Ensure referrer has a wallet entry and lock it
	var walletID string
	var balance float64
	err := tx.QueryRow(ctx, `
		SELECT id, balance
		FROM wallets
		WHERE user_id = $1
		FOR UPDATE
	`, referrerID).Scan(&walletID, &balance)

	if errors.Is(err, pgx.ErrNoRows) {
		// Create wallet if it doesn't exist
		err = tx.QueryRow(ctx, `
			INSERT INTO wallets (user_id, balance)
			VALUES ($1, 0.00)
			ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW()
			RETURNING id, balance
		`, referrerID).Scan(&walletID, &balance)
		if err != nil {
			return fmt.Errorf("failed to create wallet for referrer: %w", err)
		}
	} else if err != nil {
		return fmt.Errorf("failed to lock referrer wallet: %w", err)
	}

	openingBalance := balance
	closingBalance := balance + rewardAmount

	// Credit wallet
	_, err = tx.Exec(ctx, `
		UPDATE wallets
		SET balance = balance + $1, updated_at = NOW()
		WHERE id = $2
	`, rewardAmount, walletID)
	if err != nil {
		return fmt.Errorf("failed to update wallet balance: %w", err)
	}

	// Insert wallet transaction
	var txnID string
	err = tx.QueryRow(ctx, `
		INSERT INTO wallet_transactions (
			wallet_id,
			user_id,
			reference_id,
			type,
			status,
			amount,
			opening_balance,
			closing_balance,
			title,
			subtitle,
			category,
			payment_method,
			payment_method_type
		)
		VALUES ($1, $2, $3, 'referral_reward', 'completed', $4, $5, $6, $7, $8, 'referral', 'AbhiShare Referral', 'referral')
		RETURNING id
	`,
		walletID,
		referrerID,
		refTxnID,
		rewardAmount,
		openingBalance,
		closingBalance,
		"Referral Reward",
		fmt.Sprintf("₹50 reward earned for referring %s", refereeName),
	).Scan(&txnID)
	if err != nil {
		return fmt.Errorf("failed to record referral wallet transaction: %w", err)
	}

	// Update referral record
	_, err = tx.Exec(ctx, `
		UPDATE referrals
		SET status = 'reward_credited',
		    referrer_ride_completed = true,
		    referee_ride_completed = true,
		    reward_credited_at = NOW(),
		    reward_transaction_id = $1,
		    updated_at = NOW()
		WHERE id = $2
	`, txnID, referralID)
	if err != nil {
		return fmt.Errorf("failed to update referral status: %w", err)
	}

	// Send notification to referrer
	bonusMsg := fmt.Sprintf("Congratulations! ₹50 has been credited to your AbhiShare Wallet for referring %s.", refereeName)
	_, _ = tx.Exec(ctx, `
		INSERT INTO notifications (user_id, type, title, message)
		VALUES ($1, 'referral_reward', 'Referral Bonus Received! 🎉', $2)
	`, referrerID, bonusMsg)

	if s.NotificationService != nil {
		s.NotificationService.SendPush(ctx, referrerID, "referral_reward", "Referral Bonus Received! 🎉", bonusMsg, map[string]string{
			"referral_id": referralID,
		})
	}

	return nil
}

func maskPhoneNumber(phone string) string {
	cleaned := strings.TrimSpace(phone)
	if len(cleaned) <= 4 {
		return cleaned
	}
	last4 := cleaned[len(cleaned)-4:]
	if strings.HasPrefix(cleaned, "+91") && len(cleaned) >= 10 {
		return fmt.Sprintf("+91 ••••• ••%s", last4[2:])
	}
	return fmt.Sprintf("•••• ••• %s", last4)
}
