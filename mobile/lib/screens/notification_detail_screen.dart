import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/phone_call_service.dart';
import 'ride_details_screen.dart';

class NotificationDetailScreen extends StatefulWidget {
  final Map<String, dynamic> notification;
  final ApiService? apiService;

  const NotificationDetailScreen({
    super.key,
    required this.notification,
    this.apiService,
  });

  @override
  State<NotificationDetailScreen> createState() =>
      _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  late final ApiService _apiService = widget.apiService ?? ApiService();

  late Map<String, dynamic> _notif;
  Map<String, dynamic>? _ride;
  Map<String, dynamic>? _booking;
  bool _isLoading = true;

  static const Color _kNavy = Color(0xFF0F1B4D);
  static const Color _kTeal = Color(0xFF12B58A);
  static const Color _kBlue = Color(0xFF0B6FE0);
  static const Color _kBackground = Color(0xFFF3F7FD);
  static const Color _kCardBg = Colors.white;
  static const Color _kTextMuted = Color(0xFF6B7A90);
  static const Color _kEmerald = Color(0xFF059669);

  @override
  void initState() {
    super.initState();
    _notif = Map<String, dynamic>.from(widget.notification);
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);

    final notifId = _notif['id']?.toString() ?? '';
    final rideIdFromNotif = _notif['ride_id']?.toString();
    final bookingIdFromNotif = _notif['booking_id']?.toString();

    Map<String, dynamic>? fetchedRide;
    Map<String, dynamic>? fetchedBooking;

    // 1. Try fetching full notification detail from backend
    if (notifId.isNotEmpty) {
      try {
        final detail = await _apiService.getNotificationDetail(notifId);
        if (detail.isNotEmpty) {
          if (detail['ride'] is Map) {
            fetchedRide = Map<String, dynamic>.from(detail['ride'] as Map);
          }
          if (detail['booking'] is Map) {
            fetchedBooking =
                Map<String, dynamic>.from(detail['booking'] as Map);
          }
          _notif = {..._notif, ...detail};
        }
      } catch (_) {
        // Fall back gracefully to direct ride/booking calls
      }
    }

    // 2. If ride is still missing and ride_id is available, fetch ride detail directly
    final effectiveRideId = fetchedRide?['id']?.toString() ??
        fetchedBooking?['ride_id']?.toString() ??
        rideIdFromNotif;

    if (fetchedRide == null &&
        effectiveRideId != null &&
        effectiveRideId.isNotEmpty) {
      try {
        final rideRes =
            await _apiService.getRideDetail(rideId: effectiveRideId);
        final r = (rideRes['ride'] is Map)
            ? Map<String, dynamic>.from(rideRes['ride'] as Map)
            : rideRes;
        if (r.isNotEmpty) {
          fetchedRide = r;
        }
      } catch (_) {}
    }

