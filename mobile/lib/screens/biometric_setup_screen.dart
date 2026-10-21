import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../services/security_service.dart';
import 'home_screen.dart';

class BiometricSetupScreen extends StatefulWidget {
  final bool isReset;
  const BiometricSetupScreen({super.key, this.isReset = false});

  @override
  State<BiometricSetupScreen> createState() => _BiometricSetupScreenState();
}

class _BiometricSetupScreenState extends State<BiometricSetupScreen> {
  final SecurityService _securityService = SecurityService();

  static const Color _navy = Color(0xFF0B1B3B);
  static const Color _blue = Color(0xFF145DA0);
  static const Color _green = Color(0xFF0E8A6A);
  static const Color _grey = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFFAFBFE);

  bool _isChecking = true;
  bool _canCheckBiometrics = false;
  String _biometricName = 'Biometrics';
  IconData _biometricIcon = Icons.fingerprint_rounded;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _checkCapabilities();
  }

  Future<void> _checkCapabilities() async {
    final canCheck = await _securityService.canCheckBiometrics();
    final available = await _securityService.getAvailableBiometrics();

    String name = 'Biometric Login';
    IconData icon = Icons.fingerprint_rounded;

    if (available.contains(BiometricType.face)) {
      name = 'Face ID';
      icon = Icons.face_retouching_natural_rounded;
    } else if (available.contains(BiometricType.fingerprint)) {
      name = 'Fingerprint';
      icon = Icons.fingerprint_rounded;
    } else if (available.contains(BiometricType.iris)) {
      name = 'Iris Scan';
      icon = Icons.remove_red_eye_rounded;
    }

    if (!mounted) return;
    setState(() {
      _canCheckBiometrics = canCheck;
      _biometricName = name;
      _biometricIcon = icon;
      _isChecking = false;
    });
  }

  Future<void> _enableBiometric() async {
    setState(() {
      _isAuthenticating = true;
    });

    final success = await _securityService.authenticateWithBiometrics(
      reason: 'Authenticate to enable $_biometricName for AbhiShare',
    );

    if (!mounted) return;

    if (success) {
      await _securityService.setBiometricEnabled(true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_biometricName enabled successfully!'),
          backgroundColor: _green,
        ),
      );

      if (widget.isReset) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } else {
      setState(() {
        _isAuthenticating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric authentication failed or cancelled. You can try again or skip.'),
        ),
      );
    }
  }

  Future<void> _skip() async {
    await _securityService.setBiometricEnabled(false);
    if (!mounted) return;
    if (widget.isReset) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: CircularProgressIndicator(color: _blue),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Icon container
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _blue.withValues(alpha: 0.15),
                      _blue.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _blue.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: Icon(
                  _biometricIcon,
                  size: 56,
                  color: _blue,
                ),
              ),
              const SizedBox(height: 32),

              // Title per requirements: "Enable biometric login?"
              const Text(
                'Enable biometric login?',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                _canCheckBiometrics
                    ? 'Use $_biometricName for seamless, instant, and secure access to your account.'
                    : 'Biometric authentication is not currently available or set up on this device. You can still use your PIN.',
                style: const TextStyle(
                  fontSize: 15,
                  color: _grey,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              // Buttons: [ Enable ]  [ Skip ]
              if (_canCheckBiometrics) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isAuthenticating ? null : _enableBiometric,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    child: _isAuthenticating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Enable',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _isAuthenticating ? null : _skip,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _grey,
                    side: BorderSide(color: _grey.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
