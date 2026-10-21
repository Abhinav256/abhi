import 'package:flutter/material.dart';

/// Enum representing the kind of wallet transaction.
enum TransactionType {
  moneyAdded,
  withdrawal,
  ridePayment,
  refund,
  referralReward,
  rideEarningsUpi,
  platformChargeCash;

  static TransactionType fromString(String? val) {
    switch (val) {
      case 'money_added':
        return TransactionType.moneyAdded;
      case 'withdrawal':
        return TransactionType.withdrawal;
      case 'ride_payment':
        return TransactionType.ridePayment;
      case 'refund':
        return TransactionType.refund;
      case 'referral_reward':
        return TransactionType.referralReward;
      case 'ride_earnings_upi':
        return TransactionType.rideEarningsUpi;
      case 'platform_charge_cash':
        return TransactionType.platformChargeCash;
      default:
        return TransactionType.moneyAdded;
    }
  }
}

extension TransactionTypeExtension on TransactionType {
  String get displayName {
    switch (this) {
      case TransactionType.moneyAdded:
        return 'Money Added';
      case TransactionType.withdrawal:
        return 'Withdrawal';
      case TransactionType.ridePayment:
        return 'Ride Payment';
      case TransactionType.refund:
        return 'Refund';
      case TransactionType.referralReward:
        return 'Referral Reward';
      case TransactionType.rideEarningsUpi:
        return 'Ride Earnings (UPI)';
      case TransactionType.platformChargeCash:
        return 'Platform Charge (Cash)';
    }
  }

  String get code {
    switch (this) {
      case TransactionType.moneyAdded:
        return 'money_added';
      case TransactionType.withdrawal:
        return 'withdrawal';
      case TransactionType.ridePayment:
        return 'ride_payment';
      case TransactionType.refund:
        return 'refund';
      case TransactionType.referralReward:
        return 'referral_reward';
      case TransactionType.rideEarningsUpi:
        return 'ride_earnings_upi';
      case TransactionType.platformChargeCash:
        return 'platform_charge_cash';
    }
  }

  static TransactionType fromString(String? val) => TransactionType.fromString(val);

  IconData get icon {
    switch (this) {
      case TransactionType.moneyAdded:
        return Icons.arrow_downward_rounded;
      case TransactionType.withdrawal:
        return Icons.arrow_upward_rounded;
      case TransactionType.ridePayment:
        return Icons.directions_car_rounded;
      case TransactionType.refund:
        return Icons.replay_rounded;
      case TransactionType.referralReward:
        return Icons.card_giftcard_rounded;
      case TransactionType.rideEarningsUpi:
        return Icons.trending_up_rounded;
      case TransactionType.platformChargeCash:
        return Icons.receipt_long_rounded;
    }
  }

  Color get color {
    switch (this) {
      case TransactionType.moneyAdded:
        return const Color(0xFF0E8A6A); // Emerald green
      case TransactionType.withdrawal:
        return const Color(0xFFE65100); // Deep orange
      case TransactionType.ridePayment:
        return const Color(0xFF0B6FE0); // Brand blue
      case TransactionType.refund:
        return const Color(0xFF673AB7); // Purple
      case TransactionType.referralReward:
        return const Color(0xFFE91E63); // Pink / Reward accent
      case TransactionType.rideEarningsUpi:
        return const Color(0xFF0E8A6A); // Emerald green for earnings
      case TransactionType.platformChargeCash:
        return const Color(0xFFE65100); // Deep orange for commission debit
    }
  }

  Color get backgroundColor {
    switch (this) {
      case TransactionType.moneyAdded:
        return const Color(0xFFE8F5E9);
      case TransactionType.withdrawal:
        return const Color(0xFFFFF3E0);
      case TransactionType.ridePayment:
        return const Color(0xFFE3F2FD);
      case TransactionType.refund:
        return const Color(0xFFEDE7F6);
      case TransactionType.referralReward:
        return const Color(0xFFFCE4EC);
      case TransactionType.rideEarningsUpi:
        return const Color(0xFFE8F5E9);
      case TransactionType.platformChargeCash:
        return const Color(0xFFFFF3E0);
    }
  }

