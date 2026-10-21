import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abhi_share/models/wallet_models.dart';
import 'package:abhi_share/screens/refer_and_earn_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Refer and Earn Tests', () {
    test('TransactionType.referralReward properties and mapping', () {
      final type = TransactionType.fromString('referral_reward');
      expect(type, TransactionType.referralReward);
      expect(type.displayName, 'Referral Reward');
      expect(type.code, 'referral_reward');
      expect(type.isCredit, true);
      expect(type.icon, Icons.card_giftcard_rounded);
    });

    testWidgets('ReferAndEarnScreen renders initial loading state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ReferAndEarnScreen(),
        ),
      );

      expect(find.text('Refer & Earn'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
