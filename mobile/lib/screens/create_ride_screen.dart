import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/notification_state.dart';
import '../services/wallet_service.dart';
import '../models/location_result.dart';
import '../models/route_option.dart';
import '../widgets/location_search_bottom_sheet.dart';
import '../widgets/route_selector_map.dart';
import '../widgets/swipe_to_confirm.dart';
import 'recurring_schedules_screen.dart';
import 'vehicles_screen.dart';

// -----------------------------------------------------------------------------
// THEME COLORS (taken from the design mockups)
// -----------------------------------------------------------------------------

class _C {
  static const navy = Color(0xFF0B1B4D);
  static const blue = Color(0xFF0B5FD1);
  static const blueLight = Color(0xFF3B8BEB);
  static const green = Color(0xFF12A37B);
  static const red = Color(0xFFE5484D);
  static const hint = Color(0xFF7B879C);
  static const border = Color(0xFFD5DCE8);
  static const chip = Color(0xFFE8F1FE);
  static const bgTop = Color(0xFFFFFFFF);
  static const bgBottom = Color(0xFFF1F6FE);
}

class CreateRideScreen extends StatefulWidget {
  final Map<String, dynamic>? initialRide;

  const CreateRideScreen({super.key, this.initialRide});

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  LocationResult? _pickupLocation;
  LocationResult? _destinationLocation;

  // Route Selection State
  List<RouteOption> _availableRoutes = [];
  RouteOption? _selectedRoute;
  bool _isLoadingRoutes = false;
  String? _routesError;

  double _swapRotationTurns = 0.0;

  List<Map<String, dynamic>> _vehicles = [];

  Map<String, dynamic>? _selectedVehicle;

  DateTime? _journeyDate;
  TimeOfDay? _departureTime;
  TimeOfDay? _arrivalTime;

  int? _availableSeats;

  String? _rideId;
  double? _userAmount;
  double? _appAmount;
  double? _totalAmount;

  XFile? _selfie;
  Uint8List? _selfieBytes;
  String? _remoteSelfieUrl;
  String? _pendingVehicleId;
  Map<String, dynamic>? _detectedDraftRide;

  bool _isLoadingVehicles = true;
  bool _isCreatingRide = false;
  bool _isUploadingSelfie = false;
  bool _isPublishing = false;

  int _currentStep = 0;

  // Recurring Schedule State
  bool _isRecurring = false;
  String _recurrenceType =
      'does_not_repeat'; // 'does_not_repeat', 'every_day', 'every_week', 'every_2_weeks', 'custom'
  final Set<String> _selectedWeekdays = {'Mon', 'Wed', 'Fri'};
  DateTime? _recurringStartDate;
  DateTime? _recurringEndDate;
  int? _recurringOccurrenceCount;
  bool _endByDate = true;
  String? _recurringScheduleId;
  int _generatedRideCount = 0;

