import 'package:flutter/material.dart';

import '../services/api_service.dart';

const Color _kNavy = Color(0xFF08183A);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kMuted = Color(0xFF64748B);
const Color _kGreen = Color(0xFF10B981);

/// Shows a dialog to report a user.
/// Retains conversations in database indefinitely for safety & investigation.
Future<void> showReportUserDialog(
  BuildContext context, {
  required String targetUserId,
  required String targetUserName,
  String? rideId,
  String? conversationId,
  VoidCallback? onSuccess,
}) async {
  final api = ApiService();
  final reasons = [
    'Inappropriate messages / conduct',
    'Harassment or safety concern',
    'No-show / cancelled without notice',
    'Unsafe driving / vehicle issue',
    'Asking for off-app payment',
    'Other',
  ];
  String selectedReason = reasons[0];
  final descController = TextEditingController();
  bool isSubmitting = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.report_problem_outlined, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text(
              'Report User',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _kNavy,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reporting $targetUserName. Your report will be kept confidential and relevant ride history/messages will be preserved for investigation.',
                style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reason',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _kNavy,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: _kBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedReason,
                    items: reasons
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r, style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: isSubmitting
                        ? null
                        : (val) {
                            if (val != null) {
                              setDialogState(() => selectedReason = val);
                            }
                          },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Details (optional)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _kNavy,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: descController,
                enabled: !isSubmitting,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe what happened...',
                  hintStyle: const TextStyle(fontSize: 13, color: _kMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _kMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: isSubmitting
                ? null
                : () async {
                    setDialogState(() => isSubmitting = true);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await api.reportChatUser(
                        userId: targetUserId,
                        reason: selectedReason,
                        description: descController.text.trim(),
                        rideId: rideId,
                        conversationId: conversationId,
                      );
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Report submitted. Relevant records will be securely retained for review.',
                            ),
                            backgroundColor: _kGreen,
                          ),
                        );
                        onSuccess?.call();
                      }
                    } catch (e) {
                      setDialogState(() => isSubmitting = false);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            e.toString().replaceFirst('Exception: ', ''),
                          ),
                          backgroundColor: Colors.red.shade700,
                        ),
                      );
                    }
                  },
            child: isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit Report'),
          ),
        ],
      ),
    ),
  );
}

/// Shows a dialog to confirm blocking a user.
/// Retains conversations in database indefinitely for safety & investigation.
Future<void> showBlockUserConfirmation(
  BuildContext context, {
  required String targetUserId,
  required String targetUserName,
  VoidCallback? onSuccess,
}) async {
  final api = ApiService();
  bool isSubmitting = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text(
              'Block User',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _kNavy,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to block $targetUserName?\n\n'
          'They will not be able to message you or book your rides. Existing records will be retained for safety.',
          style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _kMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: isSubmitting
                ? null
                : () async {
                    setDialogState(() => isSubmitting = true);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await api.blockChatUser(userId: targetUserId);
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('$targetUserName has been blocked.'),
                            backgroundColor: _kNavy,
                          ),
                        );
                        onSuccess?.call();
                      }
                    } catch (e) {
                      setDialogState(() => isSubmitting = false);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            e.toString().replaceFirst('Exception: ', ''),
                          ),
                          backgroundColor: Colors.red.shade700,
                        ),
                      );
                    }
                  },
            child: isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Block User'),
          ),
        ],
      ),
    ),
  );
}
