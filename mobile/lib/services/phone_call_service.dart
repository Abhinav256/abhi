import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Direct cellular phone calling service for AbhiShare.
///
/// Initiates real phone calls through the device's native dialler (`tel:` URI).
/// Does NOT use VoIP, WebRTC, telephony proxies, or masked numbers.
class PhoneCallService {
  PhoneCallService._();

  /// Normalizes a phone number by stripping whitespace, dashes, brackets,
  /// and invalid characters while preserving any leading '+' country code.
  static String normalizePhoneNumber(String? rawNumber) {
    if (rawNumber == null) return '';
    final trimmed = rawNumber.trim();
    if (trimmed.isEmpty) return '';

    final hasPlus = trimmed.startsWith('+');
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) return '';

    return hasPlus ? '+$digitsOnly' : digitsOnly;
  }

  /// Validates whether a phone number has a realistic length (7-15 digits E.164).
  static bool isValidPhoneNumber(String? rawNumber) {
    final normalized = normalizePhoneNumber(rawNumber);
    final digits = normalized.replaceAll(RegExp(r'[^\d]'), '');
    return digits.length >= 7 && digits.length <= 15;
  }

  /// Checks if two phone numbers refer to the same device/account.
  static bool isSameNumber(String? phoneA, String? phoneB) {
    final a = normalizePhoneNumber(phoneA);
    final b = normalizePhoneNumber(phoneB);
    if (a.isEmpty || b.isEmpty) return false;

    if (a == b) return true;

    // Compare last 10 digits to handle local vs +91 international formatting
    final digitsA = a.replaceAll(RegExp(r'[^\d]'), '');
    final digitsB = b.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsA.length >= 10 && digitsB.length >= 10) {
      final last10A = digitsA.substring(digitsA.length - 10);
      final last10B = digitsB.substring(digitsB.length - 10);
      return last10A == last10B;
    }

    return false;
  }

  /// Opens the native phone dialler with [phoneNumber] prefilled.
  ///
  /// - [context]: BuildContext for displaying user feedback (SnackBars).
  /// - [phoneNumber]: The real registered phone number of the recipient.
  /// - [recipientName]: Friendly name of the recipient (e.g. driver/passenger name).
  /// - [currentUserPhone]: Optional phone of the logged-in user to prevent self-calls.
  ///
  /// Returns `true` if the dialler opened successfully, `false` otherwise.
  static Future<bool> makePhoneCall({
    required BuildContext context,
    required String? phoneNumber,
    String? recipientName,
    String? currentUserPhone,
  }) async {
    final normalized = normalizePhoneNumber(phoneNumber);

    if (normalized.isEmpty || !isValidPhoneNumber(normalized)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              recipientName != null && recipientName.isNotEmpty
                  ? 'Phone number for $recipientName is not available.'
                  : 'Phone number is not available or invalid.',
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    // Prevent accidental self-calling
    if (currentUserPhone != null && isSameNumber(normalized, currentUserPhone)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot place a call to your own registered phone number.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: normalized,
    );

    try {
      final canLaunch = await canLaunchUrl(phoneUri);
      if (canLaunch) {
        final launched = await launchUrl(
          phoneUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          return true;
        }
      }

      // If canLaunch is false or launchUrl failed (e.g. tablet/emulator without telephony)
      await Clipboard.setData(ClipboardData(text: normalized));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No phone dialler available on this device. Copied $normalized to clipboard.',
            ),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
            backgroundColor: Colors.blueGrey.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return false;
    } catch (e) {
      // In case of platform exception, provide fallback to clipboard
      await Clipboard.setData(ClipboardData(text: normalized));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open dialler. Copied $normalized to clipboard.',
            ),
            backgroundColor: Colors.blueGrey.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }
}