  bool get isCredit {
    return this == TransactionType.moneyAdded ||
        this == TransactionType.refund ||
        this == TransactionType.referralReward ||
        this == TransactionType.rideEarningsUpi;
  }
}

/// Enum for transaction status.
enum TransactionStatus {
  completed,
  pending,
  failed;

  static TransactionStatus fromString(String? val) {
    switch (val) {
      case 'completed':
        return TransactionStatus.completed;
      case 'pending':
        return TransactionStatus.pending;
      case 'failed':
        return TransactionStatus.failed;
      default:
        return TransactionStatus.completed;
    }
  }
}

extension TransactionStatusExtension on TransactionStatus {
  String get displayName {
    switch (this) {
      case TransactionStatus.completed:
        return 'Completed';
      case TransactionStatus.pending:
        return 'Processing';
      case TransactionStatus.failed:
        return 'Failed';
    }
  }

  String get code {
    switch (this) {
      case TransactionStatus.completed:
        return 'completed';
      case TransactionStatus.pending:
        return 'pending';
      case TransactionStatus.failed:
        return 'failed';
    }
  }

  static TransactionStatus fromString(String? val) => TransactionStatus.fromString(val);

  Color get color {
    switch (this) {
      case TransactionStatus.completed:
        return const Color(0xFF0E8A6A);
      case TransactionStatus.pending:
        return const Color(0xFFF59E0B);
      case TransactionStatus.failed:
        return const Color(0xFFDC2626);
    }
  }

  Color get badgeBg {
    switch (this) {
      case TransactionStatus.completed:
        return const Color(0xFFE6F4EA);
      case TransactionStatus.pending:
        return const Color(0xFFFEF3C7);
      case TransactionStatus.failed:
        return const Color(0xFFFEE2E2);
    }
  }

  IconData get icon {
    switch (this) {
      case TransactionStatus.completed:
        return Icons.check_circle_rounded;
      case TransactionStatus.pending:
        return Icons.access_time_filled_rounded;
      case TransactionStatus.failed:
        return Icons.error_rounded;
    }
  }
}

/// A transaction record in the AbhiShare Wallet.
class WalletTransaction {
  final String id;
  final String title;
  final String subtitle;
  final double amount;
  final TransactionType type;
  final TransactionStatus status;
  final DateTime timestamp;
  final String paymentMethod;
  final String referenceNumber;
  final String? bankOrUpiInfo;
  final String? failureReason;
  final String category;

  const WalletTransaction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.type,
    required this.status,
    required this.timestamp,
    required this.paymentMethod,
    required this.referenceNumber,
    this.bankOrUpiInfo,
    this.failureReason,
    this.category = 'General',
  });

  bool get isCredit => type.isCredit;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    final double amount = (rawAmount is num) ? rawAmount.toDouble() : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;

    DateTime parsedDate = DateTime.now();
    final rawDate = json['created_at'] ?? json['timestamp'];
    if (rawDate != null) {
      parsedDate = DateTime.tryParse(rawDate.toString())?.toLocal() ?? DateTime.now();
    }

    return WalletTransaction(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Transaction',
      subtitle: json['subtitle']?.toString() ?? '',
      amount: amount,
      type: TransactionTypeExtension.fromString(json['type']?.toString()),
      status: TransactionStatusExtension.fromString(json['status']?.toString()),
      timestamp: parsedDate,
      paymentMethod: json['payment_method']?.toString() ?? 'UPI',
      referenceNumber: json['reference_id']?.toString() ?? json['reference_number']?.toString() ?? '',
      bankOrUpiInfo: json['destination_info']?.toString() ?? json['bank_or_upi_info']?.toString(),
      failureReason: json['failure_reason']?.toString(),
      category: json['category']?.toString() ?? 'General',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'amount': amount,
      'type': type.code,
      'status': status.code,
      'created_at': timestamp.toIso8601String(),
      'payment_method': paymentMethod,
      'reference_id': referenceNumber,
      'destination_info': bankOrUpiInfo,
      'failure_reason': failureReason,
      'category': category,
    };
  }

  WalletTransaction copyWith({
    String? id,
    String? title,
    String? subtitle,
    double? amount,
    TransactionType? type,
    TransactionStatus? status,
    DateTime? timestamp,
    String? paymentMethod,
    String? referenceNumber,
    String? bankOrUpiInfo,
    String? failureReason,
    String? category,
  }) {
    return WalletTransaction(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      bankOrUpiInfo: bankOrUpiInfo ?? this.bankOrUpiInfo,
      failureReason: failureReason ?? this.failureReason,
      category: category ?? this.category,
    );
  }
}

