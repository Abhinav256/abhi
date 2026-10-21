import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'otp_screen.dart';
import 'passcode_login_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _identifierController = TextEditingController();

  bool _isLoading = false;
  String? _identifierError;

  // ---- Design constants (taken from the reference image) ----
  static const Color _navy = Color(0xFF0B1B3B);
  static const Color _blue = Color(0xFF145DA0);
  static const Color _green = Color(0xFF097B65);
  static const Color _linkBlue = Color(0xFF0B3EDB);
  static const Color _grey = Color(0xFF6B7280);

  // Background image intrinsic ratio (935 x 1683)
  static const double _bgAspect = 1683 / 935;

  // Card starts at ~52% of screen height in the reference
  static const double _cardTopFraction = 0.52;

  // Logo size relative to screen width. Tune this one value if your
  // logo.png has extra transparent padding.
  static const double _logoWidthFraction = 0.46;

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    final identifier = _identifierController.text.trim();

    if (identifier.isEmpty) {
      _showMessage('Enter your mobile number or email.');
      return;
    }

    setState(() {
      _isLoading = true;
      _identifierError = null;
    });

    try {
      // 1. Check if identifier exists and has a passcode created
      final checkRes = await _apiService.checkAuthIdentifier(identifier: identifier);
      final bool exists = checkRes['exists'] == true;
      final bool hasPin = checkRes['has_pin'] == true;
      final bool isLocked = checkRes['account_locked'] == true;
      final String idType = checkRes['type'] ?? (identifier.contains('@') ? 'email' : 'phone');

      if (!mounted) return;

      if (exists && hasPin) {
        // Existing user with passcode: direct to passcode screen!
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PasscodeLoginScreen(
              identifier: identifier,
              identifierType: idType,
              isInitiallyLocked: isLocked,
            ),
          ),
        );
      } else {
        // New user or user without a passcode: send OTP and go to OTP verification
        final res = await _apiService.sendOTPUniversal(identifier: identifier);

        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OTPScreen(
              identifier: identifier,
              purpose: 'login',
              identifierType: res['type'] ?? idType,
              otpData: res,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      final message = e.toString().replaceFirst('Exception: ', '');
      final normalizedMessage = message.toLowerCase();
      final emailDeliveryFailed = identifier.contains('@') &&
          (normalizedMessage.contains('smtp') ||
              normalizedMessage.contains('mailbox') ||
              normalizedMessage.contains('recipient'));

      if (emailDeliveryFailed) {
        setState(() => _identifierError = 'Email is invalid');
      } else {
        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    // ScaffoldMessenger.of(
    //   context,
    // ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final double w = media.size.width;
    final double h = media.size.height; // stays constant when keyboard opens
    final double keyboard = media.viewInsets.bottom;
    final double inputFontSize = (w * 0.043).clamp(15.0, 19.0);
    final double inputVerticalPadding = (h * 0.018).clamp(13.0, 20.0);
    final double inputHorizontalPadding = (w * 0.035).clamp(12.0, 20.0);
    final double inputIconSize = (w * 0.065).clamp(22.0, 28.0);

    // Background: scale to full width, then shift up so the road scene
    // (car / bike / highway) sits just above the card, like the reference.
    final double bgHeight = w * _bgAspect;
    final double bgTop = math.min(0.0, h * 0.47 - bgHeight * 0.677);

    // Logo block
    final double logoWidth = w * _logoWidthFraction;
    final double logoBoxHeight = logoWidth * 0.95;
    final double logoTop = math.max(
      media.padding.top + 8,
      h * 0.17 - logoBoxHeight / 2,
    );

    // Minimum top position for the card (just below the logo with some padding)
    final double minCardTop = logoTop + logoBoxHeight + 8.0;
    
    // Original top position for the card
    final double originalCardTop = h * _cardTopFraction;

    // To prevent the keyboard from pushing the content unnecessarily high,
    // we want the card to slide up just enough to fit its content (~290px) 
    // above the keyboard, but NEVER higher than the logo.
    final double idealCardTop = (h - keyboard) - 290.0;
    final double cardTop = idealCardTop.clamp(minCardTop, originalCardTop);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFBFE0F7),
        // Background must not resize with the keyboard; the card is moved manually.
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // 1. Full background image, positioned exactly like the reference
            Positioned(
              top: bgTop,
              left: 0,
              right: 0,
              height: bgHeight,
              child: Image.asset(
                'assets/images/background.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),

            // 2. Logo + tagline (top centre)
            Positioned(
              top: logoTop,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: logoWidth,
                      height: logoBoxHeight,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 2),
                    const Text(
  'Share more, Save more',
  style: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: Color(0xFF3F4756),
    fontStyle: FontStyle.italic,
  ),
),
                  ],
                ),
              ),
            ),

            // 3. Bottom card
            Positioned(
              left: 0,
              right: 0,
              top: cardTop,
              bottom: keyboard,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFFAFBFE),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 20,
                      offset: Offset(0, -5),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Heading with blue -> green gradient on "AbhiShare"
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                            fontFamily: 'Roboto',
                            height: 1.2,
                          ),
                          children: [
                            const TextSpan(text: 'Welcome to '),
                            TextSpan(
                              text: 'AbhiShare',
                              style: TextStyle(
                                foreground: Paint()
                                  ..shader = const LinearGradient(
                                    colors: [Color(0xFF1565C0), Color(0xFF0E8A6A)],
                                    stops: [0.38, 0.52],
                                  ).createShader(
                                    const Rect.fromLTWH(0, 0, 150, 30),
                                  ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Share your journey. Travel together.',
                        style: TextStyle(
                          fontSize: 15,
                          color: _grey,
                        ),
                      ),
                      const SizedBox(height: 26),

                      // Input
                      TextField(
                        controller: _identifierController,
                        onChanged: (_) {
                          if (_identifierError != null) {
                            setState(() => _identifierError = null);
                          }
                        },
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(
                          fontSize: inputFontSize,
                          color: _navy,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Mobile number or email',
                          hintText: 'Enter mobile or email',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          labelStyle: const TextStyle(
                            color: _blue,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          floatingLabelStyle: const TextStyle(
                            color: _blue,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          hintStyle: TextStyle(
                            color: _grey,
                            fontSize: inputFontSize,
                          ),
                          errorText: _identifierError,
                          errorStyle: const TextStyle(fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFFFAFBFE),
                          contentPadding: EdgeInsets.symmetric(
                            vertical: inputVerticalPadding,
                            horizontal: inputHorizontalPadding,
                          ),
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: _blue,
                            size: inputIconSize,
                          ),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: (w * 0.16).clamp(54.0, 72.0),
                            minHeight: inputIconSize,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide:
                                const BorderSide(color: _blue, width: 1.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide:
                                const BorderSide(color: _blue, width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide:
                                const BorderSide(color: _blue, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Gradient "Continue" button
                      _buildContinueButton(),
                      const SizedBox(height: 22),

                    ],
                  ),
                ),
              ),
            ),

            // 4. Waves overlay at the bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _WavePainter(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(27),
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
          borderRadius: BorderRadius.circular(27),
          onTap: _isLoading ? null : _handleContinue,
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
                  'Continue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Positioned(
                  right: 22,
                  child: Icon(Icons.arrow_forward,
                      size: 22, color: Colors.white),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);

    // Back wave – light, high at both edges, dips in the middle
    final paint1 = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x9938B6C8), Color(0x9950B8A0), Color(0x99A5D55A)],
      ).createShader(rect);

    final path1 = Path()
      ..moveTo(0, h * 0.08)
      ..cubicTo(w * 0.15, h * 0.02, w * 0.30, h * 0.30, w * 0.50, h * 0.42)
      ..cubicTo(w * 0.70, h * 0.55, w * 0.88, h * 0.20, w, h * 0.0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    // Middle wave – teal to green
    final paint2 = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xCC1FA0C8), Color(0xCC2DB39A), Color(0xCC6DBE4B)],
      ).createShader(rect);

    final path2 = Path()
      ..moveTo(0, h * 0.28)
      ..cubicTo(w * 0.18, h * 0.16, w * 0.32, h * 0.50, w * 0.55, h * 0.58)
      ..cubicTo(w * 0.75, h * 0.66, w * 0.90, h * 0.40, w, h * 0.24)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    // Front wave – deep blue to teal
    final paint3 = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xE60F5FA8), Color(0xE61C8FBF), Color(0xE640B59A)],
      ).createShader(rect);

    final path3 = Path()
      ..moveTo(0, h * 0.62)
      ..cubicTo(w * 0.20, h * 0.50, w * 0.40, h * 0.68, w * 0.62, h * 0.74)
      ..cubicTo(w * 0.82, h * 0.80, w * 0.92, h * 0.68, w, h * 0.55)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(path1, paint1);
    canvas.drawPath(path2, paint2);
    canvas.drawPath(path3, paint3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
