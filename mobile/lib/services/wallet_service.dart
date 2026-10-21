import 'package:flutter/foundation.dart';
import '../models/wallet_models.dart';
import 'api_service.dart';

/// Singleton service managing wallet state, transactions, and live Supabase synchronization.
/// No mock or hardcoded financial data — all balances and transactions come from the backend.
class WalletService extends ChangeNotifier {
  WalletService._internal();

  static final WalletService instance = WalletService._internal();

  factory WalletService() => instance;

  final ApiService _apiService = ApiService();

  double _balance = 0.00;
  bool _isBalanceHidden = false;
  bool _isLoading = false;

  double get balance => _balance;
  bool get isBalanceHidden => _isBalanceHidden;
  bool get isLoading => _isLoading;

  final List<WalletTransaction> _transactions = [];
  final List<BankAccount> _savedBankAccounts = [];
  final List<SavedUpiId> _savedUpiIds = [];
  final List<SavedCard> _savedCards = [];

  List<WalletTransaction> get transactions => List.unmodifiable(_transactions);
  List<BankAccount> get savedBankAccounts => List.unmodifiable(_savedBankAccounts);
  List<SavedUpiId> get savedUpiIds => List.unmodifiable(_savedUpiIds);
  List<SavedCard> get savedCards => List.unmodifiable(_savedCards);

  List<WalletTransaction> get recentTransactions =>
      List.unmodifiable(_transactions.take(5).toList());

  void toggleBalanceVisibility() {
    _isBalanceHidden = !_isBalanceHidden;
    notifyListeners();
  }

  void setBalanceVisibility(bool hidden) {
    if (_isBalanceHidden != hidden) {
      _isBalanceHidden = hidden;
      notifyListeners();
    }
  }

