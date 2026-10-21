import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/security_service.dart';
import '../services/session_service.dart';
import 'forgot_pin_otp_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'pin_setup_screen.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({
    super.key,
    this.initialUserId,
    this.initialIsBiometricEnabled,
    this.initialHasBiometrics,
    this.initialBiometricLabel,
  });

  final String? initialUserId;
  final bool? initialIsBiometricEnabled;
  final bool? initialHasBiometrics;
  final String? initialBiometricLabel;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen>
    with SingleTickerProviderStateMixin {
  final SecurityService _securityService = SecurityService();
  final ApiService _apiService = ApiService();
  final SessionService _sessionService = SessionService();

  static const Color _navy = Color(0xFF0E1E38);
  static const Color _brandBlue = Color(0xFF0066FF);
  static const Color _brandGreen = Color(0xFF00A86B);
  static const Color _blue = Color(0xFF0066FF);
  static const Color _red = Color(0xFFDC2626);
  static const Color _grey = Color(0xFF718096);
  static const Color _bg = Color(0xFFF8FAFD);

  String? _userId;
  String _enteredPin = '';
  String? _errorMessage;
  bool _isChecking = true;
  bool _isBiometricEnabled = false;
  bool _hasBiometrics = false;
  String _biometricLabel = 'Biometrics';
  bool _isVerifying = false;

  String? _registeredEmail;
  String? _registeredPhone;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 12)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);

    if (widget.initialUserId != null) {
      _userId = widget.initialUserId;
      _isChecking = false;
      _isBiometricEnabled = widget.initialIsBiometricEnabled ?? false;
      _hasBiometrics = widget.initialHasBiometrics ?? false;
      _biometricLabel = widget.initialBiometricLabel ?? 'Biometrics';
      _loadContactInfo();
      if (_isBiometricEnabled && _hasBiometrics) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _triggerBiometric();
        });
      }
    } else {
      _initAuth();
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _initAuth() async {
    // 0. Ensure an active session exists
    final session = await _sessionService.getSession();
    final uid = session?['userId'];
    if (session == null || uid == null || uid.isEmpty) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      return;
    }
    _userId = uid;

    // 1. Verify if THIS specific user has set a PIN
    final hasPin = await _securityService.hasPin(userId: _userId);
    if (!mounted) return;

    if (!hasPin) {
      // First successful login/signup requires setting PIN
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PinSetupScreen(isReset: false)),
      );
      return;
    }

    // 2. Fetch contact info for Forgot PIN recovery
    _loadContactInfo();

    // 3. Check biometric availability strictly for THIS user
    _isBiometricEnabled = await _securityService.isBiometricEnabled(userId: _userId);
    _hasBiometrics = await _securityService.canCheckBiometrics();
    _biometricLabel = await _securityService.getBiometricTypeLabel();

    setState(() {
      _isChecking = false;
    });

    // 4. Priority 1: Biometric authentication (if enabled and available for this user)
    if (_isBiometricEnabled && _hasBiometrics) {
      // Small post-frame delay so the UI settles
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerBiometric();
      });
    }
  }

  Future<void> _loadContactInfo() async {
    _registeredEmail = await _securityService.getUserEmail(userId: _userId);
    _registeredPhone = await _securityService.getUserPhone(userId: _userId);

    if (_registeredEmail == null || _registeredPhone == null) {
      try {
        final user = await _apiService.getCurrentUser();
        _registeredEmail = user['email']?.toString();
        _registeredPhone = user['phone']?.toString();
        await _securityService.saveUserContactInfo(
          userId: _userId,
          email: _registeredEmail,
          phone: _registeredPhone,
        );
      } catch (_) {}
    }
  }

  Future<void> _triggerBiometric() async {
    final success = await _securityService.authenticateWithBiometrics(
      reason: 'Authenticate with $_biometricLabel to access AbhiShare',
    );

    if (!mounted) return;

    if (success) {
      // Biometric SUCCESS -> HOME
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
    // If fail/cancel: remains on PIN screen as required by hierarchy
  }

  void _onKeyPress(String digit) {
    if (_isVerifying) return;
    if (_enteredPin.length >= 4) return;

    HapticFeedback.lightImpact();

    setState(() {
      _errorMessage = null;
      _enteredPin += digit;
    });

    if (_enteredPin.length == 4) {
      _verifyPin();
    }
  }

  void _onDelete() {
    if (_isVerifying || _enteredPin.isEmpty) return;

    HapticFeedback.selectionClick();

    setState(() {
      _errorMessage = null;
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  Future<void> _verifyPin() async {
    setState(() {
      _isVerifying = true;
    });

    final isValid = await _securityService.verifyPin(_enteredPin, userId: _userId);

    if (!mounted) return;

    if (isValid) {
      // PIN SUCCESS -> HOME
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);

      setState(() {
        _errorMessage = 'Incorrect PIN';
        _enteredPin = '';
        _isVerifying = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // FORGOT PIN FLOW
  // ---------------------------------------------------------------------------

  void _showForgotPinDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ForgotPinSheet(
        registeredEmail: _registeredEmail,
        registeredPhone: _registeredPhone,
        onSendEmailOtp: (email) => _sendOtpAndNavigate(email, 'email'),
        onSendMobileOtp: (phone) => _sendOtpAndNavigate(phone, 'phone'),
      ),
    );
  }

  Future<void> _sendOtpAndNavigate(String identifier, String type) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: _blue),
      ),
    );

    try {
      await _apiService.sendOTPUniversal(identifier: identifier);

      if (!mounted) return;
      // Dismiss loading dialog
      Navigator.of(context).pop();

      // Navigate to OTP screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ForgotPinOtpScreen(
            identifier: identifier,
            identifierType: type,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _brandBlue)),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // Top Bar: Back Button & AbhiShare Branding
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEEF4FC),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.arrow_back_rounded,
                                  color: Color(0xFF1E3A8A),
                                  size: 22,
                                ),
                                onPressed: () {
                                  if (Navigator.of(context).canPop()) {
                                    Navigator.of(context).pop();
                                  } else {
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                                      (route) => false,
                                    );
                                  }
                                },
                              ),
                            ),
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Abhi',
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w800,
                                    color: _brandBlue,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                Text(
                                  'Share',
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w800,
                                    color: _brandGreen,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 44, height: 44),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Center Security Lock Illustration with Shield Badge
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 106,
                            height: 106,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFFFFFF),
                                  Color(0xFFEFF5FE),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                                  blurRadius: 36,
                                  offset: const Offset(0, 12),
                                  spreadRadius: 4,
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.lock_rounded,
                                size: 48,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8FDF3),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.verified_user_rounded,
                                  size: 16,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Title: Enter your PIN
                      const Text.rich(
                        TextSpan(
                          text: 'Enter your ',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                            letterSpacing: -0.5,
                          ),
                          children: [
                            TextSpan(
                              text: 'PIN',
                              style: TextStyle(
                                color: _brandBlue,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 8),

                      // Subtitle
                      const Text(
                        'Enter your 4-digit security PIN\nto continue',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: _grey,
                          height: 1.35,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Capsule PIN dots container [ O O O O ]
                      AnimatedBuilder(
                        animation: _shakeController,
                        builder: (context, child) {
                          final offset = _shakeAnimation.value *
                              (mathSin(_shakeController.value * 3 * 3.14159));
                          return Transform.translate(
                            offset: Offset(offset, 0),
                            child: child,
                          );
                        },
                        child: Container(
                          width: 280,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F7FD),
                            borderRadius: BorderRadius.circular(36),
                            border: Border.all(
                              color: const Color(0xFFE2EDFB),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (index) {
                              final isFilled = index < _enteredPin.length;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.symmetric(horizontal: 14),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isFilled ? _brandBlue : Colors.transparent,
                                  border: Border.all(
                                    color: isFilled
                                        ? _brandBlue
                                        : const Color(0xFF94A3B8),
                                    width: 1.8,
                                  ),
                                  boxShadow: isFilled
                                      ? [
                                          BoxShadow(
                                            color: _brandBlue.withValues(alpha: 0.35),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                              );
                            }),
                          ),
                        ),
                      ),

                      // Error message
                      SizedBox(
                        height: 24,
                        child: Center(
                          child: _errorMessage != null
                              ? Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: _red,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                )
                              : null,
                        ),
                      ),

                      // "Forgot PIN?" Link
                      TextButton(
                        onPressed: _showForgotPinDialog,
                        style: TextButton.styleFrom(
                          foregroundColor: _brandBlue,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                        ),
                        child: const Text(
                          'Forgot PIN?',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                            color: _brandBlue,
                            decoration: TextDecoration.underline,
                            decorationColor: _brandBlue,
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Number Pad
                      _buildNumberPad(),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double mathSin(double val) {
    return (val - (val * val * val) / 6.0);
  }

  Widget _buildNumberPad() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildKey('1'),
              _buildKey('2'),
              _buildKey('3'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildKey('4'),
              _buildKey('5'),
              _buildKey('6'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildKey('7'),
              _buildKey('8'),
              _buildKey('9'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_isBiometricEnabled && _hasBiometrics)
                _buildBiometricKey()
              else
                const SizedBox(width: 76, height: 76),
              _buildKey('0'),
              _buildBackspaceKey(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String digit) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          splashColor: _brandBlue.withValues(alpha: 0.12),
          highlightColor: _brandBlue.withValues(alpha: 0.06),
          onTap: () => _onKeyPress(digit),
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFFE2EDFB),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          splashColor: _brandBlue.withValues(alpha: 0.16),
          highlightColor: _brandBlue.withValues(alpha: 0.08),
          onTap: _onDelete,
          child: const Center(
            child: Icon(
              Icons.backspace_outlined,
              size: 26,
              color: _navy,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricKey() {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          splashColor: _brandBlue.withValues(alpha: 0.12),
          highlightColor: _brandBlue.withValues(alpha: 0.06),
          onTap: _triggerBiometric,
          child: Center(
            child: Icon(
              _biometricLabel.contains('Face')
                  ? Icons.face_retouching_natural_rounded
                  : Icons.fingerprint_rounded,
              size: 28,
              color: _brandBlue,
            ),
          ),
        ),
      ),
    );
  }

}

// -----------------------------------------------------------------------------
// FORGOT PIN BOTTOM SHEET (Strictly per Section 5 Requirements)
// -----------------------------------------------------------------------------

class _ForgotPinSheet extends StatefulWidget {
  final String? registeredEmail;
  final String? registeredPhone;
  final Function(String email) onSendEmailOtp;
  final Function(String phone) onSendMobileOtp;

  const _ForgotPinSheet({
    required this.registeredEmail,
    required this.registeredPhone,
    required this.onSendEmailOtp,
    required this.onSendMobileOtp,
  });

  @override
  State<_ForgotPinSheet> createState() => _ForgotPinSheetState();
}

class _ForgotPinSheetState extends State<_ForgotPinSheet> {
  static const Color _navy = Color(0xFF0B1B3B);
  static const Color _linkBlue = Color(0xFF0B3EDB);
  static const Color _grey = Color(0xFF6B7280);

  final TextEditingController _customEmailController = TextEditingController();
  final TextEditingController _customPhoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.registeredEmail != null) {
      _customEmailController.text = widget.registeredEmail!;
    }
    if (widget.registeredPhone != null) {
      _customPhoneController.text = widget.registeredPhone!;
    }
  }

  @override
  void dispose() {
    _customEmailController.dispose();
    _customPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title per prompt: "Send OTP to your email address?"
          const Text(
            'Send OTP to your email address?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _navy,
            ),
          ),
          const SizedBox(height: 8),

          if (widget.registeredEmail != null && widget.registeredEmail!.isNotEmpty)
            Text(
              widget.registeredEmail!,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _grey,
              ),
            )
          else ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customEmailController,
              decoration: const InputDecoration(
                labelText: 'Enter your registered email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Primary Button: [ Send OTP ]
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                final email = _customEmailController.text.trim();
                if (email.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter your email')),
                  );
                  return;
                }
                Navigator.of(context).pop();
                widget.onSendEmailOtp(email);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Send OTP',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Exact alternative as a hyperlink-style text:
          // "No, send to mobile number"
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              _showMobileRecoveryDialog();
            },
            child: const Text(
              'No, send to mobile number',
              style: TextStyle(
                fontSize: 14,
                color: _linkBlue,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _showMobileRecoveryDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Send OTP to your mobile number?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _navy,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.registeredPhone != null &&
                widget.registeredPhone!.isNotEmpty)
              Text(
                widget.registeredPhone!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _grey,
                ),
              )
            else ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Enter your registered mobile number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  final phone = _customPhoneController.text.trim();
                  if (phone.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter your mobile number'),
                      ),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop();
                  widget.onSendMobileOtp(phone);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Send OTP',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
