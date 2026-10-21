import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'secondary_otp_screen.dart';

class SignupScreen extends StatefulWidget {
  final String primaryIdentifier;
  final String primaryType; // "phone" or "email"

  const SignupScreen({
    super.key,
    required this.primaryIdentifier,
    required this.primaryType,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _secondaryController = TextEditingController();
  final _referralController = TextEditingController();

  DateTime? _dateOfBirth;
  String _gender = '';
  bool _isLoading = false;
  String? _secondaryError;
  bool _isValidatingReferral = false;
  bool _isReferralValid = false;
  String? _referralMessage;
  String? _referralError;

  static const _ink = Color(0xFF101A30);
  static const _muted = Color(0xFF828CA3);
  static const _icon = Color(0xFF6E788D);
  static const _outline = Color(0xFFDCE3F0);
  static const _blue = Color(0xFF0875F9);

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _secondaryController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final initialDate = _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day);
    DateTime tempDate = initialDate;
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (BuildContext builder) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _dateOfBirth = tempDate);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: initialDate,
                  minimumDate: DateTime(1900),
                  maximumDate: now,
                  onDateTimeChanged: (DateTime newDate) {
                    tempDate = newDate;
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _validateReferralCode({bool showMessageOnSuccess = true}) async {
    final code = _referralController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _isReferralValid = false;
        _referralMessage = null;
        _referralError = null;
      });
      return;
    }

    setState(() {
      _isValidatingReferral = true;
      _referralError = null;
      _referralMessage = null;
    });

    try {
      final res = await _apiService.validateReferralCode(code);
      final valid = res['valid'] == true;
      final referrerName = res['referrer_name']?.toString() ?? '';
      final msg = res['message']?.toString() ?? 'Referral code applied!';

      if (!mounted) return;
      setState(() {
        _isReferralValid = valid;
        if (valid) {
          _referralMessage = referrerName.isNotEmpty
              ? 'Referred by $referrerName'
              : msg;
          _referralError = null;
        } else {
          _referralError = msg;
        }
      });
      if (valid && showMessageOnSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_referralMessage ?? 'Referral code applied!'),
            backgroundColor: const Color(0xFF0E8A6A),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isReferralValid = false;
        _referralError = msg;
        _referralMessage = null;
      });
    } finally {
      if (mounted) setState(() => _isValidatingReferral = false);
    }
  }

  Future<void> _sendSecondaryOTP() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null) {
      _showMessage('Please select your date of birth.');
      return;
    }
    if (_gender.isEmpty) {
      _showMessage('Please select your gender.');
      return;
    }

    final referralCode = _referralController.text.trim();
    if (referralCode.isNotEmpty && !_isReferralValid) {
      await _validateReferralCode(showMessageOnSuccess: false);
      if (!_isReferralValid) {
        _showMessage(_referralError ?? 'Please provide a valid referral code or leave it blank.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _secondaryError = null;
    });

    try {
      final secondaryType = widget.primaryType == 'phone' ? 'email' : 'phone';

      // Check if secondary identifier is already used and send OTP
      final res = await _apiService.checkSecondaryIdentifier(
        identifier: _secondaryController.text.trim(),
        type: secondaryType,
      );

      if (!mounted) return;

      final date = '${_dateOfBirth!.year.toString().padLeft(4, '0')}-'
          '${_dateOfBirth!.month.toString().padLeft(2, '0')}-'
          '${_dateOfBirth!.day.toString().padLeft(2, '0')}';

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SecondaryOTPScreen(
            fullName: _nameController.text.trim(),
            nickname: _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
            dateOfBirth: date,
            gender: _gender,
            primaryIdentifier: widget.primaryIdentifier,
            primaryType: widget.primaryType,
            secondaryIdentifier: _secondaryController.text.trim(),
            secondaryType: secondaryType,
            otpData: res,
            referralCode: referralCode.isNotEmpty ? referralCode.toUpperCase() : null,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      final normalized = message.toLowerCase();
      if (normalized.contains('already exists')) {
        setState(() => _secondaryError = message);
      } else {
        _showMessage(message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _decoration(String hint, IconData icon,
      {Widget? suffix, String? errorText}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w400),
      filled: true,
      fillColor: const Color(0xFFFEFEFF),
      contentPadding: const EdgeInsets.symmetric(vertical: 18),
      prefixIcon: Icon(icon, color: _icon, size: 27),
      prefixIconConstraints: const BoxConstraints(minWidth: 72),
      suffixIcon: suffix,
      errorText: errorText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: const BorderSide(color: _outline, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: const BorderSide(color: _outline, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: const BorderSide(color: _blue, width: 1.7),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.7),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final compact = media.size.height < 760;
    final side = (width * 0.06).clamp(20.0, 52.0);
    final fieldHeight = (media.size.height * 0.066).clamp(54.0, 72.0);
    final gap = (media.size.height * 0.014).clamp(9.0, 17.0);
    final titleSize = (width * 0.061).clamp(25.0, 34.0);
    final logoWidth = (width * 0.48).clamp(190.0, 390.0);
    final topSpace = compact ? 12.0 : (media.size.height * 0.045).clamp(20.0, 58.0);

    final isPrimaryPhone = widget.primaryType == 'phone';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(side, topSpace, side, 14),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        SizedBox(height: compact ? 0 : constraints.maxHeight * 0.025),
                        Image.asset('assets/images/logo.png',
                            width: logoWidth,
                            height: logoWidth * 0.73,
                            fit: BoxFit.contain),
                        SizedBox(
                            height: compact
                                ? 24
                                : (media.size.height * 0.034).clamp(24.0, 48.0)),
                        Text('Complete Profile',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _ink,
                                fontSize: titleSize,
                                fontWeight: FontWeight.w700,
                                height: 1.15)),
                        const SizedBox(height: 8),
                        Text('Just a few more details to join AbhiShare',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _muted,
                                fontSize: (width * 0.034).clamp(16.0, 23.0))),
                        SizedBox(
                            height: compact
                                ? 24
                                : (media.size.height * 0.024).clamp(18.0, 32.0)),
                        SizedBox(
                            height: fieldHeight,
                            child: TextFormField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              style: const TextStyle(fontSize: 17, color: _ink),
                              decoration:
                                  _decoration('Full name', Icons.person_outline),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Enter your full name'
                                  : null,
                            )),
                        SizedBox(height: gap),

                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(left: 8.0, bottom: 6.0),
                            child: Text(
                              'What should we call you?',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                            height: fieldHeight,
                            child: TextFormField(
                              controller: _nicknameController,
                              textCapitalization: TextCapitalization.words,
                              style: const TextStyle(fontSize: 17, color: _ink),
                              decoration: _decoration('Nickname (Optional)', Icons.face),
                            )),
                        SizedBox(height: gap),
                        
                        // Show the secondary identifier input (whichever is missing)
                        if (isPrimaryPhone)
                          ConstrainedBox(
                              constraints: BoxConstraints(minHeight: fieldHeight),
                              child: TextFormField(
                                controller: _secondaryController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(fontSize: 17, color: _ink),
                                onChanged: (_) {
                                  if (_secondaryError != null) {
                                    setState(() => _secondaryError = null);
                                  }
                                },
                                decoration: _decoration(
                                  'Email address',
                                  Icons.mail_outline,
                                  errorText: _secondaryError,
                                ),
                                validator: (v) => v == null || !v.contains('@')
                                    ? 'Enter a valid email'
                                    : null,
                              ))
                        else
                          SizedBox(
                              height: fieldHeight,
                              child: TextFormField(
                                controller: _secondaryController,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(fontSize: 17, color: _ink),
                                onChanged: (_) {
                                  if (_secondaryError != null) {
                                    setState(() => _secondaryError = null);
                                  }
                                },
                                decoration: _decoration(
                                  'Mobile number',
                                  Icons.phone_android_outlined,
                                  errorText: _secondaryError,
                                ),
                                validator: (v) => v == null || v.trim().length < 10
                                    ? 'Enter a valid mobile number'
                                    : null,
                              )),
                        SizedBox(height: gap),
                        SizedBox(
                            height: fieldHeight,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(25),
                              onTap: _selectDate,
                              child: InputDecorator(
                                decoration: _decoration(
                                    'Date of birth', Icons.calendar_month_outlined,
                                    suffix: const Icon(Icons.keyboard_arrow_down,
                                        color: _icon, size: 29)),
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                        _dateOfBirth == null
                                            ? 'Date of birth'
                                            : '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}',
                                        style: TextStyle(
                                            color: _dateOfBirth == null
                                                ? _muted
                                                : _ink,
                                            fontSize: 17))),
                              ),
                            )),
                        SizedBox(height: gap),
                        SizedBox(
                            height: fieldHeight,
                            child: DropdownButtonFormField<String>(
                              value: _gender.isEmpty ? null : _gender,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down,
                                  color: _icon, size: 29),
                              style: const TextStyle(color: _ink, fontSize: 17),
                              decoration:
                                  _decoration('Gender', Icons.people_outline),
                              items: const [
                                DropdownMenuItem(
                                    value: 'male', child: Text('Male')),
                                DropdownMenuItem(
                                    value: 'female', child: Text('Female')),
                                DropdownMenuItem(
                                    value: 'other', child: Text('Other')),
                              ],
                              onChanged: (value) {
                                if (value != null) setState(() => _gender = value);
                              },
                            )),
                        SizedBox(height: gap),

                        // Referral Code (Optional)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(minHeight: fieldHeight),
                              child: TextFormField(
                                controller: _referralController,
                                textCapitalization: TextCapitalization.characters,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: _ink,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                                onChanged: (val) {
                                  if (_isReferralValid || _referralError != null || _referralMessage != null) {
                                    setState(() {
                                      _isReferralValid = false;
                                      _referralMessage = null;
                                      _referralError = null;
                                    });
                                  }
                                },
                                decoration: _decoration(
                                  'Referral Code (Optional)',
                                  Icons.card_giftcard_outlined,
                                  errorText: _referralError,
                                  suffix: Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: _isValidatingReferral
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : _isReferralValid
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF0E8A6A), size: 22),
                                                  IconButton(
                                                    icon: const Icon(Icons.close, size: 18, color: _muted),
                                                    onPressed: () {
                                                      _referralController.clear();
                                                      setState(() {
                                                        _isReferralValid = false;
                                                        _referralMessage = null;
                                                        _referralError = null;
                                                      });
                                                    },
                                                  ),
                                                ],
                                              )
                                            : TextButton(
                                                onPressed: _referralController.text.trim().isEmpty
                                                    ? null
                                                    : () => _validateReferralCode(),
                                                child: const Text(
                                                  'Apply',
                                                  style: TextStyle(
                                                    color: _blue,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                  ),
                                ),
                              ),
                            ),
                            if (_isReferralValid && _referralMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 12.0, top: 4.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.verified_rounded, size: 15, color: Color(0xFF0E8A6A)),
                                    const SizedBox(width: 5),
                                    Text(
                                      _referralMessage!,
                                      style: const TextStyle(
                                        color: Color(0xFF0E8A6A),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: gap * 1.5),
                        SizedBox(
                            height: (fieldHeight * 1.12).clamp(60.0, 78.0),
                            width: double.infinity,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFF0875F9),
                                  Color(0xFF1467F5)
                                ]),
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x330875F9),
                                      blurRadius: 14,
                                      offset: Offset(0, 7))
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(25),
                                  onTap: _isLoading ? null : _sendSecondaryOTP,
                                  child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        if (_isLoading)
                                          const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2))
                                        else ...[
                                          Text('Continue',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: (width * 0.034)
                                                      .clamp(17.0, 23.0),
                                                  fontWeight: FontWeight.w600)),
                                          const Positioned(
                                              right: 24,
                                              child: Icon(Icons.arrow_forward,
                                                  color: Colors.white, size: 30)),
                                        ],
                                      ]),
                                ),
                              ),
                            )),
                        SizedBox(height: compact ? 20 : 30),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 5,
                          children: [
                            const Text('Entered the wrong details?',
                                style: TextStyle(color: _muted, fontSize: 16)),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: const Text('Go Back',
                                  style: TextStyle(
                                      color: _blue,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
