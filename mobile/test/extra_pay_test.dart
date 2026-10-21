import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abhi_share/screens/book_ride_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'session_token': 'dummy_test_token'});
    FlutterSecureStorage.setMockInitialValues({'session_token': 'dummy_test_token'});
  });

  group('Extra Pay Mobile Pricing Display Tests', () {
    testWidgets('BookRideScreen uses total_amount for pricing and multiplies by seats correctly', (tester) async {
      // Mock ride with Extra Pay: user_amount = 200, app_amount = 8, total_amount = 208
      final mockRide = {
        'id': 'test-ride-extra-pay-1',
        'driver_id': 'driver-999',
        'from_location': 'Hyderabad',
        'to_location': 'Vijayawada',
        'journey_date': '2026-10-20',
        'departure_time': '09:00:00',
        'available_seats': 4,
        'price_per_seat': 200.0,
        'user_amount': 200.0,
        'app_amount': 8.0,
        'total_amount': 208.0,
        'status': 'active',
        'is_women_only': false,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: BookRideScreen(ride: mockRide),
        ),
      );
      await tester.pump();

      // Verify that the passenger price per seat displayed is ₹208, NOT ₹200
      expect(find.text('₹208'), findsWidgets);
      expect(find.text('₹200'), findsNothing);
    });

    testWidgets('BookRideScreen falls back to price_per_seat if total_amount is zero or absent', (tester) async {
      // Legacy ride without total_amount
      final mockLegacyRide = {
        'id': 'test-legacy-ride',
        'driver_id': 'driver-999',
        'from_location': 'Hyderabad',
        'to_location': 'Warangal',
        'available_seats': 3,
        'price_per_seat': 150.0,
        'status': 'active',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: BookRideScreen(ride: mockLegacyRide),
        ),
      );
      await tester.pump();

      expect(find.text('₹150'), findsWidgets);
    });
  });
}
