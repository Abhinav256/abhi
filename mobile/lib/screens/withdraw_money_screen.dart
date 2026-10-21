import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/wallet_models.dart';
import '../services/wallet_service.dart';

class WithdrawMoneyScreen extends StatefulWidget {
  const WithdrawMoneyScreen({super.key});

  @override
  State<WithdrawMoneyScreen> createState() => _WithdrawMoneyScreenState();
}

class _WithdrawMoneyScreenState extends State<WithdrawMoneyScreen> {
  static const Color _navy = Color(0xFF0F1B4D);
  static const Color _blue = Color(0xFF0B6FE0);
  static const Color _bg = Color(0xFFF3F7FD);

  final WalletService _walletService = WalletService.instance;
  final TextEditingController _amountController = TextEditingController();

  // Mode: 'bank' or 'upi'
  String _destinationMode = 'bank';

  // Selected destinations
  String? _selectedBankAccountId;
  String? _selectedUpiId;

  @override
  void initState() {
    super.initState();
    _walletService.addListener(_onWalletChanged);

    if (_walletService.savedBankAccounts.isNotEmpty) {
      _selectedBankAccountId = _walletService.savedBankAccounts.first.id;
    }
    if (_walletService.savedUpiIds.isNotEmpty) {
      _selectedUpiId = _walletService.savedUpiIds.first.id;
    }
  }