  // Women Only Ride State (exclusive to verified female drivers)
  bool _isWomenOnly = false;
  bool _isFemaleDriver = false;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
    _loadUserProfile();
    if (widget.initialRide != null) {
      _applyInitialRide(widget.initialRide!);
    } else {
      _checkForDraftRide();
    }
  }

  void _applyInitialRide(Map<String, dynamic> ride) {
    _rideId = ride['id']?.toString();
    _fromController.text = ride['from_location']?.toString() ?? '';
    _toController.text = ride['to_location']?.toString() ?? '';

    final priceVal = ride['price_per_seat'];
    if (priceVal != null) {
      final pNum = double.tryParse(priceVal.toString());
      if (pNum != null) {
        _priceController.text = pNum == pNum.roundToDouble()
            ? pNum.toInt().toString()
            : pNum.toString();
      } else {
        _priceController.text = priceVal.toString();
      }
    }

    _availableSeats = int.tryParse(ride['available_seats']?.toString() ?? '');
    _isWomenOnly = ride['is_women_only'] == true;
    _pendingVehicleId = ride['vehicle_id']?.toString();

    final pLat = (ride['pickup_latitude'] as num?)?.toDouble();
    final pLon = (ride['pickup_longitude'] as num?)?.toDouble();
    final dLat = (ride['destination_latitude'] as num?)?.toDouble();
    final dLon = (ride['destination_longitude'] as num?)?.toDouble();
    if (pLat != null && pLon != null) {
      _pickupLocation = LocationResult(
        name: _fromController.text,
        formattedAddress: _fromController.text,
        latitude: pLat,
        longitude: pLon,
      );
    }
    if (dLat != null && dLon != null) {
      _destinationLocation = LocationResult(
        name: _toController.text,
        formattedAddress: _toController.text,
        latitude: dLat,
        longitude: dLon,
      );
    }
    if (_pickupLocation != null && _destinationLocation != null) {
      _fetchAvailableRoutes();
    }

    // Match vehicle if already loaded
    if (_vehicles.isNotEmpty && _pendingVehicleId != null) {
      for (final v in _vehicles) {
        if (v['id']?.toString() == _pendingVehicleId) {
          _selectedVehicle = v;
          break;
        }
      }
    }

    // Parse Journey Date
    final rawDate = ride['journey_date']?.toString();
    if (rawDate != null && rawDate.isNotEmpty) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed != null) {
        _journeyDate = parsed;
      } else if (rawDate.length >= 10) {
        final p = rawDate.substring(0, 10).split('-');
        if (p.length == 3) {
          final y = int.tryParse(p[0]);
          final m = int.tryParse(p[1]);
          final d = int.tryParse(p[2]);
          if (y != null && m != null && d != null) {
            _journeyDate = DateTime(y, m, d);
          }
        }
      }
    }

    // Parse Departure Time
    final rawDep = ride['departure_time']?.toString();
    if (rawDep != null && rawDep.isNotEmpty) {
      _departureTime = _parseTimeOfDay(rawDep);
    }

    // Parse Arrival Time
    final rawArr = ride['estimated_arrival_time']?.toString();
    if (rawArr != null && rawArr.isNotEmpty) {
      _arrivalTime = _parseTimeOfDay(rawArr);
    }

    // Selfie
    final selfieUrl = ride['driver_selfie_url']?.toString();
    if (selfieUrl != null && selfieUrl.isNotEmpty) {
      _remoteSelfieUrl = selfieUrl;
    }

    final status = ride['status']?.toString() ?? 'draft';
    // If it's a draft or selfie_uploaded, it takes the user to where they left off (Step 2 - Live Selfie Verification)
    if (status == 'draft' || status == 'selfie_uploaded') {
      _currentStep = 1;
    }
  }

  TimeOfDay? _parseTimeOfDay(String raw) {
    if (raw.contains('T')) {
      final dt = DateTime.tryParse(raw);
      if (dt != null) {
        return TimeOfDay(hour: dt.hour, minute: dt.minute);
      }
    }
    final parts = raw.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        return TimeOfDay(hour: h, minute: m);
      }
    }
    return null;
  }

  Future<void> _checkForDraftRide() async {
    try {
      final myRides = await _apiService.getMyRides();
      final drafts = myRides.where((r) {
        final s = r['status']?.toString();
        return s == 'draft' || s == 'selfie_uploaded';
      }).toList();
      if (drafts.isNotEmpty && mounted) {
        setState(() {
          _detectedDraftRide = drafts.first;
        });
      }
    } catch (_) {}
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${ApiService.baseUrl}$url';
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = await _apiService.getCurrentUser();
      final gender = user['gender']?.toString().toLowerCase().trim();
      if (mounted) {
        setState(() {
          _isFemaleDriver = gender == 'female';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // VEHICLES
  // ---------------------------------------------------------------------------

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoadingVehicles = true;
    });

    try {
      final vehicles = await _apiService.getVehicles();

      if (!mounted) return;

      setState(() {
        _vehicles = vehicles;
        _isLoadingVehicles = false;
        if (_selectedVehicle == null && _pendingVehicleId != null) {
          for (final v in vehicles) {
            if (v['id']?.toString() == _pendingVehicleId) {
              _selectedVehicle = v;
              break;
            }
          }
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingVehicles = false;
      });

      _showMessage('Failed to load vehicles: $e');
    }
  }

  int _getMaximumSeats(Map<String, dynamic> vehicle) {
    final vehicleType = vehicle['vehicle_type']?.toString();

    switch (vehicleType) {
      case 'two_wheeler':
        return 1;

      case 'five_seater':
        return 4;

      case 'seven_seater':
        return 6;

      default:
        return 1;
    }
  }

  String _getVehicleTypeLabel(String? type) {
    switch (type) {
      case 'two_wheeler':
        return '2-Seater';

      case 'five_seater':
        return '5-Seater';

      case 'seven_seater':
        return '7-Seater';

      default:
        return type ?? 'Vehicle';
    }
  }

  // ---------------------------------------------------------------------------
  // DATE / TIME
  // ---------------------------------------------------------------------------

  Future<void> _selectJourneyDate() async {
    final now = DateTime.now();

    final selectedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
      initialDate: _journeyDate ?? now,
    );

    if (selectedDate == null) return;

    setState(() {
      _journeyDate = selectedDate;
    });
  }

  Future<void> _selectRecurringStartDate() async {
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
      initialDate: _recurringStartDate ?? now,
    );
    if (selectedDate == null) return;
    setState(() {
      _recurringStartDate = selectedDate;
      if (_recurringEndDate != null &&
          _recurringEndDate!.isBefore(selectedDate)) {
        _recurringEndDate = selectedDate.add(const Duration(days: 30));
      }
    });
  }

  Future<void> _selectRecurringEndDate() async {
    final start = _recurringStartDate ?? DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: DateTime(start.year + 2, start.month, start.day),
      initialDate: _recurringEndDate ?? start.add(const Duration(days: 30)),
    );
    if (selectedDate == null) return;
    setState(() {
      _recurringEndDate = selectedDate;
    });
  }

  List<DateTime> _calculatePreviewDates() {
    final start = _recurringStartDate ?? _journeyDate ?? DateTime.now();
    final cleanStart = DateTime(start.year, start.month, start.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (cleanStart.isBefore(today)) return [];

    final weekdayMap = <int, bool>{};
    for (final w in _selectedWeekdays) {
      switch (w.toLowerCase()) {
        case 'mon':
          weekdayMap[DateTime.monday] = true;
          break;
        case 'tue':
          weekdayMap[DateTime.tuesday] = true;
          break;
        case 'wed':
          weekdayMap[DateTime.wednesday] = true;
          break;
        case 'thu':
          weekdayMap[DateTime.thursday] = true;
          break;
        case 'fri':
          weekdayMap[DateTime.friday] = true;
          break;
        case 'sat':
          weekdayMap[DateTime.saturday] = true;
          break;
        case 'sun':
          weekdayMap[DateTime.sunday] = true;
          break;
      }
    }

    final dates = <DateTime>[];
    var current = cleanStart;
    final maxCount = _endByDate
        ? 60
        : (_recurringOccurrenceCount ?? 10).clamp(1, 60);
    final endDate = _endByDate ? _recurringEndDate : null;

    for (var i = 0; i < 120 && dates.length < maxCount; i++) {
      if (endDate != null && current.isAfter(endDate)) break;

      var include = false;
      switch (_recurrenceType) {
        case 'every_day':
        case 'daily':
          include = true;
          break;
        case 'every_week':
        case 'weekly':
          if (current.difference(cleanStart).inDays % 7 == 0) include = true;
          break;
        case 'every_2_weeks':
        case 'biweekly':
          if (current.difference(cleanStart).inDays % 14 == 0) include = true;
          break;
        case 'custom':
          if (weekdayMap[current.weekday] == true) include = true;
          break;
      }

      if (include) {
        dates.add(current);
      }
      current = current.add(const Duration(days: 1));
    }
    return dates;
  }

  Future<void> _selectDepartureTime() async {
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _departureTime ?? TimeOfDay.now(),
    );

    if (selectedTime == null) return;

    setState(() {
      _departureTime = selectedTime;
      _calculateArrivalTime();
    });
  }

  void _calculateArrivalTime() {
    if (_departureTime == null) return;

    int durationMin = 0;
    if (_selectedRoute != null) {
      durationMin = _selectedRoute!.durationMinutes;
      if (durationMin <= 0 && _selectedRoute!.durationSeconds > 0) {
        durationMin = (_selectedRoute!.durationSeconds / 60).round();
      }
    }

    if (durationMin <= 0) return;

    final depMinutes = _departureTime!.hour * 60 + _departureTime!.minute;
    final totalArrMinutes = (depMinutes + durationMin) % (24 * 60);
    final arrHour = (totalArrMinutes ~/ 60) % 24;
    final arrMinute = totalArrMinutes % 60;

    _arrivalTime = TimeOfDay(hour: arrHour, minute: arrMinute);
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return '$year-$month-$day';
  }

  String _formatDisplayDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');

    return '$hour:$minute:00';
  }

  void _swapLocations() {
    if (_isBusy) return;
    HapticFeedback.lightImpact();
    setState(() {
      _swapRotationTurns += 0.5;
      final temp = _fromController.text;
      _fromController.text = _toController.text;
      _toController.text = temp;

      final tempLoc = _pickupLocation;
      _pickupLocation = _destinationLocation;
      _destinationLocation = tempLoc;

      _fromController.selection = TextSelection.collapsed(
        offset: _fromController.text.length,
      );
      _toController.selection = TextSelection.collapsed(
        offset: _toController.text.length,
      );
    });

    if (_pickupLocation != null && _destinationLocation != null) {
      _fetchAvailableRoutes();
    }
  }

  Future<void> _fetchAvailableRoutes() async {
    final p = _pickupLocation;
    final d = _destinationLocation;
    if (p == null || d == null) return;
    if (p.latitude == null ||
        p.longitude == null ||
        d.latitude == null ||
        d.longitude == null)
      return;
    if (p.latitude == 0 && p.longitude == 0) return;
    if (d.latitude == 0 && d.longitude == 0) return;

    setState(() {
      _isLoadingRoutes = true;
      _routesError = null;
    });

    try {
      final res = await _apiService.calculateRoutes(
        fromLat: p.latitude!,
        fromLon: p.longitude!,
        toLat: d.latitude!,
        toLon: d.longitude!,
      );

      final rawList = res['routes'];
      final parsed = <RouteOption>[];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is Map) {
            parsed.add(RouteOption.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }

      if (mounted) {
        setState(() {
          _availableRoutes = parsed;
          if (parsed.isNotEmpty) {
            _selectedRoute = parsed.first;
            _calculateArrivalTime();
          }
          _isLoadingRoutes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRoutes = false;
          _routesError = 'Could not calculate routes automatically';
        });
      }
    }
  }

  Future<void> _pickLocation({required bool isPickup}) async {
    if (_isBusy) return;
    final title = isPickup ? 'Choose Pickup Location' : 'Choose Destination';
    final currentText = isPickup ? _fromController.text : _toController.text;

    final result = await showLocationSearchSheet(
      context: context,
      title: title,
      isPickup: isPickup,
      initialQuery: currentText,
    );

    if (result != null) {
      setState(() {
        if (isPickup) {
          _pickupLocation = result;
          _fromController.text = result.displayName;
        } else {
          _destinationLocation = result;
          _toController.text = result.displayName;
        }
      });
      _formKey.currentState?.validate();
      if (_pickupLocation != null && _destinationLocation != null) {
        _fetchAvailableRoutes();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // STEP 1 - CREATE DRAFT
  // ---------------------------------------------------------------------------

  Future<void> _createRideDraft() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check if user has reached the -₹100 negative wallet balance limit
    if (WalletService.instance.balance <= -100.00) {
      await _showOutstandingChargesDialog();
      return;
    }

    if (_selectedVehicle == null) {
      _showMessage('Please select a vehicle.');
      return;
    }

    if (!_isRecurring && _journeyDate == null) {
      _showMessage('Please select the journey date.');
      return;
    }

    if (_isRecurring) {
      final start = _recurringStartDate ?? _journeyDate ?? DateTime.now();
      final preview = _calculatePreviewDates();
      if (preview.isEmpty) {
        _showMessage(
          'No valid future dates found for this schedule. Please check start/end dates.',
        );
        return;
      }
      if (_recurrenceType == 'custom' && _selectedWeekdays.isEmpty) {
        _showMessage('Please select at least one day of the week.');
        return;
      }
    }

    if (_departureTime == null) {
      _showMessage('Please select the departure time.');
      return;
    }

    if (_arrivalTime == null) {
      _calculateArrivalTime();
      if (_arrivalTime == null && _departureTime != null) {
        final depMinutes = _departureTime!.hour * 60 + _departureTime!.minute;
        final totalArrMinutes = (depMinutes + 60) % (24 * 60);
        _arrivalTime = TimeOfDay(
          hour: (totalArrMinutes ~/ 60) % 24,
          minute: totalArrMinutes % 60,
        );
      }
    }

    if (_availableSeats == null) {
      _showMessage('Please select available seats.');
      return;
    }

    final maximumSeats = _getMaximumSeats(_selectedVehicle!);

    if (_availableSeats! > maximumSeats) {
      _showMessage(
        'This vehicle allows a maximum of '
        '$maximumSeats passenger seat(s).',
      );
      return;
    }

    final price = double.tryParse(_priceController.text.trim());

    if (price == null || price < 0) {
      _showMessage('Please enter a valid price.');
      return;
    }

    if (_isRecurring) {
      final start = _recurringStartDate ?? _journeyDate ?? DateTime.now();
      final preview = _calculatePreviewDates();
      if (preview.isEmpty) {
        _showMessage(
          'No valid future dates found for this schedule. Please check start/end dates.',
        );
        return;
      }
      if (_recurrenceType == 'custom' && _selectedWeekdays.isEmpty) {
        _showMessage('Please select at least one day of the week.');
        return;
      }

      setState(() {
        _isCreatingRide = true;
      });

      try {
        final result = await _apiService.createRecurringSchedule(
          vehicleId: _selectedVehicle!['id'].toString(),
          fromLocation: _fromController.text.trim(),
          toLocation: _toController.text.trim(),
          departureTime: _formatTime(_departureTime!),
          estimatedArrivalTime: _formatTime(_arrivalTime!),
          availableSeats: _availableSeats!,
          pricePerSeat: price,
          recurrenceType: _recurrenceType,
          selectedWeekdays: _selectedWeekdays.toList(),
          startDate: _formatDate(start),
          endDate: _endByDate && _recurringEndDate != null
              ? _formatDate(_recurringEndDate!)
              : null,
          occurrenceCount: !_endByDate ? _recurringOccurrenceCount : null,
          isWomenOnly: _isFemaleDriver && _isWomenOnly,
        );

        NotificationState.instance.refresh();
        if (!mounted) return;

        final scheduleId = result['schedule_id']?.toString();
        final count = result['ride_count'] is int
            ? result['ride_count'] as int
            : preview.length;

        if (scheduleId == null || scheduleId.isEmpty) {
          throw Exception('Server did not return a schedule ID.');
        }

        final userAmt =
            double.tryParse(result['user_amount']?.toString() ?? '') ?? price;
        final appAmt =
            double.tryParse(result['app_amount']?.toString() ?? '') ?? 0.0;
        final totalAmt =
            double.tryParse(result['total_amount']?.toString() ?? '') ??
            (userAmt + appAmt);

        setState(() {
          _recurringScheduleId = scheduleId;
          _generatedRideCount = count;
          _userAmount = userAmt;
          _appAmount = appAmt;
          _totalAmount = totalAmt;
          _currentStep = 1;
          _isCreatingRide = false;
        });

        _showMessage(
          'Recurring schedule created ($count rides). Take your live selfie.',
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isCreatingRide = false;
        });
        if ((e is ApiException && e.code == 'OUTSTANDING_PLATFORM_CHARGES') ||
            e.toString().contains('₹100 negative wallet limit') ||
            e.toString().contains('OUTSTANDING_PLATFORM_CHARGES') ||
            e.toString().contains('Outstanding Platform Charges')) {
          await _showOutstandingChargesDialog();
          return;
        }
        _showMessage('Failed to create recurring schedule: $e');
      }
      return;
    }

    if (_rideId != null) {
      setState(() {
        _isCreatingRide = true;
      });

      try {
        await _apiService.updateRideDraft(
          rideId: _rideId!,
          vehicleId: _selectedVehicle!['id'].toString(),
          fromLocation: _fromController.text.trim(),
          toLocation: _toController.text.trim(),
          journeyDate: _formatDate(_journeyDate!),
          departureTime: _formatTime(_departureTime!),
          estimatedArrivalTime: _formatTime(_arrivalTime!),
          availableSeats: _availableSeats!,
          pricePerSeat: price,
          isWomenOnly: _isFemaleDriver && _isWomenOnly,
          pickupLatitude: _pickupLocation?.latitude,
          pickupLongitude: _pickupLocation?.longitude,
          destinationLatitude: _destinationLocation?.latitude,
          destinationLongitude: _destinationLocation?.longitude,
          routeGeometry: _selectedRoute?.coordinates,
          routeDistance: _selectedRoute?.distanceMeters,
          routeDuration: _selectedRoute?.durationSeconds,
          routeSummary: _selectedRoute?.summary,
          routeWaypoints: _selectedRoute?.intermediatePoints
              .map((p) => p.toJson())
              .toList(),
        );
      } catch (_) {
        // Fallback gracefully if endpoint isn't reached
      }

      if (!mounted) return;
      setState(() {
        _currentStep = 1;
        _isCreatingRide = false;
      });
      _showMessage('Draft details updated. Proceed with selfie verification.');
      return;
    }

    setState(() {
      _isCreatingRide = true;
    });

    try {
      final result = await _apiService.createRide(
        vehicleId: _selectedVehicle!['id'].toString(),
        fromLocation: _fromController.text.trim(),
        toLocation: _toController.text.trim(),
        journeyDate: _formatDate(_journeyDate!),
        departureTime: _formatTime(_departureTime!),
        estimatedArrivalTime: _formatTime(_arrivalTime!),
        availableSeats: _availableSeats!,
        pricePerSeat: price,
        isWomenOnly: _isFemaleDriver && _isWomenOnly,
        pickupLatitude: _pickupLocation?.latitude,
        pickupLongitude: _pickupLocation?.longitude,
        destinationLatitude: _destinationLocation?.latitude,
        destinationLongitude: _destinationLocation?.longitude,
        routeGeometry: _selectedRoute?.coordinates,
        routeDistance: _selectedRoute?.distanceMeters,
        routeDuration: _selectedRoute?.durationSeconds,
        routeSummary: _selectedRoute?.summary,
        routeWaypoints: _selectedRoute?.intermediatePoints
            .map((p) => p.toJson())
            .toList(),
      );

      NotificationState.instance.refresh();

      if (!mounted) return;

      final ride = result['ride'];

      String? rideId;

      if (ride is Map) {
        rideId = ride['id']?.toString();
      }

      rideId ??= result['ride_id']?.toString();

      if (rideId == null || rideId.isEmpty) {
        throw Exception('Server did not return a ride ID.');
      }

      final userAmt =
          double.tryParse(result['user_amount']?.toString() ?? '') ?? price;
      final appAmt =
          double.tryParse(result['app_amount']?.toString() ?? '') ?? 0.0;
      final totalAmt =
          double.tryParse(result['total_amount']?.toString() ?? '') ??
          (userAmt + appAmt);

      setState(() {
        _rideId = rideId;
        _userAmount = userAmt;
        _appAmount = appAmt;
        _totalAmount = totalAmt;
        _currentStep = 1;
        _isCreatingRide = false;
      });

      _showMessage('Ride draft created. Take your live selfie.');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isCreatingRide = false;
      });

      if ((e is ApiException && e.code == 'OUTSTANDING_PLATFORM_CHARGES') ||
          e.toString().contains('₹100 negative wallet limit') ||
          e.toString().contains('OUTSTANDING_PLATFORM_CHARGES') ||
          e.toString().contains('Outstanding Platform Charges')) {
        await _showOutstandingChargesDialog();
        return;
      }

      _showMessage('Failed to create ride: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // STEP 2 - TAKE LIVE SELFIE
  // ---------------------------------------------------------------------------

  Future<void> _takeSelfie() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );

      if (image == null) {
        return;
      }

      final bytes = await image.readAsBytes();

      if (!mounted) return;

      setState(() {
        _selfie = image;
        _selfieBytes = bytes;
      });

      _showMessage('Selfie captured successfully.');
    } catch (e) {
      if (!mounted) return;

      _showMessage('Unable to access camera: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // STEP 2 - UPLOAD SELFIE + PUBLISH
  // ---------------------------------------------------------------------------

  Future<void> _uploadSelfieAndPublish() async {
    if (_isRecurring) {
      if (_recurringScheduleId == null) {
        _showMessage('Recurring schedule draft is missing.');
        return;
      }
      if (_selfie == null) {
        _showMessage('Please take a live selfie first.');
        return;
      }

      setState(() => _isUploadingSelfie = true);

      try {
        await _apiService.uploadRecurringSelfie(
          scheduleId: _recurringScheduleId!,
          selfie: _selfie!,
        );

        if (!mounted) return;

        setState(() {
          _isUploadingSelfie = false;
          _isPublishing = true;
        });

        final res = await _apiService.publishRecurringSchedule(
          scheduleId: _recurringScheduleId!,
        );

        NotificationState.instance.refresh();

        if (!mounted) return;

        setState(() {
          _isPublishing = false;
        });

        final publishedCount = res['published_count'] ?? _generatedRideCount;
        await _showRecurringPublishedDialog(publishedCount);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isUploadingSelfie = false;
          _isPublishing = false;
        });
        _showMessage('Failed to publish recurring schedule: $e');
      }
      return;
    }

    if (_rideId == null) {
      _showMessage('Ride draft is missing.');
      return;
    }

    final hasLocalSelfie = _selfie != null;
    final hasRemoteSelfie =
        _remoteSelfieUrl != null && _remoteSelfieUrl!.isNotEmpty;

    if (!hasLocalSelfie && !hasRemoteSelfie) {
      _showMessage('Please take a live selfie first.');
      return;
    }

    setState(() {
      _isUploadingSelfie = hasLocalSelfie;
    });

    try {
      if (hasLocalSelfie) {
        await _apiService.uploadRideSelfie(rideId: _rideId!, selfie: _selfie!);
      }

      if (!mounted) return;

      setState(() {
        _isUploadingSelfie = false;
        _isPublishing = true;
      });

      await _apiService.publishRide(rideId: _rideId!);

      if (!mounted) return;

      setState(() {
        _isPublishing = false;
      });

      await _showRidePublishedDialog();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isUploadingSelfie = false;
        _isPublishing = false;
      });

      _showMessage('Failed to publish ride: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // OUTSTANDING CHARGES LIMIT DIALOG
  // ---------------------------------------------------------------------------

  Future<void> _showOutstandingChargesDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Outstanding Platform Charges',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: const Text(
            'You have reached your ₹100 negative wallet limit. Please pay the outstanding platform charges from your previous rides before creating a new ride.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SUCCESS
  // ---------------------------------------------------------------------------

  Future<void> _showRidePublishedDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 10),
              Text('Ride Published'),
            ],
          ),
          content: const Text(
            'Your ride is now active and '
            'visible to passengers.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    Navigator.of(context).pop(true);
  }

  Future<void> _showRecurringPublishedDialog(int count) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 10),
              Expanded(child: Text('Recurring Rides Published!')),
            ],
          ),
          content: Text(
            '$count rides have been scheduled and published.\nPassengers can now search and book each date.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RecurringSchedulesScreen(),
                  ),
                );
              },
              child: const Text('View Schedules'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // ---------------------------------------------------------------------------
  // UI HELPERS
  // ---------------------------------------------------------------------------

  void _showMessage(String message) {
    // if (!mounted) return;

    // ScaffoldMessenger.of(context)
    //   ..hideCurrentSnackBar()
    //   ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _isBusy {
    return _isCreatingRide || _isUploadingSelfie || _isPublishing;
  }

  /// Shared outlined-field look: floating blue label, rounded corners.
  InputDecoration _decoration({
    required String label,
    Widget? prefix,
    Widget? suffix,
    String? helper,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperStyle: const TextStyle(color: _C.hint, fontSize: 12),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: const TextStyle(
        color: _C.blue,
        fontWeight: FontWeight.w500,
        fontSize: 16,
      ),
      floatingLabelStyle: const TextStyle(
        color: _C.blue,
        fontWeight: FontWeight.w500,
        fontSize: 16,
      ),
      hintStyle: const TextStyle(color: _C.hint, fontSize: 16),
      filled: true,
      fillColor: Colors.white,
      prefixIcon: prefix,
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: 48),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border(_C.border),
      enabledBorder: border(_C.border),
      disabledBorder: border(_C.border),
      focusedBorder: border(_C.blue, 1.6),
      errorBorder: border(_C.red),
      focusedErrorBorder: border(_C.red, 1.6),
    );
  }

  Widget _circleIcon(IconData icon, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: _C.chip,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: _C.blue, size: 22),
        ),
      ),
    );
  }

  Widget _buildSwapButton() {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2.5,
      shadowColor: _C.navy.withOpacity(0.2),
      child: Tooltip(
        message: 'Swap pickup and destination',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _isBusy ? null : _swapLocations,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _C.border, width: 1.2),
            ),
            child: AnimatedRotation(
              turns: _swapRotationTurns,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: const Icon(
                Icons.swap_vert_rounded,
                color: _C.blue,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: _C.bgTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: _C.navy,
          ),
          onPressed: () {
            if (_currentStep == 1) {
              setState(() => _currentStep = 0);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        iconTheme: const IconThemeData(color: _C.navy),
        title: Text(
          _rideId != null ? 'Continue Ride' : 'Create Ride',
          style: const TextStyle(
            color: _C.navy,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoadingVehicles
          ? const Center(child: CircularProgressIndicator())
          : _vehicles.isEmpty
          ? _buildNoVehiclesView()
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_C.bgTop, _C.bgBottom],
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _currentStep == 0
            ? _buildRideDetailsStep(topInset)
            : _buildSelfieStep(topInset),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEPPER
  // ---------------------------------------------------------------------------

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepIndicator(
            number: 1,
            title: 'Ride Details',
            active: _currentStep == 0,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: Stack(
                    children: [
                      Container(color: const Color(0xFFDCE3EF)),
                      FractionallySizedBox(
                        widthFactor: _currentStep == 0 ? 0.3 : 1.0,
                        child: Container(color: _C.blue),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildStepIndicator(
            number: 2,
            title: 'Selfie',
            active: _currentStep == 1,
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator({
    required int number,
    required String title,
    required bool active,
  }) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active
                  ? const LinearGradient(
                      colors: [_C.blueLight, _C.blue],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    )
                  : null,
              color: active ? null : const Color(0xFFE3E7F0),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: _C.blue.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFF5B677F),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: active ? _C.blue : _C.hint,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 1 UI
  // ---------------------------------------------------------------------------

  Widget _buildRideDetailsStep(double topInset) {
    final maximumSeats = _selectedVehicle == null
        ? 0
        : _getMaximumSeats(_selectedVehicle!);
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 380;
    final horizontalMargin = screenWidth < 360
        ? 10.0
        : (screenWidth < 400 ? 12.0 : 14.0);
    final horizontalPadding = screenWidth < 360
        ? 12.0
        : (screenWidth < 400 ? 14.0 : 16.0);

    return SingleChildScrollView(
      key: const ValueKey('step-details'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Stack(
        children: [
          // Header illustration (car on the road) behind the title.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/images/create_ride_header.png',
              fit: BoxFit.fitWidth,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: topInset + 4),
                _buildProgressIndicator(),
                const SizedBox(height: 22),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: _TitleText(first: 'Ride ', second: 'Details'),
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Tell passengers about your journey.',
                    style: TextStyle(color: _C.hint, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 22),

                if (_detectedDraftRide != null && _rideId == null)
                  _buildDraftResumeBanner(horizontalMargin),

                // ---------------- FORM CARD ----------------
                Container(
                  margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    22,
                    horizontalPadding,
                    22,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: _C.blue.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Vehicle
                      DropdownButtonFormField<Map<String, dynamic>>(
                        initialValue: _selectedVehicle,
                        isExpanded: true,
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: _C.blue,
                          size: 28,
                        ),
                        hint: const Text(
                          'Select vehicle type',
                          style: TextStyle(color: _C.hint, fontSize: 16),
                        ),
                        decoration: _decoration(
                          label: 'Vehicle',
                          prefix: const Icon(
                            Icons.directions_car_filled_rounded,
                            color: _C.green,
                          ),
                        ),
                        items: _vehicles.map((vehicle) {
                          final vehicleType = vehicle['vehicle_type']
                              ?.toString();
                          final model = vehicle['model']?.toString() ?? '';
                          final vehicleNumber =
                              vehicle['vehicle_number']?.toString() ?? '';

                          return DropdownMenuItem<Map<String, dynamic>>(
                            value: vehicle,
                            child: Text(
                              '$model • '
                              '$vehicleNumber • '
                              '${_getVehicleTypeLabel(vehicleType)}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _C.navy,
                                fontSize: 16,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: _isBusy
                            ? null
                            : (vehicle) {
                                if (vehicle == null) {
                                  return;
                                }

                                final maxSeats = _getMaximumSeats(vehicle);

                                setState(() {
                                  _selectedVehicle = vehicle;
                                  _availableSeats = maxSeats == 1 ? 1 : null;
                                });
                              },
                        validator: (value) {
                          if (value == null) {
                            return 'Please select a vehicle';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // From / To with route connector
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Column(
                            children: [
                              TextFormField(
                                controller: _fromController,
                                readOnly: true,
                                onTap: _isBusy
                                    ? null
                                    : () => _pickLocation(isPickup: true),
                                enabled: !_isBusy,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(
                                  color: _C.navy,
                                  fontSize: 16,
                                ),
                                decoration: _decoration(
                                  label: 'From',
                                  prefix: const Icon(
                                    Icons.location_on,
                                    color: _C.green,
                                    size: 28,
                                  ),
                                ).copyWith(hintText: 'Enter pickup location'),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter starting location';
                                  }

                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _toController,
                                readOnly: true,
                                onTap: _isBusy
                                    ? null
                                    : () => _pickLocation(isPickup: false),
                                enabled: !_isBusy,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(
                                  color: _C.navy,
                                  fontSize: 16,
                                ),
                                decoration: _decoration(
                                  label: 'To',
                                  prefix: const Icon(
                                    Icons.location_on,
                                    color: _C.red,
                                    size: 28,
                                  ),
                                ).copyWith(hintText: 'Enter drop location'),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter destination';
                                  }

                                  return null;
                                },
                              ),
                            ],
                          ),
                          Positioned(
                            left: 6,
                            top: 50,
                            child: _buildSwapButton(),
                          ),
                        ],
                      ),

                      if (_isLoadingRoutes) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _C.border),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _C.blue,
                                ),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Calculating driving routes via Geoapify...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _C.navy,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_routesError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _routesError!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_availableRoutes.isNotEmpty &&
                          _selectedRoute != null &&
                          _pickupLocation?.latitude != null &&
                          _pickupLocation?.longitude != null &&
                          _destinationLocation?.latitude != null &&
                          _destinationLocation?.longitude != null) ...[
                        const SizedBox(height: 16),
                        RouteSelectorMap(
                          routes: _availableRoutes,
                          selectedRoute: _selectedRoute!,
                          onRouteSelected: (route) {
                            setState(() {
                              _selectedRoute = route;
                              _calculateArrivalTime();
                            });
                          },
                          fromLat: _pickupLocation!.latitude!,
                          fromLon: _pickupLocation!.longitude!,
                          toLat: _destinationLocation!.latitude!,
                          toLon: _destinationLocation!.longitude!,
                          fromName: _fromController.text,
                          toName: _toController.text,
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Schedule Mode Switcher: Single Ride vs Recurring Series
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: _C.blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _isRecurring = false;
                                  _recurrenceType = 'does_not_repeat';
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !_isRecurring
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: !_isRecurring
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.06,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.directions_car_outlined,
                                        size: 18,
                                        color: !_isRecurring
                                            ? _C.blue
                                            : _C.hint,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'Single Ride',
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: !_isRecurring
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              color: !_isRecurring
                                                  ? _C.navy
                                                  : _C.hint,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isRecurring = true;
                                    if (_recurrenceType == 'does_not_repeat') {
                                      _recurrenceType = 'every_day';
                                    }
                                    _recurringStartDate ??=
                                        _journeyDate ?? DateTime.now();
                                    _recurringEndDate ??=
                                        (_recurringStartDate ?? DateTime.now())
                                            .add(const Duration(days: 30));
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isRecurring
                                        ? _C.blue
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: _isRecurring
                                        ? [
                                            BoxShadow(
                                              color: _C.blue.withOpacity(0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.event_repeat_rounded,
                                        size: 18,
                                        color: _isRecurring
                                            ? Colors.white
                                            : _C.hint,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'Schedule Recurring',
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: _isRecurring
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              color: _isRecurring
                                                  ? Colors.white
                                                  : _C.hint,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (!_isRecurring)
                        // Single Journey date
                        _PickerField(
                          decoration: _decoration(
                            label: 'Journey Date',
                            prefix: const Icon(
                              Icons.calendar_month_outlined,
                              color: _C.blue,
                            ),
                            suffix: _circleIcon(Icons.calendar_today_outlined),
                          ),
                          value: _journeyDate == null
                              ? null
                              : _formatDisplayDate(_journeyDate!),
                          placeholder: 'Select date',
                          onTap: _isBusy ? null : _selectJourneyDate,
                        )
                      else
                        // Recurring schedule config section
                        _buildRecurringScheduleConfig(),

                      const SizedBox(height: 16),

                      // Departure time
                      _PickerField(
                        decoration: _decoration(
                          label: 'Departure Time',
                          prefix: const Icon(
                            Icons.directions_bus_filled_outlined,
                            color: _C.blue,
                          ),
                          suffix: _circleIcon(Icons.schedule),
                        ),
                        value: _departureTime?.format(context),
                        placeholder: 'Select time',
                        onTap: _isBusy ? null : _selectDepartureTime,
                      ),

                      const SizedBox(height: 16),

                      // Arrival time (auto-calculated based on maps route duration)
                      _PickerField(
                        decoration: _decoration(
                          label: 'Estimated Arrival Time',
                          prefix: const Icon(Icons.access_time, color: _C.blue),
                          suffix: _circleIcon(Icons.auto_awesome),
                          helper: _selectedRoute != null &&
                                  _selectedRoute!.durationFormatted.isNotEmpty
                              ? 'Auto-calculated from route (${_selectedRoute!.durationFormatted})'
                              : null,
                        ),
                        value: _arrivalTime?.format(context),
                        placeholder: _departureTime == null
                            ? 'Auto-calculated after departure time'
                            : (_selectedRoute == null
                                ? 'Calculating from route...'
                                : 'Auto-calculated from route'),
                        onTap: null,
                      ),

                      const SizedBox(height: 16),

                      // Seats (key forces a rebuild when the vehicle changes so
                      // the old value can never be missing from the new items)
                      DropdownButtonFormField<int>(
                        key: ValueKey('seats-${_selectedVehicle?['id']}'),
                        initialValue: _availableSeats,
                        isExpanded: true,
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: _C.blue,
                          size: 28,
                        ),
                        hint: const Text(
                          'Select available seats',
                          style: TextStyle(color: _C.hint, fontSize: 16),
                        ),
                        decoration: _decoration(
                          label: 'Available Seats',
                          prefix: const Icon(
                            Icons.event_seat_outlined,
                            color: _C.blue,
                          ),
                          helper: _selectedVehicle == null
                              ? 'Maximum seats will depend on selected vehicle'
                              : 'Maximum $maximumSeats seat'
                                    '${maximumSeats == 1 ? '' : 's'} '
                                    'for this vehicle',
                        ),
                        items: List.generate(maximumSeats, (index) {
                          final seats = index + 1;

                          return DropdownMenuItem<int>(
                            value: seats,
                            child: Text(
                              '$seats seat'
                              '${seats == 1 ? '' : 's'}',
                              style: const TextStyle(
                                color: _C.navy,
                                fontSize: 16,
                              ),
                            ),
                          );
                        }),
                        onChanged: _isBusy || _selectedVehicle == null
                            ? null
                            : (value) {
                                setState(() {
                                  _availableSeats = value;
                                });
                              },
                        validator: (value) {
                          if (value == null) {
                            return 'Please select available seats';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      // Price
                      TextFormField(
                        controller: _priceController,
                        enabled: !_isBusy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(color: _C.navy, fontSize: 16),
                        decoration: _decoration(
                          label: 'Price Per Seat',
                          prefix: const Icon(
                            Icons.currency_rupee,
                            color: _C.blue,
                          ),
                          helper:
                              'Your ride price (AbhiShare adds Extra Pay for passengers)',
                        ).copyWith(hintText: 'Enter price per seat'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter price per seat';
                          }

                          final price = double.tryParse(value.trim());

                          if (price == null || price < 0) {
                            return 'Please enter a valid price';
                          }

                          return null;
                        },
                      ),

                      if (_isFemaleDriver) ...[
                        const SizedBox(height: 16),
                        Material(
                          color: _isWomenOnly
                              ? const Color(0xFFFDF2F8)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _isBusy
                                ? null
                                : () {
                                    setState(() {
                                      _isWomenOnly = !_isWomenOnly;
                                    });
                                  },
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 12 : 16,
                                vertical: isCompact ? 10 : 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _isWomenOnly
                                      ? const Color(0xFFF472B6)
                                      : _C.border,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _isWomenOnly
                                        ? const Color(
                                            0xFFEC4899,
                                          ).withValues(alpha: 0.12)
                                        : _C.navy.withValues(alpha: 0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: isCompact ? 38 : 42,
                                    height: isCompact ? 38 : 42,
                                    decoration: BoxDecoration(
                                      color: _isWomenOnly
                                          ? const Color(0xFFFCE7F3)
                                          : const Color(0xFFF1F5F9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.female_rounded,
                                      color: _isWomenOnly
                                          ? const Color(0xFFDB2777)
                                          : _C.hint,
                                      size: isCompact ? 22 : 25,
                                    ),
                                  ),
                                  SizedBox(width: isCompact ? 10 : 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 6,
                                          runSpacing: 3,
                                          children: [
                                            Text(
                                              'Women Only Ride',
                                              style: TextStyle(
                                                fontSize: isCompact ? 14 : 15.5,
                                                fontWeight: FontWeight.bold,
                                                color: _C.navy,
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1.5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFBCFE8),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'EXCLUSIVE',
                                                style: TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF9D174D),
                                                  letterSpacing: 0.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Only verified female passengers can book this ride',
                                          style: TextStyle(
                                            fontSize: isCompact ? 11 : 12,
                                            height: 1.25,
                                            color: _isWomenOnly
                                                ? const Color(0xFFBE185D)
                                                : _C.hint,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Transform.scale(
                                      scale: isCompact ? 0.85 : 0.95,
                                      child: Switch.adaptive(
                                        value: _isWomenOnly,
                                        activeThumbColor: const Color(
                                          0xFFDB2777,
                                        ),
                                        activeTrackColor: const Color(
                                          0xFFFBCFE8,
                                        ),
                                        onChanged: _isBusy
                                            ? null
                                            : (val) {
                                                setState(() {
                                                  _isWomenOnly = val;
                                                });
                                              },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      _GradientButton(
                        label: _isRecurring
                            ? 'Continue to Selfie (${_calculatePreviewDates().length} Rides)'
                            : 'Continue to Selfie',
                        trailingIcon: Icons.arrow_forward_rounded,
                        loading: _isCreatingRide,
                        onPressed: _isBusy ? null : _createRideDraft,
                      ),
                    ],
                  ),
                ),

                const _WaveFooter(),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringScheduleConfig() {
    final previewDates = _calculatePreviewDates();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.chip.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.blue.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_repeat_rounded, color: _C.blue, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Schedule Recurring Ride',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _C.navy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _C.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SERIES',
                  style: TextStyle(
                    color: _C.blue,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Recurrence Type Dropdown
          DropdownButtonFormField<String>(
            value: _recurrenceType == 'does_not_repeat'
                ? 'every_day'
                : _recurrenceType,
            decoration: _decoration(
              label: 'Repeats',
              prefix: const Icon(Icons.repeat_rounded, color: _C.blue),
            ),
            items: const [
              DropdownMenuItem(value: 'every_day', child: Text('Every day')),
              DropdownMenuItem(value: 'every_week', child: Text('Every week')),
              DropdownMenuItem(
                value: 'every_2_weeks',
                child: Text('Every 2 weeks'),
              ),
              DropdownMenuItem(
                value: 'custom',
                child: Text('Custom (Select days)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _recurrenceType = val);
            },
          ),

          // If Custom, Weekdays Multi-Selector
          if (_recurrenceType == 'custom') ...[
            const SizedBox(height: 14),
            const Text(
              'Select Days of the Week',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _C.navy,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: weekdayNames.map((day) {
                final isSelected = _selectedWeekdays.contains(day);
                return FilterChip(
                  label: Text(day),
                  selected: isSelected,
                  selectedColor: _C.blue,
                  backgroundColor: Colors.white,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : _C.navy,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? _C.blue : Colors.grey.shade300,
                    ),
                  ),
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedWeekdays.add(day);
                      } else {
                        if (_selectedWeekdays.length > 1) {
                          _selectedWeekdays.remove(day);
                        }
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 14),

          // Start Date
          _PickerField(
            decoration: _decoration(
              label: 'Start Date',
              prefix: const Icon(Icons.calendar_today_outlined, color: _C.blue),
              suffix: _circleIcon(Icons.calendar_month_outlined),
            ),
            value: _recurringStartDate == null
                ? null
                : _formatDisplayDate(_recurringStartDate!),
            placeholder: 'Select start date',
            onTap: _isBusy ? null : _selectRecurringStartDate,
          ),

          const SizedBox(height: 14),

          // End Condition Selector: Date vs Count
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Until Date'),
                    ),
                  ),
                  selected: _endByDate,
                  selectedColor: _C.blue.withOpacity(0.15),
                  labelStyle: TextStyle(
                    color: _endByDate ? _C.blue : _C.hint,
                    fontWeight: _endByDate ? FontWeight.bold : FontWeight.w500,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _endByDate = true);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Number of Rides'),
                    ),
                  ),
                  selected: !_endByDate,
                  selectedColor: _C.blue.withOpacity(0.15),
                  labelStyle: TextStyle(
                    color: !_endByDate ? _C.blue : _C.hint,
                    fontWeight: !_endByDate ? FontWeight.bold : FontWeight.w500,
                  ),
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _endByDate = false;
                        _recurringOccurrenceCount ??= 10;
                      });
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // End Date Picker OR Count Stepper
          if (_endByDate)
            _PickerField(
              decoration: _decoration(
                label: 'End Date',
                prefix: const Icon(
                  Icons.event_available_outlined,
                  color: _C.blue,
                ),
                suffix: _circleIcon(Icons.calendar_month_outlined),
              ),
              value: _recurringEndDate == null
                  ? null
                  : _formatDisplayDate(_recurringEndDate!),
              placeholder: 'Select end date',
              onTap: _isBusy ? null : _selectRecurringEndDate,
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: const Text(
                        'Total Occurrences:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _C.navy,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: _C.blue,
                        ),
                        onPressed: (_recurringOccurrenceCount ?? 10) > 2
                            ? () => setState(
                                () => _recurringOccurrenceCount =
                                    (_recurringOccurrenceCount ?? 10) - 1,
                              )
                            : null,
                      ),
                      Text(
                        '${_recurringOccurrenceCount ?? 10}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _C.navy,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: _C.blue,
                        ),
                        onPressed: (_recurringOccurrenceCount ?? 10) < 60
                            ? () => setState(
                                () => _recurringOccurrenceCount =
                                    (_recurringOccurrenceCount ?? 10) + 1,
                              )
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // REVIEW RECURRING SCHEDULE BOX
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _C.blue.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: _C.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${previewDates.length} Rides will be created',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _C.navy,
                      ),
                    ),
                  ],
                ),
                if (previewDates.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Dates: ' +
                        previewDates
                            .take(5)
                            .map((d) => '${d.day} ${months[d.month - 1]}')
                            .join(', ') +
                        (previewDates.length > 5
                            ? ' (+${previewDates.length - 5} more)'
                            : ''),
                    style: const TextStyle(fontSize: 12, color: _C.hint),
                  ),
                ],
                const SizedBox(height: 4),
                const Text(
                  'A single selfie will publish all rides for these dates.',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: _C.blue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 2 UI
  // ---------------------------------------------------------------------------

  Widget _buildSelfieStep(double topInset) {
    final isProcessing = _isUploadingSelfie || _isPublishing;
    final hasLocalSelfie = _selfie != null;
    final hasRemoteSelfie =
        _remoteSelfieUrl != null && _remoteSelfieUrl!.isNotEmpty;
    final hasAnySelfie = hasLocalSelfie || hasRemoteSelfie;

    final publishLabel = _isUploadingSelfie
        ? 'Uploading selfie...'
        : _isPublishing
        ? (_isRecurring
              ? 'Publishing all $_generatedRideCount rides...'
              : 'Publishing your ride...')
        : (_isRecurring
              ? 'Upload & Publish Series ($_generatedRideCount Rides)'
              : 'Upload & Publish Ride');

    return SingleChildScrollView(
      key: const ValueKey('step-selfie'),
      child: Stack(
        children: [
          // Soft decorative bubbles
          Positioned(
            top: 10,
            right: -70,
            child: _bubble(200, _C.blueLight.withValues(alpha: 0.08)),
          ),
          Positioned(
            top: 80,
            right: -45,
            child: _bubble(110, _C.green.withValues(alpha: 0.13)),
          ),
          Positioned(
            top: 190,
            left: -50,
            child: _bubble(110, _C.blueLight.withValues(alpha: 0.07)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: topInset + 4),
              Align(
                alignment: Alignment.centerLeft,
                child: _buildProgressIndicator(),
              ),
              const SizedBox(height: 22),
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [_C.blueLight, _C.blue],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ).createShader(rect),
                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 88,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const _TitleText(first: 'Verify ', second: 'Yourself'),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _isRecurring
                      ? 'Take a live selfie to publish all $_generatedRideCount scheduled rides.\n'
                            'This single selfie will be used to verify the entire series.'
                      : 'Take a live selfie before publishing your ride.\n'
                            'This selfie will be associated with the ride.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _C.hint,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 22),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSelfiePreview(),
              ),

              const SizedBox(height: 14),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildPriceBreakdownCard(),
              ),

              const SizedBox(height: 14),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _GradientButton(
                  label: hasAnySelfie
                      ? 'Retake Live Selfie'
                      : 'Take Live Selfie',
                  leadingIcon: Icons.photo_camera_rounded,
                  onPressed: isProcessing ? null : _takeSelfie,
                ),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTipsRow(),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: !hasAnySelfie || isProcessing
                    ? Opacity(
                        opacity: 0.5,
                        child: _GradientButton(
                          label: publishLabel,
                          leadingIcon: Icons.file_upload_outlined,
                          loading: isProcessing,
                          onPressed: null,
                        ),
                      )
                    : SwipeToConfirm(
                        text: 'Swipe to Publish Ride',
                        isLoading: isProcessing,
                        onConfirm: _uploadSelfieAndPublish,
                      ),
              ),

              const SizedBox(height: 12),

              Center(
                child: TextButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () {
                          setState(() {
                            _currentStep = 0;
                          });
                        },
                  icon: const Icon(
                    Icons.edit_note_rounded,
                    size: 20,
                    color: _C.blue,
                  ),
                  label: const Text(
                    'Review or Edit Ride Details',
                    style: TextStyle(
                      color: _C.blue,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Your ride becomes visible to passengers only after the '
                  'selfie is uploaded and the ride is published.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _C.hint, fontSize: 12.5, height: 1.4),
                ),
              ),

              const _WaveFooter(),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bubble(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildSelfiePreview() {
    final hasLocalSelfie = _selfie != null && _selfieBytes != null;
    final hasRemoteSelfie =
        _remoteSelfieUrl != null && _remoteSelfieUrl!.isNotEmpty;
    final hasSelfie = hasLocalSelfie || hasRemoteSelfie;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE6ECF7)),
        boxShadow: [
          BoxShadow(
            color: _C.blue.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SizedBox(
        height: 260,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: hasLocalSelfie
                  ? Image.memory(_selfieBytes!, fit: BoxFit.cover)
                  : (hasRemoteSelfie
                        ? Image.network(
                            _resolveUrl(_remoteSelfieUrl!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFFF0F3F9),
                              child: const Center(
                                child: Text(
                                  'Failed to load uploaded selfie',
                                  style: TextStyle(color: _C.hint),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: const Color(0xFFF0F3F9),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _FaceFrame(),
                                SizedBox(height: 14),
                                Text(
                                  'No selfie captured',
                                  style: TextStyle(
                                    color: _C.navy,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Use the front camera',
                                  style: TextStyle(
                                    color: _C.hint,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _DashedRRectPainter(
                  color: hasSelfie ? _C.green : const Color(0xFFC3CCDD),
                  radius: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceBreakdownCard() {
    final userPrice =
        _userAmount ?? double.tryParse(_priceController.text.trim()) ?? 0.0;
    final appPay = _appAmount ?? 0.0;
    final totalPrice = _totalAmount ?? (userPrice + appPay);

    String fmt(double val) => val == val.roundToDouble()
        ? '₹${val.toInt()}'
        : '₹${val.toStringAsFixed(2)}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE6F5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1B4D).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _C.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 18,
                  color: _C.blue,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Price Breakdown',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _C.navy,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _C.chip,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Per Seat',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _C.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your ride price',
                style: TextStyle(
                  fontSize: 14,
                  color: _C.hint,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                fmt(userPrice),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _C.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'AbhiShare Extra Pay',
                    style: TextStyle(
                      fontSize: 14,
                      color: _C.hint,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: const Text(
                      'Platform Fee',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '+${fmt(appPay)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total passenger price',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _C.navy,
                ),
              ),
              Text(
                fmt(totalPrice),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _C.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTipsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FD),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _TipItem(
                icon: Icons.verified_user_outlined,
                color: _C.blue,
                background: Color(0xFFCFE2FB),
                text: 'Clear face\nvisible',
              ),
            ),
            VerticalDivider(width: 1, color: Color(0xFFD2DDF0)),
            Expanded(
              child: _TipItem(
                icon: Icons.wb_sunny_outlined,
                color: _C.green,
                background: Color(0xFFD3F0E6),
                text: 'Good\nlighting',
              ),
            ),
            VerticalDivider(width: 1, color: Color(0xFFD2DDF0)),
            Expanded(
              child: _TipItem(
                icon: Icons.masks,
                color: _C.red,
                background: Color(0xFFF8D9DB),
                text: 'No mask\nor sunglasses',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftResumeBanner(double horizontalMargin) {
    if (_detectedDraftRide == null) return const SizedBox.shrink();

    final fromLoc =
        _detectedDraftRide!['from_location']?.toString() ?? 'Origin';
    final toLoc =
        _detectedDraftRide!['to_location']?.toString() ?? 'Destination';

    return Container(
      margin: EdgeInsets.only(
        left: horizontalMargin,
        right: horizontalMargin,
        bottom: 16,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.blue.withOpacity(0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _C.blue.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _C.blue.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit_road_rounded,
                  color: _C.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Unfinished Ride Draft',
                  style: TextStyle(
                    color: _C.navy,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: _C.hint),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _detectedDraftRide = null;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$fromLoc  →  $toLoc',
            style: const TextStyle(
              color: _C.navy,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _applyInitialRide(_detectedDraftRide!);
                      _detectedDraftRide = null;
                    });
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Continue Draft'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _detectedDraftRide = null;
                  });
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _C.hint,
                  side: const BorderSide(color: _C.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                child: const Text('Start New'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // NO VEHICLES
  // ---------------------------------------------------------------------------

  Widget _buildNoVehiclesView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.directions_car_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'No vehicles available',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add a vehicle before creating a ride.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              onPressed: () {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(builder: (_) => const VehiclesScreen()),
                    )
                    .then((_) {
                      _loadVehicles();
                    });
              },
              label: const Text('Add Vehicle'),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// REUSABLE WIDGETS
// -----------------------------------------------------------------------------

/// Two-tone heading, e.g. "Ride" (navy) + "Details" (green).
class _TitleText extends StatelessWidget {
  final String first;
  final String second;

  const _TitleText({required this.first, required this.second});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: first,
            style: const TextStyle(color: _C.navy),
          ),
          TextSpan(
            text: second,
            style: const TextStyle(color: _C.green),
          ),
        ],
      ),
      style: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    );
  }
}

/// Tappable read-only field used for date / time pickers.
class _PickerField extends StatelessWidget {
  final InputDecoration decoration;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;

  const _PickerField({
    required this.decoration,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: decoration,
        child: Text(
          value ?? placeholder,
          style: TextStyle(
            fontSize: 16,
            color: value == null ? _C.hint : _C.navy,
          ),
        ),
      ),
    );
  }
}

/// Pill-shaped gradient button used on both steps.
class _GradientButton extends StatelessWidget {
  final String label;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;
  final bool loading;

  const _GradientButton({
    required this.label,
    this.leadingIcon,
    this.trailingIcon,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null || loading;
    final fg = enabled ? Colors.white : const Color(0xFF8A94A8);

    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: _C.blue.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: enabled
                ? const LinearGradient(
                    colors: [Color(0xFF0A55BE), Color(0xFF2F7FE0)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: enabled ? null : const Color(0xFFE3E7F0),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: loading ? null : onPressed,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: trailingIcon != null ? 48 : 20,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (loading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      else if (leadingIcon != null)
                        Icon(leadingIcon, color: fg, size: 24),
                      if (loading || leadingIcon != null)
                        const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: fg,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailingIcon != null && !loading)
                  Positioned(
                    right: 22,
                    child: Icon(trailingIcon, color: fg, size: 26),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Face placeholder with blue scanner corners.
class _FaceFrame extends StatelessWidget {
  const _FaceFrame();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 110,
      child: CustomPaint(
        painter: _CornersPainter(),
        child: Center(
          child: Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFDDE3EF),
            ),
            child: const Icon(
              Icons.person_rounded,
              size: 58,
              color: Color(0xFF9AA8C4),
            ),
          ),
        ),
      ),
    );
  }
}

class _TipItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  const _TipItem({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF4A5670),
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

/// Decorative wave at the bottom of each step.
class _WaveFooter extends StatelessWidget {
  const _WaveFooter();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      width: double.infinity,
      child: CustomPaint(painter: _WavePainter()),
    );
  }
}

// -----------------------------------------------------------------------------
// PAINTERS
// -----------------------------------------------------------------------------

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    final back = Path()
      ..moveTo(0, h * 0.35)
      ..quadraticBezierTo(w * 0.25, h * 0.0, w * 0.55, h * 0.4)
      ..quadraticBezierTo(w * 0.8, h * 0.7, w, h * 0.25)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final front = Path()
      ..moveTo(0, h * 0.7)
      ..quadraticBezierTo(w * 0.3, h * 0.45, w * 0.6, h * 0.75)
      ..quadraticBezierTo(w * 0.85, h * 0.95, w, h * 0.6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      back,
      Paint()
        ..shader = LinearGradient(
          colors: [
            _C.green.withValues(alpha: 0.28),
            _C.blueLight.withValues(alpha: 0.28),
          ],
        ).createShader(rect),
    );

    canvas.drawPath(
      front,
      Paint()
        ..shader = LinearGradient(
          colors: [
            _C.blueLight.withValues(alpha: 0.35),
            _C.green.withValues(alpha: 0.3),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dash;
  final double gap;

  _DashedRRectPainter({
    required this.color,
    required this.radius,
    this.dash = 6,
    this.gap = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.7),
          Radius.circular(radius),
        ),
      );

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

class _CornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _C.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const len = 26.0;
    const r = 10.0;
    final w = size.width;
    final h = size.height;

    // top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, len)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0)
        ..lineTo(len, 0),
      paint,
    );
    // top-right
    canvas.drawPath(
      Path()
        ..moveTo(w - len, 0)
        ..lineTo(w - r, 0)
        ..quadraticBezierTo(w, 0, w, r)
        ..lineTo(w, len),
      paint,
    );
    // bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(0, h - len)
        ..lineTo(0, h - r)
        ..quadraticBezierTo(0, h, r, h)
        ..lineTo(len, h),
      paint,
    );
    // bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(w - len, h)
        ..lineTo(w - r, h)
        ..quadraticBezierTo(w, h, w, h - r)
        ..lineTo(w, h - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