    // 3. If booking is still missing and booking_id is available, fetch booking directly
    final effectiveBookingId =
        fetchedBooking?['id']?.toString() ?? bookingIdFromNotif;
    if (fetchedBooking == null &&
        effectiveBookingId != null &&
        effectiveBookingId.isNotEmpty) {
      try {
        final bRes =
            await _apiService.getBooking(bookingId: effectiveBookingId);
        final b = (bRes['booking'] is Map)
            ? Map<String, dynamic>.from(bRes['booking'] as Map)
            : bRes;
        if (b.isNotEmpty) {
          fetchedBooking = b;
          if (fetchedRide == null && b['ride_id'] != null) {
            try {
              final rRes = await _apiService.getRideDetail(
                  rideId: b['ride_id'].toString());
              final r = (rRes['ride'] is Map)
                  ? Map<String, dynamic>.from(rRes['ride'] as Map)
                  : rRes;
              if (r.isNotEmpty) fetchedRide = r;
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _ride = fetchedRide;
      _booking = fetchedBooking;
      _isLoading = false;
    });
  }

  // --- Fallback String Extraction Helpers ---
  String? _extractFromLocation() {
    if (_ride != null && _ride!['from_location'] != null) {
      final loc = _ride!['from_location'].toString();
      if (loc.isNotEmpty) return loc;
    }
    final msg = _notif['message']?.toString() ?? '';
    final match = RegExp(r'from\s+(.*?)\s+to\s+(.*?)(?:\.|\s|$)',
            caseSensitive: false)
        .firstMatch(msg);
    if (match != null && match.groupCount >= 1) {
      return match.group(1)?.trim();
    }
    return null;
  }

  String? _extractToLocation() {
    if (_ride != null && _ride!['to_location'] != null) {
      final loc = _ride!['to_location'].toString();
      if (loc.isNotEmpty) return loc;
    }
    final msg = _notif['message']?.toString() ?? '';
    final match = RegExp(r'from\s+(.*?)\s+to\s+(.*?)(?:\.|\s|$)',
            caseSensitive: false)
        .firstMatch(msg);
    if (match != null && match.groupCount >= 2) {
      return match.group(2)?.trim();
    }
    return null;
  }

  String? _extractSeats() {
    if (_booking != null && _booking!['seats_booked'] != null) {
      return _booking!['seats_booked'].toString();
    }
    if (_ride != null && _ride!['available_seats'] != null) {
      return '${_ride!['available_seats']} available';
    }
    final msg = _notif['message']?.toString() ?? '';
    final match = RegExp(r'(\d+)\s+seats?', caseSensitive: false).firstMatch(msg);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }

  // --- Formatting Helpers ---
  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final d = parsed.day.toString().padLeft(2, '0');
    final m = _monthName(parsed.month);
    final y = parsed.year;
    final suffix = parsed.hour >= 12 ? 'PM' : 'AM';
    var h12 = parsed.hour % 12;
    if (h12 == 0) h12 = 12;
    final min = parsed.minute.toString().padLeft(2, '0');
    return '$d $m $y • $h12:$min $suffix';
  }

  String _formatDateOnly(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      if (raw.length >= 10) {
        final p = raw.substring(0, 10).split('-');
        if (p.length == 3) {
          final mInt = int.tryParse(p[1]) ?? 1;
          return '${p[2]} ${_monthName(mInt)} ${p[0]}';
        }
      }
      return raw;
    }
    final d = parsed.day.toString().padLeft(2, '0');
    final m = _monthName(parsed.month);
    return '$d $m ${parsed.year}';
  }

