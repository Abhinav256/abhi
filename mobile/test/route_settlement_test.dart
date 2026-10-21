import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abhi_share/models/route_option.dart';
import 'package:abhi_share/widgets/route_selector_map.dart';

void main() {
  group('Route Settlement Discovery and RouteSelectorMap Tests', () {
    final samplePoints = [
      const RouteWaypoint(
        name: 'Hydla Puram',
        category: 'village',
        latitude: 16.8526,
        longitude: 79.5709,
        distanceAlongRouteMeters: 1800.0,
      ),
      const RouteWaypoint(
        name: 'Vemulapally',
        category: 'village',
        latitude: 16.9285,
        longitude: 79.5297,
        distanceAlongRouteMeters: 12200.0,
      ),
      const RouteWaypoint(
        name: 'Tipparthy',
        category: 'village',
        latitude: 17.0156,
        longitude: 79.4164,
        distanceAlongRouteMeters: 28200.0,
      ),
      const RouteWaypoint(
        name: 'Nalgonda',
        category: 'city',
        latitude: 17.0504,
        longitude: 79.2669,
        distanceAlongRouteMeters: 52000.0,
      ),
      const RouteWaypoint(
        name: 'Panagal',
        category: 'town',
        latitude: 17.0765,
        longitude: 79.2886,
        distanceAlongRouteMeters: 55000.0,
      ),
      const RouteWaypoint(
        name: 'Narkatpalli',
        category: 'town',
        latitude: 17.2040,
        longitude: 79.1963,
        distanceAlongRouteMeters: 75000.0,
      ),
      const RouteWaypoint(
        name: 'Choutuppal',
        category: 'town',
        latitude: 17.2526,
        longitude: 78.8964,
        distanceAlongRouteMeters: 110000.0,
      ),
    ];

    final sampleRoute = RouteOption(
      id: 'fastest',
      title: 'Fastest Route',
      summary: 'via Nalgonda, Panagal, Narkatpalli (NH 65)',
      distanceMeters: 146300.0,
      distanceKm: 146.3,
      durationSeconds: 7980.0,
      durationMinutes: 133,
      durationFormatted: '2h 13m',
      hasTolls: true,
      intermediatePoints: samplePoints,
      coordinates: const [
        [79.5634, 16.8718],
        [79.2669, 17.0504],
        [78.8964, 17.2526],
        [78.4867, 17.3850],
      ],
    );

    test('RouteWaypoint JSON deserialization preserves category and distance', () {
      final json = {
        'name': 'Choutuppal',
        'category': 'town',
        'latitude': 17.2526,
        'longitude': 78.8964,
        'distance_along_route_meters': 110000.0,
      };

      final wp = RouteWaypoint.fromJson(json);
      expect(wp.name, 'Choutuppal');
      expect(wp.category, 'town');
      expect(wp.latitude, 17.2526);
      expect(wp.longitude, 78.8964);
      expect(wp.distanceAlongRouteMeters, 110000.0);
    });

    testWidgets('RouteSelectorMap displays discovered settlements count and names',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RouteSelectorMap(
                routes: [sampleRoute],
                selectedRoute: sampleRoute,
                onRouteSelected: (_) {},
                fromLat: 16.8718,
                fromLon: 79.5634,
                toLat: 17.3850,
                toLon: 78.4867,
                fromName: 'Miryalaguda',
                toName: 'Hyderabad',
              ),
            ),
          ),
        ),
      );

      // Verify header and settlement counter
      expect(find.text('Intermediate Towns & Villages'), findsOneWidget);
      expect(find.text('7 found'), findsOneWidget);

      // Verify settlements appear in compact view (first 6)
      expect(find.text('Nalgonda'), findsOneWidget);
      expect(find.text('Narkatpalli'), findsOneWidget);

      // Verify category badges
      expect(find.text('City'), findsWidgets);
      expect(find.text('Town'), findsWidgets);
      expect(find.text('Village'), findsWidgets);

      // Verify expansion toggle
      expect(find.text('View all 7 towns & villages'), findsOneWidget);
    });

    testWidgets('RouteSelectorMap toggles expanded settlement list without overflow',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RouteSelectorMap(
                routes: [sampleRoute],
                selectedRoute: sampleRoute,
                onRouteSelected: (_) {},
                fromLat: 16.8718,
                fromLon: 79.5634,
                toLat: 17.3850,
                toLon: 78.4867,
                fromName: 'Miryalaguda',
                toName: 'Hyderabad',
              ),
            ),
          ),
        ),
      );

      // Tap View all towns & villages
      await tester.tap(find.text('View all 7 towns & villages'));
      await tester.pump();

      // Show Less and all items including Choutuppal should now be visible
      expect(find.text('Show Less'), findsOneWidget);
      expect(find.text('Choutuppal'), findsOneWidget);
      expect(find.text('Add missing stop'), findsOneWidget);
    });
  });
}
