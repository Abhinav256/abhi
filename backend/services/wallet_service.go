package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/abhishare16/Abhi-Share/backend/models"
)

type WalletService struct {
	DB *pgxpool.Pool
}

func NewWalletService(db *pgxpool.Pool) *WalletService {
	return &WalletService{DB: db}
}

// GetOrCreateWallet ensures the user has a wallet entry and returns it.
func (s *WalletService) GetOrCreateWallet(ctx context.Context, userID string) (*models.Wallet, error) {
	var w models.Wallet

	err := s.DB.QueryRow(
		ctx,
		`SELECT id, user_id, balance, currency, is_locked, created_at, updated_at
		 FROM wallets
		 WHERE user_id = $1`,
		userID,
	).Scan(&w.ID, &w.UserID, &w.Balance, &w.Currency, &w.IsLocked, &w.CreatedAt, &w.UpdatedAt)

	if err == nil {
		return &w, nil
	}

	if errors.Is(err, pgx.ErrNoRows) {
		// Create wallet for user, pulling initial balance from money_earned if set
		err = s.DB.QueryRow(
			ctx,
			`INSERT INTO wallets (user_id, balance)
			 VALUES ($1, COALESCE((SELECT money_earned FROM users WHERE id = $1), 0))
			 ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW()
			 RETURNING id, user_id, balance, currency, is_locked, created_at, updated_at`,
			userID,
		).Scan(&w.ID, &w.UserID, &w.Balance, &w.Currency, &w.IsLocked, &w.CreatedAt, &w.UpdatedAt)
		if err != nil {
			return nil, err
		}
		return &w, nil
	}

	return nil, err
}

// GetWalletSummary returns the wallet, recent 5 transactions, and saved payment methods.
func (s *WalletService) GetWalletSummary(ctx context.Context, userID string) (*models.WalletSummaryResponse, error) {
	wallet, err := s.GetOrCreateWallet(ctx, userID)
	if err != nil {
		return nil, err
	}

	recentTxns, _, err := s.GetTransactions(ctx, userID, "", 5, 0)
	if err != nil {
		return nil, err
	}

	bankAccounts, err := s.GetBankAccounts(ctx, userID)
	if err != nil {
		return nil, err
	}

	upiIDs, err := s.GetUPIIDs(ctx, userID)
	if err != nil {
		return nil, err
	}

	cards, err := s.GetCards(ctx, userID)
	if err != nil {
		return nil, err
	}

	return &models.WalletSummaryResponse{
		Wallet:             *wallet,
		RecentTransactions: recentTxns,
		SavedBankAccounts:  bankAccounts,
		SavedUPIIDs:        upiIDs,
		SavedCards:         cards,
	}, nil
}

// GetTransactions returns paginated transactions for a user, optionally filtered by type.
func (s *WalletService) GetTransactions(ctx context.Context, userID string, txnType string, limit, offset int) ([]models.WalletTransaction, int, error) {
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	if offset < 0 {
		offset = 0
	}

	var totalCount int
	var countQuery string
	var countArgs []interface{}

	if txnType != "" {
		countQuery = `SELECT COUNT(*) FROM wallet_transactions WHERE user_id = $1 AND type = $2`
		countArgs = []interface{}{userID, txnType}
	} else {
		countQuery = `SELECT COUNT(*) FROM wallet_transactions WHERE user_id = $1`
		countArgs = []interface{}{userID}
	}

	if err := s.DB.QueryRow(ctx, countQuery, countArgs...).Scan(&totalCount); err != nil {
		return nil, 0, err
	}

	var query string
	var args []interface{}

	if txnType != "" {
		query = `SELECT id, wallet_id, user_id, reference_id, type, status, amount,
		                opening_balance, closing_balance, title, subtitle, category,
		                payment_method, payment_method_type, destination_info, failure_reason,
		                metadata, created_at, updated_at
		         FROM wallet_transactions
		         WHERE user_id = $1 AND type = $2
		         ORDER BY created_at DESC
		         LIMIT $3 OFFSET $4`
		args = []interface{}{userID, txnType, limit, offset}
	} else {
		query = `SELECT id, wallet_id, user_id, reference_id, type, status, amount,
		                opening_balance, closing_balance, title, subtitle, category,
		                payment_method, payment_method_type, destination_info, failure_reason,
		                metadata, created_at, updated_at
		         FROM wallet_transactions
		         WHERE user_id = $1
		         ORDER BY created_at DESC
		         LIMIT $2 OFFSET $3`
		args = []interface{}{userID, limit, offset}
	}

	rows, err := s.DB.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var txns []models.WalletTransaction
	for rows.Next() {
		var t models.WalletTransaction
		err := rows.Scan(
			&t.ID, &t.WalletID, &t.UserID, &t.ReferenceID, &t.Type, &t.Status, &t.Amount,
			&t.OpeningBalance, &t.ClosingBalance, &t.Title, &t.Subtitle, &t.Category,
			&t.PaymentMethod, &t.PaymentMethodType, &t.DestinationInfo, &t.FailureReason,
			&t.Metadata, &t.CreatedAt, &t.UpdatedAt,
		)
		if err != nil {
			return nil, 0, err
		}
		txns = append(txns, t)
	}

	if txns == nil {
		txns = []models.WalletTransaction{}
	}

	return txns, totalCount, nil
}

