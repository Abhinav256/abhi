import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/notification_state.dart';
import '../services/razorpay_service.dart';
import '../services/wallet_service.dart';
import '../widgets/railone_payment_components.dart';

enum RailOneStep {
  primarySelection, // Screen 1: Primary choices (UPI, Credit / Debit Card)
  makePayment, // Screen A alias for ride compatibility
  upiOptions, // Screen 2: Dedicated UPI selection (Pay by App / Pay by UPI ID)
  upiAppSelection, // Screen 3A: UPI app selection
  upiAppList, // Screen 3A alias
  upiIdEntry, // Screen 3B: UPI ID entry
  cardEntry, // Screen 4: Dedicated Credit / Debit Card entry
  paymentMethods, // Screen B: Ride payment methods
}

/// RailOne-style complete payment screen supporting both Ride Bookings and Wallet Top-Ups.
class RailOnePaymentScreen extends StatefulWidget {
  final String purpose; // 'ride_booking' or 'wallet_topup'
  final double totalAmount;
  final Map<String, dynamic>? ride;
  final int seatsBooked;
  final double pricePerSeat;
  final List<Map<String, dynamic>>? passengers;
  final ApiService? apiService;
  final WalletService? walletService;
  final RazorpayService? razorpayService;

  const RailOnePaymentScreen({
    super.key,
    required this.purpose,
    required this.totalAmount,
    this.ride,
    this.seatsBooked = 1,
    this.pricePerSeat = 0.0,
    this.passengers,
    this.apiService,
    this.walletService,
    this.razorpayService,
  });

  factory RailOnePaymentScreen.forRide({
    Key? key,
    required Map<String, dynamic> ride,
    required int seatsBooked,
    required double pricePerSeat,
    required double totalAmount,
    required List<Map<String, dynamic>> passengers,
    ApiService? apiService,
    WalletService? walletService,
    RazorpayService? razorpayService,
  }) {
    return RailOnePaymentScreen(
      key: key,
      purpose: 'ride_booking',
      totalAmount: totalAmount,
      ride: ride,
      seatsBooked: seatsBooked,
      pricePerSeat: pricePerSeat,
      passengers: passengers,
      apiService: apiService,
      walletService: walletService,
      razorpayService: razorpayService,
    );
  }

  factory RailOnePaymentScreen.forWallet({
    Key? key,
    required double amount,
    ApiService? apiService,
    WalletService? walletService,
    RazorpayService? razorpayService,
  }) {
    return RailOnePaymentScreen(
      key: key,
      purpose: 'wallet_topup',
      totalAmount: amount,
      apiService: apiService,
      walletService: walletService,
      razorpayService: razorpayService,
    );
  }

  @override
  State<RailOnePaymentScreen> createState() => _RailOnePaymentScreenState();
}

class _RailOnePaymentScreenState extends State<RailOnePaymentScreen> {
  static const Color _primaryBlue = Color(0xFF1E60E8);
  static const Color _bg = Color(0xFFF4F7FB);
  static const Color _darkText = Color(0xFF0F172A);

  late final ApiService _apiService = widget.apiService ?? ApiService();
  late final WalletService _walletService =
      widget.walletService ?? WalletService.instance;
  late final RazorpayService _razorpayService =
      widget.razorpayService ?? RazorpayService();

  late RailOneStep _currentStep;

  // Selected option on Screen A ('upi', 'card', or 'other')
  late String _screenASelected;

  // Expandable state on Screen B
  bool _isUpiExpanded = true;
  bool _isNetbankingExpanded = false;
  String _selectedBank = 'State Bank of India';

  // Screen D state (UPI ID)
  final TextEditingController _upiIdController = TextEditingController();
  String? _upiError;

  // Card Entry State (Screen 4)
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _cardExpiryController = TextEditingController();
  final TextEditingController _cardCvvController = TextEditingController();
  final TextEditingController _cardNameController = TextEditingController();
  String? _cardNumberError;
  String? _cardExpiryError;
  String? _cardCvvError;
  String? _cardNameError;
  bool _isCvvObscured = true;
  String _cardNetwork = '';

