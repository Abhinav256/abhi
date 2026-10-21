import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abhi_share/widgets/add_money_bottom_sheet.dart';
import 'package:abhi_share/services/api_service.dart';
import 'package:abhi_share/services/razorpay_service.dart';
import 'package:abhi_share/services/session_service.dart';

class MockWalletRazorpayService extends RazorpayService {
  bool initCalled = false;
  bool disposeCalled = false;
  Map<String, dynamic>? lastCheckoutOptions;
  bool autoSucceed = false;
  bool autoFail = false;
  String failMessage = 'Top-up cancelled by user';

  @override
  void init() {
    initCalled = true;
  }

  @override
  void dispose() {
    disposeCalled = true;
  }

  @override
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
    lastCheckoutOptions = {
      'keyId': keyId,
      'orderId': orderId,
      'amountPaise': amountPaise,
      'name': name,
      'description': description,
      'paymentMethod': paymentMethod,
      'bank': bank,
      'vpa': vpa,
      'upiApp': upiApp,
      'cardNumber': cardNumber,
      'cardExpiryMonth': cardExpiryMonth,
      'cardExpiryYear': cardExpiryYear,
      'cardCvv': cardCvv,
      'cardHolderName': cardHolderName,
    };
    if (autoSucceed) {
      onSuccess?.call('pay_wal_topup_999', orderId, 'valid_wallet_sig');
    } else if (autoFail) {
      onError?.call(0, failMessage);
    }
  }
}

class MockWalletApiService extends ApiService {
  final Map<String, dynamic> mockUser;
  Map<String, dynamic>? lastOrderPayload;
  Map<String, dynamic>? lastVerifyPayload;
  int orderCallCount = 0;
  int verifyCallCount = 0;
  int cancelCallCount = 0;

  MockWalletApiService({
    required this.mockUser,
  });

  @override
  Future<Map<String, dynamic>> getCurrentUser() async {
    return mockUser;
  }

  @override
  Future<Map<String, dynamic>> getWalletSummary() async {
    return {
      'wallet': {'balance': 750.0},
      'recent_transactions': [],
      'saved_bank_accounts': [],
      'saved_upi_ids': [],
      'saved_cards': [],
    };
  }

  @override
  Future<Map<String, dynamic>> createPaymentOrder({
    required String purpose,
    double? amount,
    String? rideId,
    int? seatsBooked,
    List<Map<String, dynamic>>? passengers,
    double? pickupDistanceAlongRoute,
    double? dropDistanceAlongRoute,
    double? pickupLatitude,
    double? pickupLongitude,
    double? destinationLatitude,
    double? destinationLongitude,
    String? fromLocation,
    String? toLocation,
  }) async {
    orderCallCount++;
    lastOrderPayload = {
      'purpose': purpose,
      'amount': amount,
    };
    return {
      'order_id': 'order_wal_555',
      'key_id': 'rzp_test_TlUKfo2Pi9FVYU',
      'amount_paise': ((amount ?? 0) * 100).toInt(),
      'currency': 'INR',
      'status': 'created',
    };
  }

