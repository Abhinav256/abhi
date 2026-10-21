import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/notification_state.dart';
import 'ride_details_screen.dart';

class RecurringSchedulesScreen extends StatefulWidget {
  const RecurringSchedulesScreen({super.key});

  @override
  State<RecurringSchedulesScreen> createState() => _RecurringSchedulesScreenState();
}

class _RecurringSchedulesScreenState extends State<RecurringSchedulesScreen> {
  final ApiService _apiService = ApiService();

  static const Color _navy = Color(0xFF0B1B4D);
  static const Color _blue = Color(0xFF0B5FD1);
  static const Color _bg = Color(0xFFF3F7FD);
  static const Color _green = Color(0xFF12A37B);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _red = Color(0xFFE5484D);
  static const Color _hint = Color(0xFF7B879C);

  List<Map<String, dynamic>> _schedules = [];
  bool _isLoading = true;
  String _filter = 'all'; // 'all', 'active', 'paused', 'cancelled'

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() => _isLoading = true);
    try {
      final list = await _apiService.getRecurringSchedules();
      if (!mounted) return;
      setState(() {
        _schedules = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load recurring schedules: $e')),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredSchedules {
    if (_filter == 'all') return _schedules;
    return _schedules.where((s) => s['status'] == _filter).toList();
  }

  String _formatRecurrenceLabel(Map<String, dynamic> s) {
    final type = s['recurrence_type']?.toString().toLowerCase() ?? '';
    final weekdays = s['selected_weekdays'];
    switch (type) {
      case 'daily':
      case 'every_day':
      case 'everyday':
        return 'Every Day';
      case 'weekly':
      case 'every_week':
        return 'Every Week';
      case 'biweekly':
      case 'every_2_weeks':
        return 'Every 2 Weeks';
      case 'custom':
        if (weekdays is List && weekdays.isNotEmpty) {
          final capitalized = weekdays.map((w) => w.toString().toUpperCase()).join(', ');
          return 'Custom ($capitalized)';
        }
        return 'Custom Days';
      default:
        return type.toUpperCase();
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }

  Future<void> _togglePause(Map<String, dynamic> schedule) async {
    final scheduleId = schedule['id']?.toString() ?? '';
    final isPaused = schedule['status'] == 'paused';
    final action = isPaused ? 'Resume' : 'Pause';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action Schedule?'),
        content: Text(
          isPaused
              ? 'Are you sure you want to resume this recurring schedule?'
              : 'Are you sure you want to pause this recurring schedule?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: isPaused ? _green : _amber),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (isPaused) {
        await _apiService.resumeRecurringSchedule(scheduleId);
      } else {
        await _apiService.pauseRecurringSchedule(scheduleId);
      }
      NotificationState.instance.refresh();
      _loadSchedules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Schedule ${isPaused ? "resumed" : "paused"} successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update schedule: $e')),
        );
      }
    }
  }

  Future<void> _cancelSchedule(Map<String, dynamic> schedule) async {
    final scheduleId = schedule['id']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Entire Schedule?'),
        content: const Text(
          'This will cancel the recurring series and all future unbooked rides in this schedule.\n\nAre you sure?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Schedule')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Cancel Schedule'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _apiService.cancelRecurringSchedule(scheduleId);
      NotificationState.instance.refresh();
      _loadSchedules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recurring schedule cancelled.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel schedule: $e')),
        );
      }
    }
  }

  void _openScheduleDetails(Map<String, dynamic> schedule) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RecurringScheduleDetailScreen(
          scheduleId: schedule['id'].toString(),
          onChanged: _loadSchedules,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _navy,
        title: const Text(
          'Recurring Schedules',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSchedules,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSchedules.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadSchedules,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: _filteredSchedules.length,
                          itemBuilder: (context, index) {
                            return _buildScheduleCard(_filteredSchedules[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = [
      {'key': 'all', 'label': 'All'},
      {'key': 'active', 'label': 'Active'},
      {'key': 'paused', 'label': 'Paused'},
      {'key': 'cancelled', 'label': 'Cancelled'},
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final selected = _filter == f['key'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f['label']!),
                selected: selected,
                selectedColor: _blue.withOpacity(0.12),
                backgroundColor: _bg,
                labelStyle: TextStyle(
                  color: selected ? _blue : _navy,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: selected ? _blue : Colors.grey.shade300,
                  ),
                ),
                onSelected: (val) {
                  if (val) setState(() => _filter = f['key']!);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> s) {
    final template = s['ride_template'] is Map ? s['ride_template'] as Map : {};
    final from = template['from_location']?.toString() ?? 'Origin';
    final to = template['to_location']?.toString() ?? 'Destination';
    final depTime = template['departure_time']?.toString() ?? '-';
    final price = template['price_per_seat']?.toString() ?? '0';
    final status = s['status']?.toString() ?? 'active';

    final totalRides = s['total_rides'] ?? 0;
    final activeRides = s['active_rides'] ?? 0;
    final completedRides = s['completed_rides'] ?? 0;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'active':
        statusColor = _green;
        statusLabel = 'ACTIVE';
        break;
      case 'paused':
        statusColor = _amber;
        statusLabel = 'PAUSED';
        break;
      case 'cancelled':
        statusColor = _red;
        statusLabel = 'CANCELLED';
        break;
      default:
        statusColor = _hint;
        statusLabel = status.toUpperCase();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
          onTap: () => _openScheduleDetails(s),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Recurrence chip + status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _blue.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.repeat_rounded, size: 14, color: _blue),
                          const SizedBox(width: 4),
                          Text(
                            _formatRecurrenceLabel(s),
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Route
                Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: _green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 18,
                          color: Colors.grey.shade300,
                        ),
                        const Icon(Icons.location_on, size: 12, color: _red),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            from,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _navy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            to,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _navy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Price
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹$price',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _blue,
                          ),
                        ),
                        const Text(
                          '/ seat',
                          style: TextStyle(fontSize: 11, color: _hint),
                        ),
                      ],
                    ),
                  ],
                ),

                const Divider(height: 24),

                // Info row: dates + stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.schedule, size: 14, color: _hint),
                            const SizedBox(width: 4),
                            Text(
                              depTime,
                              style: const TextStyle(fontSize: 13, color: _navy, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.date_range, size: 14, color: _hint),
                            const SizedBox(width: 4),
                            Text(
                              '${_formatDate(s['start_date']?.toString())} → ${_formatDate(s['end_date']?.toString())}',
                              style: const TextStyle(fontSize: 12, color: _hint),
                            ),
                          ],
                        ),
                      ],
                    ),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$activeRides active • $completedRides done • $totalRides total',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                // Action buttons if active/paused
                if (status != 'cancelled') ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        icon: Icon(
                          status == 'paused' ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          size: 16,
                          color: status == 'paused' ? _green : _amber,
                        ),
                        label: Text(
                          status == 'paused' ? 'Resume' : 'Pause',
                          style: TextStyle(
                            color: status == 'paused' ? _green : _amber,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => _togglePause(s),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.cancel_outlined, size: 16, color: _red),
                        label: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: _red,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => _cancelSchedule(s),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _openScheduleDetails(s),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('View Rides', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_repeat_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No Recurring Schedules',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _navy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'When you create a ride with the "Schedule Recurring" option, all generated rides and series can be managed here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _hint, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DETAIL SCREEN: RECURRING SCHEDULE OCCURRENCES
// -----------------------------------------------------------------------------

class _RecurringScheduleDetailScreen extends StatefulWidget {
  final String scheduleId;
  final VoidCallback onChanged;

  const _RecurringScheduleDetailScreen({
    required this.scheduleId,
    required this.onChanged,
  });

  @override
  State<_RecurringScheduleDetailScreen> createState() => _RecurringScheduleDetailScreenState();
}

class _RecurringScheduleDetailScreenState extends State<_RecurringScheduleDetailScreen> {
  final ApiService _apiService = ApiService();

  static const Color _navy = Color(0xFF0B1B4D);
  static const Color _blue = Color(0xFF0B5FD1);
  static const Color _bg = Color(0xFFF3F7FD);
  static const Color _green = Color(0xFF12A37B);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _red = Color(0xFFE5484D);
  static const Color _hint = Color(0xFF7B879C);

  Map<String, dynamic>? _schedule;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _isLoading = true);
    try {
      final s = await _apiService.getRecurringScheduleDetail(widget.scheduleId);
      if (!mounted) return;
      setState(() {
        _schedule = s;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load schedule detail: $e')),
      );
    }
  }

  Future<void> _cancelOccurrence(Map<String, dynamic> ride) async {
    final rideId = ride['id']?.toString() ?? '';
    final dateStr = ride['journey_date']?.toString().substring(0, math.min(10, ride['journey_date'].toString().length)) ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel This Occurrence?'),
        content: Text(
          'Cancel ride on $dateStr?\n\nOnly this specific ride will be cancelled. The rest of your recurring schedule will remain active.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Ride')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Cancel Ride'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _apiService.cancelRide(rideId: rideId);
      NotificationState.instance.refresh();
      _loadDetail();
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ride on $dateStr cancelled.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel ride: $e')),
        );
      }
    }
  }

  Future<void> _showEditDialog() async {
    final template = _schedule?['ride_template'] is Map ? _schedule!['ride_template'] as Map : {};
    final currentSeats = template['available_seats'] ?? 1;
    final currentPrice = template['price_per_seat']?.toString() ?? '100';

    final seatsCtrl = TextEditingController(text: currentSeats.toString());
    final priceCtrl = TextEditingController(text: currentPrice);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Recurring Schedule'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Changes will apply to future unbooked rides in this schedule.',
              style: TextStyle(fontSize: 13, color: _hint),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: seatsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Available Seats',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price Per Seat (₹)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final newSeats = int.tryParse(seatsCtrl.text.trim());
    final newPrice = double.tryParse(priceCtrl.text.trim());

    try {
      await _apiService.updateRecurringSchedule(
        scheduleId: widget.scheduleId,
        availableSeats: newSeats,
        pricePerSeat: newPrice,
      );
      _loadDetail();
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recurring schedule updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final s = _schedule;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Schedule Details')),
        body: const Center(child: Text('Schedule not found.')),
      );
    }

    final template = s['ride_template'] is Map ? s['ride_template'] as Map : {};
    final from = template['from_location']?.toString() ?? 'Origin';
    final to = template['to_location']?.toString() ?? 'Destination';
    final rides = s['rides'] is List ? s['rides'] as List : [];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _navy,
        title: const Text(
          'Schedule Details',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (s['status'] == 'active')
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Schedule',
              onPressed: _showEditDialog,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$from → $to',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy),
                ),
                const SizedBox(height: 8),
                Text(
                  'Departure: ${template['departure_time'] ?? '-'} • Price: ₹${template['price_per_seat'] ?? '0'}/seat',
                  style: const TextStyle(fontSize: 14, color: _hint),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vehicle: ${template['vehicle_model'] ?? 'Vehicle'} • Seats: ${template['available_seats'] ?? 1}',
                  style: const TextStyle(fontSize: 14, color: _hint),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Occurrences header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Generated Rides (${rides.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navy),
              ),
              const Text(
                'Individual occurrences',
                style: TextStyle(fontSize: 12, color: _hint),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Rides list
          ...rides.map((ride) {
            final dateStr = ride['journey_date']?.toString().substring(0, math.min(10, ride['journey_date'].toString().length)) ?? '-';
            final status = ride['status']?.toString() ?? 'active';
            final rideId = ride['id']?.toString() ?? '';

            Color stColor = _green;
            if (status == 'draft' || status == 'selfie_uploaded') stColor = _amber;
            if (status == 'cancelled') stColor = _red;
            if (status == 'completed') stColor = _blue;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.directions_car_filled_outlined, color: _blue, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateStr,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navy),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${template['departure_time'] ?? '-'} • ${ride['available_seats'] ?? 0} seats left',
                          style: const TextStyle(fontSize: 13, color: _hint),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: stColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(color: stColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: _hint),
                    onSelected: (val) {
                      if (val == 'view') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RideDetailsScreen(rideId: rideId),
                          ),
                        );
                      } else if (val == 'cancel') {
                        _cancelOccurrence(ride);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: Text('View Ride Details'),
                      ),
                      if (status == 'active')
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('Cancel Occurrence', style: TextStyle(color: _red)),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
