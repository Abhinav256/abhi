import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'api_service.dart';
import 'session_service.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal() {
    // Purge any legacy device-global credentials to prevent cross-account leaks
    cleanupLegacyGlobalKeys();
  }

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final LocalAuthentication _localAuth = LocalAuthentication();
  final ApiService _apiService = ApiService();
  final SessionService _sessionService = SessionService();

  // ---------------------------------------------------------------------------
  // USER-SCOPED STORAGE KEY GENERATORS
  // ---------------------------------------------------------------------------

  String _keyPinHash(String userId) => 'user_${userId}_pin_hash';
  String _keyPinSalt(String userId) => 'user_${userId}_pin_salt';
  String _keyBiometricEnabled(String userId) => 'user_${userId}_biometric_enabled';
  String _keyUserEmail(String userId) => 'user_${userId}_email';
  String _keyUserPhone(String userId) => 'user_${userId}_phone';

  Future<String?> _resolveUserId(String? userId) async {
    if (userId != null && userId.isNotEmpty) return userId;
    return await _sessionService.getUserId();
  }

  Future<void> cleanupLegacyGlobalKeys() async {
    try {
      await _storage.delete(key: 'abhishare_pin_hash');
      await _storage.delete(key: 'abhishare_pin_salt');
      await _storage.delete(key: 'abhishare_biometric_enabled');
      await _storage.delete(key: 'abhishare_user_email');
      await _storage.delete(key: 'abhishare_user_phone');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // PIN MANAGEMENT (ISOLATED PER USER ACCOUNT)
  // ---------------------------------------------------------------------------

  /// Sets a new numeric PIN strictly for the given user account.
  /// Validated and encrypted with Argon2id in the backend database.
  /// Also stores salted SHA-256 in secure device hardware (Keychain/Keystore) scoped to this user.
  Future<void> setPin(String pin, {String? userId}) async {
    final uid = await _resolveUserId(userId);
    if (uid == null) {
      throw Exception('Cannot set PIN without an authenticated user ID.');
    }

    // 1. Encrypt and save in database via backend
    try {
      await _apiService.setPIN(pin: pin);
    } catch (e) {
      debugPrint('Backend setPIN warning: $e');
    }

    // 2. Also keep user-scoped salted hash in secure device storage for offline resilience
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);

    await _storage.write(key: _keyPinSalt(uid), value: salt);
    await _storage.write(key: _keyPinHash(uid), value: hash);
  }

  /// Verifies entered PIN against backend database (Argon2id) for this user.
  /// Falls back to user-scoped local secure storage if offline.
  Future<bool> verifyPin(String enteredPin, {String? userId}) async {
    final uid = await _resolveUserId(userId);
    if (uid == null) {
      return false;
    }

    // 1. Primary verification through backend DB for authenticated session
    try {
      final isValid = await _apiService.verifyPIN(pin: enteredPin);
      return isValid;
    } catch (e) {
      debugPrint('Backend PIN verification unavailable or failed: $e, falling back to user-scoped storage');
    }

    // 2. Hardware-backed user-scoped fallback check
    final salt = await _storage.read(key: _keyPinSalt(uid));
    final storedHash = await _storage.read(key: _keyPinHash(uid));

    if (salt == null || storedHash == null) {
      return false;
    }

    final enteredHash = _hashPin(enteredPin, salt);
    return enteredHash == storedHash;
  }

  /// Checks if a PIN has been set for this specific user.
  /// Never allows another account's PIN state to be returned.
  Future<bool> hasPin({String? userId, bool? backendHasPin}) async {
    // If backend explicitly provided has_pin for this user, respect server authority!
    if (backendHasPin != null) {
      return backendHasPin;
    }

    final uid = await _resolveUserId(userId);
    if (uid == null) {
      return false;
    }

    // Query backend for active user profile if possible
    try {
      final user = await _apiService.getCurrentUser();
      if (user['id']?.toString() == uid && user.containsKey('has_pin')) {
        return user['has_pin'] == true;
      }
    } catch (_) {}

    // Check user-scoped local secure storage
    final storedHash = await _storage.read(key: _keyPinHash(uid));
    return storedHash != null && storedHash.isNotEmpty;
  }

  /// Clears stored PIN data for the given user.
  Future<void> clearPin({String? userId}) async {
    final uid = await _resolveUserId(userId);
    if (uid != null) {
      await _storage.delete(key: _keyPinHash(uid));
      await _storage.delete(key: _keyPinSalt(uid));
    }
  }

  // ---------------------------------------------------------------------------
  // BIOMETRIC MANAGEMENT (ISOLATED PER USER ACCOUNT)
  // ---------------------------------------------------------------------------

  /// Checks if biometric login is enabled for THIS specific user on this device.
  /// If User B has never enabled biometric, this strictly returns false.
  Future<bool> isBiometricEnabled({String? userId}) async {
    final uid = await _resolveUserId(userId);
    if (uid == null) {
      return false;
    }

    final val = await _storage.read(key: _keyBiometricEnabled(uid));
    return val == 'true';
  }

  /// Sets whether biometric login is enabled for THIS specific user.
  Future<void> setBiometricEnabled(bool enabled, {String? userId}) async {
    final uid = await _resolveUserId(userId);
    if (uid == null) {
      throw Exception('Cannot configure biometric without an authenticated user ID.');
    }

    await _storage.write(
      key: _keyBiometricEnabled(uid),
      value: enabled ? 'true' : 'false',
    );
  }

  /// Checks if device has biometric hardware and support.
  Future<bool> canCheckBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics.timeout(
        const Duration(milliseconds: 1500),
      );
      final isSupported = await _localAuth.isDeviceSupported().timeout(
        const Duration(milliseconds: 1500),
      );
      return canCheck && isSupported;
    } catch (e) {
      debugPrint('Error checking biometric support: $e');
      return false;
    }
  }

  /// Retrieves available biometric types (Face ID, Fingerprint, etc.).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics().timeout(
        const Duration(milliseconds: 1500),
      );
    } catch (e) {
      debugPrint('Error getting available biometrics: $e');
      return [];
    }
  }

  /// Returns user-friendly name of the biometric type on this device.
  Future<String> getBiometricTypeLabel() async {
    try {
      final biometrics = await getAvailableBiometrics();
      if (biometrics.contains(BiometricType.face)) {
        return 'Face ID';
      } else if (biometrics.contains(BiometricType.fingerprint)) {
        return 'Fingerprint';
      } else if (biometrics.contains(BiometricType.iris)) {
        return 'Iris Scan';
      }
    } catch (_) {}
    return 'Biometrics';
  }

  /// Performs native OS biometric authentication.
  /// Returns true on success, false on cancel, failure, or unavailability.
  Future<bool> authenticateWithBiometrics({
    String reason = 'Authenticate to access AbhiShare',
  }) async {
    try {
      final canAuthenticate = await canCheckBiometrics();
      if (!canAuthenticate) return false;

      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('Biometric authentication failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // USER CONTACT INFO (FOR FORGOT PIN RECOVERY, ISOLATED PER USER)
  // ---------------------------------------------------------------------------

  Future<void> saveUserContactInfo({
    String? userId,
    String? email,
    String? phone,
  }) async {
    final uid = await _resolveUserId(userId);
    if (uid == null) return;

    if (email != null && email.isNotEmpty) {
      await _storage.write(key: _keyUserEmail(uid), value: email);
    }
    if (phone != null && phone.isNotEmpty) {
      await _storage.write(key: _keyUserPhone(uid), value: phone);
    }
  }

  Future<String?> getUserEmail({String? userId}) async {
    final uid = await _resolveUserId(userId);
    if (uid == null) return null;
    return await _storage.read(key: _keyUserEmail(uid));
  }

  Future<String?> getUserPhone({String? userId}) async {
    final uid = await _resolveUserId(userId);
    if (uid == null) return null;
    return await _storage.read(key: _keyUserPhone(uid));
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  String _generateSalt() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Encode(values);
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }
}