  @override
  void dispose() {
    _walletService.removeListener(_onWalletChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _onWalletChanged() {
    if (mounted) setState(() {});
  }

  double get _enteredAmount {
    return double.tryParse(_amountController.text.trim()) ?? 0.0;
  }

  void _onProceed() {
    final amount = _enteredAmount;
    final available = _walletService.balance;

    if (amount < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimum withdrawal amount is ₹100'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (amount > available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Amount exceeds available balance of ${WalletService.formatAmount(available)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_destinationMode == 'bank' && _selectedBankAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or add a bank account'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_destinationMode == 'upi' && _selectedUpiId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or add a UPI ID'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _showConfirmationBottomSheet();
  }

  void _showConfirmationBottomSheet() {
    final amount = _enteredAmount;
    String destTitle = '';
    String destDetail = '';

    if (_destinationMode == 'bank') {
      final bank = _walletService.savedBankAccounts
          .firstWhere((b) => b.id == _selectedBankAccountId);
      destTitle = bank.bankName;
      destDetail = '${bank.maskedAccountNumber} • ${bank.accountHolderName}';
    } else {
      final upi = _walletService.savedUpiIds
          .firstWhere((u) => u.id == _selectedUpiId);
      destTitle = 'UPI Transfer';
      destDetail = upi.upiId;
    }

    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(sheetCtx).padding.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Confirm Withdrawal',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Funds will be transferred to your registered account.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 18),

                  // Secure transfer badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.security_rounded, color: _blue, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Direct Bank Payout • Instant IMPS Settlement',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E40AF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Breakdown
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _buildSummaryRow('Withdrawal Amount', WalletService.formatAmount(amount)),
                        const SizedBox(height: 10),
                        _buildSummaryRow('Transfer Destination', destTitle),
                        const SizedBox(height: 6),
                        _buildSummaryRow('Account Details', destDetail, isSecondary: true),
                        const SizedBox(height: 10),
                        _buildSummaryRow('Transfer Fee (IMPS)', 'FREE (₹0)', isFree: true),
                        const SizedBox(height: 10),
                        _buildSummaryRow('Estimated Time', 'Instant / 15 Mins'),
                        const Divider(height: 24),
                        _buildSummaryRow(
                          'Total Debited',
                          WalletService.formatAmount(amount),
                          isTotal: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Real Withdrawal Action Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isProcessing
                          ? null
                          : () async {
                              setSheetState(() => isProcessing = true);
                              try {
                                final ref = 'IMPS/${DateTime.now().millisecondsSinceEpoch}';
                                final txn = await _walletService.withdrawMoney(
                                  amount: amount,
                                  destinationMode: _destinationMode,
                                  destinationTitle: destTitle,
                                  destinationDetail: destDetail,
                                  destinationId: _destinationMode == 'bank'
                                      ? _selectedBankAccountId
                                      : _selectedUpiId,
                                  referenceId: ref,
                                  status: TransactionStatus.completed,
                                );
                                if (!mounted) return;
                                if (sheetCtx.mounted) {
                                  Navigator.of(sheetCtx).pop();
                                }
                                _showResultScreen(txn);
                              } catch (e) {
                                setSheetState(() => isProcessing = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Withdrawal failed: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE65100),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Confirm & Withdraw ${WalletService.formatAmount(amount)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showResultScreen(WalletTransaction txn) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: txn.status.badgeBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  txn.status.icon,
                  color: txn.status.color,
                  size: 40,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                txn.status == TransactionStatus.completed
                    ? 'Withdrawal Successful!'
                    : (txn.status == TransactionStatus.pending
                        ? 'Withdrawal Processing'
                        : 'Withdrawal Failed'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                txn.status == TransactionStatus.completed
                    ? '${WalletService.formatAmount(txn.amount)} transferred to ${txn.paymentMethod}.'
                    : (txn.status == TransactionStatus.pending
                        ? 'Your request for ${WalletService.formatAmount(txn.amount)} is processing. Funds will reflect within 15 minutes.'
                        : (txn.failureReason ?? 'Withdrawal could not be processed.')),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Ref: ${txn.referenceNumber}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Back to Wallet'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isTotal = false,
    bool isFree = false,
    bool isSecondary = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : (isSecondary ? 11 : 13),
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? _navy : Colors.grey.shade600,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: isTotal ? 18 : (isSecondary ? 11 : 13),
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: isFree
                  ? const Color(0xFF0E8A6A)
                  : (isTotal ? const Color(0xFFE65100) : (isSecondary ? Colors.grey.shade700 : _navy)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = _walletService.balance;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'Withdraw Money',
          style: TextStyle(
            color: _navy,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _navy, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Balance info card
                    _buildBalanceHeader(available),

                    const SizedBox(height: 20),

                    // Amount input card
                    _buildAmountInputCard(available),

                    const SizedBox(height: 20),

                    // Destination Header & Tabs
                    const Text(
                      'Choose Withdrawal Destination',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select a verified bank account or UPI ID to receive funds',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 14),

                    // Tabs (Bank Account vs UPI ID)
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _destinationMode = 'bank'),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _destinationMode == 'bank' ? _blue : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _destinationMode == 'bank' ? _blue : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.account_balance_rounded,
                                    color: _destinationMode == 'bank' ? Colors.white : _navy,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Bank Account',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: _destinationMode == 'bank' ? Colors.white : _navy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _destinationMode = 'upi'),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _destinationMode == 'upi' ? _blue : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _destinationMode == 'upi' ? _blue : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.qr_code_2_rounded,
                                    color: _destinationMode == 'upi' ? Colors.white : _navy,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'UPI ID',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: _destinationMode == 'upi' ? Colors.white : _navy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Destination Content
                    if (_destinationMode == 'bank')
                      _buildBankAccountsList()
                    else
                      _buildUpiIdsList(),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Bottom action bar
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceHeader(double available) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F1B4D), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available Wallet Balance',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                WalletService.formatAmount(available),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.flash_on_rounded, color: Colors.amber, size: 16),
                SizedBox(width: 4),
                Text(
                  'Instant IMPS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountInputCard(double available) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Withdrawal Amount',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    _amountController.text = available.toInt().toString();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Withdraw All',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _blue,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                '₹',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                    letterSpacing: -0.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Min ₹100 • Max ${WalletService.formatAmount(available)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ---- Bank Accounts List ----
  Widget _buildBankAccountsList() {
    final banks = _walletService.savedBankAccounts;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (banks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.account_balance_outlined, size: 36, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    const Text(
                      'No Bank Accounts Linked',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _navy),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add your bank account below to receive payouts.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            )
          else
            ...banks.map((bank) {
            final isSelected = _selectedBankAccountId == bank.id;

            return ListTile(
              onTap: () => setState(() => _selectedBankAccountId = bank.id),
              leading: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFE3F2FD),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_rounded, color: _blue, size: 22),
              ),
              title: Text(
                bank.bankName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${bank.maskedAccountNumber} • IFSC: ${bank.ifscCode}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Text(
                    bank.accountHolderName,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
              trailing: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                color: isSelected ? _blue : Colors.grey.shade400,
                size: 22,
              ),
            );
          }),

          const Divider(height: 1),

          // Add New Bank Account Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: _showAddBankAccountDialog,
              child: const Row(
                children: [
                  Icon(Icons.add_circle_outline, color: _blue, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Add New Bank Account',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _blue,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- UPI IDs List ----
  Widget _buildUpiIdsList() {
    final upis = _walletService.savedUpiIds;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (upis.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.alternate_email_rounded, size: 36, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    const Text(
                      'No UPI IDs Saved',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _navy),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add your UPI ID below for instant transfers.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            )
          else
            ...upis.map((upi) {
            final isSelected = _selectedUpiId == upi.id;

            return ListTile(
              onTap: () => setState(() => _selectedUpiId = upi.id),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.alternate_email_rounded, color: Color(0xFF0E8A6A), size: 22),
              ),
              title: Text(
                upi.upiId,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
              subtitle: Text(
                upi.label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              trailing: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                color: isSelected ? _blue : Colors.grey.shade400,
                size: 22,
              ),
            );
          }),

          const Divider(height: 1),

          // Add New UPI ID Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: _showAddUpiIdDialog,
              child: const Row(
                children: [
                  Icon(Icons.add_circle_outline, color: _blue, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Add New UPI ID',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _blue,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Bottom Proceed Bar ----
  Widget _buildBottomBar() {
    final amount = _enteredAmount;
    final available = _walletService.balance;
    final isEnabled = amount >= 100 && amount <= available;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Withdrawal Amount',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                WalletService.formatAmount(amount),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: FilledButton(
              onPressed: isEnabled ? _onProceed : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Withdraw Funds',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Add New Bank Account Dialog ----
  void _showAddBankAccountDialog() {
    final holderNameController = TextEditingController();
    final accNumberController = TextEditingController();
    final confirmAccController = TextEditingController();
    final ifscController = TextEditingController();
    final bankNameController = TextEditingController();

    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void detectBankFromIfsc(String ifsc) {
              final upper = ifsc.toUpperCase().trim();
              if (upper.startsWith('HDFC')) {
                bankNameController.text = 'HDFC Bank';
              } else if (upper.startsWith('SBIN')) {
                bankNameController.text = 'State Bank of India';
              } else if (upper.startsWith('ICIC')) {
                bankNameController.text = 'ICICI Bank';
              } else if (upper.startsWith('UTIB')) {
                bankNameController.text = 'Axis Bank';
              } else if (upper.startsWith('KKBK')) {
                bankNameController.text = 'Kotak Mahindra Bank';
              }
              setModalState(() {});
            }

            return Container(
              height: MediaQuery.of(modalCtx).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(modalCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Add Bank Account',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(modalCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (errorText != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          errorText!,
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Account holder name
                    TextField(
                      controller: holderNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Account Holder Name',
                        hintText: 'As per bank records',
                        prefixIcon: const Icon(Icons.person_outline),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Account number
                    TextField(
                      controller: accNumberController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Bank Account Number',
                        hintText: 'Enter account number',
                        prefixIcon: const Icon(Icons.account_balance_outlined),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Confirm account number
                    TextField(
                      controller: confirmAccController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Confirm Account Number',
                        hintText: 'Re-enter account number',
                        prefixIcon: const Icon(Icons.lock_outline),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // IFSC Code
                    TextField(
                      controller: ifscController,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(11),
                      ],
                      onChanged: detectBankFromIfsc,
                      decoration: InputDecoration(
                        labelText: 'IFSC Code',
                        hintText: 'e.g. HDFC0000128',
                        prefixIcon: const Icon(Icons.numbers_rounded),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Bank Name
                    TextField(
                      controller: bankNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Bank Name',
                        hintText: 'e.g. HDFC Bank, SBI',
                        prefixIcon: const Icon(Icons.domain_rounded),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final holder = holderNameController.text.trim();
                          final acc = accNumberController.text.trim();
                          final confirm = confirmAccController.text.trim();
                          final ifsc = ifscController.text.trim().toUpperCase();
                          final bankName = bankNameController.text.trim();

                          if (holder.isEmpty) {
                            setModalState(() => errorText = 'Please enter account holder name');
                            return;
                          }
                          if (acc.length < 8) {
                            setModalState(() => errorText = 'Please enter a valid bank account number');
                            return;
                          }
                          if (acc != confirm) {
                            setModalState(() => errorText = 'Account numbers do not match');
                            return;
                          }
                          final ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
                          if (!ifscRegex.hasMatch(ifsc)) {
                            setModalState(() => errorText = 'Please enter a valid 11-digit IFSC code');
                            return;
                          }
                          if (bankName.isEmpty) {
                            setModalState(() => errorText = 'Please enter bank name');
                            return;
                          }

                          final newBa = BankAccount(
                            id: '',
                            accountHolderName: holder,
                            accountNumber: acc,
                            ifscCode: ifsc,
                            bankName: bankName,
                          );

                          try {
                            final saved = await _walletService.addBankAccount(newBa);
                            if (!mounted) return;
                            setState(() {
                              _selectedBankAccountId = saved.id;
                            });

                            if (modalCtx.mounted) {
                              Navigator.of(modalCtx).pop();
                            }

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Bank account ($bankName •••• ${acc.substring(acc.length - 4)}) linked successfully.'),
                                  backgroundColor: const Color(0xFF0E8A6A),
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() => errorText = 'Failed to link account: $e');
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _navy,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Verify & Save Bank Account'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---- Add New UPI ID Dialog ----
  void _showAddUpiIdDialog() {
    final upiController = TextEditingController();
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(modalCtx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add UPI ID for Withdrawal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _navy,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(modalCtx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (errorText != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        errorText!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  TextField(
                    controller: upiController,
                    decoration: InputDecoration(
                      labelText: 'UPI ID / VPA',
                      hintText: 'e.g. mobile@upi or username@okhdfcbank',
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                      filled: true,
                      fillColor: _bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Quick Handle Suggestions
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['@okhdfcbank', '@okaxis', '@oksbi', '@paytm', '@ybl'].map((h) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              final current = upiController.text;
                              final name = current.contains('@') ? current.split('@')[0] : current;
                              upiController.text = '$name$h';
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                h,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final val = upiController.text.trim();
                        final regex = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$');
                        if (!regex.hasMatch(val)) {
                          setModalState(() => errorText = 'Please enter a valid UPI ID (e.g. name@bank)');
                          return;
                        }

                        final newUpi = SavedUpiId(
                          id: '',
                          upiId: val,
                          label: 'Saved UPI',
                        );

                        try {
                          final saved = await _walletService.addUpiId(newUpi);
                          if (!mounted) return;
                          setState(() {
                            _selectedUpiId = saved.id;
                          });

                          if (modalCtx.mounted) {
                            Navigator.of(modalCtx).pop();
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('UPI ID ($val) saved successfully.'),
                                backgroundColor: const Color(0xFF0E8A6A),
                              ),
                            );
                          }
                        } catch (e) {
                          setModalState(() => errorText = 'Failed to save UPI ID: $e');
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _navy,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Verify & Save UPI ID'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
