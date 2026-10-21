import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/security_service.dart';
import 'forgot_pin_otp_screen.dart';
import 'home_screen.dart';

class PasscodeLoginScreen extends StatefulWidget {
  final String identifier;
  final String identifierType; // 'email' or 'phone'
  final bool isInitiallyLocked;

  const PasscodeLoginScreen({
    super.key,
    required this.identifier,
    required this.identifierType,
    this.isInitiallyLocked = false,
  });

  @override
  State<PasscodeLoginScreen> createState() => _PasscodeLoginScreenState();
}

class _PasscodeLoginScreenState extends State<PasscodeLoginScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final SecurityService _securityService = SecurityService();

  static const Color _navy = Color(0xFF0E1E38);
  static const Color _brandBlue = Color(0xFF0066FF);
  static const Color _brandGreen = Color(0xFF00A86B);
  static const Color _red = Color(0xFFDC2626);
  static const Color _grey = Color(0xFF718096);
  static const Color _bg = Color(0xFFF8FAFD);


  String _enteredPin = '';
  String? _errorMessage;
  bool _isVerifying = false;
  bool _isSendingResetOtp = false;

  bool _isAccountLocked = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

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

    if (widget.isInitiallyLocked) {
      _isAccountLocked = true;
      _errorMessage =
          'Account is locked. Please verify with OTP to unlock your account.';
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownSeconds = seconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownSeconds > 1) {
          _cooldownSeconds--;
        } else {
          _cooldownSeconds = 0;
          _errorMessage = null;
          timer.cancel();
        }
      });
    });
  }

  void _onKeyPress(String digit) {
    if (_isVerifying || _isSendingResetOtp || _isAccountLocked || _cooldownSeconds > 0) {
      return;
    }
    if (_enteredPin.length >= 4) return;

    HapticFeedback.lightImpact();

    setState(() {
      _errorMessage = null;
      _enteredPin += digit;
    });

    if (_enteredPin.length == 4) {
      _handleLogin();
    }
  }

  void _onDelete() {
    if (_isVerifying || _isSendingResetOtp || _isAccountLocked || _cooldownSeconds > 0) {
      return;
    }
    if (_enteredPin.isEmpty) return;

    HapticFeedback.selectionClick();

    setState(() {
      _errorMessage = null;
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiService.loginWithPasscode(
        identifier: widget.identifier,
        pin: _enteredPin,
      );

      final user = res['user'];
      final userId = user is Map ? user['id']?.toString() : null;

      // Keep user-scoped local hardware storage synchronized
      if (userId != null && userId.isNotEmpty) {
        try {
          await _securityService.setPin(_enteredPin, userId: userId);
        } catch (_) {}
      }

      if (!mounted) return;

      // Login success -> Home Screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);

      final msg = e.toString().replaceFirst('Exception: ', '');
      final lower = msg.toLowerCase();

      if (lower.contains('locked') || lower.contains('15 failed')) {
        setState(() {
          _isAccountLocked = true;
          _errorMessage =
              'Account is locked due to 15 failed attempts. Please verify with OTP to unlock.';
          _enteredPin = '';
          _isVerifying = false;
        });
      } else if (lower.contains('seconds')) {
        final RegExp regex = RegExp(r'(\d+)\s*seconds?');
        final match = regex.firstMatch(msg);
        final seconds = match != null
            ? (int.tryParse(match.group(1) ?? '30') ?? 30)
            : 30;

        _startCooldown(seconds);
        setState(() {
          _errorMessage =
              'Too many attempts. Please try again in ${seconds}s.';
          _enteredPin = '';
          _isVerifying = false;
        });
      } else {
        setState(() {
          _errorMessage = msg;
          _enteredPin = '';
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _handleResetPasscode() async {
    if (_isVerifying || _isSendingResetOtp) return;

    setState(() {
      _isSendingResetOtp = true;
    });

    try {
      await _apiService.sendOTPUniversal(identifier: widget.identifier);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'OTP sent to ${_maskIdentifier(widget.identifier)}',
          ),
          backgroundColor: const Color(0xFF0E8A6A),
        ),
      );

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ForgotPinOtpScreen(
            identifier: widget.identifier,
            identifierType: widget.identifierType,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: _red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingResetOtp = false;
        });
      }
    }
  }

  String _maskIdentifier(String id) {
    if (widget.identifierType == 'email' || id.contains('@')) {
      final parts = id.split('@');
      if (parts.length != 2) return id;
      final user = parts[0];
      final domain = parts[1];
      if (user.length <= 2) return '$user***@$domain';
      return '${user.substring(0, 2)}***${user.substring(user.length - 1)}@$domain';
    } else {
      if (id.length <= 4) return id;
      return '${id.substring(0, 3)}****${id.substring(id.length - 3)}';
    }
  }

  @override
  Widget build(BuildContext context) {
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
                                onPressed: () => Navigator.of(context).pop(),
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
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _isAccountLocked
                                    ? const [
                                        Color(0xFFFFFFFF),
                                        Color(0xFFFEEFEF),
                                      ]
                                    : const [
                                        Color(0xFFFFFFFF),
                                        Color(0xFFEFF5FE),
                                      ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isAccountLocked ? _red : const Color(0xFF2563EB))
                                      .withValues(alpha: 0.12),
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
                            child: Center(
                              child: Icon(
                                _isAccountLocked
                                    ? Icons.lock_outline_rounded
                                    : Icons.lock_rounded,
                                size: 48,
                                color: _isAccountLocked ? _red : const Color(0xFF2563EB),
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
                                color: _isAccountLocked
                                    ? const Color(0xFFFEE2E2)
                                    : const Color(0xFFE8FDF3),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isAccountLocked ? _red : const Color(0xFF10B981))
                                        .withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  _isAccountLocked
                                      ? Icons.warning_amber_rounded
                                      : Icons.verified_user_rounded,
                                  size: 16,
                                  color: _isAccountLocked ? _red : const Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Title: Enter Passcode / Account Locked
                      if (_isAccountLocked)
                        const Text(
                          'Account Locked',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: _red,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        )
                      else
                        const Text.rich(
                          TextSpan(
                            text: 'Enter ',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                              letterSpacing: -0.5,
                            ),
                            children: [
                              TextSpan(
                                text: 'Passcode',
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
                      Text(
                        _isAccountLocked
                            ? 'Your account is locked due to 15 failed passcode attempts.\nPlease verify with OTP to unlock your account.'
                            : 'Enter your 4-digit passcode for\n${_maskIdentifier(widget.identifier)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: _grey,
                          height: 1.35,
                        ),
                      ),

                      if (!_isAccountLocked) ...[
                        const SizedBox(height: 28),

                        // Capsule PIN dots container [ O O O O ]
                        AnimatedBuilder(
                          animation: _shakeController,
                          builder: (context, child) {
                            final offset = _shakeAnimation.value *
                                (math.sin(_shakeController.value * 3 * 3.14159));
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
                      ],

                      // Cooldown timer badge or error message
                      Container(
                        height: 40,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _isVerifying
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: _brandBlue,
                                ),
                              )
                            : (_cooldownSeconds > 0
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _red.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.timer_outlined,
                                            size: 16, color: _red),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Try again in ${_cooldownSeconds}s',
                                          style: const TextStyle(
                                            color: _red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : (_errorMessage != null
                                    ? Text(
                                        _errorMessage!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: _red,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5,
                                        ),
                                      )
                                    : null)),
                      ),

                      if (_isAccountLocked) ...[
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12),
                          child: SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton.icon(
                              onPressed: _isSendingResetOtp
                                  ? null
                                  : _handleResetPasscode,
                              icon: _isSendingResetOtp
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.verified_user_rounded,
                                      color: Colors.white),
                              label: const Text(
                                'Verify with OTP to Unlock',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _navy,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                elevation: 3,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                      ] else ...[
                        // Reset Passcode Option
                        TextButton(
                          onPressed: (_isVerifying || _isSendingResetOtp)
                              ? null
                              : _handleResetPasscode,
                          style: TextButton.styleFrom(
                            foregroundColor: _brandBlue,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                          ),
                          child: _isSendingResetOtp
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _brandBlue,
                                  ),
                                )
                              : const Text(
                                  'Reset Passcode',
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

                        // Number Pad with Cooldown state
                        Opacity(
                          opacity: _cooldownSeconds > 0 ? 0.4 : 1.0,
                          child: _buildNumberPad(),
                        ),

                        const SizedBox(height: 24),
                      ],
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
}

