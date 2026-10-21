import 'package:flutter/material.dart';

import '../services/security_service.dart';
import 'biometric_setup_screen.dart';
import 'change_pin_screen.dart';

class SafetyAndPrivacyScreen extends StatefulWidget {
  const SafetyAndPrivacyScreen({super.key});

  @override
  State<SafetyAndPrivacyScreen> createState() => _SafetyAndPrivacyScreenState();
}

class _SafetyAndPrivacyScreenState extends State<SafetyAndPrivacyScreen> {
  final SecurityService _securityService = SecurityService();
  static const Color _navy = Color(0xFF0F1B4D);
  static const Color _bg = Color(0xFFF3F7FD);

  bool _biometricEnabled = false;
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await _securityService.isBiometricEnabled();
    final canCheck = await _securityService.canCheckBiometrics();
    
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled;
      _canCheckBiometrics = canCheck;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Navigate to BiometricSetupScreen to enable
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BiometricSetupScreen(isReset: true)),
      );
      _loadSettings();
    } else {
      // Just disable it
      await _securityService.setBiometricEnabled(false);
      setState(() {
        _biometricEnabled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Safety & Privacy', style: TextStyle(color: _navy)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: _navy),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Security Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _navy,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline, color: Color(0xFF0B6FE0)),
                  title: const Text('Change Login PIN'),
                  subtitle: const Text('Update your 4-digit PIN'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ChangePinScreen()),
                    ).then((_) => _loadSettings());
                  },
                ),
                if (_canCheckBiometrics) ...[
                  const Divider(height: 1, indent: 56),
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint, color: Color(0xFF12B58A)),
                    title: const Text('Biometric Login'),
                    subtitle: const Text('Use Face ID or Fingerprint'),
                    value: _biometricEnabled,
                    activeColor: const Color(0xFF0B6FE0),
                    onChanged: _toggleBiometric,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