/// Bank account model for withdrawals.
class BankAccount {
  final String id;
  final String accountHolderName;
  final String accountNumber;
  final String ifscCode;
  final String bankName;
  final String? branch;
  final bool isPrimary;

  const BankAccount({
    required this.id,
    required this.accountHolderName,
    required this.accountNumber,
    required this.ifscCode,
    required this.bankName,
    this.branch,
    this.isPrimary = false,
  });

  String get maskedAccountNumber {
    if (accountNumber.length <= 4) return accountNumber;
    final last4 = accountNumber.substring(accountNumber.length - 4);
    return '•••• •••• $last4';
  }

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: json['id']?.toString() ?? '',
      accountHolderName: json['account_holder_name']?.toString() ?? '',
      accountNumber: json['account_number']?.toString() ?? '',
      ifscCode: json['ifsc_code']?.toString() ?? '',
      bankName: json['bank_name']?.toString() ?? '',
      branch: json['branch']?.toString(),
      isPrimary: json['is_primary'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'account_holder_name': accountHolderName,
      'account_number': accountNumber,
      'ifsc_code': ifscCode,
      'bank_name': bankName,
      'branch': branch,
      'is_primary': isPrimary,
    };
  }
}

/// Saved UPI ID model.
class SavedUpiId {
  final String id;
  final String upiId;
  final String label;
  final bool isPrimary;

  const SavedUpiId({
    required this.id,
    required this.upiId,
    required this.label,
    this.isPrimary = false,
  });

  factory SavedUpiId.fromJson(Map<String, dynamic> json) {
    return SavedUpiId(
      id: json['id']?.toString() ?? '',
      upiId: json['upi_id']?.toString() ?? '',
      label: json['label']?.toString() ?? 'UPI',
      isPrimary: json['is_primary'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'upi_id': upiId,
      'label': label,
      'is_primary': isPrimary,
    };
  }
}

/// Saved Card model.
class SavedCard {
  final String id;
  final String lastFourDigits;
  final String cardHolderName;
  final String expiryDate;
  final String cardNetwork; // Visa, Mastercard, RuPay, Amex
  final bool isCredit;

  const SavedCard({
    required this.id,
    required this.lastFourDigits,
    required this.cardHolderName,
    required this.expiryDate,
    required this.cardNetwork,
    this.isCredit = false,
  });

  String get displayType => isCredit ? 'Credit Card' : 'Debit Card';

  factory SavedCard.fromJson(Map<String, dynamic> json) {
    return SavedCard(
      id: json['id']?.toString() ?? '',
      lastFourDigits: json['last_four_digits']?.toString() ?? '',
      cardHolderName: json['card_holder_name']?.toString() ?? '',
      expiryDate: json['expiry_date']?.toString() ?? '',
      cardNetwork: json['card_network']?.toString() ?? 'Card',
      isCredit: json['is_credit'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'last_four_digits': lastFourDigits,
      'card_holder_name': cardHolderName,
      'expiry_date': expiryDate,
      'card_network': cardNetwork,
      'is_credit': isCredit,
    };
  }
}
