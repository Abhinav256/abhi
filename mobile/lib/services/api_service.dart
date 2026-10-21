import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import 'image_compression_service.dart';
import 'push_notification_service.dart';
import 'security_service.dart';
import 'session_service.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? code;
  final Map<String, dynamic>? data;

  const ApiException({
    required this.message,
    required this.statusCode,
    this.code,
    this.data,
  });

  @override
  String toString() => message;
}

class ApiService {
  static final ApiService instance = ApiService();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://abhishare-api.onrender.com',
  );

  final SessionService _sessionService = SessionService();

  Future<bool> get isAuthenticated => _sessionService.isLoggedIn();

  static String resolveImageMimeType(
    List<int> bytes, {
    String? declaredMime,
    String? fileName,
    String? filePath,
  }) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'application/pdf';
    }

    if (declaredMime != null &&
        declaredMime.isNotEmpty &&
        declaredMime != 'application/octet-stream') {
      return declaredMime;
    }

    final path = (fileName != null && fileName.isNotEmpty)
        ? fileName
        : (filePath ?? '');
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }

    return 'image/jpeg';
  }

  static String _ensureValidFilename(String originalName, String mimeType) {
    var name = originalName.trim();
    if (name.isEmpty) {
      name = 'image';
    }
    final lower = name.toLowerCase();
    if (mimeType == 'image/jpeg' &&
        !lower.endsWith('.jpg') &&
        !lower.endsWith('.jpeg')) {
      return '$name.jpg';
    }
    if (mimeType == 'image/png' && !lower.endsWith('.png')) {
      return '$name.png';
    }
    if (mimeType == 'image/webp' && !lower.endsWith('.webp')) {
      return '$name.webp';
    }
    if (mimeType == 'application/pdf' && !lower.endsWith('.pdf')) {
      return '$name.pdf';
    }
    return name;
  }

  Future<Map<String, String>> _headers({bool authenticated = false}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (authenticated) {
      final token = await _sessionService.getSessionToken();

      if (token == null || token.isEmpty) {
        throw Exception('You are not logged in.');
      }

      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    Map<String, dynamic> data = {};

    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        data = {'message': response.body};
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg =
          data['error']?.toString() ??
          data['message']?.toString() ??
          'Request failed (${response.statusCode})';
      final code = data['code']?.toString();
      throw ApiException(
        message: msg,
        statusCode: response.statusCode,
        code: code,
        data: data,
      );
    }

    return data;
  }

  // ------------------------------------------------------------
  // HEALTH
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> healthCheck() async {
    final response = await http.get(Uri.parse('$baseUrl/health'));

    return _handleResponse(response);
  }

  // ------------------------------------------------------------
  // AUTH
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> checkAuthIdentifier({
    required String identifier,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/start'),
      headers: await _headers(),
      body: jsonEncode({'identifier': identifier}),
    );

    return _handleResponse(response);
  }

  // --- NEW UNIFIED AUTH ENDPOINTS ---

  Future<Map<String, dynamic>> sendOTPUniversal({
    required String identifier,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/unified/send-otp'),
      headers: await _headers(),
      body: jsonEncode({'identifier': identifier}),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> verifyOTPAndCheck({
    required String identifier,
    required String otp,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/unified/verify-check'),
      headers: await _headers(),
      body: jsonEncode({'identifier': identifier, 'otp': otp}),
    );

    final data = await _handleResponse(response);

    if (data['exists'] == true) {
      final sessionToken = data['session_token']?.toString();
      final user = data['user'];

      if (sessionToken == null || sessionToken.isEmpty) {
        throw Exception('Server did not return a session token.');
      }
      if (user is! Map<String, dynamic>) {
        throw Exception('Server did not return user information.');
      }
      final userId = user['id']?.toString();
      if (userId == null || userId.isEmpty) {
        throw Exception('Server did not return user ID.');
      }

      await _sessionService.saveSession(
        sessionToken: sessionToken,
        userId: userId,
      );

      // Sync device push notification token to backend for this user
      PushNotificationService.instance.syncDeviceToken();

      final email = user['email']?.toString();
      final phone = user['phone']?.toString();
      await SecurityService().saveUserContactInfo(
        userId: userId,
        email: email,
        phone: phone,
      );
    }

    return data;
  }

  Future<Map<String, dynamic>> checkSecondaryIdentifier({
    required String identifier,
    required String type,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/unified/check-secondary'),
      headers: await _headers(),
      body: jsonEncode({'identifier': identifier, 'type': type}),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> completeSignup({
    required String fullName,
    String? nickname,
    required String phone,
    required String email,
    required String dateOfBirth,
    required String gender,
    required String secondaryIdentifier,
    required String secondaryOtp,
    String? referralCode,
  }) async {
    final payload = <String, dynamic>{
      'full_name': fullName,
      'nickname': nickname,
      'phone': phone,
      'email': email,
      'date_of_birth': dateOfBirth,
      'gender': gender,
      'secondary_identifier': secondaryIdentifier,
      'secondary_otp': secondaryOtp,
    };
    if (referralCode != null && referralCode.trim().isNotEmpty) {
      payload['referral_code'] = referralCode.trim().toUpperCase();
    }

    final response = await http.post(
      Uri.parse('$baseUrl/auth/unified/complete-signup'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );

    final data = await _handleResponse(response);

    final sessionToken = data['session_token']?.toString();
    final user = data['user'];

    if (sessionToken == null || sessionToken.isEmpty) {
      throw Exception('Server did not return a session token.');
    }
    if (user is! Map<String, dynamic>) {
      throw Exception('Server did not return user information.');
    }
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) {
      throw Exception('Server did not return user ID.');
    }

    await _sessionService.saveSession(
      sessionToken: sessionToken,
      userId: userId,
    );

    // Sync device push notification token to backend for this user
    PushNotificationService.instance.syncDeviceToken();

    final savedEmail = user['email']?.toString() ?? email;
    final savedPhone = user['phone']?.toString() ?? phone;
    await SecurityService().saveUserContactInfo(
      userId: userId,
      email: savedEmail,
      phone: savedPhone,
    );

    return data;
  }

  // --- PIN MANAGEMENT ENDPOINTS (BACKEND DB VALIDATED) ---

  Future<void> setPIN({required String pin}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/pin/set'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({'pin': pin}),
    );

    await _handleResponse(response);
  }

  Future<bool> verifyPIN({required String pin}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/pin/verify'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({'pin': pin}),
    );

    final data = await _handleResponse(response);
    return data['valid'] == true;
  }

  Future<void> changePIN({
    required String oldPin,
    required String newPin,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/pin/change'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({'old_pin': oldPin, 'new_pin': newPin}),
    );

    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> loginWithPasscode({
    required String identifier,
    required String pin,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login/passcode'),
      headers: await _headers(),
      body: jsonEncode({'identifier': identifier, 'pin': pin}),
    );

    final data = await _handleResponse(response);

    final sessionToken = data['session_token']?.toString();
    final user = data['user'];

    if (sessionToken == null || sessionToken.isEmpty) {
      throw Exception('Server did not return a session token.');
    }
    if (user is! Map<String, dynamic>) {
      throw Exception('Server did not return user information.');
    }
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) {
      throw Exception('Server did not return user ID.');
    }

    await _sessionService.saveSession(
      sessionToken: sessionToken,
      userId: userId,
    );

    // Sync device push notification token to backend for this user
    PushNotificationService.instance.syncDeviceToken();

    final email = user['email']?.toString();
    final phone = user['phone']?.toString();
    await SecurityService().saveUserContactInfo(
      userId: userId,
      email: email,
      phone: phone,
    );

    return data;
  }

  // --- END NEW UNIFIED AUTH ENDPOINTS ---

  Future<void> sendLoginOTP({required String identifier}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login/send-otp'),
      headers: await _headers(),
      body: jsonEncode({'identifier': identifier}),
    );

    await _handleResponse(response);
  }

  Future<void> sendSignupOTP({
    required String fullName,
    required String phone,
    required String email,
    required String dateOfBirth,
    required String gender,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/signup/send-otp'),
      headers: await _headers(),
      body: jsonEncode({
        'full_name': fullName,
        'phone': phone,
        'email': email,
        'date_of_birth': dateOfBirth,
        'gender': gender,
      }),
    );

    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> verifyOTP({
    required String identifier,
    required String otp,
    required String purpose,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/verify'),
      headers: await _headers(),
      body: jsonEncode({
        'identifier': identifier,
        'otp': otp,
        'purpose': purpose,
      }),
    );

    final data = await _handleResponse(response);

    final sessionToken = data['session_token']?.toString();
    final user = data['user'];

    if (sessionToken == null || sessionToken.isEmpty) {
      throw Exception('Server did not return a session token.');
    }

    if (user is! Map<String, dynamic>) {
      throw Exception('Server did not return user information.');
    }

    final userId = user['id']?.toString();

    if (userId == null || userId.isEmpty) {
      throw Exception('Server did not return user ID.');
    }

    await _sessionService.saveSession(
      sessionToken: sessionToken,
      userId: userId,
    );

    // Sync device push notification token to backend for this user
    PushNotificationService.instance.syncDeviceToken();

    final savedEmail = user['email']?.toString();
    final savedPhone = user['phone']?.toString();
    await SecurityService().saveUserContactInfo(
      userId: userId,
      email: savedEmail,
      phone: savedPhone,
    );

    return data;
  }

  Future<Map<String, dynamic>> updateProfile(
    String fullName,
    String? nickname,
    String dob,
    String gender,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/auth/me'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'full_name': fullName,
        'nickname': nickname,
        'date_of_birth': dob,
        'gender': gender,
      }),
    );

    final data = await _handleResponse(response);
    return data;
  }

  Future<dynamic> saveLocation(String name, String address) async {
    final response = await http.post(
      Uri.parse('$baseUrl/locations'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({'name': name, 'address': address}),
    );
    return _handleResponse(response);
  }

  Future<List<dynamic>> getLocations() async {
    final response = await http.get(
      Uri.parse('$baseUrl/locations'),
      headers: await _headers(authenticated: true),
    );
    final data = await _handleResponse(response);
    final locs = data['locations'];
    return locs is List ? locs : [];
  }

  Future<List<dynamic>> getNotifications() async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications'),
      headers: await _headers(authenticated: true),
    );
    final data = await _handleResponse(response);
    final notifs = data['notifications'];
    return notifs is List ? notifs : [];
  }

  Future<void> markNotificationRead(String id) async {
    final response = await http.put(
      Uri.parse('$baseUrl/notifications/$id/read'),
      headers: await _headers(authenticated: true),
    );
    await _handleResponse(response);
  }

  /// Fetches elaborate notification details including linked ride and booking if available.
  Future<Map<String, dynamic>> getNotificationDetail(String notifId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications/$notifId'),
      headers: await _headers(authenticated: true),
    );
    final data = await _handleResponse(response);
    final notif = data['notification'];
    if (notif is Map<String, dynamic>) {
      return notif;
    } else if (notif is Map) {
      return Map<String, dynamic>.from(notif);
    }
    return data;
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/device-token'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'token': token,
        'platform': platform,
      }),
    );
    await _handleResponse(response);
  }

  Future<void> unregisterDeviceToken({
    required String token,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/notifications/device-token'),
        headers: await _headers(authenticated: true),
        body: jsonEncode({
          'token': token,
        }),
      );
      await _handleResponse(response);
    } catch (_) {}
  }

  /// Returns the inner user object directly (not the wrapper).
  Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: await _headers(authenticated: true),
    );

    final data = await _handleResponse(response);

    // Backend returns {"user": {...}}. Extract the inner user object.
    final user = data['user'];
    if (user is Map<String, dynamic>) {
      await SecurityService().saveUserContactInfo(
        userId: user['id']?.toString(),
        email: user['email']?.toString(),
        phone: user['phone']?.toString(),
      );
      return user;
    }

    return data;
  }

  Future<void> logout() async {
    try {
      await PushNotificationService.instance.clearDeviceToken();
    } catch (_) {}

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: await _headers(authenticated: true),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Still clear the local session.
      }
    } finally {
      await _sessionService.clearSession();
    }
  }

  // ------------------------------------------------------------
  // VEHICLES
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> addVehicle({
    required String vehicleNumber,
    required String vehicleType,
    required String model,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/vehicles'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'vehicle_number': vehicleNumber,
        'vehicle_type': vehicleType,
        'model': model,
      }),
    );

    return _handleResponse(response);
  }

  Future<List<Map<String, dynamic>>> getVehicles() async {
    final response = await http.get(
      Uri.parse('$baseUrl/vehicles'),
      headers: await _headers(authenticated: true),
    );

    final data = await _handleResponse(response);

    final vehicles = data['vehicles'];

    if (vehicles is! List) {
      return [];
    }

    return vehicles
        .whereType<Map>()
        .map((vehicle) => Map<String, dynamic>.from(vehicle))
        .toList();
  }

  Future<Map<String, dynamic>> getVehicle({required String vehicleId}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/vehicles/$vehicleId'),
      headers: await _headers(authenticated: true),
    );

    return _handleResponse(response);
  }

  Future<void> deleteVehicle(String vehicleId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/vehicles/$vehicleId'),
      headers: await _headers(authenticated: true),
    );

    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> uploadVehicleImage({
    required String vehicleId,
    required XFile image,
    required String imageType,
  }) async {
    final token = await _sessionService.getSessionToken();

    if (token == null || token.isEmpty) {
      throw Exception('You are not logged in.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/upload/vehicle-image'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    request.fields['vehicle_id'] = vehicleId;
    request.fields['type'] = imageType;

    final category = (imageType == 'rc')
        ? ImageCategory.rcDocument
        : ImageCategory.vehiclePhoto;

    final compressed = await ImageCompressionService.compressXFile(
      image,
      category: category,
    );

    final imageBytes = compressed.bytes;
    final mimeType = compressed.mimeType;
    final filename = _ensureValidFilename(compressed.outputFileName, mimeType);
    final mediaType = MediaType.parse(mimeType);

    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: filename,
        contentType: mediaType,
      ),
    );

    final streamedResponse = await request.send();

    final response = await http.Response.fromStream(streamedResponse);

    return _handleResponse(response);
  }

  // ------------------------------------------------------------
  // RIDES
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> createRide({
    required String vehicleId,
    required String fromLocation,
    required String toLocation,
    required String journeyDate,
    required String departureTime,
    required String estimatedArrivalTime,
    required int availableSeats,
    required double pricePerSeat,
    bool isWomenOnly = false,
    double? pickupLatitude,
    double? pickupLongitude,
    double? destinationLatitude,
    double? destinationLongitude,
    dynamic routeGeometry,
    double? routeDistance,
    double? routeDuration,
    String? routeSummary,
    dynamic routeWaypoints,
  }) async {
    final payload = <String, dynamic>{
      'vehicle_id': vehicleId,
      'from_location': fromLocation,
      'to_location': toLocation,
      'journey_date': journeyDate,
      'departure_time': departureTime,
      'estimated_arrival_time': estimatedArrivalTime,
      'available_seats': availableSeats,
      'price_per_seat': pricePerSeat,
      'is_women_only': isWomenOnly,
    };

    if (pickupLatitude != null) payload['pickup_latitude'] = pickupLatitude;
    if (pickupLongitude != null) payload['pickup_longitude'] = pickupLongitude;
    if (destinationLatitude != null)
      payload['destination_latitude'] = destinationLatitude;
    if (destinationLongitude != null)
      payload['destination_longitude'] = destinationLongitude;
    if (routeGeometry != null) payload['route_geometry'] = routeGeometry;
    if (routeDistance != null) payload['route_distance'] = routeDistance;
    if (routeDuration != null) payload['route_duration'] = routeDuration;
    if (routeSummary != null) payload['route_summary'] = routeSummary;
    if (routeWaypoints != null) payload['route_waypoints'] = routeWaypoints;

    final response = await http.post(
      Uri.parse('$baseUrl/rides'),
      headers: await _headers(authenticated: true),
      body: jsonEncode(payload),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> uploadRideSelfie({
    required String rideId,
    required XFile selfie,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/rides/$rideId/selfie'),
    );

    final token = await _sessionService.getSessionToken();

    if (token == null || token.isEmpty) {
      throw Exception('You are not logged in.');
    }

    request.headers['Authorization'] = 'Bearer $token';

    final compressed = await ImageCompressionService.compressXFile(
      selfie,
      category: ImageCategory.selfie,
    );

    final bytes = compressed.bytes;
    final mimeType = compressed.mimeType;
    final filename = _ensureValidFilename(compressed.outputFileName, mimeType);
    final mediaType = MediaType.parse(mimeType);

    request.files.add(
      http.MultipartFile.fromBytes(
        'selfie',
        bytes,
        filename: filename,
        contentType: mediaType,
      ),
    );

    final streamedResponse = await request.send();

    final response = await http.Response.fromStream(streamedResponse);

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> publishRide({required String rideId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rides/$rideId/publish'),
      headers: await _headers(authenticated: true),
    );

    return _handleResponse(response);
  }

  // ------------------------------------------------------------
  // RECURRING SCHEDULES
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> createRecurringSchedule({
    required String vehicleId,
    required String fromLocation,
    required String toLocation,
    required String departureTime,
    required String estimatedArrivalTime,
    required int availableSeats,
    required double pricePerSeat,
    required String recurrenceType,
    required List<String> selectedWeekdays,
    required String startDate,
    String? endDate,
    int? occurrenceCount,
    bool isWomenOnly = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/recurring-schedules'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'vehicle_id': vehicleId,
        'from_location': fromLocation,
        'to_location': toLocation,
        'departure_time': departureTime,
        'estimated_arrival_time': estimatedArrivalTime,
        'available_seats': availableSeats,
        'price_per_seat': pricePerSeat,
        'recurrence_type': recurrenceType,
        'selected_weekdays': selectedWeekdays,
        'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        if (occurrenceCount != null) 'occurrence_count': occurrenceCount,
        'is_women_only': isWomenOnly,
      }),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> uploadRecurringSelfie({
    required String scheduleId,
    required XFile selfie,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/recurring-schedules/$scheduleId/selfie'),
    );

    final token = await _sessionService.getSessionToken();
    if (token == null || token.isEmpty) {
      throw Exception('You are not logged in.');
    }

    request.headers['Authorization'] = 'Bearer $token';

    final compressed = await ImageCompressionService.compressXFile(
      selfie,
      category: ImageCategory.selfie,
    );

    final bytes = compressed.bytes;
    final mimeType = compressed.mimeType;
    final filename = _ensureValidFilename(compressed.outputFileName, mimeType);
    final mediaType = MediaType.parse(mimeType);

    request.files.add(
      http.MultipartFile.fromBytes(
        'selfie',
        bytes,
        filename: filename,
        contentType: mediaType,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> publishRecurringSchedule({
    required String scheduleId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/recurring-schedules/$scheduleId/publish'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  Future<List<Map<String, dynamic>>> getRecurringSchedules() async {
    final response = await http.get(
      Uri.parse('$baseUrl/recurring-schedules'),
      headers: await _headers(authenticated: true),
    );
    final data = await _handleResponse(response);
    final list = data['schedules'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> getRecurringScheduleDetail(
    String scheduleId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/recurring-schedules/$scheduleId'),
      headers: await _headers(authenticated: true),
    );
    final data = await _handleResponse(response);
    return Map<String, dynamic>.from(data['schedule'] ?? {});
  }

  Future<void> pauseRecurringSchedule(String scheduleId) async {
    final response = await http.put(
      Uri.parse('$baseUrl/recurring-schedules/$scheduleId/pause'),
      headers: await _headers(authenticated: true),
    );
    await _handleResponse(response);
  }

  Future<void> resumeRecurringSchedule(String scheduleId) async {
    final response = await http.put(
      Uri.parse('$baseUrl/recurring-schedules/$scheduleId/resume'),
      headers: await _headers(authenticated: true),
    );
    await _handleResponse(response);
  }

  Future<void> cancelRecurringSchedule(String scheduleId) async {
    final response = await http.put(
      Uri.parse('$baseUrl/recurring-schedules/$scheduleId/cancel'),
      headers: await _headers(authenticated: true),
    );
    await _handleResponse(response);
  }

  Future<void> updateRecurringSchedule({
    required String scheduleId,
    int? availableSeats,
    double? pricePerSeat,
    String? endDate,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/recurring-schedules/$scheduleId'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        if (availableSeats != null) 'available_seats': availableSeats,
        if (pricePerSeat != null) 'price_per_seat': pricePerSeat,
        if (endDate != null) 'end_date': endDate,
      }),
    );
    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> calculateRoutes({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    final uri = Uri.parse('$baseUrl/locations/routes').replace(
      queryParameters: {
        'from_lat': fromLat.toString(),
        'from_lon': fromLon.toString(),
        'to_lat': toLat.toString(),
        'to_lon': toLon.toString(),
      },
    );
    final response = await http.get(uri);
    return _handleResponse(response);
  }

  Future<List<Map<String, dynamic>>> searchRides({
    required String fromLocation,
    required String toLocation,
    required String journeyDate,
    double? fromLat,
    double? fromLon,
    double? toLat,
    double? toLon,
  }) async {
    final query = <String, String>{
      'from': fromLocation,
      'to': toLocation,
      'date': journeyDate,
    };
    if (fromLat != null && fromLon != null && toLat != null && toLon != null) {
      query['from_lat'] = fromLat.toString();
      query['from_lon'] = fromLon.toString();
      query['to_lat'] = toLat.toString();
      query['to_lon'] = toLon.toString();
    }

    final uri = Uri.parse('$baseUrl/rides').replace(queryParameters: query);

    final response = await http.get(uri);

    final data = await _handleResponse(response);

    final rides = data['rides'];

    if (rides is! List) {
      return [];
    }

    return rides
        .whereType<Map>()
        .map((ride) => Map<String, dynamic>.from(ride))
        .toList();
  }

  /// Fetches enriched ride details (includes driver name, vehicle info).
  Future<Map<String, dynamic>> getRideDetail({required String rideId}) async {
    final response = await http.get(Uri.parse('$baseUrl/rides/$rideId'));

    final data = await _handleResponse(response);

    final ride = data['ride'];
    if (ride is Map<String, dynamic>) {
      return ride;
    }

    return data;
  }

  Future<void> deleteDraft(String rideId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/rides/$rideId/draft'),
      headers: await _headers(authenticated: true),
    );
    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateRideDraft({
    required String rideId,
    required String vehicleId,
    required String fromLocation,
    required String toLocation,
    required String journeyDate,
    required String departureTime,
    required String estimatedArrivalTime,
    required int availableSeats,
    required double pricePerSeat,
    required bool isWomenOnly,
    double? pickupLatitude,
    double? pickupLongitude,
    double? destinationLatitude,
    double? destinationLongitude,
    dynamic routeGeometry,
    double? routeDistance,
    double? routeDuration,
    String? routeSummary,
    dynamic routeWaypoints,
  }) async {
    final payload = <String, dynamic>{
      'vehicle_id': vehicleId,
      'from_location': fromLocation,
      'to_location': toLocation,
      'journey_date': journeyDate,
      'departure_time': departureTime,
      'estimated_arrival_time': estimatedArrivalTime,
      'available_seats': availableSeats,
      'price_per_seat': pricePerSeat,
      'is_women_only': isWomenOnly,
    };

    if (pickupLatitude != null) payload['pickup_latitude'] = pickupLatitude;
    if (pickupLongitude != null) payload['pickup_longitude'] = pickupLongitude;
    if (destinationLatitude != null)
      payload['destination_latitude'] = destinationLatitude;
    if (destinationLongitude != null)
      payload['destination_longitude'] = destinationLongitude;
    if (routeGeometry != null) payload['route_geometry'] = routeGeometry;
    if (routeDistance != null) payload['route_distance'] = routeDistance;
    if (routeDuration != null) payload['route_duration'] = routeDuration;
    if (routeSummary != null) payload['route_summary'] = routeSummary;
    if (routeWaypoints != null) payload['route_waypoints'] = routeWaypoints;

    final response = await http.put(
      Uri.parse('$baseUrl/rides/$rideId/draft'),
      headers: await _headers(authenticated: true),
      body: jsonEncode(payload),
    );
    return _handleResponse(response);
  }

  /// Fetches rides created by the authenticated driver.
  Future<List<Map<String, dynamic>>> getMyRides() async {
    final response = await http.get(
      Uri.parse('$baseUrl/rides/me'),
      headers: await _headers(authenticated: true),
    );

    final data = await _handleResponse(response);

    final rides = data['rides'];

    if (rides is! List) {
      return [];
    }

    return rides
        .whereType<Map>()
        .map((ride) => Map<String, dynamic>.from(ride))
        .toList();
  }

  Future<Map<String, dynamic>> completeRide({required String rideId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rides/$rideId/complete'),
      headers: await _headers(authenticated: true),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> cancelRide({required String rideId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rides/$rideId/cancel'),
      headers: await _headers(authenticated: true),
    );

    return _handleResponse(response);
  }

  // ------------------------------------------------------------
  // BOOKINGS
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> createBooking({
    required String rideId,
    int seatsBooked = 1,
    required String paymentMode,
    String? passengerName,
    int? passengerAge,
    String? passengerGender,
    List<Map<String, dynamic>>? passengers,
    String? fromLocation,
    String? toLocation,
    double? pickupLatitude,
    double? pickupLongitude,
    double? destinationLatitude,
    double? destinationLongitude,
    double? pickupDistanceAlongRoute,
    double? dropDistanceAlongRoute,
  }) async {
    final body = <String, dynamic>{
      'ride_id': rideId,
      'seats_booked': seatsBooked,
      'payment_mode': paymentMode,
    };

    if (fromLocation != null && fromLocation.isNotEmpty) {
      body['from_location'] = fromLocation;
    }
    if (toLocation != null && toLocation.isNotEmpty) {
      body['to_location'] = toLocation;
    }
    if (pickupLatitude != null) body['pickup_latitude'] = pickupLatitude;
    if (pickupLongitude != null) body['pickup_longitude'] = pickupLongitude;
    if (destinationLatitude != null)
      body['destination_latitude'] = destinationLatitude;
    if (destinationLongitude != null)
      body['destination_longitude'] = destinationLongitude;
    if (pickupDistanceAlongRoute != null)
      body['pickup_distance_along_route'] = pickupDistanceAlongRoute;
    if (dropDistanceAlongRoute != null)
      body['drop_distance_along_route'] = dropDistanceAlongRoute;

    if (passengers != null && passengers.isNotEmpty) {
      body['passengers'] = passengers;
      body['passenger_name'] = passengers[0]['name'];
      body['passenger_age'] = passengers[0]['age'];
      body['passenger_gender'] = passengers[0]['gender'];
    } else {
      if (passengerName != null) body['passenger_name'] = passengerName;
      if (passengerAge != null) body['passenger_age'] = passengerAge;
      if (passengerGender != null) body['passenger_gender'] = passengerGender;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/bookings'),
      headers: await _headers(authenticated: true),
      body: jsonEncode(body),
    );

    return _handleResponse(response);
  }

  /// Uses /bookings/me — the backend derives the user from the session token.
  Future<List<Map<String, dynamic>>> getMyBookings() async {
    final response = await http.get(
      Uri.parse('$baseUrl/bookings/me'),
      headers: await _headers(authenticated: true),
    );

    final data = await _handleResponse(response);

    final bookings = data['bookings'];

    if (bookings is! List) {
      return [];
    }

    return bookings
        .whereType<Map>()
        .map((booking) => Map<String, dynamic>.from(booking))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getRideBookings({
    required String rideId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/bookings/ride/$rideId'),
      headers: await _headers(authenticated: true),
    );

    final data = await _handleResponse(response);

    final bookings = data['bookings'];

    if (bookings is! List) {
      return [];
    }

    return bookings
        .whereType<Map>()
        .map((booking) => Map<String, dynamic>.from(booking))
        .toList();
  }

  Future<Map<String, dynamic>> getBooking({required String bookingId}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/bookings/$bookingId'),
      headers: await _headers(authenticated: true),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> cancelBooking({
    required String bookingId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/bookings/$bookingId/cancel'),
      headers: await _headers(authenticated: true),
    );

    return _handleResponse(response);
  }

  // ------------------------------------------------------------
  // RATINGS
  // ------------------------------------------------------------

  Future<void> submitRatings({
    required String rideId,
    required List<Map<String, dynamic>> ratings,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ratings'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({'ride_id': rideId, 'ratings': ratings}),
    );

    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> getPendingRating() async {
    final response = await http.get(
      Uri.parse('$baseUrl/ratings/pending'),
      headers: await _headers(authenticated: true),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getRideRatingParticipants({
    required String rideId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/ratings/rides/$rideId'),
      headers: await _headers(authenticated: true),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getMyRatingSummary() async {
    final response = await http.get(
      Uri.parse('$baseUrl/ratings/me'),
      headers: await _headers(authenticated: true),
    );

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getUserRatingSummary(String userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/ratings/users/$userId'),
      headers: await _headers(authenticated: true),
    );

    return _handleResponse(response);
  }

  // ------------------------------------------------------------
  // WALLET
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> getWalletSummary() async {
    final response = await http.get(
      Uri.parse('$baseUrl/wallet'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getWalletTransactions({
    String? type,
    int limit = 20,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (type != null && type.isNotEmpty) 'type': type,
    };
    final uri = Uri.parse(
      '$baseUrl/wallet/transactions',
    ).replace(queryParameters: queryParams);
    final response = await http.get(
      uri,
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getWalletTransactionDetail(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/wallet/transactions/$id'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> addMoneyToWallet({
    required double amount,
    required String paymentMethod,
    required String paymentMethodType,
    String? referenceId,
    String? status,
    String? failureReason,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/wallet/add-money'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'amount': amount,
        'payment_method': paymentMethod,
        'payment_method_type': paymentMethodType,
        if (referenceId != null) 'reference_id': referenceId,
        if (status != null) 'status': status,
        if (failureReason != null) 'failure_reason': failureReason,
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> withdrawFromWallet({
    required double amount,
    required String destinationMode,
    required String destinationTitle,
    required String destinationDetail,
    String? destinationId,
    String? referenceId,
    String? status,
    String? failureReason,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/wallet/withdraw'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'amount': amount,
        'destination_mode': destinationMode,
        'destination_title': destinationTitle,
        'destination_detail': destinationDetail,
        if (destinationId != null) 'destination_id': destinationId,
        if (referenceId != null) 'reference_id': referenceId,
        if (status != null) 'status': status,
        if (failureReason != null) 'failure_reason': failureReason,
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getSavedBankAccounts() async {
    final response = await http.get(
      Uri.parse('$baseUrl/wallet/bank-accounts'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> addSavedBankAccount({
    required String accountHolderName,
    required String accountNumber,
    required String ifscCode,
    required String bankName,
    String? branch,
    bool isPrimary = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/wallet/bank-accounts'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'account_holder_name': accountHolderName,
        'account_number': accountNumber,
        'ifsc_code': ifscCode,
        'bank_name': bankName,
        if (branch != null) 'branch': branch,
        'is_primary': isPrimary,
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> deleteSavedBankAccount(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/wallet/bank-accounts/$id'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getSavedUPIIDs() async {
    final response = await http.get(
      Uri.parse('$baseUrl/wallet/upi-ids'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> addSavedUPIID({
    required String upiId,
    String? label,
    bool isPrimary = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/wallet/upi-ids'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'upi_id': upiId,
        if (label != null) 'label': label,
        'is_primary': isPrimary,
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> deleteSavedUPIID(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/wallet/upi-ids/$id'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getSavedCards() async {
    final response = await http.get(
      Uri.parse('$baseUrl/wallet/cards'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> addSavedCard({
    required String lastFourDigits,
    required String cardHolderName,
    required String expiryDate,
    required String cardNetwork,
    bool isCredit = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/wallet/cards'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'last_four_digits': lastFourDigits,
        'card_holder_name': cardHolderName,
        'expiry_date': expiryDate,
        'card_network': cardNetwork,
        'is_credit': isCredit,
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> deleteSavedCard(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/wallet/cards/$id'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  // ── Refer and Earn Endpoints ──────────────────────────────────────────

  Future<Map<String, dynamic>> validateReferralCode(String code) async {
    final response = await http.post(
      Uri.parse('$baseUrl/referrals/validate'),
      headers: await _headers(),
      body: jsonEncode({'referral_code': code.trim().toUpperCase()}),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getReferralSummary() async {
    final response = await http.get(
      Uri.parse('$baseUrl/referrals/summary'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  // ── Razorpay Payment Endpoints ────────────────────────────────────────

  Future<Map<String, dynamic>> getPaymentConfig() async {
    final response = await http.get(
      Uri.parse('$baseUrl/payments/config'),
      headers: await _headers(),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> createPaymentOrder({
    required String purpose,
    double? amount,
    String? rideId,
    int? seatsBooked,
    List<Map<String, dynamic>>? passengers,
    String? fromLocation,
    String? toLocation,
    double? pickupLatitude,
    double? pickupLongitude,
    double? destinationLatitude,
    double? destinationLongitude,
    double? pickupDistanceAlongRoute,
    double? dropDistanceAlongRoute,
  }) async {
    final body = <String, dynamic>{
      'purpose': purpose,
      if (amount != null) 'amount': amount,
      if (rideId != null) 'ride_id': rideId,
      if (seatsBooked != null) 'seats_booked': seatsBooked,
      if (passengers != null) 'passengers': passengers,
      if (fromLocation != null) 'from_location': fromLocation,
      if (toLocation != null) 'to_location': toLocation,
      if (pickupLatitude != null) 'pickup_latitude': pickupLatitude,
      if (pickupLongitude != null) 'pickup_longitude': pickupLongitude,
      if (destinationLatitude != null)
        'destination_latitude': destinationLatitude,
      if (destinationLongitude != null)
        'destination_longitude': destinationLongitude,
      if (pickupDistanceAlongRoute != null)
        'pickup_distance_along_route': pickupDistanceAlongRoute,
      if (dropDistanceAlongRoute != null)
        'drop_distance_along_route': dropDistanceAlongRoute,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/payments/create-order'),
      headers: await _headers(authenticated: true),
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payments/verify'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> cancelPaymentOrder({
    required String orderId,
    String? reason,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payments/cancel'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'order_id': orderId,
        'reason': reason ?? 'cancelled_by_user',
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getPaymentStatus({
    required String orderId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/payments/status/$orderId'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  // ------------------------------------------------------------
  // In-App Ride Chat APIs
  // ------------------------------------------------------------

  Future<Map<String, dynamic>> getOrCreateChatConversation({
    required String bookingId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/conversations/get-or-create'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({'booking_id': bookingId}),
    );
    return _handleResponse(response);
  }

  Future<List<Map<String, dynamic>>> getChatConversations() async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/conversations'),
      headers: await _headers(authenticated: true),
    );
    final data = await _handleResponse(response);
    final list = data['conversations'];
    if (list is List) {
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> getChatConversation({
    required String conversationId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/conversations/$conversationId'),
      headers: await _headers(authenticated: true),
    );
    return _handleResponse(response);
  }

  Future<List<Map<String, dynamic>>> getChatMessages({
    required String conversationId,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/chat/conversations/$conversationId/messages?limit=$limit&offset=$offset',
      ),
      headers: await _headers(authenticated: true),
    );
    final data = await _handleResponse(response);
    final list = data['messages'];
    if (list is List) {
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> sendChatMessage({
    required String conversationId,
    required String content,
    String messageType = 'text',
    String? clientMessageId,
  }) async {
    final body = <String, dynamic>{
      'content': content,
      'message_type': messageType,
    };
    if (clientMessageId != null) {
      body['client_message_id'] = clientMessageId;
    }
    final response = await http.post(
      Uri.parse('$baseUrl/chat/conversations/$conversationId/messages'),
      headers: await _headers(authenticated: true),
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Future<int> markChatMessagesAsRead({required String conversationId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/conversations/$conversationId/read'),
      headers: await _headers(authenticated: true),
    );
    final data = await _handleResponse(response);
    return data['marked_read'] is int
        ? data['marked_read'] as int
        : int.tryParse(data['marked_read']?.toString() ?? '0') ?? 0;
  }

  Future<int> getUnreadChatCount() async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/unread-count'),
      headers: await _headers(authenticated: true),
    );
    final data = await _handleResponse(response);
    return data['total_unread'] is int
        ? data['total_unread'] as int
        : int.tryParse(data['total_unread']?.toString() ?? '0') ?? 0;
  }

  Future<void> blockChatUser({required String userId, String? reason}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/block'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'user_id': userId,
        if (reason != null) 'reason': reason,
      }),
    );
    await _handleResponse(response);
  }

  Future<void> reportChatUser({
    required String userId,
    String? rideId,
    String? conversationId,
    required String reason,
    String? description,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/report'),
      headers: await _headers(authenticated: true),
      body: jsonEncode({
        'user_id': userId,
        if (rideId != null) 'ride_id': rideId,
        if (conversationId != null) 'conversation_id': conversationId,
        'reason': reason,
        if (description != null) 'description': description,
      }),
    );
    await _handleResponse(response);
  }

  /// Retrieves authorized contact information (phone number, name, role)
  /// for a confirmed or completed booking.
  Future<Map<String, dynamic>?> getBookingContact({
    required String bookingId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/bookings/$bookingId/contact'),
        headers: await _headers(authenticated: true),
      );
      final data = await _handleResponse(response);
      final contact = data['contact'];
      if (contact is Map<String, dynamic>) {
        return contact;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------
  // GEOAPIFY LOCATION AUTOCOMPLETE & REVERSE GEOCODING
  // ------------------------------------------------------------

  /// Fetches live autocomplete place suggestions from backend Geoapify integration
  Future<List<Map<String, dynamic>>> autocompleteLocations(String query) async {
    final uri = Uri.parse(
      '$baseUrl/locations/autocomplete',
    ).replace(queryParameters: {'q': query});
    final response = await http.get(
      uri,
      headers: await _headers(authenticated: false),
    );
    final data = await _handleResponse(response);
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Resolves device coordinates into a normalized place name and formatted address
  Future<Map<String, dynamic>> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$baseUrl/locations/reverse').replace(
      queryParameters: {
        'lat': latitude.toString(),
        'lon': longitude.toString(),
      },
    );
    final response = await http.get(
      uri,
      headers: await _headers(authenticated: false),
    );
    return await _handleResponse(response);
  }
}
