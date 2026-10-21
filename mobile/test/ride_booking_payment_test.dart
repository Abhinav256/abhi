import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abhi_share/screens/book_ride_screen.dart';
import 'package:abhi_share/screens/ride_payment_screen.dart';
import 'package:abhi_share/services/api_service.dart';
import 'package:abhi_share/services/razorpay_service.dart';
import 'package:abhi_share/services/session_service.dart';

class MockRazorpayService extends RazorpayService {
  bool initCalled = false;
  bool disposeCalled = false;
  Map<String, dynamic>? lastCheckoutOptions;
  bool autoSucceed = false;
  bool autoFail = false;
  String failMessage = 'Payment cancelled by user';

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
      onSuccess?.call('pay_test_123456', orderId, 'valid_signature_hash');
    } else if (autoFail) {
      onError?.call(0, failMessage);
    }
  }
}

class MockBookingApiService extends ApiService {
  final Map<String, dynamic> mockRide;
  final Map<String, dynamic> mockUser;
  Map<String, dynamic>? lastOrderPayload;
  Map<String, dynamic>? lastVerifyPayload;
  int orderCallCount = 0;
  int verifyCallCount = 0;

  MockBookingApiService({
    required this.mockRide,
    required this.mockUser,
  });

  @override
  Future<Map<String, dynamic>> getCurrentUser() async {
    return mockUser;
  }