  String _formatTimeOnly(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    if (raw.contains('T')) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        final suffix = parsed.hour >= 12 ? 'PM' : 'AM';
        var h12 = parsed.hour % 12;
        if (h12 == 0) h12 = 12;
        return '$h12:${parsed.minute.toString().padLeft(2, '0')} $suffix';
      }
    }
    final parts = raw.split(':');
    if (parts.length >= 2) {
      final h24 = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h24 != null && m != null) {
        final suffix = h24 >= 12 ? 'PM' : 'AM';
        var h12 = h24 % 12;
        if (h12 == 0) h12 = 12;
        return '$h12:${m.toString().padLeft(2, '0')} $suffix';
      }
    }
    return raw;
  }

  String _timeAgo(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes <= 1) return 'Just now';
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '';
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'ride_booked':
        return Icons.confirmation_number_rounded;
      case 'ride_created':
        return Icons.add_road_rounded;
      case 'ride_canceled':
        return Icons.cancel_rounded;
      case 'ride_completed':
        return Icons.check_circle_rounded;
      case 'referral':
        return Icons.card_giftcard_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _getColorForType(String? type) {
    switch (type) {
      case 'ride_booked':
        return _kTeal;
      case 'ride_created':
        return _kBlue;
      case 'ride_canceled':
        return const Color(0xFFE53935);
      case 'ride_completed':
        return const Color(0xFF10B981);
      case 'referral':
        return const Color(0xFFF59E0B);
      default:
        return _kNavy;
    }
  }

  String _getTypeLabel(String? type) {
    switch (type) {
      case 'ride_booked':
        return 'Ride Booking';
      case 'ride_created':
        return 'Ride Published';
      case 'ride_canceled':
        return 'Cancellation';
      case 'ride_completed':
        return 'Ride Completed';
      case 'referral':
        return 'Referral Bonus';
      default:
        return 'Alert';
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final double maxW = math.min(media.size.width, 560);
    final String type = _notif['type']?.toString() ?? '';
    final Color themeColor = _getColorForType(type);

    final fromLoc = _extractFromLocation();
    final toLoc = _extractToLocation();
    final hasRoute = fromLoc != null && toLoc != null;

    final rideId = _ride?['id']?.toString() ??
        _booking?['ride_id']?.toString() ??
        _notif['ride_id']?.toString();

    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _kNavy,
        toolbarHeight: 52,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _kNavy,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Notification Details',
          style: TextStyle(
            color: _kNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: _kNavy),
            onPressed: _loadDetails,
          ),
        ],
      ),
      body: Center(
        child: SizedBox(
          width: maxW,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              media.padding.bottom + 24,
            ),
            children: [
              // 1. Notification Summary Hero Card
              _buildNotificationHeroCard(themeColor, type),

              const SizedBox(height: 16),

              // 2. Elaborate Journey / Route Card (From, To, Date, Times, Fare)
              if (hasRoute || _ride != null)
                _buildRouteCard(fromLoc, toLoc, themeColor),

              if (hasRoute || _ride != null) const SizedBox(height: 16),

              // 3. Driver & Vehicle Card
              if (_ride != null &&
                  ((_ride!['driver_name'] != null &&
                          _ride!['driver_name'].toString().isNotEmpty) ||
                      (_ride!['vehicle_model'] != null &&
                          _ride!['vehicle_model'].toString().isNotEmpty)))
                _buildDriverVehicleCard(),

              if (_ride != null &&
                  ((_ride!['driver_name'] != null &&
                          _ride!['driver_name'].toString().isNotEmpty) ||
                      (_ride!['vehicle_model'] != null &&
                          _ride!['vehicle_model'].toString().isNotEmpty)))
                const SizedBox(height: 16),

              // 4. Booking Details Card (if available)
              if (_booking != null) _buildBookingCard(),

              if (_booking != null) const SizedBox(height: 16),

              // 5. Loading indicator if still fetching background info
              if (_isLoading)
                Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: themeColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Updating live ride details...',
                        style: TextStyle(fontSize: 13, color: _kTextMuted),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // 6. Action Button: View Full Ride Details
              if (rideId != null && rideId.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RideDetailsScreen(rideId: rideId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.directions_car_rounded, size: 20),
                  label: const Text(
                    'View Full Ride Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                ),

              const SizedBox(height: 12),

              // 7. Back Button
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kNavy,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Back to Notifications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card 1: Notification Hero Card
  // ---------------------------------------------------------------------------
  Widget _buildNotificationHeroCard(Color themeColor, String type) {
    final title = _notif['title']?.toString() ?? 'Notification';
    final message = _notif['message']?.toString() ?? '';
    final createdAt = _notif['created_at']?.toString();
    final timeAgoStr = _timeAgo(createdAt);
    final isRead = _notif['is_read'] == true;

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Type Badge + Read Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getIconForType(type), size: 16, color: themeColor),
                    const SizedBox(width: 6),
                    Text(
                      _getTypeLabel(type),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: themeColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isRead ? Colors.grey.shade100 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRead ? Icons.done_all_rounded : Icons.mark_email_unread_outlined,
                      size: 14,
                      color: isRead ? Colors.grey.shade600 : _kBlue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isRead ? 'Read' : 'New',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isRead ? Colors.grey.shade600 : _kBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Title
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _kNavy,
              height: 1.25,
            ),
          ),

          const SizedBox(height: 6),

          // Formatted Date & Time Row
          Row(
            children: [
              Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                _formatDateTime(createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (timeAgoStr.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  '($timeAgoStr)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: themeColor,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEFF2F7)),
          const SizedBox(height: 14),

          // Message Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 20,
                  color: themeColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF2D3748),
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
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
  // Card 2: Elaborate Journey & Route Card
  // ---------------------------------------------------------------------------
  Widget _buildRouteCard(
    String? fromLoc,
    String? toLoc,
    Color themeColor,
  ) {
    final dateStr = _ride?['journey_date']?.toString();
    final depTimeStr = _ride?['departure_time']?.toString();
    final arrTimeStr = _ride?['estimated_arrival_time']?.toString();
    final price = _ride?['price_per_seat'];
    final seatsStr = _extractSeats();
    final status = _ride?['status']?.toString();
    final isWomenOnly = _ride?['is_women_only'] == true;

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _kBlue.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      size: 18,
                      color: _kBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Trip & Route Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _kNavy,
                    ),
                  ),
                ],
              ),
              if (status != null && status.isNotEmpty)
                _buildStatusChip(status),
            ],
          ),

          const SizedBox(height: 16),

          // Visual Route Timeline
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EEF5)),
            ),
            child: Column(
              children: [
                // FROM Location Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 36,
                          color: Colors.grey.shade300,
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PICKUP LOCATION',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fromLoc ?? 'Not specified',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _kNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // TO Location Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DROP-OFF LOCATION',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            toLoc ?? 'Not specified',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _kNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Journey Metadata Grid (Date, Dep Time, Arr Time, Price)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (dateStr != null && dateStr.isNotEmpty)
                _buildInfoBadge(
                  icon: Icons.calendar_today_rounded,
                  label: 'Journey Date',
                  value: _formatDateOnly(dateStr),
                  color: _kBlue,
                ),
              if (depTimeStr != null && depTimeStr.isNotEmpty)
                _buildInfoBadge(
                  icon: Icons.departure_board_rounded,
                  label: 'Departure',
                  value: _formatTimeOnly(depTimeStr),
                  color: _kTeal,
                ),
              if (arrTimeStr != null && arrTimeStr.isNotEmpty)
                _buildInfoBadge(
                  icon: Icons.flag_rounded,
                  label: 'Est. Arrival',
                  value: _formatTimeOnly(arrTimeStr),
                  color: Colors.indigo,
                ),
              if (price != null)
                _buildInfoBadge(
                  icon: Icons.currency_rupee_rounded,
                  label: 'Price per Seat',
                  value: '₹$price',
                  color: _kEmerald,
                ),
              if (seatsStr != null && seatsStr.isNotEmpty)
                _buildInfoBadge(
                  icon: Icons.airline_seat_recline_normal_rounded,
                  label: 'Seats',
                  value: seatsStr,
                  color: Colors.orange.shade800,
                ),
              if (isWomenOnly)
                _buildInfoBadge(
                  icon: Icons.female_rounded,
                  label: 'Safety',
                  value: 'Women Only Ride',
                  color: Colors.pink,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card 3: Driver & Vehicle Card
  // ---------------------------------------------------------------------------
  Widget _buildDriverVehicleCard() {
    final driverName = _ride?['driver_name']?.toString() ?? 'Driver';
    final driverPhone = _ride?['driver_phone']?.toString() ?? '';
    final driverGender = _ride?['driver_gender']?.toString() ?? '';
    final vehicleModel = _ride?['vehicle_model']?.toString() ?? '';
    final vehicleNumber = _ride?['vehicle_number']?.toString() ?? '';
    final vehicleType = _ride?['vehicle_type']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_pin_rounded,
                  size: 18,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Driver & Vehicle',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Driver Row
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _kBlue.withOpacity(0.15),
                child: Text(
                  driverName.isNotEmpty ? driverName[0].toUpperCase() : 'D',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _kBlue,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _kNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      driverGender.isNotEmpty
                          ? 'Driver • ${driverGender.toUpperCase()}'
                          : 'Ride Host',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (driverPhone.isNotEmpty) ...[
                IconButton.filled(
                  icon: const Icon(Icons.phone, size: 18, color: Colors.white),
                  tooltip: 'Call Driver',
                  style: IconButton.styleFrom(backgroundColor: _kBlue),
                  onPressed: () => PhoneCallService.makePhoneCall(
                    context: context,
                    phoneNumber: driverPhone,
                    recipientName: driverName,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: 'Copy Phone Number',
                  onPressed: () =>
                      _copyToClipboard(driverPhone, 'Phone number'),
                ),
              ],
            ],
          ),

          if (driverPhone.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F7FD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16, color: _kBlue),
                  const SizedBox(width: 8),
                  Text(
                    driverPhone,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kNavy,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _copyToClipboard(driverPhone, 'Phone number'),
                    child: const Text(
                      'Copy',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Vehicle Info if available
          if (vehicleModel.isNotEmpty || vehicleNumber.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFEFF2F7)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VEHICLE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vehicleModel.isNotEmpty ? vehicleModel : 'Vehicle',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _kNavy,
                        ),
                      ),
                      if (vehicleType.isNotEmpty)
                        Text(
                          vehicleType,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                if (vehicleNumber.isNotEmpty) _buildLicensePlate(vehicleNumber),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card 4: Booking Summary Card
  // ---------------------------------------------------------------------------
  Widget _buildBookingCard() {
    final passengerName =
        _booking?['passenger_name']?.toString() ?? 'Passenger';
    final seats = _booking?['seats_booked']?.toString() ?? '1';
    final totalAmount = _booking?['total_amount']?.toString() ?? '0';
    final paymentMode = _booking?['payment_mode']?.toString() ?? 'cash';
    final status = _booking?['status']?.toString() ?? 'confirmed';
    final bookingId = _booking?['id']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      size: 18,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Booking Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _kNavy,
                    ),
                  ),
                ],
              ),
              _buildStatusChip(status),
            ],
          ),

          const SizedBox(height: 16),

          // Passenger info & seats
          Row(
            children: [
              Expanded(
                child: _buildDetailTile(
                  label: 'PASSENGER',
                  value: passengerName,
                  icon: Icons.person_outline_rounded,
                ),
              ),
              Expanded(
                child: _buildDetailTile(
                  label: 'SEATS BOOKED',
                  value: '$seats Seat(s)',
                  icon: Icons.event_seat_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildDetailTile(
                  label: 'TOTAL AMOUNT',
                  value: '₹$totalAmount',
                  icon: Icons.payments_outlined,
                ),
              ),
              Expanded(
                child: _buildDetailTile(
                  label: 'PAYMENT METHOD',
                  value: paymentMode.toUpperCase(),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
            ],
          ),

          if (bookingId.isNotEmpty) ...[
            const SizedBox(height: 14),
            InkWell(
              onTap: () => _copyToClipboard(bookingId, 'Booking ID'),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Text(
                      'Ref ID: ${bookingId.length > 12 ? '${bookingId.substring(0, 12)}...' : bookingId}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: _kTextMuted,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.copy_rounded,
                        size: 14, color: _kBlue),
                    const SizedBox(width: 4),
                    const Text(
                      'Copy',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper Widgets
  // ---------------------------------------------------------------------------
  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status.toLowerCase()) {
      case 'active':
      case 'confirmed':
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        label = status == 'active' ? 'Active Ride' : 'Confirmed';
        break;
      case 'completed':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
        label = 'Completed';
        break;
      case 'cancelled':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        label = 'Cancelled';
        break;
      case 'draft':
      case 'selfie_uploaded':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        label = 'Pending Review';
        break;
      default:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade700;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildInfoBadge({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLicensePlate(String plateNumber) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0D47A1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: const Text(
              'IND',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            plateNumber.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _kNavy,
          ),
        ),
      ],
    );
  }
}