  @override
  Future<Map<String, dynamic>> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    verifyCallCount++;
    lastVerifyPayload = {
      'order_id': orderId,
      'payment_id': paymentId,
      'signature': signature,
    };
    return {
      'success': true,
      'status': 'verified',
      'payment_id': paymentId,
      'wallet_txn': {
        'id': 'TXN-999',
        'title': 'Money Added',
        'subtitle': 'Razorpay (Google Pay)',
        'amount': lastOrderPayload?['amount'] ?? 250.0,
        'type': 'money_added',
        'status': 'completed',
        'timestamp': DateTime.now().toIso8601String(),
        'reference_number': paymentId,
        'payment_method': 'Razorpay Gateway',
      },
      'message': 'Payment verified and wallet credited successfully.',
    };
  }

  @override
  Future<Map<String, dynamic>> cancelPaymentOrder({
    required String orderId,
    String? reason,
  }) async {
    cancelCallCount++;
    return {'status': 'cancelled'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseUser = {
    'id': 'user-uuid-888',
    'full_name': 'Abhinav Reddy',
    'phone': '9876543210',
    'email': 'abhinav@example.com',
  };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('Add Money to Wallet Razorpay Tests', () {
    testWidgets(
        '1. Screen A presents EXACTLY UPI and Credit/Debit Card choices for wallet topup',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await SessionService()
          .saveSession(sessionToken: 'token', userId: 'user-uuid-888');

      final mockApi = MockWalletApiService(mockUser: baseUser);
      final mockRazorpay = MockWalletRazorpayService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddMoneyBottomSheet(
              initialAmount: 250.0,
              apiService: mockApi,
              razorpayService: mockRazorpay,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Add Money bottom sheet UI and suggestion chips
      expect(find.text('Add Money to Wallet'), findsOneWidget);
      expect(find.text('+₹100'), findsOneWidget);
      expect(find.text('+₹200'), findsOneWidget);
      expect(find.text('+₹500'), findsOneWidget);
      expect(find.text('+₹1000'), findsOneWidget);
      expect(find.text('Proceed to Pay'), findsOneWidget);

      // Tap Proceed to Pay
      await tester.tap(find.text('Proceed to Pay'));
      await tester.pumpAndSettle();

      // Verify Screen A displays EXACTLY two primary choices: UPI and Credit / Debit Card
      expect(find.text('UPI'), findsOneWidget);
      expect(find.text('Credit / Debit Card'), findsOneWidget);
      expect(find.text('Other Payment Methods'), findsNothing);
      expect(find.text('Netbanking'), findsNothing);
    });

    testWidgets(
        '2. UPI App flow displays all 7 required apps and initiates targeted UPI checkout',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await SessionService()
          .saveSession(sessionToken: 'token', userId: 'user-uuid-888');

      final mockApi = MockWalletApiService(mockUser: baseUser);
      final mockRazorpay = MockWalletRazorpayService()..autoSucceed = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddMoneyBottomSheet(
              initialAmount: 250.0,
              apiService: mockApi,
              razorpayService: mockRazorpay,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Proceed to Pay
      await tester.tap(find.text('Proceed to Pay'));
      await tester.pumpAndSettle();

      // Screen A: Tap UPI option
      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();

      // Dedicated UPI screen: shows Pay by UPI App and Pay by Any UPI ID
      expect(find.text('Pay by UPI App'), findsOneWidget);
      expect(find.text('Pay by Any UPI ID'), findsOneWidget);

      // Tap Pay by UPI App
      await tester.tap(find.text('Pay by UPI App'));
      await tester.pumpAndSettle();

      // Verify all 7 required apps are displayed
      expect(find.text('BHIM'), findsOneWidget);
      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('PhonePe'), findsOneWidget);
      expect(find.text('Paytm'), findsOneWidget);
      expect(find.text('Navi'), findsOneWidget);
      expect(find.text('CRED'), findsOneWidget);
      expect(find.text('super.money'), findsOneWidget);

      // Tap Google Pay
      await tester.tap(find.text('Google Pay'));
      await tester.pumpAndSettle();

      // 1. Verify backend payment order created
      expect(mockApi.orderCallCount, 1);
      expect(mockApi.lastOrderPayload?['purpose'], 'wallet_topup');
      expect(mockApi.lastOrderPayload?['amount'], 250.0);

      // 2. Verify Razorpay checkout modal opened with targeted upi/gpay
      expect(mockRazorpay.lastCheckoutOptions?['orderId'], 'order_wal_555');
      expect(mockRazorpay.lastCheckoutOptions?['amountPaise'], 25000);
      expect(mockRazorpay.lastCheckoutOptions?['paymentMethod'], 'upi');
      expect(mockRazorpay.lastCheckoutOptions?['upiApp'], 'gpay');

      // 3. Verify server-side signature verification called
      expect(mockApi.verifyCallCount, 1);
      expect(mockApi.lastVerifyPayload?['order_id'], 'order_wal_555');
      expect(mockApi.lastVerifyPayload?['payment_id'], 'pay_wal_topup_999');

      // 4. Verify Success Dialog displayed
      expect(find.text('Money Added Successfully!'), findsOneWidget);
    });

    testWidgets(
        '3. Pay by Any UPI ID flow validates format, supports test simulation chips, and proceeds',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await SessionService()
          .saveSession(sessionToken: 'token', userId: 'user-uuid-888');

      final mockApi = MockWalletApiService(mockUser: baseUser);
      final mockRazorpay = MockWalletRazorpayService()..autoSucceed = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddMoneyBottomSheet(
              initialAmount: 300.0,
              apiService: mockApi,
              razorpayService: mockRazorpay,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Proceed to Pay'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();

      // Tap Pay by Any UPI ID
      await tester.tap(find.text('Pay by Any UPI ID'));
      await tester.pumpAndSettle();

      // Verify Test Mode simulation chips exist
      expect(find.text('success@razorpay'), findsOneWidget);
      expect(find.text('failure@razorpay'), findsOneWidget);

      // Tap success@razorpay simulation chip
      await tester.tap(find.text('success@razorpay'));
      await tester.pumpAndSettle();

      // Tap dynamic Pay button
      await tester.tap(find.text('Pay ₹300.00'));
      await tester.pumpAndSettle();

      // Verify targeted checkout opened with VPA
      expect(mockRazorpay.lastCheckoutOptions?['paymentMethod'], 'upi');
      expect(mockRazorpay.lastCheckoutOptions?['vpa'], 'success@razorpay');
      expect(mockApi.verifyCallCount, 1);
    });

    testWidgets(
        '4. Credit / Debit Card flow validates card inputs and passes parameters securely via client-side Razorpay SDK',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await SessionService()
          .saveSession(sessionToken: 'token', userId: 'user-uuid-888');

      final mockApi = MockWalletApiService(mockUser: baseUser);
      final mockRazorpay = MockWalletRazorpayService()..autoSucceed = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddMoneyBottomSheet(
              initialAmount: 500.0,
              apiService: mockApi,
              razorpayService: mockRazorpay,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Proceed to Pay'));
      await tester.pumpAndSettle();

      // Screen A: Tap Credit / Debit Card
      await tester.tap(find.text('Credit / Debit Card'));
      await tester.pumpAndSettle();

      // Verify dedicated Card Entry screen elements
      expect(find.text('Card Number'), findsOneWidget);
      expect(find.text('Expires (MM/YY)'), findsOneWidget);
      expect(find.text('CVV'), findsOneWidget);
      expect(find.text('Cardholder Name'), findsOneWidget);
      expect(find.text('Pay ₹500.00'), findsOneWidget);

      // Attempt submit without filling fields -> triggers validation
      await tester.tap(find.text('Pay ₹500.00'));
      await tester.pumpAndSettle();
      expect(find.text('Card number is required'), findsOneWidget);

      // Enter invalid card number (fails Luhn)
      await tester.enterText(find.widgetWithText(TextField, '1234 5678 9012 3456'), '4111 1111 1111 1112');
      await tester.tap(find.text('Pay ₹500.00'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid card number'), findsOneWidget);

      // Enter valid Visa test card number (passes Luhn)
      await tester.enterText(find.widgetWithText(TextField, '1234 5678 9012 3456'), '4012 8888 8888 1881');
      await tester.pumpAndSettle();

      // Verify live network detection identifies Visa
      expect(find.text('Visa'), findsOneWidget);

      // Fill remaining fields
      await tester.enterText(find.widgetWithText(TextField, 'MM/YY'), '12/28');
      await tester.enterText(find.widgetWithText(TextField, '123'), '321');
      await tester.enterText(find.widgetWithText(TextField, 'Name as printed on card'), 'Abhinav Reddy');
      await tester.pumpAndSettle();

      // Tap Pay ₹500.00
      await tester.tap(find.text('Pay ₹500.00'));
      await tester.pumpAndSettle();

      // Verify Razorpay checkout options received card parameters client-side
      expect(mockRazorpay.lastCheckoutOptions?['paymentMethod'], 'card');
      expect(mockRazorpay.lastCheckoutOptions?['cardNumber'], '4012888888881881');
      expect(mockRazorpay.lastCheckoutOptions?['cardExpiryMonth'], '12');
      expect(mockRazorpay.lastCheckoutOptions?['cardExpiryYear'], '2028');
      expect(mockRazorpay.lastCheckoutOptions?['cardCvv'], '321');
      expect(mockRazorpay.lastCheckoutOptions?['cardHolderName'], 'Abhinav Reddy');

      // PCI-DSS CHECK: Backend order payload must NEVER contain card number or CVV
      expect(mockApi.lastOrderPayload?['cardNumber'], isNull);
      expect(mockApi.lastOrderPayload?['cardCvv'], isNull);
      expect(mockApi.lastOrderPayload?['cvv'], isNull);

      // Verify backend verification was completed and success dialog shown
      expect(mockApi.verifyCallCount, 1);
      expect(find.text('Money Added Successfully!'), findsOneWidget);
    });

    testWidgets(
        '5. Handles Razorpay checkout cancellation safely without crediting wallet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await SessionService()
          .saveSession(sessionToken: 'token', userId: 'user-uuid-888');

      final mockApi = MockWalletApiService(mockUser: baseUser);
      final mockRazorpay = MockWalletRazorpayService()..autoFail = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddMoneyBottomSheet(
              initialAmount: 100.0,
              apiService: mockApi,
              razorpayService: mockRazorpay,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Proceed to Pay
      await tester.tap(find.text('Proceed to Pay'));
      await tester.pumpAndSettle();

      // Screen A: Tap UPI
      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();

      // Dedicated UPI: Tap Pay by UPI App
      await tester.tap(find.text('Pay by UPI App'));
      await tester.pumpAndSettle();

      // Tap Google Pay
      await tester.tap(find.text('Google Pay'));
      await tester.pumpAndSettle();

      // Verify order created
      expect(mockApi.orderCallCount, 1);
      // Verify signature verification was NEVER called
      expect(mockApi.verifyCallCount, 0);
      // Verify cancel was reported to backend
      expect(mockApi.cancelCallCount, 1);

      // Verify error snackbar shown
      expect(find.textContaining('Payment not completed'), findsOneWidget);
      // Verify Success dialog is NOT shown
      expect(find.text('Money Added Successfully!'), findsNothing);
    });
  });
}
