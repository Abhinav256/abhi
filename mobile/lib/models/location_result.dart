class LocationResult {
  final String name;
  final String formattedAddress;
  final double? latitude;
  final double? longitude;
  final String? placeId;

  const LocationResult({
    required this.name,
    required this.formattedAddress,
    this.latitude,
    this.longitude,
    this.placeId,
  });

  /// Short primary label (e.g. "Hyderabad", "Hitec City", "Secunderabad Railway Station")
  String get primaryText {
    if (name.isNotEmpty) return name;
    if (formattedAddress.isNotEmpty) {
      final parts = formattedAddress.split(',');
      return parts.first.trim();
    }
    return 'Selected Location';
  }

  /// Secondary address description (e.g. "Telangana, India", "Madhapur, Hyderabad")
  String get secondaryText {
    if (formattedAddress.isEmpty) return '';
    if (name.isNotEmpty &&
        formattedAddress.toLowerCase().startsWith(name.toLowerCase())) {
      final remainder = formattedAddress.substring(name.length).trim();
      return remainder.startsWith(',')
          ? remainder.substring(1).trim()
          : remainder;
    }
    return formattedAddress;
  }

  /// Single line representation for form text fields and ride search queries
  String get displayName {
    if (formattedAddress.isNotEmpty) return formattedAddress;
    return name;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'formatted_address': formattedAddress,
    'latitude': latitude,
    'longitude': longitude,
    'place_id': placeId,
  };

  factory LocationResult.fromJson(Map<String, dynamic> json) {
    return LocationResult(
      name: json['name']?.toString() ?? '',
      formattedAddress:
          json['formatted_address']?.toString() ??
          json['formatted']?.toString() ??
          json['address']?.toString() ??
          '',
      latitude: json['latitude'] != null
          ? double.tryParse(json['latitude'].toString())
          : (json['lat'] != null
                ? double.tryParse(json['lat'].toString())
                : null),
      longitude: json['longitude'] != null
          ? double.tryParse(json['longitude'].toString())
          : (json['lon'] != null
                ? double.tryParse(json['lon'].toString())
                : null),
      placeId: json['place_id']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationResult &&
          runtimeType == other.runtimeType &&
          displayName == other.displayName &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode =>
      displayName.hashCode ^ latitude.hashCode ^ longitude.hashCode;
}
