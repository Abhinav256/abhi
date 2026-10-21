import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abhi_share/services/phone_call_service.dart';

void main() {
  group('PhoneCallService - Normalization & Validation', () {
    test('normalizePhoneNumber handles empty or null input', () {
      expect(PhoneCallService.normalizePhoneNumber(null), '');
      expect(PhoneCallService.normalizePhoneNumber(''), '');
      expect(PhoneCallService.normalizePhoneNumber('   '), '');
    });

    test('normalizePhoneNumber preserves leading plus and strips formatting', () {
      expect(
        PhoneCallService.normalizePhoneNumber('+91 98765-43210'),
        '+919876543210',
      );
      expect(
        PhoneCallService.normalizePhoneNumber('(080) 123-4567'),
        '0801234567',
      );
      expect(
        PhoneCallService.normalizePhoneNumber('+1 (555) 234-5678'),
        '+15552345678',
      );
    });

    test('isValidPhoneNumber validates E.164 length constraints', () {
      expect(PhoneCallService.isValidPhoneNumber('+919876543210'), isTrue);
      expect(PhoneCallService.isValidPhoneNumber('9876543210'), isTrue);
      expect(PhoneCallService.isValidPhoneNumber('1234567'), isTrue); // minimum 7 digits

      // Too short (< 7 digits)
      expect(PhoneCallService.isValidPhoneNumber('12345'), isFalse);
      expect(PhoneCallService.isValidPhoneNumber(''), isFalse);
      expect(PhoneCallService.isValidPhoneNumber(null), isFalse);

      // Too long (> 15 digits)
      expect(PhoneCallService.isValidPhoneNumber('1234567890123456'), isFalse);
    });

    test('isSameNumber correctly identifies identical numbers with formatting differences', () {
      expect(
        PhoneCallService.isSameNumber('+919876543210', '9876543210'),
        isTrue,
      );
      expect(
        PhoneCallService.isSameNumber('+91 98765 43210', '+91-98765-43210'),
        isTrue,
      );
      expect(
        PhoneCallService.isSameNumber('+919876543210', '+919123456789'),
        isFalse,
      );
      expect(
        PhoneCallService.isSameNumber(null, '9876543210'),
        isFalse,
      );
    });
  });

  group('PhoneCallService - Dialler Execution Safety', () {
    testWidgets('makePhoneCall prevents calling own registered phone number', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final result = await PhoneCallService.makePhoneCall(
        context: capturedContext,
        phoneNumber: '+919876543210',
        currentUserPhone: '9876543210',
      );

      expect(result, isFalse);
      await tester.pump();
      expect(find.text('Cannot place a call to your own registered phone number.'), findsOneWidget);
    });

    testWidgets('makePhoneCall rejects empty or invalid number with helpful feedback', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final result = await PhoneCallService.makePhoneCall(
        context: capturedContext,
        phoneNumber: '',
        recipientName: 'Abhinav',
      );

      expect(result, isFalse);
      await tester.pump();
      expect(find.text('Phone number for Abhinav is not available.'), findsOneWidget);
    });
  });
}
