import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/wallet_models.dart';
import '../services/wallet_service.dart';

class TransactionDetailScreen extends StatelessWidget {
  final WalletTransaction transaction;

  const TransactionDetailScreen({
    super.key,
    required this.transaction,
  });

  static const Color _navy = Color(0xFF0F1B4D);
  static const Color _blue = Color(0xFF0B6FE0);
  static const Color _bg = Color(0xFFF3F7FD);

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = transaction.status.color;
    final statusBg = transaction.status.badgeBg;
    final isCredit = transaction.isCredit;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'Transaction Details',
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // Receipt Container
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Top Receipt Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: transaction.type.backgroundColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              transaction.type.icon,
                              color: transaction.type.color,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            transaction.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _navy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            transaction.subtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Amount
                          Text(
                            '${isCredit ? '+' : '-'}${WalletService.formatAmount(transaction.amount)}',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: isCredit ? const Color(0xFF0E8A6A) : _navy,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(transaction.status.icon, size: 16, color: statusColor),
                                const SizedBox(width: 6),
                                Text(
                                  transaction.status.displayName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Perforated divider line
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: List.generate(
                          30,
                          (index) => Expanded(
                            child: Container(
                              height: 1.5,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              color: Colors.grey.shade300,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Receipt Info Rows
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow(
                            'Transaction ID',
                            transaction.id,
                            copyable: true,
                            context: context,
                          ),
                          const SizedBox(height: 14),
                          _buildDetailRow(
                            'Date & Time',
                            _formatDate(transaction.timestamp),
                          ),
                          const SizedBox(height: 14),
                          _buildDetailRow(
                            'Payment Mode',
                            transaction.paymentMethod,
                          ),
                          const SizedBox(height: 14),
                          _buildDetailRow(
                            'Reference / UTR',
                            transaction.referenceNumber,
                            copyable: true,
                            context: context,
                          ),
                          if (transaction.bankOrUpiInfo != null) ...[
                            const SizedBox(height: 14),
                            _buildDetailRow(
                              'Destination Info',
                              transaction.bankOrUpiInfo!,
                            ),
                          ],
                          if (transaction.failureReason != null) ...[
                            const SizedBox(height: 14),
                            _buildDetailRow(
                              'Failure Reason',
                              transaction.failureReason!,
                              textColor: const Color(0xFFDC2626),
                            ),
                          ],
                          const SizedBox(height: 14),
                          _buildDetailRow(
                            'Category',
                            transaction.category,
                          ),
                          const Divider(height: 28),
                          // Financial breakdown
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Amount',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                WalletService.formatAmount(transaction.amount),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _navy,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Convenience Fee',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const Text(
                                'FREE (₹0)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0E8A6A),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Net Transacted',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _navy,
                                ),
                              ),
                              Text(
                                WalletService.formatAmount(transaction.amount),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isCredit ? const Color(0xFF0E8A6A) : _navy,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Receipt downloaded to device.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      icon: const Icon(Icons.share_outlined, size: 20, color: _navy),
                      label: const Text(
                        'Share Receipt',
                        style: TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        _showSupportDialog(context);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.headset_mic_outlined, size: 20),
                      label: const Text(
                        'Need Help?',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool copyable = false,
    BuildContext? context,
    Color? textColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor ?? _navy,
                  ),
                ),
              ),
              if (copyable && context != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Copied $label: $value'),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Icon(
                    Icons.copy_rounded,
                    size: 15,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showSupportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transaction Support'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reference: ${transaction.referenceNumber}'),
            const SizedBox(height: 12),
            const Text(
              'If you have questions regarding this transaction, our 24x7 support team is here to help. Reach out to support@abhishare.com with your reference number.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Support request logged. We will contact you.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Contact Support'),
          ),
        ],
      ),
    );
  }
}
