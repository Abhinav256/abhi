import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Callback signatures for Razorpay checkout events
typedef OnPaymentSuccess = void Function(
    String paymentId, String? orderId, String? signature);
typedef OnPaymentError = void Function(int code, String message);
typedef OnExternalWallet = void Function(String walletName);

/// Wrapper around the Razorpay Flutter SDK for test-mode payment gateway execution.
class RazorpayService {
  Razorpay? _razorpay;
  bool _isInitialized = false;

  OnPaymentSuccess? onSuccess;
  OnPaymentError? onError;
  OnExternalWallet? onExternalWallet;

  RazorpayService({
    this.onSuccess,
    this.onError,
    this.onExternalWallet,
  });

  void init() {
    if (_isInitialized) return;
    try {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      _isInitialized = true;
    } catch (e) {
      debugPrint('RazorpayService initialization notice: $e');
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    debugPrint('Razorpay payment success: ${response.paymentId}');
    onSuccess?.call(
      response.paymentId ?? '',
      response.orderId,
      response.signature,
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint(
        'Razorpay payment error: [code=${response.code}] message=${response.message} error=${response.error}');
    String msg = 'Payment cancelled or declined';
    if (response.message != null &&
        response.message != 'undefined' &&
        response.message!.trim().isNotEmpty) {
      msg = response.message!.trim();
    } else if (response.error is Map) {
      final errMap = response.error as Map;
      final desc = errMap['description']?.toString();
      if (desc != null && desc != 'undefined' && desc.isNotEmpty) {
        msg = desc;
      }
    }
    onError?.call(
      response.code ?? -1,
      msg,
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('Razorpay external wallet: ${response.walletName}');
    onExternalWallet?.call(response.walletName ?? '');
  }

  /// Opens the Razorpay Checkout flow in Test Mode.
  void openCheckout({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String name,
    required String description,
    String? contact,
    String? email,
    String? paymentMethod,
    String? bank,
    String? vpa,
    String? upiApp,
    String? cardNumber,
    String? cardExpiryMonth,
    String? cardExpiryYear,
    String? cardCvv,
    String? cardHolderName,
  }) {
    if (!_isInitialized || _razorpay == null) {
      init();
    }

    final prefillMap = <String, dynamic>{
      'contact': (contact != null && contact.trim().isNotEmpty)
          ? contact.trim()
          : '9876543210',
      'email': (email != null && email.trim().isNotEmpty)
          ? email.trim()
          : 'customer@abhishare.com',
    };

    if (paymentMethod != null && paymentMethod.trim().isNotEmpty) {
      prefillMap['method'] = paymentMethod.trim();
    }

    if (vpa != null && vpa.trim().isNotEmpty) {
      prefillMap['vpa'] = vpa.trim();
    }
    if (bank != null && bank.trim().isNotEmpty) {
      prefillMap['bank'] = bank.trim();
    }

    // Secure card details prefilling (processed client-side via Razorpay SDK)
    if (cardHolderName != null && cardHolderName.trim().isNotEmpty) {
      prefillMap['name'] = cardHolderName.trim();
    }
    if (cardNumber != null && cardNumber.trim().isNotEmpty) {
      prefillMap['card[number]'] = cardNumber.replaceAll(RegExp(r'\s+'), '');
    }
    if (cardExpiryMonth != null && cardExpiryMonth.trim().isNotEmpty) {
      prefillMap['card[expiry_month]'] = cardExpiryMonth.trim();
    }
    if (cardExpiryYear != null && cardExpiryYear.trim().isNotEmpty) {
      prefillMap['card[expiry_year]'] = cardExpiryYear.trim();
    }
    if (cardCvv != null && cardCvv.trim().isNotEmpty) {
      prefillMap['card[cvv]'] = cardCvv.trim();
    }

    final options = <String, dynamic>{
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': name,
      'description': description,
      'timeout': 300, // 5 minutes
      'theme': {
        'color': '#1E60E8',
      },
      'prefill': prefillMap,
      'retry': {
        'enabled': true,
        'max_count': 3,
      },
      'send_sms_hash': true,
    };

    if (bank != null && bank.isNotEmpty) {
      options['bank'] = bank;
    }

    if (upiApp != null && upiApp.isNotEmpty) {
      options['upi_app'] = upiApp;
    }

    // Strict method isolation so Razorpay only renders the selected method
    final isCard = paymentMethod == 'card';
    final isUpi = paymentMethod == 'upi';
    final isNetbanking = paymentMethod == 'netbanking';

    if (isCard) {
      options['method'] = {
        'card': true,
        'upi': false,
        'netbanking': false,
        'wallet': false,
        'paylater': false,
      };
      options['theme'] = {
        'color': '#1E60E8',
        'hide_topbar': true,
      };
      options['config'] = {
        'display': {
          'blocks': {
            'card_block': {
              'name': 'Credit / Debit Card',
              'instruments': [
                {'method': 'card'}
              ]
            }
          },
          'sequence': ['block.card_block'],
          'preferences': {'show_default_blocks': false},
          'hide': [
            {'method': 'upi'},
            {'method': 'netbanking'},
            {'method': 'wallet'},
            {'method': 'paylater'}
          ]
        }
      };
    } else if (isUpi) {
      options['method'] = {
        'upi': true,
        'card': false,
        'netbanking': false,
        'wallet': false,
        'paylater': false,
      };
      options['theme'] = {
        'color': '#1E60E8',
        'hide_topbar': true,
      };
      if (vpa != null && vpa.isNotEmpty) {
        options['vpa'] = vpa;
      }
      options['config'] = {
        'display': {
          'blocks': {
            'upi_block': {
              'name': 'UPI Payment',
              'instruments': [
                {'method': 'upi'}
              ]
            }
          },
          'sequence': ['block.upi_block'],
          'preferences': {'show_default_blocks': false},
          'hide': [
            {'method': 'card'},
            {'method': 'netbanking'},
            {'method': 'wallet'},
            {'method': 'paylater'}
          ]
        }
      };
    } else if (isNetbanking) {
      options['method'] = {
        'netbanking': true,
        'card': false,
        'upi': false,
        'wallet': false,
        'paylater': false,
      };
      options['theme'] = {
        'color': '#1E60E8',
        'hide_topbar': true,
      };
      options['config'] = {
        'display': {
          'blocks': {
            'nb_block': {
              'name': 'Netbanking',
              'instruments': [
                {'method': 'netbanking'}
              ]
            }
          },
          'sequence': ['block.nb_block'],
          'preferences': {'show_default_blocks': false},
          'hide': [
            {'method': 'card'},
            {'method': 'upi'},
            {'method': 'wallet'},
            {'method': 'paylater'}
          ]
        }
      };
    }

    try {
      debugPrint(
          'Opening Razorpay Checkout with order_id=$orderId, amount=$amountPaise, key=$keyId, method=$paymentMethod');
      _razorpay!.open(options);
    } catch (e) {
      debugPrint('Error opening Razorpay checkout: $e');
      onError?.call(-1, 'Could not open payment checkout: $e');
    }
  }

  void dispose() {
    try {
      _razorpay?.clear();
    } catch (_) {}
    _isInitialized = false;
  }
}
