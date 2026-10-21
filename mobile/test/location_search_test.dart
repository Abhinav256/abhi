import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abhi_share/models/location_result.dart';
import 'package:abhi_share/services/recent_locations_service.dart';
import 'package:abhi_share/widgets/location_search_bottom_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocationResult Model Tests', () {
    test(
      'LocationResult correctly parses name, formatted address and coordinates',
      () {
        final loc = LocationResult.fromJson({
          'name': 'Hitec City',
          'formatted': 'Hitec City, Madhapur, Hyderabad, Telangana, India',
          'lat': 17.4435,
          'lon': 78.3772,
          'place_id': 'place_123',
        });

        expect(loc.name, 'Hitec City');
        expect(loc.primaryText, 'Hitec City');
        expect(loc.secondaryText, 'Madhapur, Hyderabad, Telangana, India');
        expect(
          loc.displayName,
          'Hitec City, Madhapur, Hyderabad, Telangana, India',
        );
        expect(loc.latitude, 17.4435);
        expect(loc.longitude, 78.3772);
        expect(loc.placeId, 'place_123');

        final json = loc.toJson();
        expect(json['name'], 'Hitec City');
        expect(
          json['formatted_address'],
          'Hitec City, Madhapur, Hyderabad, Telangana, India',
        );
        expect(json['latitude'], 17.4435);
        expect(json['longitude'], 78.3772);
        expect(json['place_id'], 'place_123');
      },
    );

    test('LocationResult handles empty name by using formatted address', () {
      final loc = LocationResult.fromJson({
        'name': '',
        'formatted_address': 'Gachibowli, Hyderabad, India',
        'latitude': 17.4401,
        'longitude': 78.3489,
      });

      expect(loc.primaryText, 'Gachibowli');
      expect(loc.displayName, 'Gachibowli, Hyderabad, India');
    });
  });

  group('RecentLocationsService Tests', () {
    test('Saves, deduplicates and prioritizes most recent locations', () async {
      final service = RecentLocationsService();

      expect(await service.getRecentLocations(), isEmpty);

      const loc1 = LocationResult(
        name: 'Secunderabad',
        formattedAddress: 'Secunderabad Railway Station, Hyderabad, TG',
        latitude: 17.4334,
        longitude: 78.5044,
      );

      const loc2 = LocationResult(
        name: 'RGIA Airport',
        formattedAddress:
            'Rajiv Gandhi International Airport, Shamshabad, Hyderabad',
        latitude: 17.2403,
        longitude: 78.4294,
      );

      await service.saveRecentLocation(loc1);
      await service.saveRecentLocation(loc2);

      var recents = await service.getRecentLocations();
      expect(recents.length, 2);
      expect(recents[0].name, 'RGIA Airport'); // Most recent at top
      expect(recents[1].name, 'Secunderabad');

      // Re-saving loc1 should move it to the top without duplicates
      await service.saveRecentLocation(loc1);
      recents = await service.getRecentLocations();
      expect(recents.length, 2);
      expect(recents[0].name, 'Secunderabad');
      expect(recents[1].name, 'RGIA Airport');

      // Clear history
      await service.clearRecentLocations();
      expect(await service.getRecentLocations(), isEmpty);
    });
  });

  group('LocationSearchBottomSheet Widget Tests', () {
    testWidgets('Renders Pickup mode with contextual header and options', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocationSearchBottomSheet(
              title: 'Choose Pickup Location',
              isPickup: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header title
      expect(find.text('Choose Pickup Location'), findsOneWidget);

      // Check placeholder
      expect(find.text('Search for a place or address'), findsOneWidget);

      // Check "Use Current Location" option
      expect(find.text('Use Current Location'), findsOneWidget);

      // Check empty recent locations placeholder
      expect(find.text('No recent locations yet'), findsOneWidget);
    });

    testWidgets('Renders Destination mode and shows saved recents', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final recentService = RecentLocationsService();
      await recentService.saveRecentLocation(
        const LocationResult(
          name: 'Hitec City',
          formattedAddress: 'Hitec City, Madhapur, Hyderabad',
          latitude: 17.4435,
          longitude: 78.3772,
        ),
      );

      LocationResult? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    selectedResult = await showLocationSearchSheet(
                      context: context,
                      title: 'Choose Destination',
                      isPickup: false,
                    );
                  },
                  child: const Text('Open Sheet'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open bottom sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Contextual title
      expect(find.text('Choose Destination'), findsOneWidget);

      // Recent Locations section header
      expect(find.text('Recent Locations'), findsOneWidget);
      expect(find.text('Hitec City'), findsOneWidget);

      // Tap the recent location
      await tester.tap(find.text('Hitec City'));
      await tester.pumpAndSettle();

      // Bottom sheet should dismiss and return selected result
      expect(selectedResult, isNotNull);
      expect(selectedResult!.name, 'Hitec City');
    });

    testWidgets('Typing shows clear button and tapping clear resets search', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocationSearchBottomSheet(
              title: 'Choose Pickup Location',
              isPickup: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter text "Hyde"
      await tester.enterText(find.byType(TextField), 'Hyde');
      await tester.pump();

      // Clear button should be visible
      expect(find.text('Clear'), findsOneWidget);

      // Tap Clear
      await tester.tap(find.text('Clear'));
      await tester.pump();

      // Text field should be empty
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '');
    });
  });
}