  /// Synchronize balance and history directly from backend / Supabase.
  Future<void> refreshFromBackend() async {
    _isLoading = true;
    notifyListeners();

    try {
      final res = await _apiService.getWalletSummary();
      if (res['wallet'] is Map) {
        final w = res['wallet'] as Map<String, dynamic>;
        final rawBal = w['balance'];
        _balance = (rawBal is num)
            ? rawBal.toDouble()
            : double.tryParse(rawBal?.toString() ?? '0') ?? 0.0;
      }

      _transactions.clear();
      if (res['recent_transactions'] is List) {
        final list = (res['recent_transactions'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => WalletTransaction.fromJson(item))
            .toList();
        _transactions.addAll(list);
      }

      _savedBankAccounts.clear();
      if (res['saved_bank_accounts'] is List) {
        final banks = (res['saved_bank_accounts'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => BankAccount.fromJson(item))
            .toList();
        _savedBankAccounts.addAll(banks);
      }

      _savedUpiIds.clear();
      if (res['saved_upi_ids'] is List) {
        final upis = (res['saved_upi_ids'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => SavedUpiId.fromJson(item))
            .toList();
        _savedUpiIds.addAll(upis);
      }

      _savedCards.clear();
      if (res['saved_cards'] is List) {
        final cards = (res['saved_cards'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => SavedCard.fromJson(item))
            .toList();
        _savedCards.addAll(cards);
      }
    } catch (e) {
      debugPrint('WalletService.refreshFromBackend error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add money to wallet, persisting to backend/Supabase.
  Future<WalletTransaction> addMoney({
    required double amount,
    required String paymentMethod,
    required String paymentMethodType,
    String? referenceId,
    TransactionStatus status = TransactionStatus.completed,
    String? failureReason,
  }) async {
    final ref = referenceId ?? 'TXN-${DateTime.now().millisecondsSinceEpoch}';

    final res = await _apiService.addMoneyToWallet(
      amount: amount,
      paymentMethod: paymentMethod,
      paymentMethodType: paymentMethodType,
      referenceId: ref,
      status: status.code,
      failureReason: failureReason,
    );

    final txn = WalletTransaction.fromJson(res);
    if (txn.status == TransactionStatus.completed) {
      _balance += amount;
    }
    _transactions.insert(0, txn);
    notifyListeners();
    return txn;
  }

  /// Withdraw money from wallet, persisting to backend/Supabase.
  Future<WalletTransaction> withdrawMoney({
    required double amount,
    required String destinationMode,
    required String destinationTitle,
    required String destinationDetail,
    String? destinationId,
    String? referenceId,
    TransactionStatus status = TransactionStatus.completed,
    String? failureReason,
  }) async {
    final ref = referenceId ?? 'WTH-${DateTime.now().millisecondsSinceEpoch}';

    final res = await _apiService.withdrawFromWallet(
      amount: amount,
      destinationMode: destinationMode,
      destinationTitle: destinationTitle,
      destinationDetail: destinationDetail,
      destinationId: destinationId,
      referenceId: ref,
      status: status.code,
      failureReason: failureReason,
    );

    final txn = WalletTransaction.fromJson(res);
    if (txn.status == TransactionStatus.completed || txn.status == TransactionStatus.pending) {
      _balance = (_balance - amount).clamp(0.0, double.infinity);
    }
    _transactions.insert(0, txn);
    notifyListeners();
    return txn;
  }

  /// Add a saved bank account, persisting to backend/Supabase.
  Future<BankAccount> addBankAccount(BankAccount account) async {
    final res = await _apiService.addSavedBankAccount(
      accountHolderName: account.accountHolderName,
      accountNumber: account.accountNumber,
      ifscCode: account.ifscCode,
      bankName: account.bankName,
      branch: account.branch,
      isPrimary: account.isPrimary,
    );

    final saved = BankAccount.fromJson(res);
    _savedBankAccounts.add(saved);
    notifyListeners();
    return saved;
  }

  /// Add a saved UPI ID, persisting to backend/Supabase.
  Future<SavedUpiId> addUpiId(SavedUpiId upi) async {
    final res = await _apiService.addSavedUPIID(
      upiId: upi.upiId,
      label: upi.label,
      isPrimary: upi.isPrimary,
    );

    final saved = SavedUpiId.fromJson(res);
    _savedUpiIds.add(saved);
    notifyListeners();
    return saved;
  }

  /// Add a saved Card, persisting to backend/Supabase.
  Future<SavedCard> addCard(SavedCard card) async {
    final res = await _apiService.addSavedCard(
      lastFourDigits: card.lastFourDigits,
      cardHolderName: card.cardHolderName,
      expiryDate: card.expiryDate,
      cardNetwork: card.cardNetwork,
      isCredit: card.isCredit,
    );

    final saved = SavedCard.fromJson(res);
    _savedCards.add(saved);
    notifyListeners();
    return saved;
  }

  /// Format Indian rupee amounts with commas (e.g. ₹1,450.00 or -₹50.00)
  static String formatAmount(num amount, {bool includeSymbol = true}) {
    final isNegative = amount < 0;
    final absAmount = amount.abs();
    final isInt = absAmount % 1 == 0;
    final numStr = isInt ? absAmount.toInt().toString() : absAmount.toStringAsFixed(2);
    final parts = numStr.split('.');
    String whole = parts[0];
    final dec = parts.length > 1 ? '.${parts[1]}' : '';

    if (whole.length > 3) {
      final last3 = whole.substring(whole.length - 3);
      final rest = whole.substring(0, whole.length - 3);
      final buffer = StringBuffer();
      for (int i = 0; i < rest.length; i++) {
        if (i > 0 && (rest.length - i) % 2 == 0) {
          buffer.write(',');
        }
        buffer.write(rest[i]);
      }
      whole = '${buffer.toString()},$last3';
    }

    final formatted = includeSymbol ? '₹$whole$dec' : '$whole$dec';
    return isNegative ? '-$formatted' : formatted;
  }
}
