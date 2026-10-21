import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import 'pin_setup_screen.dart';

class ForgotPinOtpScreen extends StatefulWidget {
  final String identifier;
  final String identifierType; // 'email' or 'phone'

  const ForgotPinOtpScreen({
    super.key,
    required this.identifier,
    required this.identifierType,
  });

  @override
  State<ForgotPinOtpScreen> createState() => _ForgotPinOtpScreenState();
}

class _ForgotPinOtpScreenState extends State<ForgotPinOtpScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  static const Color _navy = Color(0xFF0B1B3B);
  static const Color _blue = Color(0xFF145DA0);
  static const Color _green = Color(0xFF0E8A6A);
  static const Color _grey = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFFAFBFE);

  bool _isLoading = false;
  int _resendCountdown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendCountdown = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendCountdown > 1) {
        setState(() => _resendCountdown--);
      } else {
        setState(() => _resendCountdown = 0);
        timer.cancel();
      }
    });
  }

  Future<void> _resendOTP() async {
    if (_resendCountdown > 0) return;
    setState(() => _isLoading = true);

    try {
      await _apiService.sendOTPUniversal(identifier: widget.identifier);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP sent successfully!'),
          backgroundColor: _green,
        ),
      );
      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 6-digit OTP')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _apiService.verifyOTPAndCheck(
        identifier: widget.identifier,
        otp: otp,
      );

      if (!mounted) return;

      // Successful OTP verification -> Set new PIN -> Confirm new PIN -> Home
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const PinSetupScreen(isReset: true),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _maskIdentifier(String id) {
    if (widget.identifierType == 'email') {
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
    final isEmail = widget.identifierType == 'email';
    final title = isEmail ? 'Email OTP' : 'Mobile OTP';
    final icon = isEmail ? Icons.mark_email_read_outlined : Icons.sms_outlined;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _navy),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: _navy,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _blue, size: 32),
              ),
              const SizedBox(height: 20),
              Text(
                'Verify $title',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the 6-digit code sent to\n${_maskIdentifier(widget.identifier)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: _grey,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // OTP Input boxes
              _buildOtpInput(),

              const SizedBox(height: 24),

              // Resend countdown
              if (_resendCountdown > 0)
                Text(
                  'Resend code in ${_resendCountdown}s',
                  style: const TextStyle(color: _grey, fontSize: 14),
                )
              else
                TextButton(
                  onPressed: _isLoading ? null : _resendOTP,
                  child: const Text(
                    'Resend Code',
                    style: TextStyle(
                      color: _blue,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),

              const Spacer(),

              // Verify Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify OTP',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpInput() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Hidden text field
        Opacity(
          opacity: 0.0,
          child: TextField(
            controller: _otpController,
            focusNode: _focusNode,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (val) {
              setState(() {});
              if (val.length == 6) {
                _verifyOtp();
              }
            },
          ),
        ),

        // Visual boxes
        GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              final text = _otpController.text;
              final digit = index < text.length ? text[index] : '';
              final isFocused = index == text.length;

              return Container(
                width: 46,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isFocused
                        ? _blue
                        : (digit.isNotEmpty
                            ? _navy
                            : _grey.withValues(alpha: 0.3)),
                    width: isFocused ? 2 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    digit,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
