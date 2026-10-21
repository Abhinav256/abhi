import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:abhi_share/screens/passcode_login_screen.dart';
import 'package:abhi_share/screens/pin_setup_screen.dart';
import 'package:abhi_share/screens/unlock_screen.dart';
import 'package:abhi_share/services/security_service.dart';
import 'package:abhi_share/services/session_service.dart';

class FakeLocalAuthPlatform extends LocalAuthPlatform {
  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async => false;

  @override
  Future<bool> deviceSupportsBiometrics() async => true;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => [BiometricType.fingerprint];

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> stopAuthentication() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    LocalAuthPlatform.instance = FakeLocalAuthPlatform();
    await SessionService().saveSession(sessionToken: 'test_token', userId: 'user_123');
  });

  group('PinSetupScreen Tests', () {
    testWidgets('PIN setup flow with confirmation mismatch and success', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: PinSetupScreen(isReset: false),
        ),
      );
      await tester.pump();

      // Verify initial state: Set Your PIN
      expect(find.text('Set Your PIN'), findsOneWidget);
      expect(find.text('PIN Security'), findsOneWidget);

      // Tap digits 1, 2, 3, 4
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pump(const Duration(milliseconds: 300));

      // Should transition to Confirm Your PIN
      expect(find.text('Confirm Your PIN'), findsOneWidget);

      // Enter mismatching PIN: 1, 2, 3, 5
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('5'));
      await tester.pump(const Duration(milliseconds: 500)); // drain shake animation

      // Expect error: PINs do not match
      expect(find.text('PINs do not match'), findsOneWidget);

      // Now enter matching PIN: 1, 2, 3, 4
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));

      // PIN should now be stored securely
      final securityService = SecurityService();
      expect(await securityService.hasPin(), isTrue);
      expect(await securityService.verifyPin('1234'), isTrue);
    });
  });

  group('UnlockScreen Tests', () {
    testWidgets('UnlockScreen shows Enter your PIN and Forgot PIN above numpad', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final securityService = SecurityService();
      await securityService.setPin('1234');
      await securityService.saveUserContactInfo(
        email: 'test@example.com',
        phone: '+919999988888',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: UnlockScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.text('Forgot PIN?'), findsOneWidget);

      // Tap 'Forgot PIN?'
      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();

      // Verify bottom sheet appears with exact requirements
      expect(find.text('Send OTP to your email address?'), findsOneWidget);
      expect(find.text('Send OTP'), findsOneWidget);
      expect(find.text('No, send to mobile number'), findsOneWidget);

      // Tap 'No, send to mobile number'
      await tester.tap(find.text('No, send to mobile number'));
      await tester.pumpAndSettle();

      // Verify mobile recovery sheet appears
      expect(find.text('Send OTP to your mobile number?'), findsOneWidget);
    });

    testWidgets('UnlockScreen with pre-resolved initialUserId renders immediately without loading screen', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: UnlockScreen(
            initialUserId: 'user_123',
            initialIsBiometricEnabled: false,
            initialHasBiometrics: false,
          ),
        ),
      );
      // On the first frame without pumpAndSettle, PIN screen is rendered with NO spinner
      await tester.pump();

      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Multi-account isolation: User B without PIN is redirected to PinSetupScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // User A configured PIN
      final sessionService = SessionService();
      final securityService = SecurityService();
      await sessionService.saveSession(sessionToken: 'token_a', userId: 'user_a_9030108602');
      await securityService.setPin('2244');
      await securityService.setBiometricEnabled(true);

      // User A logs out
      await sessionService.clearSession();

      // User B logs in (has no PIN configured)
      await sessionService.saveSession(sessionToken: 'token_b', userId: 'user_b_9030108603');

      // Attempting to open UnlockScreen with User B's session redirects to PinSetupScreen
      await tester.pumpWidget(
        const MaterialApp(
          home: UnlockScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify that User B is now on Set Your PIN screen and NOT on UnlockScreen
      expect(find.text('Set Your PIN'), findsOneWidget);
      expect(find.text('Enter your PIN'), findsNothing);
    });
  });

  group('PasscodeLoginScreen Tests', () {
    testWidgets('PasscodeLoginScreen shows Enter Passcode and Reset Passcode button', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: PasscodeLoginScreen(
            identifier: '9876543210',
            identifierType: 'phone',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter Passcode'), findsOneWidget);
      expect(find.text('Reset Passcode'), findsOneWidget);
      expect(find.textContaining('987****210'), findsOneWidget);

      // Tap key 1
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();

      // Check keypad digits exist
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('PasscodeLoginScreen displays email masking correctly', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: PasscodeLoginScreen(
            identifier: 'testuser@gmail.com',
            identifierType: 'email',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter Passcode'), findsOneWidget);
      expect(find.text('Reset Passcode'), findsOneWidget);
      expect(find.textContaining('te***r@gmail.com'), findsOneWidget);
    });

    testWidgets('PasscodeLoginScreen displays account locked state properly', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: PasscodeLoginScreen(
            identifier: '9876543210',
            identifierType: 'phone',
            isInitiallyLocked: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Account Locked'), findsOneWidget);
      expect(find.text('Verify with OTP to Unlock'), findsOneWidget);
      expect(find.text('Enter Passcode'), findsNothing);
    });
  });
}
