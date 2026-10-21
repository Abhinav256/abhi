import 'dart:async';
import 'package:geolocator/geolocator.dart';

import '../models/location_result.dart';
import 'api_service.dart';

enum LocationPermissionState {
  granted,
  denied,
  permanentlyDenied,
  serviceDisabled,
}

class LocationDetectionException implements Exception {
  final String message;
  final LocationPermissionState state;

  const LocationDetectionException(this.message, this.state);

  @override
  String toString() => message;
}

class LocationSearchService {
  final ApiService _apiService = ApiService();

  // In-memory query cache to avoid repeating unchanged requests
  final Map<String, List<LocationResult>> _queryCache = {};
  static const int _kMaxCacheEntries = 50;

  // Track active query ID to cancel/ignore stale out-of-order responses
  int _latestQueryId = 0;

  /// Fetches live autocomplete suggestions for [query] from Geoapify via backend.
  /// Ignores stale responses if a newer query has been issued.
  Future<List<LocationResult>> searchPlaces(
    String query, {
    int? queryId,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 3) {
      return [];
    }

    final cacheKey = cleanQuery.toLowerCase();
    if (_queryCache.containsKey(cacheKey)) {
      return _queryCache[cacheKey]!;
    }

    final currentId = queryId ?? ++_latestQueryId;

    try {
      final rawList = await _apiService.autocompleteLocations(cleanQuery);

      // Discard response if a newer query was already submitted
      if (currentId < _latestQueryId) {
        return [];
      }

      final results = rawList
          .map((json) => LocationResult.fromJson(json))
          .where((loc) => loc.displayName.isNotEmpty)
          .toList();

      // Cache result in memory
      if (_queryCache.length >= _kMaxCacheEntries) {
        _queryCache.remove(_queryCache.keys.first);
      }
      _queryCache[cacheKey] = results;

      return results;
    } catch (e) {
      if (currentId < _latestQueryId) {
        return [];
      }
      rethrow;
    }
  }

  int getNextQueryId() => ++_latestQueryId;

  /// Retrieves the device's actual current location via GPS and resolves
  /// its address using backend Geoapify reverse geocoding.
  Future<LocationResult> getCurrentLocation() async {
    // 1. Check if GPS location service is enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationDetectionException(
        'Location services (GPS) are turned off. Please enable GPS in device settings.',
        LocationPermissionState.serviceDisabled,
      );
    }

    // 2. Check and request location permission
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationDetectionException(
        'Location permission was denied. Please allow location access to use your current location.',
        LocationPermissionState.denied,
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationDetectionException(
        'Location permission is permanently denied. Please enable location permission in App Settings.',
        LocationPermissionState.permanentlyDenied,
      );
    }

    // 3. Acquire actual position from GPS hardware
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } on TimeoutException {
      position = await Geolocator.getLastKnownPosition();
      if (position == null) {
        throw const LocationDetectionException(
          'Location detection timed out. Please ensure you have a clear GPS signal and retry.',
          LocationPermissionState.granted,
        );
      }
    } catch (e) {
      position = await Geolocator.getLastKnownPosition();
      if (position == null) {
        throw LocationDetectionException(
          'Unable to acquire device coordinates: $e',
          LocationPermissionState.granted,
        );
      }
    }

    // 4. Resolve address using Geoapify reverse geocoding via backend
    try {
      final res = await _apiService.reverseGeocode(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final loc = LocationResult.fromJson(res);
      if (loc.displayName.isNotEmpty) {
        return loc;
      }
    } catch (_) {
      // Fallback to formatted coordinates if network reverse geocoding is unavailable
    }

    return LocationResult(
      name: 'Current Location',
      formattedAddress:
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
