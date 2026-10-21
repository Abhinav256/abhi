import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abhi_share/widgets/app_bottom_nav_bar.dart';
import 'package:abhi_share/screens/support_screen.dart';

void main() {
  group('AppBottomNavBar Tests', () {
    testWidgets('Renders exactly 5 items in the specified order with Wallet in the center', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(currentTab: AppNavTab.home),
          ),
        ),
      );

      // Verify all 5 tab labels exist
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Rides'), findsOneWidget);
      expect(find.text('Wallet'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      // Verify Alerts is NOT in the bottom bar
      expect(find.text('Alerts'), findsNothing);

      // Verify ordering from left to right: Home < Rides < Wallet < Support < Profile
      final homeOffset = tester.getCenter(find.text('Home')).dx;
      final ridesOffset = tester.getCenter(find.text('Rides')).dx;
      final walletOffset = tester.getCenter(find.text('Wallet')).dx;
      final supportOffset = tester.getCenter(find.text('Support')).dx;
      final profileOffset = tester.getCenter(find.text('Profile')).dx;

      expect(homeOffset < ridesOffset, isTrue);
      expect(ridesOffset < walletOffset, isTrue);
      expect(walletOffset < supportOffset, isTrue);
      expect(supportOffset < profileOffset, isTrue);

      // Verify icons
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.directions_car_outlined), findsOneWidget);
      expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
      expect(find.byIcon(Icons.support_agent_rounded), findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    });

    testWidgets('Tapping on a tab invokes onTabSelected callback', (tester) async {
      AppNavTab? selectedTab;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(
              currentTab: AppNavTab.home,
              onTabSelected: (tab) {
                selectedTab = tab;
              },
            ),
          ),
        ),
      );

      // Tap Wallet
      await tester.tap(find.text('Wallet'));
      await tester.pumpAndSettle();
      expect(selectedTab, AppNavTab.wallet);

      // Tap Support
      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      expect(selectedTab, AppNavTab.support);
    });
  });

  group('SupportScreen Tests', () {
    testWidgets('Displays Support heading and "How can I help you?" prominently', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SupportScreen(),
        ),
      );

      // Verify page heading
      expect(find.text('Support'), findsWidgets); // Heading + Bottom Bar item

      // Verify prominent message
      expect(find.text('How can I help you?'), findsOneWidget);

      // Verify Support tab is selected in bottom bar
      expect(find.byType(AppBottomNavBar), findsOneWidget);
      final navBar = tester.widget<AppBottomNavBar>(find.byType(AppBottomNavBar));
      expect(navBar.currentTab, AppNavTab.support);
    });
  });
}
