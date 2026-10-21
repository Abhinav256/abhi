import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/notification_state.dart';
import '../services/phone_call_service.dart';
import '../services/security_service.dart';
import '../services/session_service.dart';
import 'book_ride_screen.dart';
import 'chat_screen.dart';
import 'create_ride_screen.dart';
import 'provide_rating_screen.dart';
import '../widgets/report_block_dialog.dart';

// ---------------------------------------------------------------------------
// Design tokens
// ---------------------------------------------------------------------------
const Color _kPrimary = Color(0xFF0D47A1);
const Color _kPrimaryBright = Color(0xFF1565E0);
const Color _kBackground = Color(0xFFEFF5FD);
const Color _kTeal = Color(0xFF1E9E8A);
const Color _kTextDark = Color(0xFF0B1B33);
const Color _kTextMuted = Color(0xFF6B7A90);

/// Responsive scale factor (design is authored for a ~411dp wide phone).
double _scaleOf(BuildContext context) =>
    (MediaQuery.of(context).size.width / 411).clamp(0.82, 1.25).toDouble();

class RideDetailsScreen extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic>? initialRideData;
  final ApiService? apiService;
  final SessionService? sessionService;

  const RideDetailsScreen({
    super.key,
    required this.rideId,
    this.initialRideData,
    this.apiService,
    this.sessionService,
  });

  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen>
    with WidgetsBindingObserver {
  late final ApiService _apiService = widget.apiService ?? ApiService();
  late final SessionService _sessionService =
      widget.sessionService ?? SessionService();

  Map<String, dynamic>? _ride;
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    if (widget.initialRideData != null) {
      _ride = Map<String, dynamic>.from(widget.initialRideData!);
      _isLoading = false;
    }
    WidgetsBinding.instance.addObserver(this);
    _loadRideDetail();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadRideDetail();
    }
  }

  Future<void> _loadRideDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiService.getRideDetail(rideId: widget.rideId);
      final ride = (res['ride'] is Map)
          ? Map<String, dynamic>.from(res['ride'] as Map)
          : res;

      if (widget.initialRideData != null) {
        final init = widget.initialRideData!;
        if (init['is_route_matched'] == true) {
          ride['is_route_matched'] = true;
          ride['segment_distance_km'] = init['segment_distance_km'];
          ride['segment_price_per_seat'] = init['segment_price_per_seat'];
          ride['segment_user_amount'] = init['segment_user_amount'];
          ride['segment_app_amount'] = init['segment_app_amount'];
          ride['segment_total_amount'] = init['segment_total_amount'];
          ride['pickup_distance_along_route'] =
              init['pickup_distance_along_route'];
          ride['drop_distance_along_route'] = init['drop_distance_along_route'];
          ride['available_segment_seats'] = init['available_segment_seats'];
          ride['passenger_pickup_name'] = init['passenger_pickup_name'];
          ride['passenger_drop_name'] = init['passenger_drop_name'];
        }
      }

      final userId = await _sessionService.getUserId();
      final isDriver = userId != null && userId == ride['driver_id'];

      List<Map<String, dynamic>> bookings = [];
      try {
        if (isDriver) {
          bookings = await _apiService.getRideBookings(rideId: widget.rideId);
        } else {
          final myBookings = await _apiService.getMyBookings();
          bookings = myBookings
              .where((b) => b['ride_id']?.toString() == widget.rideId)
              .toList();
        }
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        _ride = ride;
        _bookings = bookings;
        _currentUserId = userId;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    if (raw.length >= 10) {
      final ymd = raw.substring(0, 10);
      final p = ymd.split('-');
      if (p.length == 3) return '${p[2]}/${p[1]}/${p[0]}';
      return ymd;
    }
    return raw;
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    // Backend may return "2000-01-01T14:30:00Z" — extract HH:MM.
    if (raw.contains('T')) {
      final parts = raw.split('T');
      if (parts.length == 2) {
        final timePart = parts[1];
        if (timePart.length >= 5) return timePart.substring(0, 5);
      }
    }
    if (raw.length >= 5) return raw.substring(0, 5);
    return raw;
  }

  String _vehicleTypeLabel(String? type) {
    switch (type) {
      case 'two_wheeler':
        return '2-Seater / Two-Wheeler';
      case 'five_seater':
        return '5-Seater';
      case 'seven_seater':
        return '7-Seater';
      default:
        return type ?? '-';
    }
  }

  void _bookRide() {
    if (_ride == null) return;

    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => BookRideScreen(ride: _ride!)))
        .then((booked) {
          if (booked == true) {
            // Refresh ride details to show updated seat count.
            _loadRideDetail();
            NotificationState.instance.refresh();
          }
        });
  }

  Future<void> _cancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Ride'),
        content: const Text('Are you sure you want to cancel this ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Yes, Cancel',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _apiService.cancelRide(rideId: widget.rideId);
      if (!mounted) return;
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('Ride cancelled successfully.')),
      // );
      _loadRideDetail();
      NotificationState.instance.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to cancel ride: $e')));
    }
  }

  Future<void> _continueRide() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreateRideScreen(initialRide: _ride)),
    );

    if (updated == true) {
      _loadRideDetail();
    }
  }

  Future<void> _deleteDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Draft?'),
        content: const Text(
          'Are you sure you want to delete this draft ride? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Draft'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // try {
    //   await _apiService.deleteDraft(widget.rideId);
    //   if (!mounted) return;
    //   ScaffoldMessenger.of(
    //     context,
    //   ).showSnackBar(const SnackBar(content: Text('Draft ride deleted.')));
    //   Navigator.of(context).pop(true);
    // } catch (e) {
    //   if (!mounted) return;
    //   ScaffoldMessenger.of(
    //     context,
    //   ).showSnackBar(SnackBar(content: Text('Failed to delete draft: $e')));
    // }
  }

  Future<void> _completeRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Ride'),
        content: const Text('Mark this ride as completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Yes, Complete',
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final bookings = _extractBookings();
    final hasBookedPassengers = bookings.any(
      (b) => b['status'] == 'confirmed' || b['status'] == 'completed',
    );

    setState(() => _isLoading = true);
    try {
      await _apiService.completeRide(rideId: widget.rideId);
      if (!mounted) return;
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('Ride completed successfully.')),
      // );

      if (hasBookedPassengers) {
        // Immediately trigger Provide Rating Screen for the driver
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProvideRatingScreen(rideId: widget.rideId),
          ),
        );
      }

      _loadRideDetail();
      NotificationState.instance.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to complete ride: $e')));
    }
  }

  // Same completion-eligibility logic as before, extracted into a helper so
  // it can be shared by the body and the bottom bar.
  bool _computeCanComplete({required bool isDriver, required String status}) {
    bool canComplete = false;
    if (isDriver && status == 'active') {
      final dateStr = _ride!['journey_date'];
      final timeRaw = _ride!['departure_time'];
      if (dateStr != null && timeRaw != null) {
        final d = DateTime.tryParse(
          dateStr.toString().split('T').first.split(' ').first,
        );
        if (d != null) {
          int h = 0, min = 0;
          var t = timeRaw.toString();
          if (t.contains('T')) t = t.split('T')[1];
          final parts = t.split(':');
          if (parts.length >= 2) {
            h = int.tryParse(parts[0]) ?? 0;
            min = int.tryParse(parts[1]) ?? 0;
          }
          final departureDt = DateTime(d.year, d.month, d.day, h, min);
          if (DateTime.now().isAfter(departureDt)) {
            canComplete = true;
          }
        }
      }
    }
    return canComplete;
  }

  String _resolveUrl(String url) =>
      url.startsWith('http') ? url : '${ApiService.baseUrl}$url';

  Future<void> _onCallPressed(String? phone) async {
    final driverName = _ride?['driver_name']?.toString() ?? 'Driver';
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Phone number for $driverName is not available.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final myPhone = await SecurityService().getUserPhone();
    if (mounted) {
      await PhoneCallService.makePhoneCall(
        context: context,
        phoneNumber: phone,
        recipientName: driverName,
        currentUserPhone: myPhone,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final showBottomBar = !_isLoading && _errorMessage == null && _ride != null;
    final s = _scaleOf(context);
    final mq = MediaQuery.of(context);

    // Cap system text scaling so large accessibility fonts can't overflow.
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.15)),
      child: Scaffold(
        backgroundColor: _kBackground,
        appBar: AppBar(
          toolbarHeight: 66 * s,
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleSpacing: 20 * s,
          title: Text(
            'Ride Details',
            style: TextStyle(fontSize: 22 * s, fontWeight: FontWeight.w600),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(32 * s),
            ),
          ),
        ),
        body: _buildBody(s),
        bottomNavigationBar: showBottomBar ? _buildBottomBar(s) : null,
      ),
    );
  }

  Widget _buildBody(double s) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loadRideDetail,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_ride == null) {
      return const Center(child: Text('Ride not found.'));
    }

    final from = _ride!['from_location']?.toString() ?? '-';
    final to = _ride!['to_location']?.toString() ?? '-';
    final date = _formatDate(_ride!['journey_date']?.toString());
    final departure = _formatTime(_ride!['departure_time']?.toString());
    final arrival = _formatTime(_ride!['estimated_arrival_time']?.toString());
    final seats = _ride!['available_seats']?.toString() ?? '0';
    final driverName = _ride!['driver_name']?.toString() ?? '-';
    final driverPhone = (_ride!['driver_phone'] ?? _ride!['driver_mobile'])
        ?.toString();
    final vehicleModel = _ride!['vehicle_model']?.toString() ?? '-';
    final vehicleNumber = _ride!['vehicle_number']?.toString() ?? '-';
    final vehicleType = _vehicleTypeLabel(_ride!['vehicle_type']?.toString());
    final vehiclePhoto = _ride!['vehicle_photo_url']?.toString();
    final selfieUrl = _ride!['driver_selfie_url']?.toString();

    final bookings = _extractBookings();

    return ListView(
      padding: EdgeInsets.fromLTRB(18 * s, 16 * s, 18 * s, 24 * s),
      children: [
        if (_ride!['is_women_only'] == true) ...[
          Container(
            margin: EdgeInsets.only(bottom: 14 * s),
            padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 12 * s),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE4EC),
              borderRadius: BorderRadius.circular(16 * s),
              border: Border.all(color: const Color(0xFFF48FB1), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6 * s),
                  decoration: const BoxDecoration(
                    color: Color(0xFFD81B60),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.female, color: Colors.white, size: 20 * s),
                ),
                SizedBox(width: 12 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Women Only Ride',
                        style: TextStyle(
                          color: const Color(0xFFD81B60),
                          fontWeight: FontWeight.bold,
                          fontSize: 15 * s,
                        ),
                      ),
                      SizedBox(height: 2 * s),
                      Text(
                        'This ride is reserved exclusively for female passengers with verified accounts.',
                        style: TextStyle(
                          color: const Color(0xFF880E4F),
                          fontSize: 12 * s,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_ride!['is_route_matched'] == true) ...[
          Container(
            margin: EdgeInsets.only(bottom: 14 * s),
            padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 12 * s),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16 * s),
              border: Border.all(color: const Color(0xFF93C5FD), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6 * s),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1D4ED8),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.alt_route_rounded,
                    color: Colors.white,
                    size: 20 * s,
                  ),
                ),
                SizedBox(width: 12 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Matched Along Driver\'s Route',
                        style: TextStyle(
                          color: const Color(0xFF1E40AF),
                          fontWeight: FontWeight.bold,
                          fontSize: 14 * s,
                        ),
                      ),
                      SizedBox(height: 2 * s),
                      Text(
                        'Your segment: ${_ride!['passenger_pickup_name'] ?? _ride!['from_location']} → ${_ride!['passenger_drop_name'] ?? _ride!['to_location']} (${_ride!['segment_distance_km'] ?? '-'} km)',
                        style: TextStyle(
                          color: const Color(0xFF1E3A8A),
                          fontSize: 12 * s,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_ride!['route_summary'] != null &&
            _ride!['route_summary'].toString().isNotEmpty) ...[
          Container(
            margin: EdgeInsets.only(bottom: 14 * s),
            padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14 * s),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.directions, color: _kPrimary, size: 18),
                SizedBox(width: 8 * s),
                Expanded(
                  child: Text(
                    'Selected Route: ${_ride!['route_summary']}',
                    style: TextStyle(
                      fontSize: 13 * s,
                      fontWeight: FontWeight.w600,
                      color: _kTextDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Route + date/time cards
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 47,
                child: _SurfaceCard(
                  padding: EdgeInsets.fromLTRB(12 * s, 16 * s, 8 * s, 16 * s),
                  child: _RouteBlock(from: from, to: to),
                ),
              ),
              SizedBox(width: 12 * s),
              Expanded(
                flex: 53,
                child: _SurfaceCard(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12 * s,
                    vertical: 14 * s,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _DetailRow(
                        icon: Icons.calendar_today_outlined,
                        iconColor: _kPrimary,
                        label: 'Date',
                        value: date,
                      ),
                      SizedBox(height: 10 * s),
                      _DetailRow(
                        icon: Icons.departure_board,
                        iconColor: _kPrimary,
                        label: 'Departure',
                        value: departure,
                      ),
                      SizedBox(height: 10 * s),
                      _DetailRow(
                        icon: Icons.access_time,
                        iconColor: _kTeal,
                        label: 'Est. Arrival',
                        value: arrival,
                      ),
                      SizedBox(height: 10 * s),
                      _DetailRow(
                        icon: Icons.event_seat,
                        iconColor: _kTeal,
                        label: 'Available Seats',
                        value: seats,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 14 * s),

        // Driver card
        _SurfaceCard(
          padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 12 * s),
          child: Row(
            children: [
              CircleAvatar(
                radius: 27 * s,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: selfieUrl != null && selfieUrl.isNotEmpty
                    ? NetworkImage(_resolveUrl(selfieUrl))
                    : null,
                onBackgroundImageError:
                    selfieUrl != null && selfieUrl.isNotEmpty
                    ? (exception, stackTrace) {}
                    : null,
                child: selfieUrl == null || selfieUrl.isEmpty
                    ? Icon(Icons.person, size: 28 * s)
                    : null,
              ),
              SizedBox(width: 14 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Driver',
                      style: TextStyle(fontSize: 14 * s, color: _kTextMuted),
                    ),
                    SizedBox(height: 1 * s),
                    Text(
                      driverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20 * s,
                        fontWeight: FontWeight.w800,
                        color: _kTextDark,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8 * s),
              Material(
                color: _kPrimaryBright,
                shape: const CircleBorder(),
                elevation: 3,
                shadowColor: _kPrimaryBright.withOpacity(0.5),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _onCallPressed(driverPhone),
                  child: SizedBox(
                    width: 42 * s,
                    height: 42 * s,
                    child: Icon(Icons.phone, color: Colors.white, size: 22 * s),
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 14 * s),

        // Vehicle card
        _SurfaceCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (vehiclePhoto != null && vehiclePhoto.isNotEmpty)
                AspectRatio(
                  aspectRatio: 2.6,
                  child: Image.network(
                    _resolveUrl(vehiclePhoto),
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: Icon(Icons.directions_car, size: 48),
                        ),
                      );
                    },
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(16 * s, 12 * s, 16 * s, 14 * s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicleModel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20 * s,
                        fontWeight: FontWeight.w800,
                        color: _kTextDark,
                      ),
                    ),
                    SizedBox(height: 4 * s),
                    Wrap(
                      spacing: 8 * s,
                      runSpacing: 6 * s,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10 * s,
                            vertical: 3 * s,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: _kTextDark, width: 1.2),
                            borderRadius: BorderRadius.circular(8 * s),
                          ),
                          child: Text(
                            vehicleNumber,
                            style: TextStyle(
                              fontSize: 16 * s,
                              color: _kTextDark,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14 * s,
                            vertical: 4 * s,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_kPrimaryBright, Color(0xFF4FA3F7)],
                            ),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            vehicleType,
                            style: TextStyle(
                              fontSize: 16 * s,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Passenger bookings (only if the ride payload contains them)
        if (bookings.isNotEmpty) ...[
          SizedBox(height: 18 * s),
          Padding(
            padding: EdgeInsets.only(left: 2 * s, bottom: 6 * s),
            child: Text(
              'Passenger Bookings',
              style: TextStyle(
                fontSize: 19 * s,
                fontWeight: FontWeight.w600,
                color: _kTextDark,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(14 * s),
            decoration: BoxDecoration(
              color: const Color(0xFFE3EAF4),
              borderRadius: BorderRadius.circular(16 * s),
            ),
            child: Column(
              children: [
                for (int i = 0; i < bookings.length; i++) ...[
                  _BookingTile(
                    booking: bookings[i],
                    onSafetyAction: _showSafetyBottomSheet,
                  ),
                  if (i != bookings.length - 1)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12 * s),
                      child: Divider(
                        height: 1,
                        thickness: 1.2,
                        color: Colors.blueGrey.shade100,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Reads passenger bookings from the already-fetched bookings or ride payload.
  List<Map<String, dynamic>> _extractBookings() {
    if (_bookings.isNotEmpty) return _bookings;
    final raw = _ride?['bookings'] ?? _ride?['passenger_bookings'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  void _showSafetyBottomSheet({
    required String targetUserId,
    required String targetUserName,
    required String userRole,
  }) {
    if (targetUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Participant information unavailable.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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
                  const Icon(
                    Icons.shield_outlined,
                    color: _kTextDark,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Safety & Support • $targetUserName',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _kTextDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Reporting or blocking permanently preserves conversation history and ride records for investigation.',
                style: TextStyle(fontSize: 13, color: _kTextMuted),
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
                title: Text(
                  'Report $userRole',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Report inappropriate conduct, safety issues, or violations',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  showReportUserDialog(
                    context,
                    targetUserId: targetUserId,
                    targetUserName: targetUserName,
                    rideId: widget.rideId,
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
                title: Text(
                  'Block $userRole',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
                subtitle: const Text(
                  'Block user from interacting or booking with you in the future',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  showBlockUserConfirmation(
                    context,
                    targetUserId: targetUserId,
                    targetUserName: targetUserName,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Bottom bar (price + primary actions) — same conditions as before
  // -------------------------------------------------------------------------
  Widget _buildBottomBar(double s) {
    final bool isRouteMatched = _ride!['is_route_matched'] == true;
    final segSeats = _ride!['available_segment_seats'];
    final seats = (isRouteMatched && segSeats != null)
        ? segSeats.toString()
        : (_ride!['available_seats']?.toString() ?? '0');
    final totalAmount = double.tryParse(
      _ride!['total_amount']?.toString() ?? '',
    );
    final pricePerSeat = double.tryParse(
      _ride!['price_per_seat']?.toString() ?? '',
    );
    final segPrice = double.tryParse(
      _ride!['segment_price_per_seat']?.toString() ?? '',
    );
    final double? effectivePrice = (isRouteMatched && segPrice != null)
        ? segPrice
        : ((totalAmount != null && totalAmount > 0)
              ? totalAmount
              : pricePerSeat);
    final price = effectivePrice != null
        ? (effectivePrice == effectivePrice.roundToDouble()
              ? effectivePrice.toInt().toString()
              : effectivePrice.toStringAsFixed(2))
        : (_ride!['price_per_seat']?.toString() ?? '0');
    final status = _ride!['status']?.toString() ?? '-';
    final seatsInt = int.tryParse(seats) ?? 0;

    final bool isDriver = _currentUserId == _ride!['driver_id'];
    final bool canBook = !isDriver && status == 'active' && seatsInt > 0;
    final bool canComplete = _computeCanComplete(
      isDriver: isDriver,
      status: status,
    );

    // Check if the current user has booked this ride as a passenger
    Map<String, dynamic>? myBooking;
    if (!isDriver) {
      for (final b in _bookings) {
        final bStatus = (b['status'] ?? '').toString().toLowerCase();
        if (bStatus == 'confirmed' || bStatus == 'completed') {
          myBooking = b;
          break;
        }
      }
    }

    Widget? actions;

    if (!isDriver && myBooking != null) {
      final bookingId = myBooking['id']?.toString() ?? '';
      final isCompleted =
          status.toLowerCase() == 'completed' ||
          (myBooking['status'] ?? '').toString().toLowerCase() == 'completed';

      if (isCompleted) {
        final driverId = _ride!['driver_id']?.toString() ?? '';
        final driverName =
            (_ride!['driver_name'] ?? _ride!['driver_full_name'] ?? 'Driver')
                .toString();
        actions = _PillButton(
          label: 'Report / Block Driver',
          icon: Icons.shield_outlined,
          filled: false,
          color: Colors.red.shade700,
          onPressed: () {
            _showSafetyBottomSheet(
              targetUserId: driverId,
              targetUserName: driverName,
              userRole: 'Driver',
            );
          },
        );
      } else {
        final chatBtn = _PillButton(
          label: 'Chat with Driver',
          icon: Icons.chat_bubble_outline_rounded,
          filled: true,
          color: _kPrimaryBright,
          onPressed: () {
            if (bookingId.isNotEmpty) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(bookingId: bookingId),
                ),
              );
            }
          },
        );

        if (canBook) {
          actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(child: chatBtn),
              SizedBox(width: 8 * s),
              Expanded(
                child: _PillButton(
                  label: 'Book More',
                  icon: Icons.add_circle_outline,
                  filled: false,
                  color: _kPrimaryBright,
                  onPressed: _bookRide,
                ),
              ),
            ],
          );
        } else {
          actions = chatBtn;
        }
      }
    } else if (canBook) {
      actions = _PillButton(
        label: 'Book Seat',
        icon: Icons.check_circle_outline,
        filled: true,
        color: _kPrimaryBright,
        onPressed: _bookRide,
      );
    } else if (isDriver && status == 'active') {
      actions = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canComplete) ...[
            _PillButton(
              label: 'Complete Ride',
              icon: Icons.check_circle,
              filled: true,
              color: Colors.green,
              onPressed: _completeRide,
            ),
            SizedBox(height: 8 * s),
          ],
          _PillButton(
            label: 'Cancel Ride',
            filled: false,
            color: Colors.red,
            onPressed: _cancelRide,
          ),
        ],
      );
    } else if (isDriver && (status == 'draft' || status == 'selfie_uploaded')) {
      actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: _PillButton(
              label: 'Continue Ride',
              icon: Icons.arrow_forward_rounded,
              filled: true,
              color: _kPrimaryBright,
              onPressed: _continueRide,
            ),
          ),
          SizedBox(width: 8 * s),
          InkWell(
            onTap: _deleteDraft,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: EdgeInsets.all(10 * s),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                color: Colors.red.shade600,
                size: 22 * s,
              ),
            ),
          ),
        ],
      );
    } else if (status == 'active' && !isDriver) {
      actions = Text(
        'No seats available.',
        textAlign: TextAlign.end,
        style: TextStyle(fontSize: 14 * s, color: _kTextMuted),
      );
    } else if (status != 'active') {
      actions = Text(
        'This ride is $status.',
        textAlign: TextAlign.end,
        style: TextStyle(fontSize: 14 * s, color: _kTextMuted),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE6EEFA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28 * s)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22 * s, 14 * s, 22 * s, 10 * s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 11,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '₹$price / seat',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 21 * s,
                          fontWeight: FontWeight.w800,
                          color: _kTextDark,
                        ),
                      ),
                    ),
                    SizedBox(height: 4 * s),
                    _StatusBadge(status: status),
                  ],
                ),
              ),
              if (actions != null) ...[
                SizedBox(width: 12 * s),
                Expanded(flex: 10, child: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Reusable widgets
// ===========================================================================

class _SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool clip;

  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.clip = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = _scaleOf(context);
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18 * s),
        boxShadow: [
          BoxShadow(
            color: _kPrimary.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// City name that never breaks mid-word: single words shrink to fit,
/// multi-word names wrap on spaces (max 2 lines).
class _LocationName extends StatelessWidget {
  final String text;
  final double minHeight;

  const _LocationName({required this.text, required this.minHeight});

  @override
  Widget build(BuildContext context) {
    final s = _scaleOf(context);
    final style = TextStyle(
      fontSize: 19 * s,
      fontWeight: FontWeight.w800,
      color: _kTextDark,
      height: 1.15,
    );
    final Widget child = text.trim().contains(' ')
        ? Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: style)
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(text, maxLines: 1, style: style),
          );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }
}

class _RouteBlock extends StatelessWidget {
  final String from;
  final String to;

  const _RouteBlock({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final s = _scaleOf(context);
    final double dot = 26 * s;
    final double pin = 30 * s;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Timeline: dot -> dashed line -> pin
        SizedBox(
          width: 30 * s,
          child: Column(
            children: [
              Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kPrimaryBright.withOpacity(0.28),
                ),
                child: Center(
                  child: Container(
                    width: dot * 0.62,
                    height: dot * 0.62,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kPrimary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: CustomPaint(
                  size: const Size(4, double.infinity),
                  painter: const _DashedLinePainter(
                    startColor: _kPrimaryBright,
                    endColor: _kTeal,
                  ),
                ),
              ),
              Icon(Icons.location_on, color: Colors.deepOrange, size: pin),
            ],
          ),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _LocationName(text: from, minHeight: dot),
              SizedBox(height: 28 * s),
              _LocationName(text: to, minHeight: pin),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color startColor;
  final Color endColor;

  const _DashedLinePainter({required this.startColor, required this.endColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    const double dashHeight = 7.0;
    const double dashSpace = 5.0;
    double startY = dashSpace;
    final paint = Paint()
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    while (startY < size.height - dashSpace) {
      final double endY = (startY + dashHeight).clamp(
        0.0,
        size.height - dashSpace,
      );
      final double t = (startY / size.height).clamp(0.0, 1.0);
      paint.color = Color.lerp(startColor, endColor, t) ?? startColor;
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, endY),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.startColor != startColor || oldDelegate.endColor != endColor;
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final s = _scaleOf(context);
    return Row(
      children: [
        Icon(icon, size: 22 * s, color: iconColor),
        SizedBox(width: 7 * s),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5 * s, color: _kTextDark),
          ),
        ),
        SizedBox(width: 4 * s),
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: 14.5 * s,
            fontWeight: FontWeight.w800,
            color: _kTextDark,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = _scaleOf(context);
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'active':
        bg = const Color(0xFFD7F5DC);
        fg = const Color(0xFF1B7F37);
        break;
      case 'cancelled':
      case 'canceled':
        bg = const Color(0xFFFFE0E0);
        fg = Colors.red.shade700;
        break;
      case 'completed':
        bg = const Color(0xFFDCE8FF);
        fg = _kPrimary;
        break;
      default:
        bg = Colors.grey.shade300;
        fg = Colors.grey.shade800;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 3 * s),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 12 * s,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;
  final Color color;
  final VoidCallback onPressed;

  const _PillButton({
    required this.label,
    required this.filled,
    required this.color,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final s = _scaleOf(context);
    final textStyle = TextStyle(fontSize: 16 * s, fontWeight: FontWeight.w600);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(40),
    );

    final labelWidget = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, maxLines: 1, style: textStyle),
    );

    return SizedBox(
      width: double.infinity,
      height: 44 * s,
      child: filled
          ? FilledButton.icon(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                shape: shape,
                padding: EdgeInsets.symmetric(horizontal: 12 * s),
              ),
              icon: Icon(icon ?? Icons.check, size: 20 * s),
              label: labelWidget,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                backgroundColor: Colors.white.withOpacity(0.4),
                side: BorderSide(color: color, width: 1.6),
                shape: shape,
                padding: EdgeInsets.symmetric(horizontal: 12 * s),
              ),
              child: labelWidget,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passenger booking tile
// ---------------------------------------------------------------------------
class _BookingTile extends StatelessWidget {
  final Map<String, dynamic> booking;
  final void Function({
    required String targetUserId,
    required String targetUserName,
    required String userRole,
  })?
  onSafetyAction;

  const _BookingTile({required this.booking, this.onSafetyAction});

  String _s(List<String> keys, [String fallback = '-']) {
    for (final k in keys) {
      final v = booking[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final s = _scaleOf(context);
    final name = _s(['booked_by', 'passenger_name', 'user_name', 'name']);
    final seats = _s(['seats_booked', 'seats', 'num_seats'], '0');
    final total = _s(['total_amount', 'total_price', 'total'], '0');
    final payment = _s(['payment_method', 'payment_mode'], '').toUpperCase();
    final status = _s(['status'], 'confirmed');

    final seatsInt = int.tryParse(seats) ?? 0;

    final rawPassengers = booking['passengers'];
    final passengers = rawPassengers is List
        ? rawPassengers.whereType<Map>().toList()
        : <Map>[];

    final isConfirmed = status.toLowerCase() == 'confirmed';
    final statusBg = isConfirmed
        ? const Color(0xFFCDEFD3)
        : const Color(0xFFFFE0E0);
    final statusFg = isConfirmed
        ? const Color(0xFF1B7F37)
        : Colors.red.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Booked by: $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17 * s,
                  fontWeight: FontWeight.w800,
                  color: _kTextDark,
                ),
              ),
            ),
            SizedBox(width: 8 * s),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 10 * s,
                vertical: 5 * s,
              ),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(14 * s),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                  fontSize: 13 * s,
                  fontWeight: FontWeight.w600,
                  color: statusFg,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8 * s),
        Wrap(
          spacing: 8 * s,
          runSpacing: 6 * s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 10 * s,
                vertical: 4 * s,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFD6E6FB),
                borderRadius: BorderRadius.circular(16 * s),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_seat, size: 18 * s, color: _kPrimary),
                  SizedBox(width: 5 * s),
                  Text(
                    '$seats ${seatsInt == 1 ? 'seat' : 'seats'}',
                    style: TextStyle(fontSize: 15 * s, color: _kPrimary),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 10 * s,
                vertical: 4 * s,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFCDEFD3),
                borderRadius: BorderRadius.circular(16 * s),
              ),
              child: Text(
                'Total: ₹$total',
                style: TextStyle(
                  fontSize: 15 * s,
                  color: const Color(0xFF1B7F37),
                ),
              ),
            ),
            if (payment.isNotEmpty)
              Text(
                payment,
                style: TextStyle(fontSize: 15 * s, color: _kTextDark),
              ),
          ],
        ),
        if (passengers.isNotEmpty) ...[
          SizedBox(height: 10 * s),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5FC),
              borderRadius: BorderRadius.circular(12 * s),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < passengers.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == passengers.length - 1 ? 0 : 6 * s,
                    ),
                    child: Text(
                      _passengerLine(i, passengers[i]),
                      style: TextStyle(fontSize: 15 * s, color: _kTextDark),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (isConfirmed) ...[
          SizedBox(height: 10 * s),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: Icon(Icons.chat_bubble_outline_rounded, size: 16 * s),
              label: Text(
                'Chat with $name',
                style: TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4FD8),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: 14 * s,
                  vertical: 8 * s,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10 * s),
                ),
                elevation: 0,
              ),
              onPressed: () {
                final bId =
                    (booking['id'] ?? booking['booking_id'])?.toString() ?? '';
                if (bId.isNotEmpty) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(bookingId: bId),
                    ),
                  );
                }
              },
            ),
          ),
        ] else if (status.toLowerCase() == 'completed') ...[
          SizedBox(height: 10 * s),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: Icon(
                Icons.shield_outlined,
                size: 16 * s,
                color: Colors.red.shade700,
              ),
              label: Text(
                'Report / Block $name',
                style: TextStyle(
                  fontSize: 13 * s,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red.shade200),
                backgroundColor: const Color(0xFFFEF2F2),
                padding: EdgeInsets.symmetric(
                  horizontal: 14 * s,
                  vertical: 8 * s,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10 * s),
                ),
              ),
              onPressed: () {
                final passengerId =
                    (booking['passenger_id'] ??
                            booking['user_id'] ??
                            booking['passengerId'])
                        ?.toString() ??
                    '';
                onSafetyAction?.call(
                  targetUserId: passengerId,
                  targetUserName: name,
                  userRole: 'Passenger',
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  String _passengerLine(int index, Map p) {
    final parts = <String>[];
    final name = (p['passenger_name'] ?? p['name'])?.toString();
    final age = (p['passenger_age'] ?? p['age'])?.toString();
    final gender = (p['passenger_gender'] ?? p['gender'])?.toString();
    if (name != null && name.isNotEmpty) parts.add(name);
    if (age != null && age.isNotEmpty) parts.add('$age yrs');
    if (gender != null && gender.isNotEmpty) parts.add(gender);
    return '${index + 1}. ${parts.join(' • ')}';
  }
}
