import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abhi_share/services/security_service.dart';
import 'package:abhi_share/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('SecurityService User Isolation Tests', () {
    final securityService = SecurityService();
    final sessionService = SessionService();

    test('Initial state: hasPin is false, isBiometricEnabled is false', () async {
      await sessionService.saveSession(sessionToken: 'token_a', userId: 'user_a');
      expect(await securityService.hasPin(), isFalse);
      expect(await securityService.isBiometricEnabled(), isFalse);
    });

    test('Set and verify correct PIN for user_a', () async {
      await sessionService.saveSession(sessionToken: 'token_a', userId: 'user_a');
      await securityService.setPin('2244');

      expect(await securityService.hasPin(), isTrue);
      expect(await securityService.verifyPin('2244'), isTrue);
      expect(await securityService.verifyPin('0000'), isFalse);
    });

    test('Multi-account isolation: User A credentials do NOT leak to User B', () async {
      // 1. User A (9030108602) logs in, sets PIN 2244, enables biometrics
      await sessionService.saveSession(sessionToken: 'token_a', userId: 'user_a_9030108602');
      await securityService.setPin('2244');
      await securityService.setBiometricEnabled(true);
      await securityService.saveUserContactInfo(
        email: 'user_a@example.com',
        phone: '9030108602',
      );

      // Verify User A has PIN, biometric enabled, and contact info
      expect(await securityService.hasPin(), isTrue);
      expect(await securityService.isBiometricEnabled(), isTrue);
      expect(await securityService.verifyPin('2244'), isTrue);
      expect(await securityService.getUserPhone(), equals('9030108602'));

      // 2. User A logs out
      await sessionService.clearSession();

      // 3. User B (9030108603) logs in via OTP. User B has never configured PIN/biometrics.
      await sessionService.saveSession(sessionToken: 'token_b', userId: 'user_b_9030108603');

      // CRITICAL ASSERTIONS: User B MUST NOT have User A's PIN or biometrics
      expect(await securityService.hasPin(), isFalse,
          reason: 'User B must not inherit User A PIN');
      expect(await securityService.isBiometricEnabled(), isFalse,
          reason: 'User B must not inherit User A biometric enabled state');
      expect(await securityService.verifyPin('2244'), isFalse,
          reason: 'User B must not be unlockable with User A PIN 2244');
      expect(await securityService.getUserPhone(), isNull,
          reason: 'User B must not see User A contact info');

      // 4. User B sets their own PIN 9999 and skips biometric
      await securityService.setPin('9999');
      await securityService.setBiometricEnabled(false);
      await securityService.saveUserContactInfo(
        phone: '9030108603',
        email: 'user_b@example.com',
      );

      expect(await securityService.hasPin(), isTrue);
      expect(await securityService.verifyPin('9999'), isTrue);
      expect(await securityService.verifyPin('2244'), isFalse,
          reason: 'User B must not accept User A PIN');
      expect(await securityService.isBiometricEnabled(), isFalse);

      // 5. User B logs out, User A logs back in
      await sessionService.clearSession();
      await sessionService.saveSession(sessionToken: 'token_a2', userId: 'user_a_9030108602');

      // User A still has their PIN 2244 and biometric enabled!
      expect(await securityService.hasPin(), isTrue);
      expect(await securityService.verifyPin('2244'), isTrue);
      expect(await securityService.verifyPin('9999'), isFalse,
          reason: 'User A must not accept User B PIN');
      expect(await securityService.isBiometricEnabled(), isTrue);
      expect(await securityService.getUserPhone(), equals('9030108602'));
    });

    test('Server authoritative has_pin flag is strictly honored', () async {
      // If server returns backendHasPin: false, hasPin returns false even if local cache exists
      await sessionService.saveSession(sessionToken: 'token_b', userId: 'user_b');
      expect(await securityService.hasPin(backendHasPin: false), isFalse);
      expect(await securityService.hasPin(backendHasPin: true), isTrue);
    });

    test('Purges legacy global credentials', () async {
      const storage = FlutterSecureStorage();
      await storage.write(key: 'abhishare_pin_hash', value: 'stale_global_hash');
      await storage.write(key: 'abhishare_biometric_enabled', value: 'true');

      // Purge legacy keys
      await securityService.cleanupLegacyGlobalKeys();

      expect(await storage.read(key: 'abhishare_pin_hash'), isNull);
      expect(await storage.read(key: 'abhishare_biometric_enabled'), isNull);
    });
  });
}
