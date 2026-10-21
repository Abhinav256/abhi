import 'package:flutter_test/flutter_test.dart';
import 'package:abhi_share/models/wallet_models.dart';
import 'package:abhi_share/services/wallet_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WalletService and Wallet Models Tests', () {
    late WalletService walletService;

    setUp(() {
      walletService = WalletService.instance;
    });

    test('Initial balance starts at 0 without hardcoded amounts', () {
      expect(walletService.balance, 0.00);
      expect(walletService.isBalanceHidden, false);

      walletService.toggleBalanceVisibility();
      expect(walletService.isBalanceHidden, true);

      walletService.toggleBalanceVisibility();
      expect(walletService.isBalanceHidden, false);
    });

    test('Currency formatting handles integers and decimals with Indian commas', () {
      expect(WalletService.formatAmount(500), '₹500');
      expect(WalletService.formatAmount(1450), '₹1,450');
      expect(WalletService.formatAmount(125000), '₹1,25,000');
      expect(WalletService.formatAmount(99.50), '₹99.50');
      expect(WalletService.formatAmount(500, includeSymbol: false), '500');
    });

    test('WalletTransaction model parses JSON and serializes correctly', () {
      final json = {
        'id': 'txn_123',
        'type': 'money_added',
        'status': 'completed',
        'amount': 500.0,
        'title': 'Money Added',
        'subtitle': 'UPI Transfer',
        'payment_method': 'Google Pay',
        'reference_number': 'TXN-987654',
        'timestamp': '2026-10-11T20:00:00Z',
      };

      final txn = WalletTransaction.fromJson(json);
      expect(txn.id, 'txn_123');
      expect(txn.type, TransactionType.moneyAdded);
      expect(txn.status, TransactionStatus.completed);
      expect(txn.amount, 500.0);
      expect(txn.isCredit, true);

      final out = txn.toJson();
      expect(out['id'], 'txn_123');
      expect(out['amount'], 500.0);
    });

    test('BankAccount model parses JSON and serializes correctly', () {
      final json = {
        'id': 'ba_1',
        'account_holder_name': 'Abhinav Reddy',
        'account_number': '123456789012',
        'ifsc_code': 'HDFC0000128',
        'bank_name': 'HDFC Bank',
        'branch': 'Indiranagar',
        'is_primary': true,
      };

      final bank = BankAccount.fromJson(json);
      expect(bank.id, 'ba_1');
      expect(bank.accountHolderName, 'Abhinav Reddy');
      expect(bank.maskedAccountNumber, '•••• •••• 9012');
      expect(bank.ifscCode, 'HDFC0000128');

      final out = bank.toJson();
      expect(out['account_number'], '123456789012');
    });

    test('SavedUpiId model parses JSON and serializes correctly', () {
      final json = {
        'id': 'upi_1',
        'upi_id': 'abhinav@okhdfcbank',
        'label': 'Primary UPI',
        'is_primary': true,
      };

      final upi = SavedUpiId.fromJson(json);
      expect(upi.id, 'upi_1');
      expect(upi.upiId, 'abhinav@okhdfcbank');

      final out = upi.toJson();
      expect(out['upi_id'], 'abhinav@okhdfcbank');
    });

    test('SavedCard model parses JSON and serializes correctly', () {
      final json = {
        'id': 'card_1',
        'last_four_digits': '4242',
        'card_holder_name': 'Abhinav Reddy',
        'expiry_date': '12/28',
        'card_network': 'Visa',
        'is_credit': true,
      };

      final card = SavedCard.fromJson(json);
      expect(card.id, 'card_1');
      expect(card.lastFourDigits, '4242');
      expect(card.displayType, 'Credit Card');

      final out = card.toJson();
      expect(out['last_four_digits'], '4242');
    });

    test('Negative currency formatting correctly puts minus sign before symbol', () {
      expect(WalletService.formatAmount(-5), '-₹5');
      expect(WalletService.formatAmount(-100), '-₹100');
      expect(WalletService.formatAmount(-1450.50), '-₹1,450.50');
      expect(WalletService.formatAmount(-5, includeSymbol: false), '-5');
    });

    test('Settlement transaction types: UPI earnings and Cash platform charge', () {
      final upiJson = {
        'id': 'settle_upi_1',
        'type': 'ride_earnings_upi',
        'status': 'completed',
        'amount': 200.0,
        'title': 'Ride Earnings (UPI)',
        'subtitle': 'Ride completed • 1 seat(s)',
        'payment_method': 'UPI',
        'reference_number': 'SETTLE-UPI-b1',
        'timestamp': '2026-10-16T12:00:00Z',
      };
      final upiTxn = WalletTransaction.fromJson(upiJson);
      expect(upiTxn.type, TransactionType.rideEarningsUpi);
      expect(upiTxn.isCredit, true);
      expect(upiTxn.amount, 200.0);
      expect(upiTxn.type.code, 'ride_earnings_upi');
      expect(upiTxn.type.displayName, 'Ride Earnings (UPI)');

      final cashJson = {
        'id': 'settle_cash_1',
        'type': 'platform_charge_cash',
        'status': 'completed',
        'amount': 8.0,
        'title': 'Platform Charge (Cash)',
        'subtitle': 'Ride completed • 1 seat(s)',
        'payment_method': 'Cash',
        'reference_number': 'SETTLE-CASH-b2',
        'timestamp': '2026-10-16T12:05:00Z',
      };
      final cashTxn = WalletTransaction.fromJson(cashJson);
      expect(cashTxn.type, TransactionType.platformChargeCash);
      expect(cashTxn.isCredit, false);
      expect(cashTxn.amount, 8.0);
      expect(cashTxn.type.code, 'platform_charge_cash');
      expect(cashTxn.type.displayName, 'Platform Charge (Cash)');
    });
  });
}
