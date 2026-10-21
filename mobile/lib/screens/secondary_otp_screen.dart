import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../services/api_service.dart';
import 'pin_setup_screen.dart';

class SecondaryOTPScreen extends StatefulWidget {
  final String fullName;
  final String? nickname;
  final String dateOfBirth;
  final String gender;
  final String primaryIdentifier;
  final String primaryType;
  final String secondaryIdentifier;
  final String secondaryType;
  final Map<String, dynamic>? otpData;
  final String? referralCode;

  const SecondaryOTPScreen({
    super.key,
    required this.fullName,
    this.nickname,
    required this.dateOfBirth,
    required this.gender,
    required this.primaryIdentifier,
    required this.primaryType,
    required this.secondaryIdentifier,
    required this.secondaryType,
    this.otpData,
    this.referralCode,
  });

  @override
  State<SecondaryOTPScreen> createState() => _SecondaryOTPScreenState();
}

class _SecondaryOTPScreenState extends State<SecondaryOTPScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  bool _isLoading = false;
  bool _isResending = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

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

  @override
  void dispose() {
    _otpController.dispose();
    _otpFocus.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _verifyAndCreate() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      _showMessage('Enter the 6-digit OTP.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final phone = widget.primaryType == 'phone' ? widget.primaryIdentifier : widget.secondaryIdentifier;
      final email = widget.primaryType == 'email' ? widget.primaryIdentifier : widget.secondaryIdentifier;

      await _apiService.completeSignup(
        fullName: widget.fullName,
        nickname: widget.nickname,
        phone: phone,
        email: email,
        dateOfBirth: widget.dateOfBirth,
        gender: widget.gender,
        secondaryIdentifier: widget.secondaryIdentifier,
        secondaryOtp: otp,
        referralCode: widget.referralCode,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const PinSetupScreen(isReset: false),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
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
      final res = await _apiService.checkSecondaryIdentifier(
        identifier: widget.secondaryIdentifier, 
        type: widget.secondaryType,
      );
      
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
    // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

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
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
          'Verify second identifier',
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
                text: widget.secondaryIdentifier,
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOtpBoxes() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double gap = 10;
        final double boxW =
            ((constraints.maxWidth - gap * (_otpLength - 1)) / _otpLength)
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
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0,
                      child: TextField(
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
                          if (value.length == _otpLength && !_isLoading) {
                            _verifyAndCreate();
                          }
                        },
                        onSubmitted: (_) {
                          if (!_isLoading) _verifyAndCreate();
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
          onTap: _isLoading ? null : _verifyAndCreate,
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
                  'Verify & Create Account',
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
}
