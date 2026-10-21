import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/notification_state.dart';
import 'create_ride_screen.dart';
import 'ride_details_screen.dart';
import 'chat_screen.dart';
import 'recurring_schedules_screen.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/report_block_dialog.dart';

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
const Color _kSelectedPill = Color(0xFFD3E4FF);
const Color _kGreen = Color(0xFF10B981);
const Color _kRed = Color(0xFFF43F5E);
const Color _kCancelRed = Color(0xFFE5192C);
const Color _kCancelBg = Color(0xFFFDE9EC);

const List<String> _kStatusFilters = ['Upcoming', 'Completed', 'Cancelled'];

const List<String> _kMonths = [
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

const List<String> _kWeekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final NotificationState _notifState = NotificationState.instance;

  late TabController _tabController;

  // Tab 0 (As Passenger): my bookings
  List<Map<String, dynamic>> _myBookings = [];
  bool _isLoadingBookings = true;

  // Tab 1 (As Driver): my rides
  List<Map<String, dynamic>> _myRides = [];
  bool _isLoadingRides = true;

  String _statusFilter = 'Upcoming';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadMyRides();
    _loadMyBookings();
    _notifState.refresh();
    _notifState.addListener(_onNotifChanged);
  }

  @override
  void dispose() {
    _notifState.removeListener(_onNotifChanged);
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  void _onNotifChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh data when the app resumes from background.
    if (state == AppLifecycleState.resumed) {
      _loadMyRides();
      _loadMyBookings();
    }
  }

  // ------------------------------------------------------------------
  // AS DRIVER: MY RIDES
  // ------------------------------------------------------------------

  Future<void> _loadMyRides() async {
    setState(() {
      _isLoadingRides = true;
    });

    try {
      final rides = await _apiService.getMyRides();

      if (!mounted) return;

      setState(() {
        _myRides = rides;
        _isLoadingRides = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingRides = false;
      });

      _showMessage('Failed to load rides: $e');
    }
  }

  Future<void> _cancelRide(String rideId) async {
    final confirmed = await _showConfirmDialog(
      'Cancel Ride?',
      'Are you sure you want to cancel this ride? All bookings will be affected.',
    );

    if (confirmed != true) return;

    try {
      await _apiService.cancelRide(rideId: rideId);

      if (!mounted) return;

      // _showMessage('Ride cancelled.');
      _loadMyRides();
      _notifState.refresh();
    } catch (e) {
      if (!mounted) return;

      _showMessage('Failed to cancel ride: $e');
    }
  }

  Future<void> _deleteDraft(String rideId) async {
    final confirmed = await _showConfirmDialog(
      'Delete Draft?',
      'Are you sure you want to delete this draft ride? This action cannot be undone.',
    );

    if (confirmed != true) return;

    try {
      await _apiService.deleteDraft(rideId);

      if (!mounted) return;

      _showMessage('Draft deleted.');
      _loadMyRides();
    } catch (e) {
      if (!mounted) return;

      _showMessage('Failed to delete draft: $e');
    }
  }

  // ------------------------------------------------------------------
  // AS PASSENGER: MY BOOKINGS
  // ------------------------------------------------------------------

  Future<void> _loadMyBookings() async {
    setState(() {
      _isLoadingBookings = true;
    });

    try {
      final bookings = await _apiService.getMyBookings();

      if (!mounted) return;

      setState(() {
        _myBookings = bookings;
        _isLoadingBookings = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingBookings = false;
      });

      _showMessage('Failed to load bookings: $e');
    }
  }

  Future<void> _cancelBooking(String bookingId) async {
    final confirmed = await _showConfirmDialog(
      'Cancel Booking?',
      'Are you sure you want to cancel this booking?',
    );

    if (confirmed != true) return;

    try {
      await _apiService.cancelBooking(bookingId: bookingId);

      if (!mounted) return;

      _showMessage('Booking cancelled.');
      _loadMyBookings();
      _notifState.refresh();
    } catch (e) {
      if (!mounted) return;

      _showMessage('Failed to cancel booking: $e');
    }
  }

  // ------------------------------------------------------------------
  // HELPERS
  // ------------------------------------------------------------------

  void _showMessage(String message) {
    // if (!mounted) return;
    // ScaffoldMessenger.of(
    //   context,
    // ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _showConfirmDialog(String title, String content) async {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }

  /// "29/09/2026" (falls back to the raw value if it can't be parsed).
  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    if (raw.length < 10) return raw;
    final parsed = DateTime.tryParse(raw.substring(0, 10));
    if (parsed == null) return raw.substring(0, 10);
    final d = parsed.day.toString().padLeft(2, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    return '$d/$m/${parsed.year}';
  }

  String _formatTime24(String? raw) {
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

  /// "HH:mm" -> "8:30 AM"
  String _formatTime(String? raw) {
    final hhmm = _formatTime24(raw);
    final parts = hhmm.split(':');
    if (parts.length < 2) return hhmm;
    final h24 = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h24 == null || m == null) return hhmm;
    final suffix = h24 >= 12 ? 'PM' : 'AM';
    var h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    return '$h12:${m.toString().padLeft(2, '0')} $suffix';
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'draft':
        return 'Draft';
      case 'selfie_uploaded':
        return 'Selfie Uploaded';
      case 'active':
      case 'confirmed':
        return 'Upcoming';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status ?? '-';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'active':
      case 'confirmed':
        return _kPrimary;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'draft':
      case 'selfie_uploaded':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// Which top-level filter a status belongs to.
  String _filterForStatus(String? status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Upcoming';
    }
  }

  List<Map<String, dynamic>> _applyStatusFilter(
    List<Map<String, dynamic>> items,
  ) {
    return items
        .where((i) => _filterForStatus(i['status']?.toString()) == _statusFilter)
        .toList();
  }

  /// Looks for the first non-empty value among [keys], checking the item
  /// itself and nested `driver` / `vehicle` objects if present.
  String? _field(Map<String, dynamic> item, List<String> keys) {
    final sources = <Map>[item];
    final driver = item['driver'];
    final vehicle = item['vehicle'];
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

  String? _driverName(Map<String, dynamic> item) => _field(item, [
        'driver_name',
        'driver_full_name',
        'driver_fullname',
      ]);

  String? _driverId(Map<String, dynamic> item) => _field(item, [
        'driver_id',
        'driverId',
      ]);

  String? _vehicleName(Map<String, dynamic> item) => _field(item, [
        'vehicle_model',
        'vehicle_name',
        'car_model',
        'car_name',
      ]);

  int? _vehicleSeats(Map<String, dynamic> item) {
    final raw = _field(item, [
      'vehicle_seats',
      'vehicle_capacity',
      'total_seats',
      'seater',
    ]);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  String? _driverRating(Map<String, dynamic> item) {
    final raw = _field(item, ['driver_rating', 'average_rating', 'rating']);
    if (raw == null) return null;
    final value = double.tryParse(raw);
    if (value == null) return raw;
    return value.toStringAsFixed(1);
  }

  String? _driverPhoto(Map<String, dynamic> item) => _field(item, [
        'driver_photo',
        'driver_photo_url',
        'driver_image',
        'profile_photo',
        'profile_image',
        'avatar_url',
        'photo_url',
      ]);

  bool _isFemaleDriver(Map<String, dynamic> item) {
    final flag = item['female_only'] ?? item['ladies_only'];
    if (flag == true || flag?.toString() == '1') return true;

    final gender = _field(item, ['driver_gender', 'gender']);
    if (gender == null) return false;
    final g = gender.toLowerCase();
    return g == 'female' || g == 'f' || g == 'woman';
  }

  // ------------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final double w = math.min(media.size.width, 520);
    final double sc = w / 935;
    double f(double px) => px * sc * 1.1;

    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _kNavy,
        toolbarHeight: 48,
        actions: [
          IconButton(
            tooltip: 'Recurring Schedules',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecurringSchedulesScreen()),
              );
            },
            icon: const Icon(Icons.repeat_rounded, color: _kNavy),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              _loadMyRides();
              _loadMyBookings();
            },
            icon: const Icon(Icons.refresh, color: _kNavy),
          ),
        ],
      ),
      body: Center(
        child: SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: _kNavy,
                      ),
                      children: [
                        TextSpan(text: 'My '),
                        TextSpan(
                          text: 'Rides',
                          style: TextStyle(color: _kTeal),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Manage your rides in one place.',
                    style: TextStyle(color: _kMuted, fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  _buildRoleSwitcher(),
                  const SizedBox(height: 18),
                  _buildStatusFilters(),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBookingsTab(),
                  _buildRidesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    _buildBottomNav(sc, f, media.padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Bottom Navigation
  // ------------------------------------------------------------------

  Widget _buildBottomNav(
    double sc,
    double Function(double) f,
    double bottomInset,
  ) {
    return const AppBottomNavBar(currentTab: AppNavTab.rides);
  }

  // ------------------------------------------------------------------
  // Header controls
  // ------------------------------------------------------------------

  Widget _buildRoleSwitcher() {
    final current = _tabController.index;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: _kNavy.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _RoleSegment(
              label: 'As Passenger',
              icon: Icons.person,
              selected: current == 0,
              onTap: () => _tabController.animateTo(0),
            ),
          ),
          Expanded(
            child: _RoleSegment(
              label: 'As Driver',
              icon: Icons.directions_car,
              selected: current == 1,
              onTap: () => _tabController.animateTo(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilters() {
    return Row(
      children: [
        for (var i = 0; i < _kStatusFilters.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _StatusFilterPill(
              label: _kStatusFilters[i],
              selected: _statusFilter == _kStatusFilters[i],
              onTap: () {
                setState(() {
                  _statusFilter = _kStatusFilters[i];
                });
              },
            ),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------
  // TABS
  // ------------------------------------------------------------------

  Widget _buildBookingsTab() {
    if (_isLoadingBookings) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = _applyStatusFilter(_myBookings);

    return _buildList(
      items: items,
      onRefresh: _loadMyBookings,
      emptyIcon: Icons.confirmation_num_outlined,
      emptyText: _myBookings.isEmpty
          ? 'You haven\'t booked any rides yet.'
          : 'No ${_statusFilter.toLowerCase()} bookings.',
      isDriver: false,
    );
  }

  Widget _buildRidesTab() {
    if (_isLoadingRides) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = _applyStatusFilter(_myRides);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecurringSchedulesScreen()),
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE7F6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD1C4E9)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.repeat_rounded, color: Color(0xFF673AB7), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Manage Recurring Schedules',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF512DA8),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF673AB7)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _buildList(
            items: items,
            onRefresh: _loadMyRides,
            emptyIcon: Icons.add_road,
            emptyText: _myRides.isEmpty
                ? 'You haven\'t created any rides yet.'
                : 'No ${_statusFilter.toLowerCase()} rides.',
            isDriver: true,
          ),
        ),
      ],
    );
  }

  Widget _buildList({
    required List<Map<String, dynamic>> items,
    required Future<void> Function() onRefresh,
    required IconData emptyIcon,
    required String emptyText,
    required bool isDriver,
  }) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(emptyIcon, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    emptyText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _kMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return _buildRideCard(items[index], isDriver: isDriver);
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // CARD (shared by "As Driver" rides and "As Passenger" bookings)
  // ------------------------------------------------------------------

  void _openRide(String? rideId, {required bool isDriver}) {
    if (rideId == null || rideId.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RideDetailsScreen(rideId: rideId),
      ),
    ).then((_) => isDriver ? _loadMyRides() : _loadMyBookings());
  }

  Future<void> _showPassengerSafetyOptions({
    required Map<String, dynamic> item,
    required String? rideId,
    required String driverName,
  }) async {
    String? driverId = _driverId(item);
    if ((driverId == null || driverId.isEmpty) && rideId != null && rideId.isNotEmpty) {
      try {
        final details = await _apiService.getRideDetail(rideId: rideId);
        driverId = details['driver_id']?.toString() ?? details['driverId']?.toString();
      } catch (_) {}
    }

    if (!mounted) return;

    if (driverId == null || driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Driver details unavailable for this completed ride.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final targetDriverId = driverId;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined, color: _kNavy, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Safety & Support • $driverName',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kNavy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Reporting or blocking preserves conversation history and ride logs indefinitely for safety review.',
                style: TextStyle(fontSize: 13, color: _kMuted),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.flag_outlined, color: Colors.orange),
                ),
                title: const Text('Report Driver', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Report misconduct, safety concerns, or policy violations'),
                onTap: () {
                  Navigator.pop(ctx);
                  showReportUserDialog(
                    context,
                    targetUserId: targetDriverId,
                    targetUserName: driverName,
                    rideId: rideId,
                  );
                },
              ),
              const Divider(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.block_outlined, color: Colors.red),
                ),
                title: const Text('Block Driver', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
                subtitle: const Text('Block driver from interacting with you or your future rides'),
                onTap: () {
                  Navigator.pop(ctx);
                  showBlockUserConfirmation(
                    context,
                    targetUserId: targetDriverId,
                    targetUserName: driverName,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> item, {required bool isDriver}) {
    final id = item['id']?.toString() ?? '';
    final rideId = isDriver ? id : item['ride_id']?.toString();
    final status = item['status']?.toString() ?? '-';
    final from = item['from_location']?.toString() ?? '-';
    final to = item['to_location']?.toString() ?? '-';
    final date = _formatDate(item['journey_date']?.toString());
    final departure = _formatTime(item['departure_time']?.toString());
    final price = item['price_per_seat']?.toString() ?? '-';

    // Seats: the driver's ride shows seats still available; a booking shows
    // the seats booked when the API provides them.
    final seatsRaw = isDriver
        ? item['available_seats']?.toString()
        : _field(item, ['seats_booked', 'booked_seats', 'seat_count', 'seats']);
    final seatsInt = seatsRaw == null ? null : int.tryParse(seatsRaw);
    final seatsLabel = seatsRaw == null
        ? null
        : '${seatsInt ?? seatsRaw} ${seatsInt == 1 ? 'seat' : 'seats'}';

    final payment = isDriver ? null : item['payment_mode']?.toString();

    final driverName = _driverName(item);
    final vehicleName = _vehicleName(item);
    final vehicleSeats = _vehicleSeats(item);
    final vehicleLine = [
      if (vehicleName != null) vehicleName,
      if (vehicleSeats != null) '$vehicleSeats-Seater',
    ].join(' · ');

    final canCancel = isDriver ? status == 'active' : status == 'confirmed';
    final canDeleteDraft = isDriver && (status == 'draft' || status == 'selfie_uploaded');
    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kNavy.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openRide(rideId, isDriver: isDriver),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DriverAvatar(
                      photoUrl: _driverPhoto(item),
                      name: driverName,
                      rating: _driverRating(item),
                      isFemale: _isFemaleDriver(item),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driverName ??
                                (isDriver ? 'Your ride' : 'Booked ride'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _kNavy,
                            ),
                          ),
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
                          if (item['recurring_schedule_id'] != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDE7F6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.repeat, size: 11, color: Color(0xFF673AB7)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Recurring Ride',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF673AB7)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (item['is_women_only'] == true) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCE4EC),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFF48FB1)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.female, size: 12, color: Color(0xFFD81B60)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Women Only',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFD81B60),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _RouteStop(color: _kGreen, label: from),
                          const _RouteConnector(),
                          _RouteStop(color: _kRed, label: to),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor == _kPrimary
                                ? _kSoftBlue
                                : statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _statusLabel(status),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '₹${(!isDriver && item['total_amount'] != null && double.tryParse(item['total_amount'].toString()) != null && double.parse(item['total_amount'].toString()) > 0) ? (double.parse(item['total_amount'].toString()) % 1 == 0 ? double.parse(item['total_amount'].toString()).toInt().toString() : double.parse(item['total_amount'].toString()).toStringAsFixed(2)) : price}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: _kPrimary,
                          ),
                        ),
                        Text(
                          isDriver
                              ? '/ seat'
                              : (seatsInt != null && seatsInt > 1
                                  ? 'Total ($seatsInt seats)'
                                  : '/ seat'),
                          style: const TextStyle(fontSize: 14, color: _kMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _MetaItem(
                        icon: Icons.calendar_month_outlined,
                        label: date,
                      ),
                      _MetaItem(icon: Icons.access_time, label: departure),
                      if (seatsLabel != null)
                        _MetaItem(
                          icon: Icons.person_outline,
                          label: seatsLabel,
                        ),
                      if (payment != null && payment.isNotEmpty)
                        _MetaItem(
                          icon: Icons.payment,
                          label: payment.toUpperCase(),
                        ),
                    ],
                  ),
                ),
                if (!isDriver && item['passengers'] is List && (item['passengers'] as List).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F6FD),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.people_outline, size: 14, color: _kMuted),
                            const SizedBox(width: 5),
                            Text(
                              'Passengers (${(item['passengers'] as List).length}):',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _kNavy,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            for (final p in (item['passengers'] as List))
                              if (p is Map)
                                Text(
                                  '• ${p['passenger_name'] ?? p['name']} (${p['passenger_age'] ?? p['age']}, ${p['passenger_gender'] ?? p['gender']})',
                                  style: const TextStyle(fontSize: 12, color: _kMuted),
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (canCancel) ...[
                Expanded(
                  child: _CardActionButton(
                    label: isDriver ? 'Cancel Ride' : 'Cancel Booking',
                    icon: Icons.close,
                    background: _kCancelBg,
                    foreground: _kCancelRed,
                    onTap: () =>
                        isDriver ? _cancelRide(id) : _cancelBooking(id),
                  ),
                ),
                const SizedBox(width: 12),
              ] else if (canDeleteDraft) ...[
                Expanded(
                  child: _CardActionButton(
                    label: 'Continue Ride',
                    icon: Icons.arrow_forward_rounded,
                    background: _kPrimary,
                    foreground: Colors.white,
                    onTap: () async {
                      final updated = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => CreateRideScreen(
                            initialRide: item,
                          ),
                        ),
                      );
                      if (updated == true) {
                        _loadMyRides();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _CardActionButton(
                  label: 'Delete',
                  icon: Icons.delete_outline,
                  background: _kCancelBg,
                  foreground: _kCancelRed,
                  onTap: () => _deleteDraft(id),
                ),
                const SizedBox(width: 8),
              ],
              if (!isDriver && status == 'confirmed') ...[
                Expanded(
                  child: _CardActionButton(
                    label: 'Chat',
                    icon: Icons.chat_bubble_outline_rounded,
                    background: const Color(0xFFE8F0FE),
                    foreground: _kPrimary,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(bookingId: id),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (!isDriver && status == 'completed') ...[
                Expanded(
                  child: _CardActionButton(
                    label: 'Report / Block',
                    icon: Icons.shield_outlined,
                    background: const Color(0xFFFEF2F2),
                    foreground: Colors.red.shade700,
                    onTap: () => _showPassengerSafetyOptions(
                      item: item,
                      rideId: rideId,
                      driverName: driverName ?? 'Driver',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _CardActionButton(
                  label: 'View Details',
                  trailingIcon: Icons.chevron_right,
                  background: _kSoftBlue,
                  foreground: _kPrimary,
                  onTap: () => _openRide(rideId, isDriver: isDriver),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable widgets
// ---------------------------------------------------------------------------

class _RoleSegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : _kNavy;

    return Material(
      color: selected ? _kPrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24, color: fg),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusFilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kSelectedPill : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? _kSelectedPill : _kBorder),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? _kPrimary : _kMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _CardActionButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.icon,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: foreground),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 6),
                      Icon(trailingIcon, size: 22, color: foreground),
                    ],
                  ],
                ),
              ),
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
    const double size = 56;

    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _kSoftBlue,
        shape: BoxShape.circle,
      ),
      child: _initial.isEmpty
          ? const Icon(Icons.person, color: _kPrimary, size: 28)
          : Text(
              _initial,
              style: const TextStyle(
                color: _kPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
    );

    final hasPhoto = photoUrl != null && photoUrl!.startsWith('http');

    return SizedBox(
      width: size,
      height: rating != null ? size + 16 : size,
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
              right: -4,
              top: size - 24,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _kRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.female, color: Colors.white, size: 15),
              ),
            ),
          if (rating != null)
            Positioned(
              bottom: 0,
              left: -4,
              right: -4,
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
                        size: 16,
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
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, color: _kNavy),
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
      padding: const EdgeInsets.only(left: 5),
      child: Container(
        width: 1.5,
        height: 12,
        color: _kBorder,
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
        Icon(icon, size: 18, color: _kMuted),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: _kNavy),
        ),
      ],
    );
  }
}

// =========================================================================
// Alerts placeholder (notifications will be built later)
// =========================================================================

class _AlertsPlaceholderScreen extends StatelessWidget {
  const _AlertsPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        title: const Text('Alerts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0B1B3B),
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 64,
              color: Color(0xFF8A94A6),
            ),
            SizedBox(height: 12),
            Text(
              'No alerts yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0B1B3B),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Notifications will appear here.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}