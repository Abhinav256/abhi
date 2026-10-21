class RouteWaypoint {
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final double distanceAlongRouteMeters;

  const RouteWaypoint({
    required this.name,
    this.category = '',
    required this.latitude,
    required this.longitude,
    required this.distanceAlongRouteMeters,
  });

  factory RouteWaypoint.fromJson(Map<String, dynamic> json) {
    return RouteWaypoint(
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      distanceAlongRouteMeters:
          (json['distance_along_route_meters'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'latitude': latitude,
    'longitude': longitude,
    'distance_along_route_meters': distanceAlongRouteMeters,
  };
}

class RouteOption {
  final String id;
  final String title;
  final String summary;
  final double distanceMeters;
  final double distanceKm;
  final double durationSeconds;
  final int durationMinutes;
  final String durationFormatted;
  final bool hasTolls;
  final List<RouteWaypoint> intermediatePoints;
  final List<List<double>> coordinates; // [ [lon, lat], ... ]

  const RouteOption({
    required this.id,
    required this.title,
    required this.summary,
    required this.distanceMeters,
    required this.distanceKm,
    required this.durationSeconds,
    required this.durationMinutes,
    required this.durationFormatted,
    required this.hasTolls,
    required this.intermediatePoints,
    required this.coordinates,
  });

  factory RouteOption.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['intermediate_points'];
    final points = <RouteWaypoint>[];
    if (rawPoints is List) {
      for (final item in rawPoints) {
        if (item is Map) {
          points.add(RouteWaypoint.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final rawCoords = json['coordinates'];
    final coords = <List<double>>[];
    if (rawCoords is List) {
      for (final pt in rawCoords) {
        if (pt is List && pt.length >= 2) {
          final lon = (pt[0] as num).toDouble();
          final lat = (pt[1] as num).toDouble();
          coords.add([lon, lat]);
        }
      }
    }

    return RouteOption(
      id: json['id']?.toString() ?? 'route',
      title: json['title']?.toString() ?? 'Route',
      summary: json['summary']?.toString() ?? '',
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 0.0,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0.0,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
      durationFormatted: json['duration_formatted']?.toString() ?? '',
      hasTolls: json['has_tolls'] == true,
      intermediatePoints: points,
      coordinates: coords,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'summary': summary,
    'distance_meters': distanceMeters,
    'distance_km': distanceKm,
    'duration_seconds': durationSeconds,
    'duration_minutes': durationMinutes,
    'duration_formatted': durationFormatted,
    'has_tolls': hasTolls,
    'intermediate_points': intermediatePoints.map((p) => p.toJson()).toList(),
    'coordinates': coordinates,
  };

  RouteOption copyWith({
    String? id,
    String? title,
    String? summary,
    double? distanceMeters,
    double? distanceKm,
    double? durationSeconds,
    int? durationMinutes,
    String? durationFormatted,
    bool? hasTolls,
    List<RouteWaypoint>? intermediatePoints,
    List<List<double>>? coordinates,
  }) {
    return RouteOption(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      distanceKm: distanceKm ?? this.distanceKm,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      durationFormatted: durationFormatted ?? this.durationFormatted,
      hasTolls: hasTolls ?? this.hasTolls,
      intermediatePoints: intermediatePoints ?? this.intermediatePoints,
      coordinates: coordinates ?? this.coordinates,
    );
  }
}