  // Razorpay Order State
  String? _orderId;
  String? _keyId;
  int? _amountPaise;
  bool _isOrderLoading = false;
  bool _isSubmitting = false;
  String? _orderError;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.purpose == 'wallet_topup'
        ? RailOneStep.primarySelection
        : RailOneStep.makePayment;
    _screenASelected = widget.purpose == 'wallet_topup' ? 'upi' : 'other';

    _cardNumberController.addListener(_onCardNumberChanged);

    _razorpayService.onSuccess = _handleRazorpaySuccess;
    _razorpayService.onError = _handleRazorpayError;
    _razorpayService.init();

    _ensureOrderCreated();
  }

  void _onCardNumberChanged() {
    final net = CardValidator.detectNetwork(_cardNumberController.text);
    if (net != _cardNetwork) {
      setState(() => _cardNetwork = net);
    }
  }

  @override
  void dispose() {
    _razorpayService.dispose();
    _upiIdController.dispose();
    _cardNumberController.removeListener(_onCardNumberChanged);
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    _cardNameController.dispose();
    super.dispose();
  }

  /// Proactively creates or fetches the Razorpay payment order from backend.
  Future<void> _ensureOrderCreated() async {
    if (_orderId != null && _orderId!.isNotEmpty) return;
    setState(() {
      _isOrderLoading = true;
      _orderError = null;
    });

    try {
      Map<String, dynamic> res;
      if (widget.purpose == 'ride_booking') {
        final rideId = widget.ride?['id']?.toString() ?? '';
        final r = widget.ride;
        res = await _apiService.createPaymentOrder(
          purpose: 'ride_booking',
          rideId: rideId,
          seatsBooked: widget.seatsBooked,
          passengers: widget.passengers,
          fromLocation:
              r?['passenger_pickup_name']?.toString() ??
              r?['from_location']?.toString(),
          toLocation:
              r?['passenger_drop_name']?.toString() ??
              r?['to_location']?.toString(),
          pickupLatitude: double.tryParse(
            r?['pickup_latitude']?.toString() ?? '',
          ),
          pickupLongitude: double.tryParse(
            r?['pickup_longitude']?.toString() ?? '',
          ),
          destinationLatitude: double.tryParse(
            r?['destination_latitude']?.toString() ?? '',
          ),
          destinationLongitude: double.tryParse(
            r?['destination_longitude']?.toString() ?? '',
          ),
          pickupDistanceAlongRoute: double.tryParse(
            r?['pickup_distance_along_route']?.toString() ?? '',
          ),
          dropDistanceAlongRoute: double.tryParse(
            r?['drop_distance_along_route']?.toString() ?? '',
          ),
        );
      } else {
        res = await _apiService.createPaymentOrder(
          purpose: 'wallet_topup',
          amount: widget.totalAmount,
        );
      }

      if (!mounted) return;
      final rawOrderId = res['order_id']?.toString();
      if (rawOrderId == null || rawOrderId.isEmpty) {
        throw Exception('Backend did not return a valid Razorpay Order ID');
      }

      setState(() {
        _orderId = rawOrderId;
        _keyId = res['key_id']?.toString() ?? 'rzp_test_TlUKfo2Pi9FVYU';
        final rawPaise = res['amount_paise'];
        _amountPaise = (rawPaise is num)
            ? rawPaise.toInt()
            : (widget.totalAmount * 100).round();
        _isOrderLoading = false;
        _orderError = null;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Payment order creation error: $e');
      setState(() {
        _isOrderLoading = false;
        _orderError = e.toString();
        _orderId = null;
      });
    }
  }

  void _onBackPress() {
    switch (_currentStep) {
      case RailOneStep.primarySelection:
      case RailOneStep.makePayment:
        Navigator.of(context).pop(false);
        break;
      case RailOneStep.paymentMethods:
        setState(() => _currentStep = RailOneStep.makePayment);
        break;
      case RailOneStep.upiOptions:
        setState(() => _currentStep = RailOneStep.primarySelection);
        break;
      case RailOneStep.upiAppSelection:
      case RailOneStep.upiAppList:
      case RailOneStep.upiIdEntry:
        setState(() {
          _currentStep = widget.purpose == 'ride_booking'
              ? RailOneStep.paymentMethods
              : RailOneStep.upiOptions;
        });
        break;
      case RailOneStep.cardEntry:
        setState(() {
          _currentStep = widget.purpose == 'ride_booking'
              ? RailOneStep.paymentMethods
              : RailOneStep.primarySelection;
        });
        break;
    }
  }

  // ---- CHECKOUT INITIATION & HANDOFF ----

  Future<void> _initiateCheckout({
    String? paymentMethod,
    String? bank,
    String? vpa,
    String? upiApp,
    String? cardNumber,
    String? cardExpiryMonth,
    String? cardExpiryYear,
    String? cardCvv,
    String? cardHolderName,
  }) async {
    if (_isSubmitting) return;

    if (_orderId == null || _orderId!.isEmpty) {
      await _ensureOrderCreated();
    }

    if (_orderId == null || _orderId!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _orderError != null && _orderError!.isNotEmpty
                  ? 'Failed to create payment order: $_orderError'
                  : 'Unable to initialize Razorpay order. Please check connection and retry.',
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _initiateCheckout(
                paymentMethod: paymentMethod,
                bank: bank,
                vpa: vpa,
                upiApp: upiApp,
                cardNumber: cardNumber,
                cardExpiryMonth: cardExpiryMonth,
                cardExpiryYear: cardExpiryYear,
                cardCvv: cardCvv,
                cardHolderName: cardHolderName,
              ),
            ),
          ),
        );
      }
      return;
    }

    final effectiveOrderId = _orderId!;
    final effectiveKeyId = _keyId ?? 'rzp_test_TlUKfo2Pi9FVYU';
    final effectiveAmountPaise =
        _amountPaise ?? (widget.totalAmount * 100).round();

    setState(() => _isSubmitting = true);

    String? contact;
    String? email;
    try {
      final user = await _apiService.getCurrentUser();
      contact = user['phone']?.toString();
      email = user['email']?.toString();
    } catch (_) {}

    final description = widget.purpose == 'ride_booking'
        ? '${widget.ride?['from_location'] ?? 'Ride'} → ${widget.ride?['to_location'] ?? 'Destination'}'
        : 'Wallet Top-up';

    _razorpayService.openCheckout(
      keyId: effectiveKeyId,
      orderId: effectiveOrderId,
      amountPaise: effectiveAmountPaise,
      name: 'AbhiShare',
      description: description,
      contact: contact,
      email: email,
      paymentMethod: paymentMethod,
      bank: bank,
      vpa: vpa,
      upiApp: upiApp,
      cardNumber: cardNumber,
      cardExpiryMonth: cardExpiryMonth,
      cardExpiryYear: cardExpiryYear,
      cardCvv: cardCvv,
      cardHolderName: cardHolderName,
    );
  }

  // ---- PAYMENT SUCCESS & VERIFICATION ----

  Future<void> _handleRazorpaySuccess(
    String paymentId,
    String? callbackOrderId,
    String? signature,
  ) async {
    final effectiveOrderId =
        (callbackOrderId != null && callbackOrderId.isNotEmpty)
        ? callbackOrderId
        : _orderId;

    if (effectiveOrderId == null || effectiveOrderId.isEmpty) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment received, but order reference was missing.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Verifying payment signature with server...'),
            ],
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }

    try {
      final verifyRes = await _apiService.verifyPayment(
        orderId: effectiveOrderId,
        paymentId: paymentId,
        signature: signature ?? '',
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (verifyRes['success'] == true) {
        if (widget.purpose == 'wallet_topup') {
          await _walletService.refreshFromBackend();
          if (mounted) {
            _showWalletSuccessDialog(paymentId);
          }
        } else {
          NotificationState.instance.refresh();
          if (mounted) {
            _showRideSuccessDialog(verifyRes, paymentId);
          }
        }
      } else {
        throw Exception(verifyRes['message'] ?? 'Payment verification failed');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment verification failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleRazorpayError(int code, String message) {
    if (_orderId != null && _orderId!.isNotEmpty) {
      _apiService.cancelPaymentOrder(orderId: _orderId!, reason: message);
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment not completed: $message'),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---- CONFIRMATION DIALOGS ----

  void _showRideSuccessDialog(
    Map<String, dynamic> verifyRes,
    String paymentId,
  ) {
    final bookingId =
        verifyRes['booking_id']?.toString() ??
        'BK-${DateTime.now().millisecondsSinceEpoch}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF0E8A6A),
                  size: 42,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Booking Confirmed!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _darkText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your payment of ₹${widget.totalAmount.toStringAsFixed(2)} was verified successfully via Razorpay. Your seat is confirmed!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _dialogRow('Booking ID', '#$bookingId', isBold: true),
                    const SizedBox(height: 6),
                    _dialogRow('Payment ID', paymentId),
                    const SizedBox(height: 6),
                    _dialogRow(
                      'Amount Paid',
                      '₹${widget.totalAmount.toStringAsFixed(2)}',
                      isGreen: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop(true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text('View Booking Details'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showWalletSuccessDialog(String paymentId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF0E8A6A),
                  size: 42,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Money Added Successfully!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _darkText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '₹${widget.totalAmount.toStringAsFixed(2)} has been added to your AbhiShare Wallet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _dialogRow('Payment ID', paymentId),
                    const SizedBox(height: 6),
                    _dialogRow(
                      'Amount Added',
                      '₹${widget.totalAmount.toStringAsFixed(2)}',
                      isGreen: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop(true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text('Back to Wallet'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dialogRow(
    String label,
    String value, {
    bool isBold = false,
    bool isGreen = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isGreen ? const Color(0xFF0E8A6A) : _darkText,
          ),
        ),
      ],
    );
  }

  // ---- FEE BOTTOM SHEET (Screen F: 8.png) ----

  void _showProcessingFeeSheet({
    required String methodTitle,
    required double fee,
    required double gst,
    required VoidCallback onProceed,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return PaymentFeeBottomSheet(
          amount: widget.totalAmount,
          fee: fee,
          gst: gst,
          isProcessing: _isSubmitting,
          onProceed: () {
            Navigator.of(sheetCtx).pop();
            onProceed();
          },
          onCancel: () {
            Navigator.of(sheetCtx).pop();
          },
        );
      },
    );
  }

  // ---- MAIN BUILD DISPATCHER ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          _currentStep == RailOneStep.primarySelection ||
          _currentStep == RailOneStep.makePayment,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _onBackPress();
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHeaderForStep(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 18),
                      _buildBodyForStep(),
                      const RailOneFooter(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderForStep() {
    final effectiveOrderId = _orderId ?? 'Loading...';

    switch (_currentStep) {
      case RailOneStep.primarySelection:
      case RailOneStep.makePayment:
        // Screen A header (1.png)
        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: _primaryBlue,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + 8,
            16,
            24,
          ),
          child: Row(
            children: [
              InkWell(
                onTap: _onBackPress,
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Make Payment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pay ₹${widget.totalAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case RailOneStep.upiOptions:
      case RailOneStep.paymentMethods:
      case RailOneStep.upiAppSelection:
      case RailOneStep.upiAppList:
      case RailOneStep.upiIdEntry:
      case RailOneStep.cardEntry:
        // Screen B, C, D, Card header (2.png, 3.png, 4.png)
        return RailOneHeader(
          orderId: effectiveOrderId,
          amount: widget.totalAmount,
          onBack: _onBackPress,
          showFloatingCard: true,
        );
    }
  }

  Widget _buildBodyForStep() {
    switch (_currentStep) {
      case RailOneStep.primarySelection:
      case RailOneStep.makePayment:
        return _buildScreenA();
      case RailOneStep.upiOptions:
        return _buildUpiOptions();
      case RailOneStep.paymentMethods:
        return _buildScreenB();
      case RailOneStep.upiAppSelection:
      case RailOneStep.upiAppList:
        return _buildScreenC();
      case RailOneStep.upiIdEntry:
        return _buildScreenD();
      case RailOneStep.cardEntry:
        return _buildCardEntry();
    }
  }

  // ===========================================================================
  // SCREEN A: Make Payment (Primary Choice: UPI or Credit / Debit Card)
  // ===========================================================================

  Widget _buildScreenA() {
    final isWallet = widget.purpose == 'wallet_topup';

    return Column(
      children: [
        // Rounded card container
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // 1. UPI Option Row
              InkWell(
                onTap: () {
                  setState(() => _screenASelected = 'upi');
                  if (isWallet) {
                    setState(() => _currentStep = RailOneStep.upiOptions);
                  }
                },
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 22,
                  ),
                  child: Row(
                    children: [
                      RailOneBrandLogos.upiBadge(height: 24),
                      const SizedBox(width: 12),
                      RailOneBrandLogos.miniUpiAppsRow(),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade700,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: DashedDivider(dashWidth: 4, dashSpace: 3),
              ),

              // 2. Second Option: Credit / Debit Card (for wallet) OR Other Payment Methods (for ride)
              if (isWallet)
                InkWell(
                  onTap: () {
                    setState(() => _screenASelected = 'card');
                    setState(() => _currentStep = RailOneStep.cardEntry);
                  },
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 22,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF64748B),
                              width: 1.2,
                            ),
                          ),
                          child: const Icon(
                            Icons.credit_card_rounded,
                            color: Color(0xFF1E293B),
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          'Credit / Debit Card',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _darkText,
                          ),
                        ),
                        const SizedBox(width: 8),
                        RailOneBrandLogos.miniCardNetworksRow(),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade700,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                )
              else
                InkWell(
                  onTap: () {
                    setState(() => _screenASelected = 'other');
                    setState(() => _currentStep = RailOneStep.paymentMethods);
                  },
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 22,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 20,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFF64748B),
                              width: 1.5,
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              height: 4,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'Other Payment Methods',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _darkText,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade700,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // Prominent Action Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: () {
              if (isWallet) {
                if (_screenASelected == 'card') {
                  setState(() => _currentStep = RailOneStep.cardEntry);
                } else {
                  setState(() => _currentStep = RailOneStep.upiOptions);
                }
              } else {
                if (_screenASelected == 'other') {
                  setState(() => _currentStep = RailOneStep.paymentMethods);
                } else {
                  setState(() => _currentStep = RailOneStep.upiAppSelection);
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: _primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              elevation: 0,
            ),
            child: Text(
              isWallet
                  ? (_screenASelected == 'card'
                        ? 'Proceed to Card Payment'
                        : 'Proceed to UPI Payment')
                  : (_screenASelected == 'other'
                        ? 'Pay Using Other Methods'
                        : 'Pay Using UPI'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SCREEN 2: Dedicated UPI Selection (Pay by UPI App OR Pay by Any UPI ID)
  // ===========================================================================

  Widget _buildUpiOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UPI Payment',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _darkText,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Choose how you would like to pay via UPI',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Option 1: Pay by UPI App
              InkWell(
                onTap: () {
                  setState(() => _currentStep = RailOneStep.upiAppSelection);
                },
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          color: _primaryBlue,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pay by UPI App',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _darkText,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'BHIM, Google Pay, PhonePe, Paytm, Navi, CRED & super.money',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade600,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: DashedDivider(dashWidth: 4, dashSpace: 3),
              ),

              // Option 2: Pay by Any UPI ID
              InkWell(
                onTap: () {
                  setState(() => _currentStep = RailOneStep.upiIdEntry);
                },
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.alternate_email_rounded,
                          color: Color(0xFF16A34A),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pay by Any UPI ID',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _darkText,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Enter your UPI ID (e.g. mobile@upi, name@bank)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade600,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SCREEN 4: Dedicated Credit / Debit Card Entry
  // ===========================================================================

  Widget _buildCardEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Credit / Debit Card',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _darkText,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Enter card details to proceed with payment',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Number Field
              const Text(
                'Card Number',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _cardNumberController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                  LengthLimitingTextInputFormatter(23),
                  CardNumberInputFormatter(),
                ],
                onChanged: (_) {
                  if (_cardNumberError != null) {
                    setState(() => _cardNumberError = null);
                  }
                },
                decoration: InputDecoration(
                  hintText: '1234 5678 9012 3456',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade400,
                    letterSpacing: 1.2,
                  ),
                  filled: true,
                  fillColor: _bg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: _primaryBlue,
                      width: 1.5,
                    ),
                  ),
                  errorText: _cardNumberError,
                  prefixIcon: const Icon(
                    Icons.credit_card_rounded,
                    color: Color(0xFF64748B),
                    size: 22,
                  ),
                  suffixIcon: _cardNetwork.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFC7D2FE),
                                  ),
                                ),
                                child: Text(
                                  _cardNetwork,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _primaryBlue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              // Expiry & CVV Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Expiration Date (MM/YY)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Expires (MM/YY)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _cardExpiryController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9/]'),
                            ),
                            LengthLimitingTextInputFormatter(5),
                            CardExpiryInputFormatter(),
                          ],
                          onChanged: (_) {
                            if (_cardExpiryError != null) {
                              setState(() => _cardExpiryError = null);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'MM/YY',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade400,
                            ),
                            filled: true,
                            fillColor: _bg,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: _primaryBlue,
                                width: 1.5,
                              ),
                            ),
                            errorText: _cardExpiryError,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Security Code (CVV)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CVV',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _cardCvvController,
                          keyboardType: TextInputType.number,
                          obscureText: _isCvvObscured,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          onChanged: (_) {
                            if (_cardCvvError != null) {
                              setState(() => _cardCvvError = null);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: '123',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade400,
                            ),
                            filled: true,
                            fillColor: _bg,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: _primaryBlue,
                                width: 1.5,
                              ),
                            ),
                            errorText: _cardCvvError,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isCvvObscured
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                              onPressed: () {
                                setState(
                                  () => _isCvvObscured = !_isCvvObscured,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Cardholder Name
              const Text(
                'Cardholder Name',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _cardNameController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (_cardNameError != null) {
                    setState(() => _cardNameError = null);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Name as printed on card',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                  ),
                  filled: true,
                  fillColor: _bg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: _primaryBlue,
                      width: 1.5,
                    ),
                  ),
                  errorText: _cardNameError,
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Security & Trust Notice
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: Color(0xFF0E8A6A),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '128-bit SSL encrypted • Card details are processed securely via Razorpay • PCI-DSS Level 1 compliant',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Prominent Pay Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _isSubmitting ? null : _submitCardPayment,
            style: FilledButton.styleFrom(
              backgroundColor: _primaryBlue,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Pay ₹${widget.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _submitCardPayment() {
    final rawNumber = _cardNumberController.text.trim();
    final rawExpiry = _cardExpiryController.text.trim();
    final rawCvv = _cardCvvController.text.trim();
    final rawName = _cardNameController.text.trim();

    String? numErr;
    String? expErr;
    String? cvvErr;
    String? nameErr;

    final cleanNum = rawNumber.replaceAll(' ', '');
    if (cleanNum.isEmpty) {
      numErr = 'Card number is required';
    } else if (!CardValidator.isValidLuhn(cleanNum)) {
      numErr = 'Please enter a valid card number';
    }

    if (rawExpiry.isEmpty) {
      expErr = 'Expiry date required (MM/YY)';
    } else if (!CardValidator.isValidExpiry(rawExpiry)) {
      expErr = 'Invalid expiry date (MM/YY)';
    }

    if (rawCvv.isEmpty) {
      cvvErr = 'CVV is required';
    } else if (!CardValidator.isValidCvv(rawCvv, network: _cardNetwork)) {
      cvvErr = 'Enter 3 or 4 digit CVV';
    }

    if (rawName.isEmpty) {
      nameErr = 'Cardholder name is required';
    } else if (rawName.length < 2) {
      nameErr = 'Please enter a valid name';
    }

    if (numErr != null || expErr != null || cvvErr != null || nameErr != null) {
      setState(() {
        _cardNumberError = numErr;
        _cardExpiryError = expErr;
        _cardCvvError = cvvErr;
        _cardNameError = nameErr;
      });
      return;
    }

    setState(() {
      _cardNumberError = null;
      _cardExpiryError = null;
      _cardCvvError = null;
      _cardNameError = null;
    });

    final expParts = rawExpiry.split('/');
    final expMonth = expParts[0];
    final expYear = '20${expParts[1]}';

    _initiateCheckout(
      paymentMethod: 'card',
      cardNumber: cleanNum,
      cardExpiryMonth: expMonth,
      cardExpiryYear: expYear,
      cardCvv: rawCvv,
      cardHolderName: rawName,
    );
  }

  // ===========================================================================
  // SCREEN B: Payment Methods (Reference: 2.png, 5.png, 7.png)
  // ===========================================================================

  Widget _buildScreenB() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            'Payment Methods',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _darkText,
            ),
          ),
        ),
        const SizedBox(height: 8),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. UPI Expandable Section
              InkWell(
                onTap: () {
                  setState(() => _isUpiExpanded = !_isUpiExpanded);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      RailOneBrandLogos.upiBadge(height: 22),
                      const SizedBox(width: 8),
                      RailOneBrandLogos.miniUpiAppsRow(),
                      const Spacer(),
                      Icon(
                        _isUpiExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey.shade700,
                        size: 26,
                      ),
                    ],
                  ),
                ),
              ),

              if (_isUpiExpanded) ...[
                const SizedBox(height: 14),
                // Pay by any UPI App sub-card
                InkWell(
                  onTap: () {
                    setState(() => _currentStep = RailOneStep.upiAppSelection);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.layers_rounded,
                            color: Color(0xFF475569),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          'Pay by any UPI App',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _darkText,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade600,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Pay by any UPI ID sub-card
                InkWell(
                  onTap: () {
                    setState(() => _currentStep = RailOneStep.upiIdEntry);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFF475569),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          'Pay by any UPI ID',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _darkText,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade600,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                const DashedDivider(dashWidth: 4, dashSpace: 3),
                const SizedBox(height: 12),

                // BHIM option
                InkWell(
                  onTap: () =>
                      _initiateCheckout(paymentMethod: 'upi', upiApp: 'bhim'),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        RailOneBrandLogos.appIcon('BHIM'),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'BHIM',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _darkText,
                              ),
                            ),
                            Text(
                              'Fast & direct bank UPI payment',
                              style: TextStyle(
                                fontSize: 12,
                                color: _primaryBlue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade600,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),
              const DashedDivider(dashWidth: 4, dashSpace: 3),
              const SizedBox(height: 14),

              // 2. Credit / Debit Cards Row
              InkWell(
                onTap: () {
                  _showProcessingFeeSheet(
                    methodTitle: 'Credit / Debit Cards',
                    fee: 0.18,
                    gst: 0.03,
                    onProceed: () => _initiateCheckout(paymentMethod: 'card'),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.credit_card_rounded,
                        color: Color(0xFF475569),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Credit / Debit Cards',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _darkText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      RailOneBrandLogos.miniCardNetworksRow(),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade700,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),
              const DashedDivider(dashWidth: 4, dashSpace: 3),
              const SizedBox(height: 14),

              // 3. Netbanking Expandable Section
              InkWell(
                onTap: () {
                  setState(
                    () => _isNetbankingExpanded = !_isNetbankingExpanded,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_balance_outlined,
                        color: Color(0xFF475569),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Netbanking',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _darkText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      RailOneBrandLogos.miniBanksRow(),
                      const Spacer(),
                      Icon(
                        _isNetbankingExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey.shade700,
                        size: 26,
                      ),
                    ],
                  ),
                ),
              ),

              if (_isNetbankingExpanded) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildBankTile('State Bank of India', 'SBIN'),
                      const DashedDivider(dashWidth: 4, dashSpace: 3),
                      _buildBankTile('Axis Bank [Retail]', 'UTIB'),
                      const DashedDivider(dashWidth: 4, dashSpace: 3),
                      _buildBankTile('HDFC Bank [Retail]', 'HDFC'),
                      const DashedDivider(dashWidth: 4, dashSpace: 3),
                      // All Other Banks Row
                      InkWell(
                        onTap: () {
                          _showProcessingFeeSheet(
                            methodTitle: 'Netbanking (All Banks)',
                            fee: 0.18,
                            gst: 0.03,
                            onProceed: () =>
                                _initiateCheckout(paymentMethod: 'netbanking'),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.search_rounded,
                                  color: Color(0xFF475569),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Text(
                                'All Other Banks',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _darkText,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.grey.shade600,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBankTile(String name, String bankCode) {
    final isSelected = _selectedBank == name;

    return InkWell(
      onTap: () {
        setState(() => _selectedBank = name);
        _showProcessingFeeSheet(
          methodTitle: name,
          fee: 0.18,
          gst: 0.03,
          onProceed: () =>
              _initiateCheckout(paymentMethod: 'netbanking', bank: bankCode),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            RailOneBrandLogos.bankLogo(name),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _darkText,
                ),
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? _primaryBlue : const Color(0xFFCBD5E1),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _primaryBlue,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SCREEN C: Pay by any UPI App (Reference: 3.png)
  // ===========================================================================

  Widget _buildScreenC() {
    final apps = const [
      {'name': 'BHIM', 'code': 'bhim'},
      {'name': 'Google Pay', 'code': 'gpay'},
      {'name': 'PhonePe', 'code': 'phonepe'},
      {'name': 'Paytm', 'code': 'paytm'},
      {'name': 'Navi', 'code': 'navi'},
      {'name': 'CRED', 'code': 'cred'},
      {'name': 'super.money', 'code': 'supermoney'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            'Pay by any UPI App',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _darkText,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Colors.blueGrey.shade700,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Razorpay Test Mode: App handoff is handled securely via Razorpay Checkout.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < apps.length; i++) ...[
                InkWell(
                  onTap: () => _initiateCheckout(
                    paymentMethod: 'upi',
                    upiApp: apps[i]['code'],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        RailOneBrandLogos.appIcon(apps[i]['name']!),
                        const SizedBox(width: 16),
                        Text(
                          apps[i]['name']!,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _darkText,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade600,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
                if (i < apps.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: DashedDivider(dashWidth: 4, dashSpace: 3),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SCREEN D: Pay by any UPI ID (Reference: 4.png)
  // ===========================================================================

  Widget _buildScreenD() {
    final chips = const [
      {'name': 'BHIM', 'suffix': '@upi'},
      {'name': 'PhonePe', 'suffix': '@ybl'},
      {'name': 'Google Pay', 'suffix': '@okhdfcbank'},
      {'name': 'Paytm', 'suffix': '@paytm'},
      {'name': 'Others', 'suffix': '@bank'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            'Pay by any UPI ID',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _darkText,
            ),
          ),
        ),
        const SizedBox(height: 8),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Horizontal row of app chips
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final chip in chips)
                    InkWell(
                      onTap: () {
                        final current = _upiIdController.text.trim();
                        final atIndex = current.indexOf('@');
                        final base = atIndex >= 0
                            ? current.substring(0, atIndex)
                            : current;
                        if (base.isNotEmpty) {
                          _upiIdController.text = '$base${chip['suffix']}';
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 58,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            RailOneBrandLogos.appIcon(chip['name']!),
                            const SizedBox(height: 6),
                            Text(
                              chip['name']!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 18),

              // Razorpay Test Mode Simulation Chips
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.science_outlined,
                          size: 15,
                          color: Colors.blueGrey.shade700,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Test Mode Simulation UPI IDs',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _darkText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _upiIdController.text = 'success@razorpay';
                                _upiError = null;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFA5D6A7),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 14,
                                    color: Color(0xFF2E7D32),
                                  ),
                                  SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'success@razorpay',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1B5E20),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _upiIdController.text = 'failure@razorpay';
                                _upiError = null;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFEF9A9A),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cancel_rounded,
                                    size: 14,
                                    color: Color(0xFFC62828),
                                  ),
                                  SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'failure@razorpay',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFB71C1C),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Enter Your UPI ID',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),

              // UPI ID input field
              TextField(
                controller: _upiIdController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) {
                  if (_upiError != null) {
                    setState(() => _upiError = null);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'e.g. mobile@upi or name@okaxis',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _primaryBlue,
                      width: 1.5,
                    ),
                  ),
                  errorText: _upiError,
                  suffixIcon: _upiIdController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _upiIdController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // Dynamic Pay Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _isSubmitting
                ? null
                : () {
                    final upi = _upiIdController.text.trim();
                    final regex = RegExp(
                      r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$',
                    );
                    if (!regex.hasMatch(upi)) {
                      setState(() {
                        _upiError =
                            'Please enter a valid UPI ID (e.g. yourname@bank)';
                      });
                      return;
                    }
                    _initiateCheckout(paymentMethod: 'upi', vpa: upi);
                  },
            style: FilledButton.styleFrom(
              backgroundColor: _primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Pay ₹${widget.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
