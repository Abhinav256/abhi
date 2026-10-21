import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../services/api_service.dart';
import '../services/security_service.dart';
import 'pin_setup_screen.dart';
import 'signup_screen.dart';
import 'unlock_screen.dart';

class OTPScreen extends StatefulWidget {
  final String identifier;
  final String purpose;
  final String? identifierType;
  final Map<String, dynamic>? otpData;

  const OTPScreen({
    super.key, 
    required this.identifier, 
    required this.purpose,
    this.identifierType,
    this.otpData,
  });

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final ApiService _apiService = ApiService();
  final SecurityService _securityService = SecurityService();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  bool _isLoading = false;
  bool _isResending = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  bool _isAccountLocked = false;
  int _lockSeconds = 0;
  Timer? _lockTimer;

  // ---- Design constants (same palette as login / signup) ----
  static const Color _navy = Color(0xFF0B1B3B);
  static const Color _blue = Color(0xFF145DA0);
  static const Color _green = Color(0xFF0E8A6A);
  static const Color _grey = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFFAFBFE);
  static const int _otpLength = 6;

  @override
  void initState() {
    super.initState();
    _startTimerFromData(widget.otpData);
  }

  void _startTimerFromData(Map<String, dynamic>? data) {
    if (data != null && data['next_resend_allowed_at'] != null) {
      final allowedAtStr = data['next_resend_allowed_at'].toString();
      if (allowedAtStr.isNotEmpty) {
        try {
          final allowedAt = DateTime.parse(allowedAtStr).toLocal();
          final now = DateTime.now();
          final diff = allowedAt.difference(now).inSeconds;
          if (diff > 0) {
            _startCooldownTimer(diff);
          } else {
            setState(() => _cooldownSeconds = 0);
          }
        } catch (e) {
          debugPrint('Error parsing next_resend_allowed_at: $e');
        }
      }
    } else {
      _startCooldownTimer(30);
    }
  }

  void _startCooldownTimer(int seconds) {
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
        if (_cooldownSeconds > 0) {
          _cooldownSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  void _startLockTimer(int seconds) {
    _lockTimer?.cancel();
    setState(() {
      _isAccountLocked = true;
      _lockSeconds = seconds;
    });
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_lockSeconds > 0) {
          _lockSeconds--;
        } else {
          _isAccountLocked = false;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    _otpFocus.dispose();
    _cooldownTimer?.cancel();
    _lockTimer?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      _showMessage('Enter the 6-digit OTP.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.purpose == 'login') {
        final res = await _apiService.verifyOTPAndCheck(
          identifier: widget.identifier,
          otp: otp,
        );
        if (!mounted) return;
        
        if (res['exists'] == true) {
          final user = res['user'];
          final userId = user is Map ? user['id']?.toString() : null;
          final bool? backendHasPin = user is Map ? user['has_pin'] as bool? : null;

          final hasPin = await _securityService.hasPin(
            userId: userId,
            backendHasPin: backendHasPin,
          );
          if (!mounted) return;

          if (hasPin) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const UnlockScreen()),
              (route) => false,
            );
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const PinSetupScreen(isReset: false)),
              (route) => false,
            );
          }
        } else {
          // Go to Signup screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SignupScreen(
                primaryIdentifier: widget.identifier,
                primaryType: res['type'] ?? (widget.identifier.contains('@') ? 'email' : 'phone'),
              ),
            ),
          );
        }
      } else {
        // Fallback for legacy flows or secondary OTP
        final res = await _apiService.verifyOTP(
          identifier: widget.identifier,
          otp: otp,
          purpose: widget.purpose,
        );

        if (!mounted) return;

        final user = res['user'];
        final userId = user is Map ? user['id']?.toString() : null;
        final bool? backendHasPin = user is Map ? user['has_pin'] as bool? : null;

        final hasPin = await _securityService.hasPin(
          userId: userId,
          backendHasPin: backendHasPin,
        );
        if (!mounted) return;

        if (hasPin) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const UnlockScreen()),
            (route) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const PinSetupScreen(isReset: false)),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      if (errorMsg.contains('Account is temporarily locked')) {
        // e.g. "Account is temporarily locked. Please try again in 5 minutes"
        final RegExp regex = RegExp(r'in (\d+) minutes');
        final match = regex.firstMatch(errorMsg);
        if (match != null) {
          final minutes = int.tryParse(match.group(1) ?? '1') ?? 1;
          _startLockTimer(minutes * 60);
        } else {
          _startLockTimer(60); // fallback 1 min
        }
      } else if (errorMsg.contains('Too many requests. Please try again in')) {
        // e.g. "Too many requests. Please try again in 120 seconds."
        final RegExp regex = RegExp(r'in (\d+) seconds');
        final match = regex.firstMatch(errorMsg);
        if (match != null) {
          final seconds = int.tryParse(match.group(1) ?? '60') ?? 60;
          _startLockTimer(seconds);
        } else {
          _startLockTimer(60);
        }
      }
      _showMessage(errorMsg);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resendOTP() async {
    if (_cooldownSeconds > 0) return;
    
    setState(() {
      _isResending = true;
    });
    
    try {
      final res = await _apiService.sendOTPUniversal(identifier: widget.identifier);
      
      if (!mounted) return;
      _showMessage('OTP resent successfully.');
      _startTimerFromData(res);
      _otpController.clear();
      FocusScope.of(context).requestFocus(_otpFocus);
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    // ScaffoldMessenger.of(
    //   context,
    // ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildBackButton(),
                            const SizedBox(height: 28),
                            _buildHeader(),
                            const SizedBox(height: 36),
                            _buildOtpBoxes(),
                            const SizedBox(height: 32),
                            _buildVerifyButton(),
                            const SizedBox(height: 24),
                            _buildResendButton(),
                            const SizedBox(height: 24),
                            _buildWrongNumber(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(
        side: BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).maybePop(),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_back, color: _navy, size: 22),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon badge
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B6BB8), _green],
            ),
            boxShadow: [
              BoxShadow(
                color: _blue.withOpacity(0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.verified_user_outlined,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Enter verification code',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: _navy,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 15,
              color: _grey,
              height: 1.45,
            ),
            children: [
              const TextSpan(text: 'We sent a 6-digit verification code to\n'),
              TextSpan(
                text: widget.identifier,
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (_isAccountLocked) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_clock, color: Color(0xFFEF4444)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Account is temporarily locked due to too many failed attempts.\nTry again in ${_lockSeconds ~/ 60}:${(_lockSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOtpBoxes() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double gap = 10;
        final double boxW = ((constraints.maxWidth - gap * (_otpLength - 1)) /
                _otpLength)
            .clamp(40.0, 60.0);
        const double boxH = 58;

        return AnimatedBuilder(
          animation: Listenable.merge([_otpController, _otpFocus]),
          builder: (context, _) {
            final text = _otpController.text;
            final bool focused = _otpFocus.hasFocus;
            final int activeIndex =
                text.length < _otpLength ? text.length : _otpLength - 1;

            return SizedBox(
              height: boxH,
              child: Stack(
                children: [
                  // Visible boxes
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(_otpLength, (i) {
                      final bool filled = i < text.length;
                      final bool active = focused && i == activeIndex;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: boxW,
                        height: boxH,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active
                                ? _blue
                                : filled
                                    ? _blue.withOpacity(0.55)
                                    : const Color(0xFFD1D5DB),
                            width: active ? 2 : 1.5,
                          ),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: _blue.withOpacity(0.18),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          filled ? text[i] : '',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: _navy,
                          ),
                        ),
                      );
                    }),
                  ),

                  // Invisible input on top: receives taps, typing and paste
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0,
                      child: TextField(
                        enabled: !_isAccountLocked,
                        controller: _otpController,
                        focusNode: _otpFocus,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        maxLength: _otpLength,
                        showCursor: false,
                        enableInteractiveSelection: false,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(_otpLength),
                        ],
                        style: const TextStyle(color: Colors.transparent),
                        cursorColor: Colors.transparent,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        onChanged: (value) {
                          if (value.length == _otpLength && !_isLoading && !_isAccountLocked) {
                            _verify();
                          }
                        },
                        onSubmitted: (_) {
                          if (!_isLoading && !_isAccountLocked) _verify();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVerifyButton() {
    const double height = 54;

    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B6BB8), Color(0xFF0F4F94)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D145DA0),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2),
          onTap: (_isLoading || _isAccountLocked) ? null : _verify,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_isLoading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              else ...[
                const Text(
                  'Verify & Continue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Positioned(
                  right: 22,
                  child: Icon(
                    Icons.arrow_forward,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResendButton() {
    return Center(
      child: Column(
        children: [
          const Text(
            "Didn't receive the OTP?",
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          _isResending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
                )
              : GestureDetector(
                  onTap: _cooldownSeconds > 0 ? null : _resendOTP,
                  child: Text(
                    _cooldownSeconds > 0
                        ? 'Resend OTP in 00:${_cooldownSeconds.toString().padLeft(2, '0')}'
                        : 'Resend OTP',
                    style: TextStyle(
                      fontSize: 14,
                      color: _cooldownSeconds > 0 ? const Color(0xFF9CA3AF) : const Color(0xFF0B3EDB),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildWrongNumber() {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 14, color: Color(0xFF374151)),
            children: [
              TextSpan(text: 'Entered the wrong details? '),
              TextSpan(
                text: 'Go back',
                style: TextStyle(
                  color: Color(0xFF0B3EDB),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}