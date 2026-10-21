import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/location_result.dart';

class RecentLocationsService {
  static const String _kKey = 'recent_ride_locations';
  static const int _kMaxRecent = 10;

  Future<List<LocationResult>> getRecentLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kKey);
      if (list == null || list.isEmpty) {
        return [];
      }

      final results = <LocationResult>[];
      for (final item in list) {
        try {
          final decoded = jsonDecode(item);
          if (decoded is Map<String, dynamic>) {
            results.add(LocationResult.fromJson(decoded));
          }
        } catch (_) {}
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecentLocation(LocationResult location) async {
    if (location.displayName.trim().isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getRecentLocations();

      // Deduplicate: remove existing entry with same name or address
      current.removeWhere((item) {
        if (location.placeId != null &&
            item.placeId != null &&
            location.placeId == item.placeId) {
          return true;
        }
        return item.displayName.toLowerCase().trim() ==
            location.displayName.toLowerCase().trim();
      });

      // Insert at the front
      current.insert(0, location);

      // Keep only up to max limit
      final trimmed = current.take(_kMaxRecent).toList();

      final jsonList = trimmed.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_kKey, jsonList);
    } catch (_) {}
  }

  Future<void> clearRecentLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
    } catch (_) {}
  }
}
