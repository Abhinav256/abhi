import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/notification_state.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'notification_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<dynamic> _notifications = [];

  static const _kNavy = Color(0xFF0F1B4D);
  static const _kTeal = Color(0xFF12B58A);
  static const _kBlue = Color(0xFF0B6FE0);
  static const _kBackground = Color(0xFFF3F7FD);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationState.instance.addListener(_onNotifChanged);
    _loadNotifications();
  }

  @override
  void dispose() {
    NotificationState.instance.removeListener(_onNotifChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onNotifChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh notifications when the app resumes from background.
    if (state == AppLifecycleState.resumed) {
      _loadNotifications();
    }
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final notifs = await _apiService.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifs;
        _isLoading = false;
      });
      NotificationState.instance.updateFromNotifications(notifs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load notifications: $e')),
      );
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      await _apiService.markNotificationRead(id);
      final index = _notifications.indexWhere((n) => n['id']?.toString() == id);
      if (index != -1 && mounted) {
        setState(() {
          _notifications[index]['is_read'] = true;
        });
        NotificationState.instance.updateFromNotifications(_notifications);
      }
    } catch (e) {
      // Handle error gracefully
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.substring(0, math.min(10, raw.length));
    
    final now = DateTime.now();
    final diff = now.difference(parsed);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) return 'Just now';
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    
    final d = parsed.day.toString().padLeft(2, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    return '$d/$m/${parsed.year}';
  }

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'ride_booked': return Icons.directions_car_outlined;
      case 'ride_created': return Icons.add_circle_outline;
      case 'ride_canceled': return Icons.cancel_outlined;
      case 'ride_completed': return Icons.check_circle_outline;
      default: return Icons.notifications_active_outlined;
    }
  }

  Color _getColorForType(String? type) {
    switch (type) {
      case 'ride_booked': return _kTeal;
      case 'ride_created': return _kBlue;
      case 'ride_canceled': return Colors.red;
      case 'ride_completed': return _kTeal;
      default: return _kNavy;
    }
  }

  String? _extractRouteSummary(String? msg) {
    if (msg == null || msg.isEmpty) return null;
    final match = RegExp(r'from\s+(.*?)\s+to\s+(.*?)(?:\.|\s|$)', caseSensitive: false).firstMatch(msg);
    if (match != null && match.groupCount >= 2) {
      final from = match.group(1)?.trim();
      final to = match.group(2)?.trim();
      if (from != null && to != null && from.isNotEmpty && to.isNotEmpty) {
        return '$from → $to';
      }
    }
    return null;
  }

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kNavy, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadNotifications,
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
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: _kNavy,
                            ),
                            children: [
                              TextSpan(text: 'My '),
                              TextSpan(
                                text: 'Alerts',
                                style: TextStyle(color: _kBlue),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _notifications.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey.shade400),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'No new notifications',
                                          style: TextStyle(fontSize: 18, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                    itemCount: _notifications.length,
                                    itemBuilder: (context, index) {
                                      final notif = _notifications[index];
                                      final isRead = notif['is_read'] == true;
                                      
                                      return GestureDetector(
                                        onTap: () async {
                                          if (!isRead) {
                                            _markAsRead(notif['id'].toString());
                                          }
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => NotificationDetailScreen(
                                                notification: notif,
                                              ),
                                            ),
                                          );
                                          _loadNotifications();
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: isRead ? Colors.white : const Color(0xFFF0F5FF),
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(isRead ? 0.04 : 0.08),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  color: _getColorForType(notif['type']).withOpacity(0.15),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  _getIconForType(notif['type']),
                                                  color: _getColorForType(notif['type']),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            notif['title']?.toString() ?? '',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                                              color: _kNavy,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          _formatDate(notif['created_at']?.toString()),
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors.grey.shade600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      notif['message']?.toString() ?? '',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.grey.shade700,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                    if (_extractRouteSummary(notif['message']?.toString()) != null) ...[
                                                        const SizedBox(height: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: _kBlue.withOpacity(0.08),
                                                            borderRadius: BorderRadius.circular(8),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const Icon(Icons.navigation_outlined, size: 12, color: _kBlue),
                                                              const SizedBox(width: 5),
                                                              Text(
                                                                _extractRouteSummary(notif['message']?.toString())!,
                                                                style: const TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight: FontWeight.w700,
                                                                  color: _kBlue,
                                                                ),
                                                             ),
                                                           ],
                                                         ),
                                                       ),
                                                     ],
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  Icons.chevron_right_rounded,
                                                  color: Colors.grey.shade400,
                                                  size: 20,
                                                ),
                                              ],
                                            ),
                                          ),
                                      );
                                    },
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

  Widget _buildBottomNav(
    double sc,
    double Function(double) f,
    double bottomInset,
  ) {
    return const AppBottomNavBar(currentTab: null);
  }
}