// GetTransactionByID gets a single transaction.
func (s *WalletService) GetTransactionByID(ctx context.Context, userID, txnID string) (*models.WalletTransaction, error) {
	var t models.WalletTransaction
	err := s.DB.QueryRow(
		ctx,
		`SELECT id, wallet_id, user_id, reference_id, type, status, amount,
		        opening_balance, closing_balance, title, subtitle, category,
		        payment_method, payment_method_type, destination_info, failure_reason,
		        metadata, created_at, updated_at
		 FROM wallet_transactions
		 WHERE id = $1 AND user_id = $2`,
		txnID, userID,
	).Scan(
		&t.ID, &t.WalletID, &t.UserID, &t.ReferenceID, &t.Type, &t.Status, &t.Amount,
		&t.OpeningBalance, &t.ClosingBalance, &t.Title, &t.Subtitle, &t.Category,
		&t.PaymentMethod, &t.PaymentMethodType, &t.DestinationInfo, &t.FailureReason,
		&t.Metadata, &t.CreatedAt, &t.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

// AddMoney adds funds to the user's wallet with ACID transaction semantics.
func (s *WalletService) AddMoney(ctx context.Context, userID string, req models.AddMoneyRequest) (*models.WalletTransaction, error) {
	if req.Amount <= 0 {
		return nil, errors.New("amount must be greater than zero")
	}

	// Ensure wallet exists
	_, err := s.GetOrCreateWallet(ctx, userID)
	if err != nil {
		return nil, err
	}

	status := req.Status
	if status == "" {
		status = "completed"
	}

	refID := req.ReferenceID
	if refID == "" {
		refID = fmt.Sprintf("TXN-%d", time.Now().UnixNano()/1e6)
	}

	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Lock wallet row for update
	var walletID string
	var currentBalance float64
	var isLocked bool
	err = tx.QueryRow(
		ctx,
		`SELECT id, balance, is_locked FROM wallets WHERE user_id = $1 FOR UPDATE`,
		userID,
	).Scan(&walletID, &currentBalance, &isLocked)
	if err != nil {
		return nil, err
	}

	if isLocked {
		return nil, errors.New("wallet is temporarily locked")
	}

	openingBalance := currentBalance
	closingBalance := currentBalance

	if status == "completed" {
		closingBalance = currentBalance + req.Amount
		_, err = tx.Exec(
			ctx,
			`UPDATE wallets SET balance = $1, updated_at = NOW() WHERE id = $2`,
			closingBalance, walletID,
		)
		if err != nil {
			return nil, err
		}
	}

	title := "Money Added"
	subtitle := fmt.Sprintf("Via %s", req.PaymentMethod)
	category := "Top-up"

	var failureReason *string
	if req.FailureReason != "" {
		failureReason = &req.FailureReason
	}

	var txn models.WalletTransaction
	err = tx.QueryRow(
		ctx,
		`INSERT INTO wallet_transactions (
			wallet_id, user_id, reference_id, type, status, amount,
			opening_balance, closing_balance, title, subtitle, category,
			payment_method, payment_method_type, failure_reason
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
		RETURNING id, wallet_id, user_id, reference_id, type, status, amount,
		          opening_balance, closing_balance, title, subtitle, category,
		          payment_method, payment_method_type, destination_info, failure_reason,
		          metadata, created_at, updated_at`,
		walletID, userID, refID, "money_added", status, req.Amount,
		openingBalance, closingBalance, title, subtitle, category,
		req.PaymentMethod, req.PaymentMethodType, failureReason,
	).Scan(
		&txn.ID, &txn.WalletID, &txn.UserID, &txn.ReferenceID, &txn.Type, &txn.Status, &txn.Amount,
		&txn.OpeningBalance, &txn.ClosingBalance, &txn.Title, &txn.Subtitle, &txn.Category,
		&txn.PaymentMethod, &txn.PaymentMethodType, &txn.DestinationInfo, &txn.FailureReason,
		&txn.Metadata, &txn.CreatedAt, &txn.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return &txn, nil
}

// WithdrawMoney handles withdrawal of funds from the wallet.
func (s *WalletService) WithdrawMoney(ctx context.Context, userID string, req models.WithdrawMoneyRequest) (*models.WalletTransaction, error) {
	if req.Amount <= 0 {
		return nil, errors.New("amount must be greater than zero")
	}

	// Ensure wallet exists
	_, err := s.GetOrCreateWallet(ctx, userID)
	if err != nil {
		return nil, err
	}

	status := req.Status
	if status == "" {
		status = "completed"
	}

	refID := req.ReferenceID
	if refID == "" {
		refID = fmt.Sprintf("WTH-%d", time.Now().UnixNano()/1e6)
	}

	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var walletID string
	var currentBalance float64
	var isLocked bool
	err = tx.QueryRow(
		ctx,
		`SELECT id, balance, is_locked FROM wallets WHERE user_id = $1 FOR UPDATE`,
		userID,
	).Scan(&walletID, &currentBalance, &isLocked)
	if err != nil {
		return nil, err
	}

	if isLocked {
		return nil, errors.New("wallet is temporarily locked")
	}

	if currentBalance < req.Amount {
		return nil, fmt.Errorf("insufficient wallet balance: available ₹%.2f, requested ₹%.2f", currentBalance, req.Amount)
	}

	openingBalance := currentBalance
	closingBalance := currentBalance

	// If completed or pending, deduct balance from wallet
	if status == "completed" || status == "pending" {
		closingBalance = currentBalance - req.Amount
		_, err = tx.Exec(
			ctx,
			`UPDATE wallets SET balance = $1, updated_at = NOW() WHERE id = $2`,
			closingBalance, walletID,
		)
		if err != nil {
			return nil, err
		}
	}

	title := fmt.Sprintf("Withdrawal to %s", req.DestinationTitle)
	subtitle := req.DestinationDetail
	category := "Withdrawal"

	var destinationInfo *string
	if req.DestinationDetail != "" {
		destinationInfo = &req.DestinationDetail
	}

	var failureReason *string
	if req.FailureReason != "" {
		failureReason = &req.FailureReason
	}

	var txn models.WalletTransaction
	err = tx.QueryRow(
		ctx,
		`INSERT INTO wallet_transactions (
			wallet_id, user_id, reference_id, type, status, amount,
			opening_balance, closing_balance, title, subtitle, category,
			payment_method, payment_method_type, destination_info, failure_reason
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
		RETURNING id, wallet_id, user_id, reference_id, type, status, amount,
		          opening_balance, closing_balance, title, subtitle, category,
		          payment_method, payment_method_type, destination_info, failure_reason,
		          metadata, created_at, updated_at`,
		walletID, userID, refID, "withdrawal", status, req.Amount,
		openingBalance, closingBalance, title, subtitle, category,
		req.DestinationTitle, req.DestinationMode, destinationInfo, failureReason,
	).Scan(
		&txn.ID, &txn.WalletID, &txn.UserID, &txn.ReferenceID, &txn.Type, &txn.Status, &txn.Amount,
		&txn.OpeningBalance, &txn.ClosingBalance, &txn.Title, &txn.Subtitle, &txn.Category,
		&txn.PaymentMethod, &txn.PaymentMethodType, &txn.DestinationInfo, &txn.FailureReason,
		&txn.Metadata, &txn.CreatedAt, &txn.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return &txn, nil
}

// Bank Account operations

func (s *WalletService) GetBankAccounts(ctx context.Context, userID string) ([]models.SavedBankAccount, error) {
	rows, err := s.DB.Query(
		ctx,
		`SELECT id, user_id, account_holder_name, account_number, ifsc_code, bank_name, branch, is_primary, created_at, updated_at
		 FROM saved_bank_accounts
		 WHERE user_id = $1
		 ORDER BY is_primary DESC, created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var banks []models.SavedBankAccount
	for rows.Next() {
		var b models.SavedBankAccount
		if err := rows.Scan(&b.ID, &b.UserID, &b.AccountHolderName, &b.AccountNumber, &b.IFSCCode, &b.BankName, &b.Branch, &b.IsPrimary, &b.CreatedAt, &b.UpdatedAt); err != nil {
			return nil, err
		}
		banks = append(banks, b)
	}

	if banks == nil {
		banks = []models.SavedBankAccount{}
	}

	return banks, nil
}

func (s *WalletService) AddBankAccount(ctx context.Context, userID string, req models.AddBankAccountRequest) (*models.SavedBankAccount, error) {
	var branch *string
	if req.Branch != "" {
		branch = &req.Branch
	}

	var b models.SavedBankAccount
	err := s.DB.QueryRow(
		ctx,
		`INSERT INTO saved_bank_accounts (user_id, account_holder_name, account_number, ifsc_code, bank_name, branch, is_primary)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 RETURNING id, user_id, account_holder_name, account_number, ifsc_code, bank_name, branch, is_primary, created_at, updated_at`,
		userID, req.AccountHolderName, req.AccountNumber, req.IFSCCode, req.BankName, branch, req.IsPrimary,
	).Scan(&b.ID, &b.UserID, &b.AccountHolderName, &b.AccountNumber, &b.IFSCCode, &b.BankName, &b.Branch, &b.IsPrimary, &b.CreatedAt, &b.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &b, nil
}

func (s *WalletService) DeleteBankAccount(ctx context.Context, userID, bankID string) error {
	cmd, err := s.DB.Exec(ctx, `DELETE FROM saved_bank_accounts WHERE id = $1 AND user_id = $2`, bankID, userID)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return errors.New("bank account not found")
	}
	return nil
}

// UPI ID operations

func (s *WalletService) GetUPIIDs(ctx context.Context, userID string) ([]models.SavedUPIID, error) {
	rows, err := s.DB.Query(
		ctx,
		`SELECT id, user_id, upi_id, label, is_primary, created_at, updated_at
		 FROM saved_upi_ids
		 WHERE user_id = $1
		 ORDER BY is_primary DESC, created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var upis []models.SavedUPIID
	for rows.Next() {
		var u models.SavedUPIID
		if err := rows.Scan(&u.ID, &u.UserID, &u.UPIID, &u.Label, &u.IsPrimary, &u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, err
		}
		upis = append(upis, u)
	}

	if upis == nil {
		upis = []models.SavedUPIID{}
	}

	return upis, nil
}

func (s *WalletService) AddUPIID(ctx context.Context, userID string, req models.AddUPIIDRequest) (*models.SavedUPIID, error) {
	label := req.Label
	if label == "" {
		label = "UPI"
	}

	var u models.SavedUPIID
	err := s.DB.QueryRow(
		ctx,
		`INSERT INTO saved_upi_ids (user_id, upi_id, label, is_primary)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id, user_id, upi_id, label, is_primary, created_at, updated_at`,
		userID, req.UPIID, label, req.IsPrimary,
	).Scan(&u.ID, &u.UserID, &u.UPIID, &u.Label, &u.IsPrimary, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (s *WalletService) DeleteUPIID(ctx context.Context, userID, upiID string) error {
	cmd, err := s.DB.Exec(ctx, `DELETE FROM saved_upi_ids WHERE id = $1 AND user_id = $2`, upiID, userID)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return errors.New("UPI ID not found")
	}
	return nil
}

// Saved Card operations

func (s *WalletService) GetCards(ctx context.Context, userID string) ([]models.SavedCard, error) {
	rows, err := s.DB.Query(
		ctx,
		`SELECT id, user_id, last_four_digits, card_holder_name, expiry_date, card_network, is_credit, created_at, updated_at
		 FROM saved_cards
		 WHERE user_id = $1
		 ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var cards []models.SavedCard
	for rows.Next() {
		var c models.SavedCard
		if err := rows.Scan(&c.ID, &c.UserID, &c.LastFourDigits, &c.CardHolderName, &c.ExpiryDate, &c.CardNetwork, &c.IsCredit, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		cards = append(cards, c)
	}

	if cards == nil {
		cards = []models.SavedCard{}
	}

	return cards, nil
}

func (s *WalletService) AddCard(ctx context.Context, userID string, req models.AddCardRequest) (*models.SavedCard, error) {
	var c models.SavedCard
	err := s.DB.QueryRow(
		ctx,
		`INSERT INTO saved_cards (user_id, last_four_digits, card_holder_name, expiry_date, card_network, is_credit)
		 VALUES ($1, $2, $3, $4, $5, $6)
		 RETURNING id, user_id, last_four_digits, card_holder_name, expiry_date, card_network, is_credit, created_at, updated_at`,
		userID, req.LastFourDigits, req.CardHolderName, req.ExpiryDate, req.CardNetwork, req.IsCredit,
	).Scan(&c.ID, &c.UserID, &c.LastFourDigits, &c.CardHolderName, &c.ExpiryDate, &c.CardNetwork, &c.IsCredit, &c.CreatedAt, &c.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (s *WalletService) DeleteCard(ctx context.Context, userID, cardID string) error {
	cmd, err := s.DB.Exec(ctx, `DELETE FROM saved_cards WHERE id = $1 AND user_id = $2`, cardID, userID)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return errors.New("card not found")
	}
	return nil
}

// GetAuthoritativeBalance retrieves the authoritative balance for a user.
func (s *WalletService) GetAuthoritativeBalance(ctx context.Context, userID string) (float64, error) {
	wallet, err := s.GetOrCreateWallet(ctx, userID)
	if err != nil {
		return 0, err
	}
	return wallet.Balance, nil
}

// GetPendingCashCommissionExposure calculates the outstanding platform commission liability for a driver's active rides.
// This is the sum of platform charges from confirmed, unsettled cash bookings.
func (s *WalletService) GetPendingCashCommissionExposure(ctx context.Context, driverID string) (float64, error) {
	var exposure float64
	err := s.DB.QueryRow(ctx, `
		SELECT COALESCE(SUM(
			CASE 
				WHEN b.platform_charge > 0 THEN b.platform_charge 
				ELSE r.app_amount * b.seats_booked 
			END
		), 0)
		FROM bookings b
		JOIN rides r ON b.ride_id = r.id
		WHERE r.driver_id = $1
		  AND r.status = 'active'
		  AND b.status = 'confirmed'
		  AND b.payment_mode = 'cash'
		  AND b.settlement_status = 'unsettled'
	`, driverID).Scan(&exposure)
	if err != nil {
		return 0, err
	}
	return exposure, nil
}

// CheckRideCreationEligibility verifies if a driver is allowed to create a new ride or recurring schedule.
// Per business rules:
// - A user whose wallet balance is below -₹100 (balance <= models.MaxNegativeWalletBalance) cannot create new rides.
// - If the wallet balance is below -₹100, reject new ride creation and display the existing outstanding-platform-charges popup.
func (s *WalletService) CheckRideCreationEligibility(ctx context.Context, driverID string) error {
	balance, err := s.GetAuthoritativeBalance(ctx, driverID)
	if err != nil {
		return err
	}

	if balance <= models.MaxNegativeWalletBalance {
		return &models.OutstandingChargesError{Balance: balance}
	}

	return nil
}

// CheckCashBookingEligibility is preserved for compatibility.
// Per business rules: once a ride is successfully published and remains available,
// eligible passengers must be able to book it regardless of the ride creator's wallet balance.
func (s *WalletService) CheckCashBookingEligibility(ctx context.Context, tx pgx.Tx, driverID string, additionalCommission float64) error {
	return nil
}

// SettleCompletedRide settles the driver's wallet atomically when a ride completes.
// - UPI bookings: credits driver's wallet with (user_amount * seats_booked), provided payment is verified in payment_orders.
// - Cash bookings: deducts platform charge (app_amount * seats_booked) from driver's wallet.
// - Auditable ledger: inserts distinct wallet_transactions for each booking with unique reference IDs.
// - Negative balance: allows wallet to become negative down to -₹100 (or records exceptional status if exceeded on existing ride).
// - Idempotency: guarded by settlement_status on rides/bookings and unique reference IDs.
func (s *WalletService) SettleCompletedRide(ctx context.Context, tx pgx.Tx, rideID string, driverID string) error {
	// 1. Lock ride and check settlement_status
	var rideSettlementStatus string
	var rideUserAmount float64
	var rideAppAmount float64
	err := tx.QueryRow(ctx, `
		SELECT settlement_status, user_amount, app_amount
		FROM rides
		WHERE id = $1
		FOR UPDATE
	`, rideID).Scan(&rideSettlementStatus, &rideUserAmount, &rideAppAmount)
	if err != nil {
		return fmt.Errorf("failed to fetch ride for settlement: %w", err)
	}

	if rideSettlementStatus == "settled" {
		// Idempotent: already settled
		return nil
	}

	// 2. Lock driver wallet row FOR UPDATE (or create if missing)
	var walletID string
	var currentBalance float64
	var isLocked bool
	err = tx.QueryRow(ctx, `
		SELECT id, balance, is_locked
		FROM wallets
		WHERE user_id = $1
		FOR UPDATE
	`, driverID).Scan(&walletID, &currentBalance, &isLocked)

	if errors.Is(err, pgx.ErrNoRows) {
		err = tx.QueryRow(ctx, `
			INSERT INTO wallets (user_id, balance)
			VALUES ($1, COALESCE((SELECT money_earned FROM users WHERE id = $1), 0))
			ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW()
			RETURNING id, balance, is_locked
		`, driverID).Scan(&walletID, &currentBalance, &isLocked)
		if err != nil {
			return fmt.Errorf("failed to initialize wallet for settlement: %w", err)
		}
	} else if err != nil {
		return fmt.Errorf("failed to lock wallet for settlement: %w", err)
	}

	// 3. Query all eligible bookings for this ride
	type bookingToSettle struct {
		id               string
		passengerID      string
		passengerName    string
		paymentMode      string
		status           string
		seatsBooked      int
		totalAmount      float64
		driverEarnings   float64
		platformCharge   float64
		settlementStatus string
	}

	rows, err := tx.Query(ctx, `
		SELECT id, passenger_id, passenger_name, payment_mode, status, seats_booked, 
		       total_amount, driver_earnings, platform_charge, settlement_status
		FROM bookings
		WHERE ride_id = $1 AND status IN ('confirmed', 'completed')
		FOR UPDATE
	`, rideID)
	if err != nil {
		return fmt.Errorf("failed to query bookings for settlement: %w", err)
	}

	var bookings []bookingToSettle
	for rows.Next() {
		var b bookingToSettle
		if err := rows.Scan(
			&b.id, &b.passengerID, &b.passengerName, &b.paymentMode, &b.status,
			&b.seatsBooked, &b.totalAmount, &b.driverEarnings, &b.platformCharge, &b.settlementStatus,
		); err != nil {
			rows.Close()
			return fmt.Errorf("failed to scan booking for settlement: %w", err)
		}
		bookings = append(bookings, b)
	}
	rows.Close()

	// 4. Process each booking
	for _, b := range bookings {
		if b.settlementStatus == "settled" {
			continue
		}

		if b.paymentMode == "upi" {
			// Verify payment in payment_orders
			var isPaid bool
			_ = tx.QueryRow(ctx, `
				SELECT EXISTS(
					SELECT 1 FROM payment_orders
					WHERE purpose = 'ride_booking'
					  AND status = 'paid'
					  AND (metadata->>'booking_id' = $1 OR order_id = $1)
				)
			`, b.id).Scan(&isPaid)

			if !isPaid {
				// UPI payment not verified on backend; do not credit driver
				continue
			}

			earnings := b.driverEarnings
			if earnings <= 0 {
				earnings = rideUserAmount * float64(b.seatsBooked)
			}

			if earnings > 0 {
				refID := fmt.Sprintf("SETTLE-UPI-%s", b.id)

				var alreadySettled bool
				_ = tx.QueryRow(ctx, `
					SELECT EXISTS(SELECT 1 FROM wallet_transactions WHERE reference_id = $1)
				`, refID).Scan(&alreadySettled)

				if !alreadySettled {
					openingBalance := currentBalance
					closingBalance := currentBalance + earnings
					currentBalance = closingBalance

					metaJSON, _ := json.Marshal(map[string]interface{}{
						"ride_id":      rideID,
						"booking_id":   b.id,
						"passenger_id": b.passengerID,
						"seats_booked": b.seatsBooked,
						"payment_mode": "upi",
					})

					_, err = tx.Exec(ctx, `
						INSERT INTO wallet_transactions (
							wallet_id, user_id, reference_id, type, status, amount,
							opening_balance, closing_balance, title, subtitle, category,
							payment_method, payment_method_type, metadata
						) VALUES ($1, $2, $3, 'ride_earnings_upi', 'completed', $4, $5, $6, $7, $8, $9, $10, $11, $12)
					`, walletID, driverID, refID, earnings, openingBalance, closingBalance,
						"Ride Earnings (UPI)", fmt.Sprintf("Ride completed • %d seat(s)", b.seatsBooked),
						"Ride Earnings", "UPI", "upi", metaJSON)
					if err != nil {
						return fmt.Errorf("failed to record UPI ride earnings transaction: %w", err)
					}

					_, err = tx.Exec(ctx, `
						UPDATE wallets SET balance = $1, updated_at = NOW() WHERE id = $2
					`, currentBalance, walletID)
					if err != nil {
						return fmt.Errorf("failed to update wallet for UPI earnings: %w", err)
					}
				}

				_, err = tx.Exec(ctx, `
					UPDATE bookings 
					SET settlement_status = 'settled', driver_earnings = $1, updated_at = NOW() 
					WHERE id = $2
				`, earnings, b.id)
				if err != nil {
					return fmt.Errorf("failed to update booking settlement status: %w", err)
				}
			}
		} else if b.paymentMode == "cash" {
			charge := b.platformCharge
			if charge <= 0 {
				charge = rideAppAmount * float64(b.seatsBooked)
			}

			if charge > 0 {
				refID := fmt.Sprintf("SETTLE-CASH-%s", b.id)

				var alreadySettled bool
				_ = tx.QueryRow(ctx, `
					SELECT EXISTS(SELECT 1 FROM wallet_transactions WHERE reference_id = $1)
				`, refID).Scan(&alreadySettled)

				if !alreadySettled {
					openingBalance := currentBalance
					closingBalance := currentBalance - charge
					currentBalance = closingBalance

					isExceptional := closingBalance < models.MaxNegativeWalletBalance

					metaJSON, _ := json.Marshal(map[string]interface{}{
						"ride_id":                      rideID,
						"booking_id":                   b.id,
						"passenger_id":                 b.passengerID,
						"seats_booked":                 b.seatsBooked,
						"payment_mode":                 "cash",
						"exceptional_negative_balance": isExceptional,
					})

					_, err = tx.Exec(ctx, `
						INSERT INTO wallet_transactions (
							wallet_id, user_id, reference_id, type, status, amount,
							opening_balance, closing_balance, title, subtitle, category,
							payment_method, payment_method_type, metadata
						) VALUES ($1, $2, $3, 'platform_charge_cash', 'completed', $4, $5, $6, $7, $8, $9, $10, $11, $12)
					`, walletID, driverID, refID, charge, openingBalance, closingBalance,
						"Platform Charge (Cash)", fmt.Sprintf("Ride completed • %d seat(s)", b.seatsBooked),
						"Platform Fee", "Cash", "cash", metaJSON)
					if err != nil {
						return fmt.Errorf("failed to record cash platform charge transaction: %w", err)
					}

					_, err = tx.Exec(ctx, `
						UPDATE wallets SET balance = $1, updated_at = NOW() WHERE id = $2
					`, currentBalance, walletID)
					if err != nil {
						return fmt.Errorf("failed to update wallet for cash platform charge: %w", err)
					}
				}

				_, err = tx.Exec(ctx, `
					UPDATE bookings 
					SET settlement_status = 'settled', platform_charge = $1, updated_at = NOW() 
					WHERE id = $2
				`, charge, b.id)
				if err != nil {
					return fmt.Errorf("failed to update booking settlement status: %w", err)
				}
			}
		}
	}

	// 5. Mark ride as settled
	_, err = tx.Exec(ctx, `
		UPDATE rides 
		SET settlement_status = 'settled', updated_at = NOW() 
		WHERE id = $1
	`, rideID)
	if err != nil {
		return fmt.Errorf("failed to mark ride as settled: %w", err)
	}

	return nil
}

