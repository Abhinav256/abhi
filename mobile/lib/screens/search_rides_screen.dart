import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/location_result.dart';
import '../services/api_service.dart';
import '../widgets/location_search_bottom_sheet.dart';
import 'ride_details_screen.dart';

// ---------------------------------------------------------------------------
// Design tokens (taken from the reference UI)
// ---------------------------------------------------------------------------
const Color _kPrimary = Color(0xFF0A66E0);
const Color _kNavy = Color(0xFF0B1F5C);
const Color _kTeal = Color(0xFF12A4B4);
const Color _kBackground = Color(0xFFF6F8FC);
const Color _kBorder = Color(0xFFDDE3EE);
const Color _kMuted = Color(0xFF6B7280);
const Color _kSoftBlue = Color(0xFFE3EEFF);
const Color _kGreen = Color(0xFF10B981);
const Color _kRed = Color(0xFFF43F5E);

const List<String> _kFilters = [
  'All',
  'Cheapest',
  'Fastest',
  'Women Only',
  '2 Seater',
  '5 Seater',
  '7 Seater',
];

class SearchRidesScreen extends StatefulWidget {
  const SearchRidesScreen({super.key});

  @override
  State<SearchRidesScreen> createState() => _SearchRidesScreenState();
}

class _SearchRidesScreenState extends State<SearchRidesScreen> {
  final ApiService _apiService = ApiService();

  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();

  LocationResult? _pickupLocation;
  LocationResult? _dropLocation;

  double _swapRotationTurns = 0.0;

  DateTime? _journeyDate;

  bool _isSearching = false;
  bool _hasSearched = false;

  List<dynamic> _rides = [];

  String? _selectedSort;
  final Set<String> _selectedFilters = <String>{};

  @override
  void initState() {
    super.initState();
    // Default to today's date, taken from the device clock.
    _journeyDate = _dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Date helpers
  // -------------------------------------------------------------------------

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime get _today => _dateOnly(DateTime.now());

  DateTime get _tomorrow {
    final t = _today;
    return DateTime(t.year, t.month, t.day + 1);
  }

  bool get _isToday => _isSameDay(_journeyDate, _today);

  bool get _isTomorrow => _isSameDay(_journeyDate, _tomorrow);

  Future<void> _selectDate() async {
    final today = _today;

    var initial = _journeyDate ?? today;
    if (initial.isBefore(today)) initial = today;

    final selectedDate = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
      initialDate: initial,
    );

    if (selectedDate == null) {
      return;
    }

    setState(() {
      _journeyDate = _dateOnly(selectedDate);
    });
  }

  void _pickToday() {
    setState(() {
      _journeyDate = _today;
    });
  }

  void _pickTomorrow() {
    setState(() {
      _journeyDate = _tomorrow;
    });
  }

