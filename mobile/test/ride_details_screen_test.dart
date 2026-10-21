import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abhi_share/screens/ride_details_screen.dart';
import 'package:abhi_share/services/api_service.dart';
import 'package:abhi_share/services/session_service.dart';

class MockApiService extends ApiService {
  final Map<String, dynamic>? mockRide;
  final List<Map<String, dynamic>> mockBookings;
  final bool shouldThrow;

  MockApiService({
    this.mockRide,
    this.mockBookings = const [],
    this.shouldThrow = false,
  });

  @override
  Future<Map<String, dynamic>> getRideDetail({required String rideId}) async {
    if (shouldThrow) throw Exception('Failed to fetch ride');
    return mockRide!;
  }

  @override
  Future<List<Map<String, dynamic>>> getRideBookings({required String rideId}) async {
    return mockBookings;
  }

  @override
  Future<List<Map<String, dynamic>>> getMyBookings() async {
    return mockBookings;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseRide = {
    "id": "bacd2fe7-4d6d-4ea8-9c35-05f805a40185",
    "driver_id": "driver_123",
    "vehicle_id": "veh_123",
    "from_location": "Hyderabad",
    "to_location": "Chennai",
    "journey_date": "2026-10-10T00:00:00Z",
    "departure_time": "2000-01-01T12:30:00Z",
    "estimated_arrival_time": "2000-01-01T23:45:00Z",
    "available_seats": 2,
    "price_per_seat": 500,
    "status": "active",
    "driver_selfie_url": "",
    "driver_name": "Abhinav Reddy",
    "driver_phone": "9876543210",
    "vehicle_model": "Kia Carens",
    "vehicle_number": "TS05EJ3205",
    "vehicle_type": "seven_seater",
    "vehicle_photo_url": ""
  };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Test RideDetailsScreen renders route, vehicle, driver, and Book button for passenger', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await SessionService().saveSession(sessionToken: 'token', userId: 'passenger_999');

    await tester.pumpWidget(
      MaterialApp(
        home: RideDetailsScreen(
          rideId: 'bacd2fe7-4d6d-4ea8-9c35-05f805a40185',
          apiService: MockApiService(mockRide: baseRide),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Hyderabad'), findsOneWidget);
    expect(find.text('Chennai'), findsOneWidget);
    expect(find.text('Abhinav Reddy'), findsOneWidget);
    expect(find.text('Kia Carens'), findsOneWidget);
    expect(find.text('TS05EJ3205'), findsOneWidget);
    expect(find.text('Book Seat'), findsOneWidget);
  });

  testWidgets('Test RideDetailsScreen displays passenger bookings correctly', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await SessionService().saveSession(sessionToken: 'token', userId: 'driver_123');

    final mockBookings = [
      {
        "id": "book_1",
        "ride_id": "bacd2fe7-4d6d-4ea8-9c35-05f805a40185",
        "passenger_name": "John Doe",
        "seats_booked": 2,
        "total_amount": "1000",
        "payment_mode": "cash",
        "status": "confirmed",
        "passengers": [
          {"passenger_name": "John Doe", "passenger_age": 30, "passenger_gender": "male"},
          {"passenger_name": "Jane Doe", "passenger_age": 28, "passenger_gender": "female"},
        ]
      }
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: RideDetailsScreen(
          rideId: 'bacd2fe7-4d6d-4ea8-9c35-05f805a40185',
          apiService: MockApiService(mockRide: baseRide, mockBookings: mockBookings),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Passenger Bookings'), findsOneWidget);
    expect(find.text('Booked by: John Doe'), findsOneWidget);
    expect(find.text('Total: ₹1000'), findsOneWidget);
    expect(find.text('1. John Doe • 30 yrs • male'), findsOneWidget);
    expect(find.text('2. Jane Doe • 28 yrs • female'), findsOneWidget);
    expect(find.text('Cancel Ride'), findsOneWidget);
  });

  testWidgets('Test RideDetailsScreen shows error state and retry button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RideDetailsScreen(
          rideId: 'invalid-id',
          apiService: MockApiService(shouldThrow: true),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Failed to fetch ride'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
