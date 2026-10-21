import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/razorpay_service.dart';
import '../services/wallet_service.dart';
import '../screens/railone_payment_screen.dart';

/// Modal bottom sheet popup asking the user how much money to add to their wallet,
/// offering quick suggestion chips (+100, +200, +500, +1000), and a "Proceed to Pay" button
/// that directly transitions into the RailOne payment gateway page.
class AddMoneyBottomSheet extends StatefulWidget {
  final double? initialAmount;
  final ApiService? apiService;
  final WalletService? walletService;
  final RazorpayService? razorpayService;
  final void Function(double amount)? onProceed;

  const AddMoneyBottomSheet({
    super.key,
    this.initialAmount,
    this.apiService,
    this.walletService,
    this.razorpayService,
    this.onProceed,
  });

  @override
  State<AddMoneyBottomSheet> createState() => _AddMoneyBottomSheetState();
}

class _AddMoneyBottomSheetState extends State<AddMoneyBottomSheet> {
  static const Color _navy = Color(0xFF0B1B3B);
  static const Color _blue = Color(0xFF0B4FD8);
  static const Color _bg = Color(0xFFF3F7FD);

  late final TextEditingController _amountController;
  final List<double> _quickSuggestions = const [100, 200, 500, 1000];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialAmount != null && widget.initialAmount! > 0
        ? widget.initialAmount!.toInt().toString()
        : '100';
    _amountController = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _enteredAmount {
    return double.tryParse(_amountController.text.trim()) ?? 0.0;
  }

  void _handleSuggestionTap(double amt) {
    setState(() {
      _amountController.text = amt.toInt().toString();
    });
  }

  Future<void> _handleProceed() async {
    final amount = _enteredAmount;
    if (amount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimum amount to add is ₹10'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (amount > 50000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum top-up limit per transaction is ₹50,000'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (widget.onProceed != null) {
      widget.onProceed!(amount);
      return;
    }

    // Default flow: close bottom sheet and push RailOnePaymentScreen
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(true);
    }
    final booked = await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => RailOnePaymentScreen.forWallet(
          amount: amount,
          apiService: widget.apiService,
          walletService: widget.walletService,
          razorpayService: widget.razorpayService,
        ),
      ),
    );

    if (booked == true) {
      final ws = widget.walletService ?? WalletService.instance;
      await ws.refreshFromBackend();
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _enteredAmount;
    final isEnabled = amount >= 10;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Money to Wallet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'How much would you like to add?',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: Colors.grey.shade600,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Large Amount Input Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  '₹',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    autofocus: widget.initialAmount == null,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: const TextStyle(
                      fontSize: 32,
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
                if (_amountController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    color: Colors.grey.shade500,
                    onPressed: () {
                      setState(() {
                        _amountController.clear();
                      });
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Suggestion Chips (+100, +200, +500, +1000)
          Row(
            children: _quickSuggestions.map((amt) {
              final isSelected = amount == amt;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _handleSuggestionTap(amt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? _blue : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? _blue : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '+₹${amt.toInt()}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : _navy,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Trust & Security badge
          Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  size: 15, color: Color(0xFF0E8A6A)),
              const SizedBox(width: 6),
              Text(
                'Zero convenience fee • 100% secure payments via Razorpay',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Proceed to Pay button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: isEnabled ? _handleProceed : null,
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Proceed to Pay',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded,
                      size: 18, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