  /// Format sent to the API (unchanged): yyyy-MM-dd
  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return '$year-$month-$day';
  }

  /// Format shown in the date input: 29/09/2026
  String _formatDisplayDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  /// Format shown on ride cards: Today, 29 Sep / Tomorrow, 30 Sep / 01 Oct
  String _formatCardDate(String raw) {
    if (raw.length < 10) return raw;
    final parsed = DateTime.tryParse(raw.substring(0, 10));
    if (parsed == null) return raw.substring(0, 10);

    final d = parsed.day.toString().padLeft(2, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    final short = '$d/$m/${parsed.year}';

    if (_isSameDay(parsed, _today)) return 'Today, $short';
    if (_isSameDay(parsed, _tomorrow)) return 'Tomorrow, $short';
    return short;
  }

  String _monthName(DateTime d) {
    const months = [
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
    return months[d.month - 1];
  }

  String _weekdayName(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[d.weekday - 1];
  }

  // -------------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------------

  Future<void> _searchRides() async {
    FocusScope.of(context).unfocus();

    final from = _fromController.text.trim();
    final to = _toController.text.trim();

    if (from.isEmpty) {
      _showMessage('Please enter the starting location.');
      return;
    }

    if (to.isEmpty) {
      _showMessage('Please enter the destination.');
      return;
    }

    if (_journeyDate == null) {
      _showMessage('Please select the journey date.');
      return;
    }

    setState(() {
      _isSearching = true;
      _rides = [];
      _hasSearched = false;
    });

    try {
      final rides = await _apiService.searchRides(
        fromLocation: from,
        toLocation: to,
        journeyDate: _formatDate(_journeyDate!),
        fromLat: _pickupLocation?.latitude,
        fromLon: _pickupLocation?.longitude,
        toLat: _dropLocation?.latitude,
        toLon: _dropLocation?.longitude,
      );

      if (!mounted) return;

      setState(() {
        _rides = rides;
        _isSearching = false;
        _hasSearched = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSearching = false;
        _hasSearched = true;
      });

      _showMessage('Failed to search rides: $e');
    }
  }

  void _showMessage(String message) {
    // ScaffoldMessenger.of(
    //   context,
    // ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _swapLocations() {
    if (_isSearching) return;
    HapticFeedback.lightImpact();
    setState(() {
      _swapRotationTurns += 0.5;
      final temp = _fromController.text;
      _fromController.text = _toController.text;
      _toController.text = temp;

      final tempLoc = _pickupLocation;
      _pickupLocation = _dropLocation;
      _dropLocation = tempLoc;

      _fromController.selection = TextSelection.collapsed(
        offset: _fromController.text.length,
      );
      _toController.selection = TextSelection.collapsed(
        offset: _toController.text.length,
      );
    });
  }

  Future<void> _pickLocation({required bool isPickup}) async {
    if (_isSearching) return;
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
          _dropLocation = result;
          _toController.text = result.displayName;
        }
      });
    }
  }

  void _openRideDetails(Map<String, dynamic> ride) {
    final rideId = ride['id']?.toString();

    if (rideId == null || rideId.isEmpty) {
      _showMessage('Ride ID not found.');
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                RideDetailsScreen(rideId: rideId, initialRideData: ride),
          ),
        )
        .then((_) {
          // Refresh search after returning (seats may have changed).
          if (_hasSearched) {
            _searchRides();
          }
        });
  }

  // -------------------------------------------------------------------------
  // Time helpers
  // -------------------------------------------------------------------------

  String _formatTimeDisplay(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    if (raw.contains('T')) {
      final parts = raw.split('T');
      if (parts.length == 2 && parts[1].length >= 5) {
        return parts[1].substring(0, 5);
      }
    }
    if (raw.length >= 5) return raw.substring(0, 5);
    return raw;
  }

  /// Converts a raw time value into minutes since midnight, or null.
  int? _timeToMinutes(String? raw) {
    final hhmm = _formatTimeDisplay(raw);
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// 24h "HH:mm" -> "8:30 AM"
  String _formatTime12h(String? raw) {
    final minutes = _timeToMinutes(raw);
    if (minutes == null) return _formatTimeDisplay(raw);
    final h24 = minutes ~/ 60;
    final m = minutes % 60;
    final suffix = h24 >= 12 ? 'PM' : 'AM';
    var h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    return '$h12:${m.toString().padLeft(2, '0')} $suffix';
  }

  int _durationMinutes(Map<String, dynamic> ride) {
    final dep = _timeToMinutes(ride['departure_time']?.toString());
    final arr = _timeToMinutes(ride['estimated_arrival_time']?.toString());
    if (dep == null || arr == null) return 1 << 30;
    var diff = arr - dep;
    if (diff < 0) diff += 24 * 60;
    return diff;
  }

  // -------------------------------------------------------------------------
  // Ride data helpers (all values come from the API response)
  // -------------------------------------------------------------------------

  /// Looks for the first non-empty value among [keys], checking the ride
  /// itself and the nested `driver` / `vehicle` objects if present.
  String? _field(Map<String, dynamic> ride, List<String> keys) {
    final sources = <Map>[ride];
    final driver = ride['driver'];
    final vehicle = ride['vehicle'];
    if (driver is Map) sources.add(driver);
    if (vehicle is Map) sources.add(vehicle);

    for (final source in sources) {
      for (final key in keys) {
        final value = source[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty && text != 'null') return text;
      }
    }
    return null;
  }

  String? _driverName(Map<String, dynamic> ride) =>
      _field(ride, ['driver_name', 'driver_full_name', 'full_name', 'name']);

  String? _vehicleName(Map<String, dynamic> ride) => _field(ride, [
    'vehicle_model',
    'vehicle_name',
    'car_model',
    'car_name',
    'model',
  ]);

  int? _vehicleSeats(Map<String, dynamic> ride) {
    final type = _field(ride, ['vehicle_type', 'type'])?.toLowerCase();
    if (type != null) {
      if (type == 'two_wheeler' || type.contains('2') || type.contains('two'))
        return 2;
      if (type == 'five_seater' || type.contains('5') || type.contains('five'))
        return 5;
      if (type == 'seven_seater' ||
          type.contains('7') ||
          type.contains('seven'))
        return 7;
    }
    final raw = _field(ride, [
      'vehicle_seats',
      'vehicle_capacity',
      'total_seats',
      'seater',
      'seats',
    ]);
    if (raw != null) {
      final parsed = int.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return null;
  }

  String? _driverRating(Map<String, dynamic> ride) {
    final raw = _field(ride, ['driver_rating', 'average_rating', 'rating']);
    if (raw == null) return null;
    final value = double.tryParse(raw);
    if (value == null) return raw;
    return value.toStringAsFixed(1);
  }

  String? _driverPhoto(Map<String, dynamic> ride) => _field(ride, [
    'driver_photo',
    'driver_photo_url',
    'driver_image',
    'profile_photo',
    'profile_image',
    'avatar_url',
    'photo_url',
  ]);

  bool _isFemaleDriver(Map<String, dynamic> ride) {
    final flag = ride['female_only'] ?? ride['ladies_only'];
    if (flag == true || flag?.toString() == '1') return true;

    final gender = _field(ride, ['driver_gender', 'gender']);
    if (gender == null) return false;
    final g = gender.toLowerCase();
    return g == 'female' || g == 'f' || g == 'woman';
  }

  // -------------------------------------------------------------------------
  // Filtering / sorting
  // -------------------------------------------------------------------------

  List<Map<String, dynamic>> get _visibleRides {
    var list = _rides
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();

    // 1. Filter by Women Only
    if (_selectedFilters.contains('Women Only') ||
        _selectedFilters.contains('Female Only')) {
      list = list
          .where((r) => r['is_women_only'] == true || _isFemaleDriver(r))
          .toList();
    }

    // 2. Filter by vehicle seating capacity
    final capacityFilters = <int>{};
    if (_selectedFilters.contains('2 Seater')) capacityFilters.add(2);
    if (_selectedFilters.contains('5 Seater')) capacityFilters.add(5);
    if (_selectedFilters.contains('7 Seater')) capacityFilters.add(7);

    if (capacityFilters.isNotEmpty) {
      list = list.where((r) {
        final seats = _vehicleSeats(r);
        return seats != null && capacityFilters.contains(seats);
      }).toList();
    }

    // 3. Sorting (based on total_amount passenger price)
    double price(Map<String, dynamic> r) {
      final total = double.tryParse(r['total_amount']?.toString() ?? '');
      if (total != null && total > 0) return total;
      return double.tryParse(r['price_per_seat']?.toString() ?? '') ??
          double.infinity;
    }

    int departure(Map<String, dynamic> r) =>
        _timeToMinutes(r['departure_time']?.toString()) ?? (1 << 30);

    if (_selectedSort == 'Cheapest') {
      list.sort((a, b) => price(a).compareTo(price(b)));
    } else if (_selectedSort == 'Fastest') {
      list.sort((a, b) => _durationMinutes(a).compareTo(_durationMinutes(b)));
    } else {
      // Default: sorted by upcoming departure time
      list.sort((a, b) => departure(a).compareTo(departure(b)));
    }

    return list;
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final visibleRides = _visibleRides;

    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _kNavy,
        centerTitle: false,
        title: const Text(
          'Search Rides',
          style: TextStyle(
            color: _kNavy,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SizedBox(height: 4),

            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: _kNavy,
                ),
                children: [
                  TextSpan(text: 'Find a '),
                  TextSpan(
                    text: 'Ride',
                    style: TextStyle(color: _kTeal),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            const Text(
              'Travel together, save together.',
              style: TextStyle(color: _kMuted, fontSize: 16),
            ),

            const SizedBox(height: 16),

            _buildSearchCard(),

            const SizedBox(height: 16),

            _buildFilterChips(),

            const SizedBox(height: 16),

            if (_isSearching)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),

            if (!_isSearching && !_hasSearched)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Enter your journey details and search for rides.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _kMuted),
                  ),
                ),
              ),

            if (_hasSearched) _buildResultsHeader(visibleRides.length),

            if (_hasSearched && visibleRides.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'No rides found for this route and date.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

            ...visibleRides.map(_buildRideCard),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Search card (From / To / Journey date / Search button)
  // -------------------------------------------------------------------------

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5EAF3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _kNavy.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildLocationFields(),
          const SizedBox(height: 14),
          _buildJourneyDate(),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [Color(0xFF0066FF), Color(0xFF0052D4)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0066FF).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: _isSearching ? null : _searchRides,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Row(
                    children: [
                      const SizedBox(width: 42),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isSearching)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            else ...[
                              const Icon(
                                Icons.search_rounded,
                                size: 24,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Search Rides',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF0066FF),
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwapButton() {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: 'Swap pickup and drop locations',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _isSearching ? null : _swapLocations,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF2F6FE),
              boxShadow: [
                BoxShadow(
                  color: _kPrimary.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: AnimatedRotation(
              turns: _swapRotationTurns,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: const Center(
                child: Icon(
                  Icons.swap_vert_rounded,
                  color: _kPrimary,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationFields() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAF3), width: 1.2),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLocationRow(
                    label: 'From',
                    hint: 'Enter pickup location',
                    controller: _fromController,
                    icon: Icons.location_on,
                    iconColor: const Color(0xFF00B074),
                    badgeColor: const Color(0xFFE2F7ED),
                  ),
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: const Color(0xFFE8EEF7),
                  ),
                  _buildLocationRow(
                    label: 'To',
                    hint: 'Enter drop location',
                    controller: _toController,
                    icon: Icons.location_on,
                    iconColor: const Color(0xFFF43F5E),
                    badgeColor: const Color(0xFFFFEAED),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(vertical: 12),
              color: const Color(0xFFE8EEF7),
            ),
            Container(
              width: 64,
              alignment: Alignment.center,
              child: _buildSwapButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    required Color iconColor,
    required Color badgeColor,
  }) {
    final isPickup = label == 'From';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSearching ? null : () => _pickLocation(isPickup: isPickup),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
                child: Center(child: Icon(icon, color: iconColor, size: 24)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        color: _kPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    TextField(
                      controller: controller,
                      readOnly: true,
                      onTap: _isSearching
                          ? null
                          : () => _pickLocation(isPickup: isPickup),
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: _kNavy,
                        height: 1.25,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: hint,
                        hintStyle: const TextStyle(
                          color: _kMuted,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w400,
                          height: 1.25,
                        ),
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJourneyDate() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final date = _journeyDate ?? _today;
        final hasDate = _journeyDate != null;
        final isCustom = hasDate && !_isToday && !_isTomorrow;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE5EAF3), width: 1.2),
              ),
              child: Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _selectDate,
                      child: Container(
                        width: 42,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEBF3FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.calendar_month_outlined,
                            color: _kPrimary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 7,
                    child: _DateChoiceButton(
                      label: hasDate ? _formatDisplayDate(date) : 'Select Date',
                      subtitle:
                          '${_weekdayName(date)}, ${date.day} ${_monthName(date)}',
                      selected: isCustom,
                      onTap: _selectDate,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 6,
                    child: _DateChoiceButton(
                      label: 'Today',
                      subtitle: '${_today.day} ${_monthName(_today)}',
                      selected: _isToday,
                      onTap: _pickToday,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 7,
                    child: _DateChoiceButton(
                      label: 'Tomorrow',
                      subtitle: '${_tomorrow.day} ${_monthName(_tomorrow)}',
                      selected: _isTomorrow,
                      onTap: _pickTomorrow,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 56,
              top: 0,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: const Text(
                  'Journey Date',
                  style: TextStyle(
                    color: _kPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  // -------------------------------------------------------------------------
  // Filter chips
  // -------------------------------------------------------------------------

  bool _isChipSelected(String chip) {
    if (chip == 'All') {
      return _selectedSort == null && _selectedFilters.isEmpty;
    }
    if (chip == 'Cheapest' || chip == 'Fastest') {
      return _selectedSort == chip;
    }
    return _selectedFilters.contains(chip);
  }

  void _handleChipTap(String chip) {
    setState(() {
      if (chip == 'All') {
        _selectedSort = null;
        _selectedFilters.clear();
      } else if (chip == 'Cheapest' || chip == 'Fastest') {
        if (_selectedSort == chip) {
          _selectedSort = null;
        } else {
          _selectedSort = chip;
        }
      } else {
        if (_selectedFilters.contains(chip)) {
          _selectedFilters.remove(chip);
        } else {
          _selectedFilters.add(chip);
        }
      }
    });
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            const Icon(Icons.filter_alt_outlined, color: _kPrimary, size: 26),
            const SizedBox(width: 12),
            for (final filter in _kFilters) ...[
              _FilterChipButton(
                label: filter,
                selected: _isChipSelected(filter),
                onTap: () => _handleChipTap(filter),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultsHeader(int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Text(
        '$count ${count == 1 ? 'ride' : 'rides'} found',
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: _kNavy,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Ride card
  // -------------------------------------------------------------------------

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final from = ride['from_location']?.toString() ?? '-';
    final to = ride['to_location']?.toString() ?? '-';
    final date = ride['journey_date']?.toString() ?? '-';
    final departure = _formatTime12h(ride['departure_time']?.toString());
    final totalAmount = double.tryParse(ride['total_amount']?.toString() ?? '');
    final pricePerSeat = double.tryParse(
      ride['price_per_seat']?.toString() ?? '',
    );
    final double? effectivePrice = (totalAmount != null && totalAmount > 0)
        ? totalAmount
        : pricePerSeat;
    final price = effectivePrice != null
        ? (effectivePrice == effectivePrice.roundToDouble()
              ? effectivePrice.toInt().toString()
              : effectivePrice.toStringAsFixed(2))
        : (ride['price_per_seat']?.toString() ?? '-');

    final bool isRouteMatched = ride['is_route_matched'] == true;
    final String? passengerPickup = ride['passenger_pickup_name']?.toString();
    final String? passengerDrop = ride['passenger_drop_name']?.toString();
    final double? segDistance = double.tryParse(
      ride['segment_distance_km']?.toString() ?? '',
    );
    final double? segPrice = double.tryParse(
      ride['segment_price_per_seat']?.toString() ?? '',
    );
    final String displayPrice = (isRouteMatched && segPrice != null)
        ? (segPrice == segPrice.roundToDouble()
              ? segPrice.toInt().toString()
              : segPrice.toStringAsFixed(0))
        : price;

    final seatsRaw = (isRouteMatched && ride['available_segment_seats'] != null)
        ? ride['available_segment_seats']?.toString() ?? '-'
        : ride['available_seats']?.toString() ?? '-';
    final seatsInt = int.tryParse(seatsRaw);
    final seatsLabel = seatsInt == null
        ? '$seatsRaw seats left'
        : '$seatsInt ${seatsInt == 1 ? 'seat' : 'seats'} left';

    final driverName = _driverName(ride);
    final vehicleName = _vehicleName(ride);
    final vehicleSeats = _vehicleSeats(ride);
    final rating = _driverRating(ride);

    final vehicleParts = <String>[
      if (vehicleName != null) vehicleName,
      if (vehicleSeats != null) '$vehicleSeats-Seater',
    ];
    final vehicleLine = vehicleParts.join(' · ');

    final displayFrom =
        (isRouteMatched &&
            passengerPickup != null &&
            passengerPickup.isNotEmpty)
        ? passengerPickup
        : from;
    final displayTo =
        (isRouteMatched && passengerDrop != null && passengerDrop.isNotEmpty)
        ? passengerDrop
        : to;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kNavy.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openRideDetails(ride),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DriverAvatar(
                      photoUrl: _driverPhoto(ride),
                      name: driverName,
                      rating: rating,
                      isFemale: _isFemaleDriver(ride),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  driverName ?? '$displayFrom → $displayTo',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: _kNavy,
                                  ),
                                ),
                              ),
                              if (ride['is_women_only'] == true) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFDF2F8),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(
                                        0xFFF472B6,
                                      ).withOpacity(0.5),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.female_rounded,
                                        size: 13,
                                        color: Color(0xFFDB2777),
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'Women Only',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFDB2777),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (isRouteMatched) ...[
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF93C5FD),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.alt_route_rounded,
                                    size: 13,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Matched Route${segDistance != null ? ' · ${segDistance.toStringAsFixed(1)} km' : ''}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (vehicleLine.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              vehicleLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: _kMuted,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          _RouteStop(color: _kGreen, label: displayFrom),
                          const _RouteConnector(),
                          _RouteStop(color: _kRed, label: displayTo),
                          if (isRouteMatched &&
                              (displayFrom != from || displayTo != to)) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Driver\'s route: $from → $to',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: _kMuted,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _MetaItem(
                                icon: Icons.calendar_today_outlined,
                                label: _formatCardDate(date),
                              ),
                              _MetaItem(
                                icon: Icons.access_time,
                                label: departure,
                              ),
                              _MetaItem(
                                icon: Icons.people_outline,
                                label: seatsLabel,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '₹$displayPrice',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: _kPrimary,
                                ),
                              ),
                              const TextSpan(
                                text: ' /seat',
                                style: TextStyle(fontSize: 14, color: _kMuted),
                              ),
                            ],
                          ),
                        ),
                        if (isRouteMatched &&
                            segPrice != null &&
                            effectivePrice != null &&
                            effectivePrice != segPrice) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Full: ₹$price',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _kMuted,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: _kSoftBlue,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _openRideDetails(ride),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'View Details',
                                  style: TextStyle(
                                    color: _kPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  color: _kPrimary,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable widgets
// ---------------------------------------------------------------------------

class _DateChoiceButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _DateChoiceButton({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : _kNavy;
    final subFg = selected ? Colors.white.withValues(alpha: 0.85) : _kMuted;

    return Material(
      color: selected ? _kPrimary : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? _kPrimary : const Color(0xFFE2E8F4),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 15, color: fg),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: fg,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: subFg,
                          fontWeight: FontWeight.w400,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kPrimary : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? _kPrimary : _kBorder,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 42,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : _kNavy,
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  final String? photoUrl;
  final String? name;
  final String? rating;
  final bool isFemale;

  const _DriverAvatar({
    required this.photoUrl,
    required this.name,
    required this.rating,
    required this.isFemale,
  });

  String get _initial {
    final n = name?.trim();
    if (n == null || n.isEmpty) return '';
    return n.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    const double size = 60;

    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _kSoftBlue,
        shape: BoxShape.circle,
      ),
      child: _initial.isEmpty
          ? const Icon(Icons.person, color: _kPrimary, size: 30)
          : Text(
              _initial,
              style: const TextStyle(
                color: _kPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
    );

    final hasPhoto = photoUrl != null && photoUrl!.startsWith('http');

    return SizedBox(
      width: size,
      height: rating != null ? size + 14 : size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: ClipOval(
              child: hasPhoto
                  ? Image.network(
                      photoUrl!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => placeholder,
                    )
                  : placeholder,
            ),
          ),
          if (isFemale)
            Positioned(
              right: -2,
              top: size - 26,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFFEC4899),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.female, color: Colors.white, size: 15),
              ),
            ),
          if (rating != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3D6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF5A623),
                        size: 15,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        rating!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _kNavy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteStop extends StatelessWidget {
  final Color color;
  final String label;

  const _RouteStop({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, color: _kNavy),
          ),
        ),
      ],
    );
  }
}

class _RouteConnector extends StatelessWidget {
  const _RouteConnector();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: SizedBox(
        width: 2,
        height: 10,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(
            2,
            (_) => Container(width: 2, height: 2, color: _kMuted),
          ),
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _kMuted),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 13, color: _kMuted)),
      ],
    );
  }
}
