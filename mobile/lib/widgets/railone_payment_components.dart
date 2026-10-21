import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Clean horizontal dashed line divider matching the RailOne payment design.
class DashedDivider extends StatelessWidget {
  final double height;
  final Color color;
  final double dashWidth;
  final double dashSpace;
  final double thickness;

  const DashedDivider({
    super.key,
    this.height = 1,
    this.color = const Color(0xFFE2E8F0),
    this.dashWidth = 4.0,
    this.dashSpace = 3.0,
    this.thickness = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _DashedLinePainter(
          color: color,
          dashWidth: dashWidth,
          dashSpace: dashSpace,
          thickness: thickness,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;
  final double thickness;

  _DashedLinePainter({
    required this.color,
    required this.dashWidth,
    required this.dashSpace,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke;

    double startX = 0;
    final y = size.height / 2;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, y),
        Offset(startX + dashWidth, y),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.dashWidth != dashWidth ||
        oldDelegate.dashSpace != dashSpace ||
        oldDelegate.thickness != thickness;
  }
}

/// RailOne-style blue top banner with back navigation, AbhiShare branding,
/// and the floating summary card displaying Order ID and dynamic Total Amount.
class RailOneHeader extends StatelessWidget {
  final String orderId;
  final double amount;
  final VoidCallback onBack;
  final bool showFloatingCard;

  static const Color headerBlue = Color(0xFF1E60E8);

  const RailOneHeader({
    super.key,
    required this.orderId,
    required this.amount,
    required this.onBack,
    this.showFloatingCard = true,
  });

  static String formatCurrency(double val) {
    return '₹${val.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: headerBlue,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        showFloatingCard ? 20 : 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Navigation & Branding Row
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.directions_car_rounded,
                  color: headerBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'AbhiShare',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),

          if (showFloatingCard) ...[
            const SizedBox(height: 18),
            // Floating Summary Card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Column(
                children: [
                  // Order ID row with copy icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Order ID',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: orderId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Order ID copied to clipboard'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Text(
                              orderId,
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                color: Color(0xFF1E293B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.copy_rounded,
                              size: 15,
                              color: Colors.grey.shade500,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Total Amount row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Amount',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        formatCurrency(amount),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Screen F — Payment Processing Fee bottom sheet matching reference 8.png
class PaymentFeeBottomSheet extends StatelessWidget {
  final double amount;
  final double fee;
  final double gst;
  final VoidCallback onProceed;
  final VoidCallback onCancel;
  final bool isProcessing;

  const PaymentFeeBottomSheet({
    super.key,
    required this.amount,
    required this.fee,
    required this.gst,
    required this.onProceed,
    required this.onCancel,
    this.isProcessing = false,
  });

  double get totalAmount => amount + fee + gst;

  static String format(double val) => '₹${val.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag indicator / Receipt Icon box
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: Color(0xFF1E60E8),
              size: 26,
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Payment Processing Fee',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'A fee as shown below will be charged in addition to transaction amount',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 22),

          // Fee rows
          _buildRow('Transaction Amount', format(amount)),
          const SizedBox(height: 10),
          _buildRow('Payment Processing Fee', format(fee)),
          const SizedBox(height: 10),
          _buildRow('GST on Payment Processing Fee @18.00%', format(gst)),
          const SizedBox(height: 14),
          const DashedDivider(dashWidth: 4, dashSpace: 3),
          const SizedBox(height: 14),
          _buildRow('Total Amount', format(totalAmount), isBold: true),

          const SizedBox(height: 28),

          // Proceed button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: isProcessing ? null : onProceed,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E60E8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                elevation: 0,
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Proceed',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // Cancel button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: isProcessing ? null : onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String title, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isBold ? 15 : 13,
            color: isBold ? const Color(0xFF0F172A) : Colors.grey.shade600,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 13,
            color: const Color(0xFF0F172A),
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Official styled brand icons and logos for payment methods.
class RailOneBrandLogos {
  /// UPI Logo Badge
  static Widget upiBadge({double height = 20}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(height * 0.9, height),
          painter: _UpiTrianglePainter(),
        ),
        const SizedBox(width: 6),
        Text(
          'UPI',
          style: TextStyle(
            fontSize: height * 0.85,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            color: const Color(0xFF0F172A),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// Mini app icons row displayed beside UPI header
  static Widget miniUpiAppsRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleLogo(const Color(0xFF00796B), 'B', Colors.white),
        const SizedBox(width: 4),
        _circleLogo(const Color(0xFF5F259F), 'पे', Colors.white),
        const SizedBox(width: 4),
        _circleLogo(const Color(0xFF4285F4), 'G', Colors.white),
        const SizedBox(width: 4),
        _circleLogo(const Color(0xFF00B9F5), 'P', Colors.white),
      ],
    );
  }

  /// Mini card network logos
  static Widget miniCardNetworksRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pillTextBadge('RuPay', const Color(0xFF097939)),
        const SizedBox(width: 4),
        _pillTextBadge('VISA', const Color(0xFF1A1F71)),
        const SizedBox(width: 4),
        _pillTextBadge('MC', const Color(0xFFEB001B)),
      ],
    );
  }

  /// Mini bank logos row
  static Widget miniBanksRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleLogo(const Color(0xFF0072BB), 'S', Colors.white),
        const SizedBox(width: 4),
        _circleLogo(const Color(0xFF97144D), 'A', Colors.white),
        const SizedBox(width: 4),
        _circleLogo(const Color(0xFF004C8F), 'H', Colors.white),
        const SizedBox(width: 4),
        _circleLogo(const Color(0xFFB02A30), 'I', Colors.white),
      ],
    );
  }

  /// App icon box for UPI Apps list
  static Widget appIcon(String appName) {
    switch (appName.toLowerCase()) {
      case 'bhim':
        return _styledAppBox(
          const Color(0xFF00796B),
          Icons.flash_on_rounded,
          'BHIM',
        );
      case 'google pay':
      case 'gpay':
        return _styledAppBox(
          const Color(0xFF4285F4),
          Icons.g_mobiledata_rounded,
          'GPay',
        );
      case 'phonepe':
        return _styledAppBox(
          const Color(0xFF5F259F),
          Icons.phone_android_rounded,
          'PhonePe',
        );
      case 'paytm':
        return _styledAppBox(
          const Color(0xFF00B9F5),
          Icons.account_balance_wallet_rounded,
          'Paytm',
        );
      case 'yono sbi':
      case 'sbi':
        return _styledAppBox(
          const Color(0xFF0072BB),
          Icons.account_balance_rounded,
          'SBI',
        );
      case 'cred':
        return _styledAppBox(
          const Color(0xFF111827),
          Icons.credit_card_rounded,
          'CRED',
        );
      case 'navi':
        return _styledAppBox(
          const Color(0xFF4338CA),
          Icons.trending_up_rounded,
          'Navi',
        );
      case 'mobikwik':
        return _styledAppBox(
          const Color(0xFF0284C7),
          Icons.mobile_friendly_rounded,
          'MobiKwik',
        );
      case 'super.money':
      case 'supermoney':
        return _styledAppBox(
          const Color(0xFF16A34A),
          Icons.currency_rupee_rounded,
          'super.money',
        );
      default:
        return _styledAppBox(
          const Color(0xFF1E60E8),
          Icons.payments_rounded,
          appName,
        );
    }
  }

  /// Bank logo box for Netbanking list
  static Widget bankLogo(String bankName) {
    Color color = const Color(0xFF1E60E8);
    String letter = 'B';
    if (bankName.contains('State Bank of India') || bankName.contains('SBI')) {
      color = const Color(0xFF0072BB);
      letter = 'SBI';
    } else if (bankName.contains('Axis')) {
      color = const Color(0xFF97144D);
      letter = 'AXIS';
    } else if (bankName.contains('HDFC')) {
      color = const Color(0xFF004C8F);
      letter = 'HDFC';
    } else if (bankName.contains('ICICI')) {
      color = const Color(0xFFB02A30);
      letter = 'ICICI';
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  static Widget _circleLogo(Color bg, String text, Color fg) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  static Widget _pillTextBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  static Widget _styledAppBox(Color color, IconData icon, String label) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// UPI Triangle double arrows painter
class _UpiTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final greenPaint = Paint()
      ..color = const Color(0xFF0E8A6A)
      ..style = PaintingStyle.fill;
    final orangePaint = Paint()
      ..color = const Color(0xFFF97316)
      ..style = PaintingStyle.fill;

    final path1 = Path()
      ..moveTo(0, size.height * 0.1)
      ..lineTo(size.width * 0.45, size.height * 0.5)
      ..lineTo(0, size.height * 0.9)
      ..close();
    canvas.drawPath(path1, greenPaint);

    final path2 = Path()
      ..moveTo(size.width * 0.45, size.height * 0.1)
      ..lineTo(size.width * 0.9, size.height * 0.5)
      ..lineTo(size.width * 0.45, size.height * 0.9)
      ..close();
    canvas.drawPath(path2, orangePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Footer showing "POWERED BY Razorpay" matching the RailOne screenshots.
class RailOneFooter extends StatelessWidget {
  const RailOneFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'POWERED BY',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFF1E60E8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 10,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Razorpay',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'TEST MODE',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Formats card numbers in groups of 4 digits: "XXXX XXXX XXXX XXXX"
class CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(' ', '');
    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      final nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != text.length && nonZeroIndex < 16) {
        buffer.write(' ');
      }
    }

    final formatted = buffer.toString();
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Formats expiration date as "MM/YY"
class CardExpiryInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll('/', '');
    if (text.length > 4) {
      text = text.substring(0, 4);
    }

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if (i == 1 && text.length > 2) {
        buffer.write('/');
      }
    }

    final formatted = buffer.toString();
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Secure validator for credit/debit card inputs adhering to PCI standards
class CardValidator {
  static bool isValidLuhn(String cardNumber) {
    final clean = cardNumber.replaceAll(RegExp(r'\s+'), '');
    if (clean.length < 13 || clean.length > 19) return false;
    int sum = 0;
    bool alternate = false;
    for (int i = clean.length - 1; i >= 0; i--) {
      int? n = int.tryParse(clean[i]);
      if (n == null) return false;
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  static String detectNetwork(String cardNumber) {
    final clean = cardNumber.replaceAll(RegExp(r'\s+'), '');
    if (clean.startsWith('4')) return 'Visa';
    if (clean.startsWith(RegExp(r'^(5[1-5]|222[1-9]|22[3-9]|2[3-6]|27[01]|2720)'))) {
      return 'Mastercard';
    }
    if (clean.startsWith(RegExp(r'^(60|65|81|82|508)'))) {
      return 'RuPay';
    }
    if (clean.startsWith(RegExp(r'^(34|37)'))) {
      return 'Amex';
    }
    return '';
  }

  static bool isValidExpiry(String expiry) {
    final parts = expiry.split('/');
    if (parts.length != 2) return false;
    final month = int.tryParse(parts[0]);
    final year = int.tryParse(parts[1]);
    if (month == null || year == null) return false;
    if (month < 1 || month > 12) return false;
    final now = DateTime.now();
    final currentYear = now.year % 100;
    final currentMonth = now.month;
    if (year < currentYear) return false;
    if (year == currentYear && month < currentMonth) return false;
    if (year > currentYear + 25) return false;
    return true;
  }

  static bool isValidCvv(String cvv, {String network = ''}) {
    final clean = cvv.trim();
    if (!RegExp(r'^\d+$').hasMatch(clean)) return false;
    if (network == 'Amex') {
      return clean.length == 4;
    }
    return clean.length == 3 || clean.length == 4;
  }
}