  @override
  Future<Map<String, dynamic>> getRideDetail({required String rideId}) async {
    return mockRide;
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
      'ride_id': rideId,
      'seats_booked': seatsBooked,
      'passengers': passengers,
    };
    return {
      'order_id': 'order_test_987',
      'key_id': 'rzp_test_TlUKfo2Pi9FVYU',
      'amount_paise': 50000,
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
      'booking_id': 'BK-TEST-12345',
      'payment_id': paymentId,
      'message': 'Payment verified and booking confirmed successfully.',
    };
  }

  @override
  Future<Map<String, dynamic>> cancelPaymentOrder({
    required String orderId,
    String? reason,
  }) async {
    return {'status': 'cancelled'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseRide = {
    'id': 'ride-uuid-999',
    'driver_id': 'driver-uuid-123',
    'from_location': 'Hyderabad',
    'to_location': 'Bangalore',
    'journey_date': '2026-10-15T00:00:00Z',
    'departure_time': '2000-01-01T08:00:00Z',
    'available_seats': 4,
    'price_per_seat': 500.0,
    'status': 'active',
    'is_women_only': false,
  };

  final baseUser = {
    'id': 'user-uuid-888',
    'full_name': 'Abhinav Reddy',
    'gender': 'male',
    'age': 25,
  };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('Ride Booking Payment Flow Tests', () {
    testWidgets(
        '1. Default payment method on BookRideScreen is UPI and updates dynamically with seats',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await SessionService()
          .saveSession(sessionToken: 'token', userId: 'user-uuid-888');

      await tester.pumpWidget(
        MaterialApp(
          home: BookRideScreen(ride: baseRide),
        ),
      );
      await tester.pumpAndSettle();

      // Check route and base price rendered dynamically
      expect(find.text('Hyderabad → Bangalore'), findsOneWidget);
      expect(find.text('₹500'), findsWidgets);

      // Verify payment mode dropdown defaults to UPI
      final paymentDropdownFinder = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.initialValue == 'upi',
      );
      expect(paymentDropdownFinder, findsOneWidget);

      // Verify Swipe to Confirm text indicates UPI payment flow with dynamic ₹500
      expect(
          find.text('Swipe to Pay & Confirm (₹500)'), findsOneWidget);
    });

    testWidgets(
        '2. Switching payment method to Cash preserves direct cash-booking flow',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await SessionService()
          .saveSession(sessionToken: 'token', userId: 'user-uuid-888');

      await tester.pumpWidget(
        MaterialApp(
          home: BookRideScreen(ride: baseRide),
        ),
      );
      await tester.pumpAndSettle();

      // Switch dropdown to Cash
      final dropdown = find.byType(DropdownButtonFormField<String>).last;
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      final cashItem = find.text('Cash').last;
      await tester.tap(cashItem);
      await tester.pumpAndSettle();

      // Swipe to confirm text should now say Swipe to Confirm (₹500)
      expect(find.text('Swipe to Confirm (₹500)'), findsOneWidget);
    });

    testWidgets(
        '3. RidePaymentScreen renders RailOne Make Payment and navigates across payment methods',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockApi = MockBookingApiService(
        mockRide: baseRide,
        mockUser: baseUser,
      );
      final mockRazorpay = MockRazorpayService();

      final passengers = [
        {'name': 'Abhinav Reddy', 'age': 25, 'gender': 'male'},
        {'name': 'Rohan Sharma', 'age': 26, 'gender': 'male'},
      ];

      // Dynamic calculation: 2 seats * ₹500 = ₹1,000 (NOT hardcoded ₹500)
      const dynamicSeats = 2;
      const dynamicPrice = 500.0;
      const dynamicTotal = 1000.0;

      await tester.pumpWidget(
        MaterialApp(
          home: RidePaymentScreen(
            ride: baseRide,
            seatsBooked: dynamicSeats,
            pricePerSeat: dynamicPrice,
            totalAmount: dynamicTotal,
            passengers: passengers,
            apiService: mockApi,
            razorpayService: mockRazorpay,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Screen A (Make Payment)
      expect(find.text('Make Payment'), findsWidgets);
      expect(find.text('Pay ₹1000.00'), findsWidgets);
      expect(find.text('Other Payment Methods'), findsOneWidget);

      // Navigate to Screen B (Payment Methods)
      await tester.tap(find.text('Other Payment Methods'));
      await tester.pumpAndSettle();

      expect(find.text('Payment Methods'), findsWidgets);
      expect(find.text('Total Amount'), findsOneWidget);
      expect(find.text('₹1000.00'), findsWidgets);
      expect(find.text('Pay by any UPI App'), findsOneWidget);
      expect(find.text('Credit / Debit Cards'), findsOneWidget);
      expect(find.text('Netbanking'), findsOneWidget);

      // Navigate to Screen C (UPI App Selection)
      await tester.tap(find.text('Pay by any UPI App'));
      await tester.pumpAndSettle();

      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('PhonePe'), findsOneWidget);
      expect(find.text('Paytm'), findsOneWidget);
      expect(find.text('BHIM'), findsOneWidget);
    });

    testWidgets(
        '4. RidePaymentScreen triggers Razorpay checkout and verifies payment server-side upon success',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockApi = MockBookingApiService(
        mockRide: baseRide,
        mockUser: baseUser,
      );
      final mockRazorpay = MockRazorpayService()..autoSucceed = true;

      final passengers = [
        {'name': 'Abhinav Reddy', 'age': 25, 'gender': 'male'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: RidePaymentScreen(
            ride: baseRide,
            seatsBooked: 1,
            pricePerSeat: 500.0,
            totalAmount: 500.0,
            passengers: passengers,
            apiService: mockApi,
            razorpayService: mockRazorpay,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Screen B then Screen C
      await tester.tap(find.text('Other Payment Methods'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pay by any UPI App'));
      await tester.pumpAndSettle();

      // Tap Google Pay in RailOne UPI App screen
      await tester.tap(find.text('Google Pay'));
      await tester.pumpAndSettle();

      // Verify payment order was created on backend
      expect(mockApi.orderCallCount, 1);
      expect(mockApi.lastOrderPayload?['purpose'], 'ride_booking');
      expect(mockApi.lastOrderPayload?['ride_id'], 'ride-uuid-999');

      // Verify Razorpay openCheckout was invoked with backend order ID and test key
      expect(mockRazorpay.lastCheckoutOptions?['orderId'], 'order_test_987');
      expect(mockRazorpay.lastCheckoutOptions?['keyId'], 'rzp_test_TlUKfo2Pi9FVYU');
      expect(mockRazorpay.lastCheckoutOptions?['paymentMethod'], 'upi');
      expect(mockRazorpay.lastCheckoutOptions?['upiApp'], 'gpay');

      // Verify backend verifyPayment was called with signature
      expect(mockApi.verifyCallCount, 1);
      expect(mockApi.lastVerifyPayload?['order_id'], 'order_test_987');
      expect(mockApi.lastVerifyPayload?['payment_id'], 'pay_test_123456');

      // Verify Booking Confirmed Dialog is displayed
      expect(find.text('Booking Confirmed!'), findsOneWidget);
      expect(find.text('#BK-TEST-12345'), findsOneWidget);
    });

    testWidgets(
        '5. RidePaymentScreen handles Razorpay checkout failure gracefully without fake confirmation',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockApi = MockBookingApiService(
        mockRide: baseRide,
        mockUser: baseUser,
      );
      final mockRazorpay = MockRazorpayService()..autoFail = true;

      final passengers = [
        {'name': 'Abhinav Reddy', 'age': 25, 'gender': 'male'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: RidePaymentScreen(
            ride: baseRide,
            seatsBooked: 1,
            pricePerSeat: 500.0,
            totalAmount: 500.0,
            passengers: passengers,
            apiService: mockApi,
            razorpayService: mockRazorpay,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Screen B then Screen C
      await tester.tap(find.text('Other Payment Methods'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pay by any UPI App'));
      await tester.pumpAndSettle();

      // Tap Google Pay
      await tester.tap(find.text('Google Pay'));
      await tester.pumpAndSettle();

      // Verify backend order created
      expect(mockApi.orderCallCount, 1);
      // Verify verifyPayment was NEVER called
      expect(mockApi.verifyCallCount, 0);

      // Verify error snackbar is shown
      expect(find.textContaining('Payment not completed'), findsOneWidget);
      // Verify Booking Confirmed dialog is NOT shown
      expect(find.text('Booking Confirmed!'), findsNothing);
    });
  });
}
