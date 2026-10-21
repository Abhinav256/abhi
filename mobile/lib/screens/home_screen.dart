import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/api_service.dart';
import '../services/chat_state.dart';
import '../services/notification_state.dart';
import '../services/push_notification_service.dart';
import 'conversations_list_screen.dart';
import 'create_ride_screen.dart';
import 'my_bookings_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'search_rides_screen.dart';
import 'ride_details_screen.dart';
import 'provide_rating_screen.dart';
import 'wallet_screen.dart';
import 'support_screen.dart';
import '../widgets/app_bottom_nav_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final NotificationState _notifState = NotificationState.instance;
  final ChatState _chatState = ChatState.instance;

  VideoPlayerController? _videoController;
  bool _videoFailed = false;

  Map<String, dynamic>? _user;
  List<_UpcomingRide> _rides = [];

  bool _isLoading = true;
  bool _ridesLoading = true;
  String? _ridesError;

  // ---- Palette (from the reference) ----
  static const Color _navy = Color(0xFF0B1B3B);
  static const Color _blue = Color(0xFF0B4FD8);
  static const Color _green = Color(0xFF0E8A6A);
  static const Color _grey = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFF6F9FF);

  bool _isCheckingRating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initVideoController();
    _loadUser();
    _loadRides();
    _checkPendingRating();
    _notifState.refresh();
    _notifState.addListener(_onNotifChanged);
    _chatState.refresh();
    _chatState.addListener(_onChatChanged);
    PushNotificationService.instance.syncDeviceToken();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.dispose();
    _notifState.removeListener(_onNotifChanged);
    _chatState.removeListener(_onChatChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _notifState.refresh();
      _chatState.refresh();
    }
    if (_videoController == null || !_videoController!.value.isInitialized) return;
    if (state == AppLifecycleState.resumed) {
      _videoController!.play();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _videoController!.pause();
    }
  }

  Future<void> _initVideoController() async {
    try {
      final controller = VideoPlayerController.asset(
        'assets/video/animated_header.mp4',
      );
      _videoController = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0.0);
      if (mounted) {
        await controller.play();
        setState(() {});
      } else {
        await controller.dispose();
      }
    } catch (e) {
      debugPrint('[HomeScreen] Video header failed to load, falling back to static image: $e');
      if (mounted) {
        setState(() {
          _videoFailed = true;
        });
      }
    }
  }

  void _onNotifChanged() {
    if (mounted) setState(() {});
    _checkPendingRating();
  }

  void _onChatChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkPendingRating() async {
    if (_isCheckingRating || !mounted) return;
    _isCheckingRating = true;

    try {
      final res = await _apiService.getPendingRating();
      if (!mounted) return;

      if (res['has_pending_rating'] == true) {
        final participants = res['participants'] as List<dynamic>? ?? [];
        final hasUnrated = participants.any((p) => p is Map && p['already_rated'] != true);
        if (hasUnrated) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProvideRatingScreen(pendingData: res),
            ),
          );
          if (mounted) {
            _loadUser();
            _loadRides();
          }
        }
      }
    } catch (_) {
      // Ignore rating check errors silently
    } finally {
      _isCheckingRating = false;
    }
  }

  // -------------------------------------------------------------------
  // Data
  // -------------------------------------------------------------------

  Future<void> _loadUser() async {
    try {
      final user = await _apiService.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      // ScaffoldMessenger.of(
      //   context,
      // ).showSnackBar(SnackBar(content: Text('Failed to load user: $e')));
    }
  }

  /// Loads the user's bookings and created rides, and keeps only future ones, nearest first.
  /// Loads rides I booked and rides I created; keeps only future,
  /// active/confirmed ones, nearest first.
  Future<void> _loadRides() async {
    if (mounted) {
      setState(() {
        _ridesLoading = true;
        _ridesError = null;
      });
    }

    try {
      final List<dynamic> results = await Future.wait([
        _apiService.getMyBookings(),
        _apiService.getMyRides(),
      ]);

      final List<_UpcomingRide> all = [
        ..._parseRides(results[0], _RideSource.booked),
        ..._parseRides(results[1], _RideSource.created),
      ];

      const okStatuses = {'active', 'confirmed', 'draft', 'selfie_uploaded'};
      final now = DateTime.now();
      final Map<String, _UpcomingRide> unique = {};

      for (final r in all) {
        if (r.when == null) continue;
        
        // Hide rides that are past their estimated arrival time
        // If there's no estimated arrival time, default to departure + 24h
        final expiryTime = r.estimatedArrival ?? r.when!.add(const Duration(hours: 24));
        if (expiryTime.isBefore(now)) continue;
        
        if (r.status != null && !okStatuses.contains(r.status)) continue;
        if (r.rideStatus != null && !okStatuses.contains(r.rideStatus)) continue;

        final key = '${r.source.name}-${r.id}-${r.when!.millisecondsSinceEpoch}';
        unique[key] = r;
      }

      final upcoming = unique.values.toList()
        ..sort((a, b) => a.when!.compareTo(b.when!));

      await Future.wait(upcoming.take(3).map(_enrich));

      if (!mounted) return;
      setState(() {
        _rides = upcoming;
        _ridesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ridesLoading = false;
        _ridesError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<_UpcomingRide> _parseRides(dynamic raw, _RideSource source) {
    final List<dynamic> items = [];

    if (raw is List) {
      items.addAll(raw);
    } else if (raw is Map) {
      for (final key in const [
        'bookings',
        'booked',
        'booked_rides',
        'created',
        'created_rides',
        'rides',
        'data',
      ]) {
        final v = raw[key];
        if (v is List) items.addAll(v);
      }
    }

    return items
        .whereType<Map>()
        .map((m) =>
            _UpcomingRide.fromJson(Map<String, dynamic>.from(m), source))
        .toList();
  }

  /// Bookings don't carry the driver's name/selfie, so fetch the ride.
  Future<void> _enrich(_UpcomingRide r) async {
    if (r.source != _RideSource.booked || r.rideId.isEmpty) return;
    if (r.nameKnown && r.photoUrl != null) return;

    try {
      // Use the same ApiService method RideDetailsScreen uses.
      final dynamic d =
          await (_apiService as dynamic).getRideDetail(rideId: r.rideId);
      if (d is! Map) return;

      final Map<String, dynamic> m = {
        ...Map<String, dynamic>.from(d),
        if (d['ride'] is Map) ...Map<String, dynamic>.from(d['ride']),
      };
      final Map<String, dynamic> driver = m['driver'] is Map
          ? Map<String, dynamic>.from(m['driver'])
          : <String, dynamic>{};

      final n = _UpcomingRide._pick(driver, const ['full_name', 'name']) ??
          _UpcomingRide._pick(m, const ['driver_name', 'driver_full_name']);
      final p = _UpcomingRide._pick(driver, const ['driver_selfie_url', 'profile_photo']) ??
          _UpcomingRide._pick(m, const ['driver_selfie_url', 'driver_photo']);
      final s = _UpcomingRide._pick(m, const ['available_seats', 'seats_available', 'seats_left']);

      if (n != null) {
        r.name = n.toString();
        r.nameKnown = true;
      }
      if (p != null) r.photoUrl = p.toString();
      if (s != null) r.seatsLeft = int.tryParse(s.toString());
    } catch (_) {
      // Keep the fallback card if details can't be loaded.
    }
  }

  // -------------------------------------------------------------------
  // Navigation (existing screens only)
  // -------------------------------------------------------------------

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) {
      _loadUser();
      _loadRides();
      _notifState.refresh();
    }
  }

  void _openSearch() => _push(const SearchRidesScreen());
  void _openCreate() => _push(const CreateRideScreen());
  void _openBookings() => _push(const MyBookingsScreen());
  void _openProfile() => _push(const ProfileScreen());
  void _openChat() => _push(const ConversationsListScreen());
  void _openAlerts() => _push(const NotificationsScreen());
  void _openWallet() => _push(const WalletScreen());
  void _openSupport() => _push(const SupportScreen());

  // -------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------

  String _formatCurrency(num amount) {
    if (amount == 0) return '₹0';
    final isInt = amount % 1 == 0;
    final numStr = isInt ? amount.toInt().toString() : amount.toStringAsFixed(2);
    final parts = numStr.split('.');
    String whole = parts[0];
    final dec = parts.length > 1 ? '.${parts[1]}' : '';

    if (whole.length > 3) {
      final last3 = whole.substring(whole.length - 3);
      final rest = whole.substring(0, whole.length - 3);
      final buffer = StringBuffer();
      for (int i = 0; i < rest.length; i++) {
        if (i > 0 && (rest.length - i) % 2 == 0) {
          buffer.write(',');
        }
        buffer.write(rest[i]);
      }
      whole = '${buffer.toString()},$last3';
    }
    return '₹$whole$dec';
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning,';
    if (h < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  String _displayName() {
    final nickname = _user?['nickname']?.toString().trim();
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;
    }
    final full = _user?['full_name']?.toString().trim() ?? '';
    if (full.isEmpty) return 'there';
    return full;
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final double w = math.min(media.size.width, 520);
    final double sc = w / 935; // reference image is 935 px wide
    double f(double px) => px * sc * 1.1; // font size, slightly bumped

    return Scaffold(
      backgroundColor: _bg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SizedBox(
                width: w,
                child: Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          await Future.wait([_loadUser(), _loadRides()]);
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTop(w, sc, f, media.padding.top),
                              SizedBox(height: 32 * sc),
                              _buildSearchBar(sc, f),
                              SizedBox(height: 52 * sc),
                              _buildUpcomingHeader(sc, f),
                              SizedBox(height: 26 * sc),
                              _buildRides(sc, f),
                              SizedBox(height: 30 * sc),
                            ],
                          ),
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

  Widget _buildHeaderBackground(double headerH) {
    final bool isVideoReady = _videoController != null &&
        _videoController!.value.isInitialized &&
        !_videoFailed;

    return IgnorePointer(
      child: SizedBox(
        height: headerH,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Static illustrated road fallback
            Image.asset(
              'assets/images/home_header.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, _, _) => CustomPaint(painter: _HeaderPainter()),
            ),
            // Animated Header Video once initialized
            if (isVideoReady)
              ClipRect(
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: _videoController!.value.size.width > 0
                          ? _videoController!.value.size.width
                          : 16,
                      height: _videoController!.value.size.height > 0
                          ? _videoController!.value.size.height
                          : 9,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- Header + action cards ----------------------------------------

  Widget _buildTop(
    double w,
    double sc,
    double Function(double) f,
    double topInset,
  ) {
    final double ti = topInset * 0.4;
    final double headerH = 477 * sc + ti;
    final double statCardsTop = 416 * sc + ti;
    final double statCardsH = 250 * sc;
    final double statCardGap = 15 * sc;
    final double actionCardsTop = statCardsTop + statCardsH + 30 * sc;
    final double cardsH = 246 * sc;

    return SizedBox(
      height: actionCardsTop + cardsH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Animated Video Header Background (with static fallback)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: headerH,
            child: _buildHeaderBackground(headerH),
          ),

          // Logo + name
          Positioned(
            top: 62 * sc + ti,
            left: 60 * sc,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 10 * sc),
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: f(44),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                    children: const [
                      TextSpan(text: 'Abhi', style: TextStyle(color: _blue)),
                      TextSpan(text: 'Share', style: TextStyle(color: _green)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Chat & Notifications
          Positioned(
            top: 68 * sc + ti,
            right: 48 * sc,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, color: _navy, size: 52 * sc),
                      if (_chatState.hasUnread)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: _blue,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              _chatState.unreadCount > 9 ? '9+' : '${_chatState.unreadCount}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: _openChat,
                ),
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.notifications_none_rounded, color: _navy, size: 56 * sc),
                      if (_notifState.hasUnread)
                        Positioned(
                          right: 1,
                          top: 1,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4B5B),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: _openAlerts,
                ),
              ],
            ),
          ),

          // Greeting
          Positioned(
            top: 172 * sc + ti,
            left: 74 * sc,
            right: 40 * sc,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: TextStyle(fontSize: f(31), color: _grey),
                ),
                SizedBox(height: 2 * sc),
                Row(
                  children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: f(50),
                            fontWeight: FontWeight.w800,
                            color: _navy,
                            height: 1.1,
                          ),
                          children: [
                            const TextSpan(text: 'Hey, '),
                            TextSpan(
                              text: '${_displayName()}!',
                              style: const TextStyle(color: _blue),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 56 * sc),
                    // Icon(
                    //   Icons.location_on,
                    //   size: 58 * sc,
                    //   color: const Color(0xFF8EC5F5).withValues(alpha: 0.85),
                    // ),
                  ],
                ),
                SizedBox(height: 2 * sc),
                Text(
                  'Where are you heading today?',
                  style: TextStyle(fontSize: f(29), color: _grey),
                ),
              ],
            ),
          ),

          // 3 Dynamic Statistics Cards
          Positioned(
            top: statCardsTop,
            left: 31 * sc,
            right: 28 * sc,
            height: statCardsH,
            child: Row(
              children: [
                Expanded(child: _buildRidesTakenCard(sc, f)),
                SizedBox(width: statCardGap),
                Expanded(child: _buildRatingCard(sc, f)),
                SizedBox(width: statCardGap),
                Expanded(child: _buildMoneyEarnedCard(sc, f)),
              ],
            ),
          ),

          // Action cards
          Positioned(
            top: actionCardsTop,
            left: 40 * sc,
            right: 38 * sc,
            height: cardsH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 428, child: _createCard(sc, f)),
                SizedBox(width: 24 * sc),
                Expanded(flex: 405, child: _searchCard(sc, f)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required double sc,
    required double Function(double) f,
    required Widget iconBadge,
    required Widget sparkline,
    required String value,
    required String label,
    required Widget chevronBtn,
    required VoidCallback onTap,
    required List<Color> gradient,
    double? valueFontSize,
  }) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.2),
          borderRadius: BorderRadius.circular(34 * sc),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0B1B3B).withValues(alpha: 0.06),
              blurRadius: 16 * sc,
              offset: Offset(0, 7 * sc),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(34 * sc),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(22 * sc, 22 * sc, 18 * sc, 20 * sc),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    iconBadge,
                    sparkline,
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: valueFontSize ?? f(38),
                        fontWeight: FontWeight.w800,
                        color: _navy,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 3 * sc),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: f(22),
                              fontWeight: FontWeight.w500,
                              color: _grey,
                            ),
                          ),
                        ),
                        chevronBtn,
                      ],
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

  Widget _chevronCircle(double sc, Color bg, Color fg) => Container(
        width: 44 * sc,
        height: 44 * sc,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(Icons.chevron_right_rounded, color: fg, size: 28 * sc),
      );

  Widget _buildRidesTakenCard(double sc, double Function(double) f) {
    final totalRides = int.tryParse(_user?['total_rides_taken']?.toString() ?? '0') ?? 0;
    return _statCard(
      sc: sc,
      f: f,
      gradient: const [Color(0xFFF1F6FF), Color(0xFFE3EEFD)],
      iconBadge: Container(
        width: 92 * sc,
        height: 92 * sc,
        decoration: const BoxDecoration(
          color: Color(0xFFD9E7FC),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.directions_car_filled,
          color: const Color(0xFF1D6EE5),
          size: 50 * sc,
        ),
      ),
      sparkline: SizedBox(
        width: 104 * sc,
        height: 44 * sc,
        child: CustomPaint(
          painter: _SparklinePainter(
            color: const Color(0xFF75A9F9),
            strokeWidth: 2.4 * sc,
          ),
        ),
      ),
      value: '$totalRides',
      label: 'Rides Taken',
      chevronBtn: _chevronCircle(sc, const Color(0xFFD9E7FC), const Color(0xFF1D6EE5)),
      onTap: _openBookings,
    );
  }

  Widget _buildRatingCard(double sc, double Function(double) f) {
    final rawAvg = _user?['average_rating'];
    final totalRatings = int.tryParse(_user?['total_ratings']?.toString() ?? '0') ?? 0;
    final double? avgRating = rawAvg != null ? double.tryParse(rawAvg.toString()) : null;

    final String ratingStr = avgRating != null && avgRating > 0
        ? avgRating.toStringAsFixed(1)
        : (totalRatings > 0 ? '0.0' : '5.0');

    return _statCard(
      sc: sc,
      f: f,
      gradient: const [Color(0xFFFFFAEC), Color(0xFFFEF1D4)],
      iconBadge: Container(
        width: 92 * sc,
        height: 92 * sc,
        decoration: const BoxDecoration(
          color: Color(0xFFFDEBC0),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.star_rounded,
          color: const Color(0xFFF59E0B),
          size: 58 * sc,
        ),
      ),
      sparkline: SizedBox(
        width: 104 * sc,
        height: 44 * sc,
        child: CustomPaint(
          painter: _SparklinePainter(
            color: const Color(0xFFFBBF24),
            strokeWidth: 2.4 * sc,
          ),
        ),
      ),
      value: ratingStr,
      label: 'Rating',
      chevronBtn: _chevronCircle(sc, const Color(0xFFFDEBC0), const Color(0xFFD97706)),
      onTap: _openProfile,
    );
  }

  Widget _buildMoneyEarnedCard(double sc, double Function(double) f) {
    final moneyEarned = num.tryParse(_user?['money_earned']?.toString() ?? '0') ?? 0;
    final moneyStr = _formatCurrency(moneyEarned);

    return _statCard(
      sc: sc,
      f: f,
      gradient: const [Color(0xFFF2FCF7), Color(0xFFDFF6EA)],
      iconBadge: Container(
        width: 92 * sc,
        height: 92 * sc,
        decoration: const BoxDecoration(
          color: Color(0xFFD3F1E2),
          shape: BoxShape.circle,
        ),
        padding: EdgeInsets.all(22 * sc),
        child: CustomPaint(
          painter: const _MoneyBagPainter(bagColor: Color(0xFF0E8A6A)),
        ),
      ),
      sparkline: SizedBox(
        width: 104 * sc,
        height: 44 * sc,
        child: CustomPaint(
          painter: _SparklinePainter(
            color: const Color(0xFF34D399),
            strokeWidth: 2.4 * sc,
          ),
        ),
      ),
      value: moneyStr,
      valueFontSize: moneyStr.length > 7 ? f(30) : (moneyStr.length > 5 ? f(34) : f(38)),
      label: 'Money Earned',
      chevronBtn: _chevronCircle(sc, const Color(0xFFD3F1E2), const Color(0xFF059669)),
      onTap: _openWallet,
    );
  }

  Widget _createCard(double sc, double Function(double) f) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(44 * sc),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1F77E8), Color(0xFF0A3FB5)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0B4FD8).withOpacity(0.30),
              blurRadius: 24 * sc,
              offset: Offset(0, 10 * sc),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(44 * sc),
          onTap: _openCreate,
          child: Stack(
            children: [
              Positioned(
                top: 40 * sc,
                left: 40 * sc,
                child: Text(
                  'Create\nRide',
                  style: TextStyle(
                    fontSize: f(35),
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
              ),
              Positioned(
                left: 40 * sc,
                bottom: 58 * sc,
                child: Text(
                  'Share your route',
                  style: TextStyle(
                    fontSize: f(24),
                    color: Colors.white.withOpacity(0.92),
                  ),
                ),
              ),
              Positioned(
                right: 34 * sc,
                bottom: 32 * sc,
                child: Container(
                  width: 82 * sc,
                  height: 82 * sc,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: Icon(
                    Icons.arrow_forward,
                    color: const Color(0xFF1F6FE8),
                    size: 42 * sc,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchCard(double sc, double Function(double) f) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(44 * sc),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFE3F6EE)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 24 * sc,
              offset: Offset(0, 10 * sc),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(44 * sc),
          onTap: _openSearch,
          child: Stack(
            children: [
              Positioned(
                top: 40 * sc,
                left: 40 * sc,
                child: Text(
                  'Search\nRide',
                  style: TextStyle(
                    fontSize: f(35),
                    fontWeight: FontWeight.w800,
                    color: _navy,
                    height: 1.25,
                  ),
                ),
              ),
              Positioned(
                left: 40 * sc,
                bottom: 58 * sc,
                child: Text(
                  'Find safe rides',
                  style: TextStyle(fontSize: f(24), color: _grey),
                ),
              ),
              Positioned(
                right: 36 * sc,
                bottom: 32 * sc,
                child: Container(
                  width: 82 * sc,
                  height: 82 * sc,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF12A070),
                  ),
                  child: Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 42 * sc,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Search bar -----------------------------------------------------

  Widget _buildSearchBar(double sc, double Function(double) f) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 42 * sc),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 103 * sc,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(52 * sc),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B4FD8).withOpacity(0.08),
                blurRadius: 22 * sc,
                offset: Offset(0, 8 * sc),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(52 * sc),
            onTap: _openSearch,
            child: Row(
              children: [
                SizedBox(width: 26 * sc),
                Container(
                  width: 72 * sc,
                  height: 72 * sc,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFE6F0FE),
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: _blue,
                    size: 38 * sc,
                  ),
                ),
                SizedBox(width: 30 * sc),
                Expanded(
                  child: Text(
                    'Where do you want to go?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: f(29), color: _grey),
                  ),
                ),
                Container(
                  width: 158 * sc,
                  height: 76 * sc,
                  margin: EdgeInsets.only(right: 14 * sc),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(38 * sc),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1668D8), Color(0xFF0A45B8)],
                    ),
                  ),
                  child: Text(
                    'Go',
                    style: TextStyle(
                      fontSize: f(29),
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Upcoming rides -------------------------------------------------

  Widget _buildUpcomingHeader(double sc, double Function(double) f) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 50 * sc),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Upcoming Rides',
            style: TextStyle(
              fontSize: f(36),
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          InkWell(
            onTap: _openBookings,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                children: [
                  Text(
                    'See all',
                    style: TextStyle(
                      fontSize: f(27),
                      fontWeight: FontWeight.w600,
                      color: _blue,
                    ),
                  ),
                  SizedBox(width: 6 * sc),
                  Icon(Icons.chevron_right, color: _blue, size: 36 * sc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRides(double sc, double Function(double) f) {
    if (_ridesLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 60 * sc),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_ridesError != null) {
      return _messageCard(
        sc,
        f,
        icon: Icons.cloud_off_outlined,
        title: 'Couldn\'t load your rides',
        subtitle: _ridesError!,
        actionLabel: 'Retry',
        onAction: _loadRides,
      );
    }

    if (_rides.isEmpty) {
      return _messageCard(
        sc,
        f,
        icon: Icons.directions_car_outlined,
        title: 'No upcoming rides',
        subtitle: 'Rides you book or create will show up here.',
        actionLabel: 'Find a ride',
        onAction: _openSearch,
      );
    }

    // Reference shows three cards; the rest live under "See all".
    final visible = _rides.take(3).toList();

    return Column(
      children: [
        for (final ride in visible)
          Padding(
            padding: EdgeInsets.only(bottom: 23 * sc),
            child: _rideCard(ride, sc, f),
          ),
      ],
    );
  }

  Widget _messageCard(
    double sc,
    double Function(double) f, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 42 * sc),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 44 * sc, horizontal: 36 * sc),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(36 * sc),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20 * sc,
              offset: Offset(0, 8 * sc),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 110 * sc,
              height: 110 * sc,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE6F0FE),
              ),
              child: Icon(icon, color: _blue, size: 56 * sc),
            ),
            SizedBox(height: 22 * sc),
            Text(
              title,
              style: TextStyle(
                fontSize: f(31),
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
            SizedBox(height: 8 * sc),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: f(25), color: _grey),
            ),
            SizedBox(height: 22 * sc),
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel,
                style: TextStyle(
                  fontSize: f(27),
                  fontWeight: FontWeight.w700,
                  color: _blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rideCard(_UpcomingRide r, double sc, double Function(double) f) {
    final double avatar = 116 * sc;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 42 * sc),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(38 * sc),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B4FD8).withOpacity(0.07),
                blurRadius: 22 * sc,
                offset: Offset(0, 8 * sc),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(38 * sc),
            onTap: () {
              if (r.rideId.isNotEmpty) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RideDetailsScreen(rideId: r.rideId),
                  ),
                ).then((_) {
                  if (mounted) {
                    _loadUser();
                    _loadRides();
                  }
                });
              }
            },
            child: Padding(
              padding: EdgeInsets.fromLTRB(28 * sc, 24 * sc, 30 * sc, 24 * sc),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  SizedBox(
                    width: avatar,
                    height: avatar,
                    child: _avatar(r, avatar, f),
                  ),
                  SizedBox(width: 30 * sc),

                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.source == _RideSource.created
                                    ? (_user?['full_name']?.toString() ?? 'Your ride')
                                    : r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: f(32),
                                  fontWeight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: _grey,
                              size: 40 * sc,
                            ),
                          ],
                        ),
                        if (r.isWomenOnly) ...[
                          SizedBox(height: 8 * sc),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10 * sc, vertical: 3 * sc),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCE4EC),
                              borderRadius: BorderRadius.circular(10 * sc),
                              border: Border.all(color: const Color(0xFFF48FB1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.female, size: 16 * sc, color: const Color(0xFFD81B60)),
                                SizedBox(width: 4 * sc),
                                Text(
                                  'Women Only',
                                  style: TextStyle(
                                    color: const Color(0xFFD81B60),
                                    fontWeight: FontWeight.bold,
                                    fontSize: f(20),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        SizedBox(height: 18 * sc),
                        Row(
                          children: [
                            _dot(const Color(0xFF12A070), sc),
                            SizedBox(width: 10 * sc),
                            Flexible(
                              child: Text(
                                r.from,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: f(26),
                                  color: const Color(0xFF374151),
                                ),
                              ),
                            ),
                            SizedBox(width: 12 * sc),
                            Icon(Icons.arrow_forward, size: 26 * sc, color: _grey),
                            SizedBox(width: 12 * sc),
                            _dot(const Color(0xFFEF4B5B), sc),
                            SizedBox(width: 10 * sc),
                            Flexible(
                              child: Text(
                                r.to,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: f(26),
                                  color: const Color(0xFF374151),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 25 * sc),
                        Row(
                          children: [
                            if (r.when != null) ...[
                              Icon(Icons.schedule, size: 28 * sc, color: _grey),
                              SizedBox(width: 6 * sc),
                              Text(
                                _formatWhen(r.when!),
                                style: TextStyle(fontSize: f(24), color: _grey),
                              ),
                            ],
                            if (r.seatsLeft != null) ...[
                              SizedBox(width: 14 * sc),
                              Icon(Icons.person_outline, size: 30 * sc, color: _grey),
                              SizedBox(width: 4 * sc),
                              Text(
                                '${r.seatsLeft} seat${r.seatsLeft == 1 ? '' : 's'} left',
                                style: TextStyle(fontSize: f(24), color: _grey),
                              ),
                            ],
                            const Spacer(),
                            if (r.price != null)
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '₹${_fmtPrice(r.price!)}',
                                      style: TextStyle(
                                        fontSize: f(34),
                                        fontWeight: FontWeight.w800,
                                        color: _blue,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '/seat',
                                      style: TextStyle(fontSize: f(24), color: _grey),
                                    ),
                                  ],
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
          ),
        ),
      ),
    );
  }

  Widget _dot(Color c, double sc) => Container(
        width: 20 * sc,
        height: 20 * sc,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _avatar(_UpcomingRide r, double size, double Function(double) f) {
    final hasPhoto = r.photoUrl != null && r.photoUrl!.isNotEmpty;
    final photoUrl = hasPhoto 
        ? (r.photoUrl!.startsWith('http') ? r.photoUrl! : '${ApiService.baseUrl}${r.photoUrl}')
        : null;

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF1B6BB8), Color(0xFF0E8A6A)],
        ),
      ),
      child: ClipOval(
        child: photoUrl != null
            ? Image.network(
                photoUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  r.source == _RideSource.created
                      ? Icons.directions_car_filled
                      : Icons.confirmation_num_outlined,
                  color: Colors.white,
                  size: size * 0.48,
                ),
              )
            : Icon(
                r.source == _RideSource.created
                    ? Icons.directions_car_filled
                    : Icons.confirmation_num_outlined,
                color: Colors.white,
                size: size * 0.48,
              ),
      ),
    );
  }

  // ---- Bottom navigation ----------------------------------------------

  Widget _buildBottomNav(
    double sc,
    double Function(double) f,
    double bottomInset,
  ) {
    return AppBottomNavBar(
      currentTab: AppNavTab.home,
      onTabSelected: (tab) {
        switch (tab) {
          case AppNavTab.home:
            break;
          case AppNavTab.rides:
            _openBookings();
            break;
          case AppNavTab.wallet:
            _openWallet();
            break;
          case AppNavTab.support:
            _openSupport();
            break;
          case AppNavTab.profile:
            _openProfile();
            break;
        }
      },
    );
  }

  // ---- Formatting -------------------------------------------------------

  String _fmtPrice(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _formatWhen(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;

    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour12:$min $ampm';

    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Tomorrow, $time';
    
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    
    if (diff < 7) return '${days[d.weekday - 1]}, $time';
    return '$dd/$mm/${d.year}, $time';
  }
}

// =========================================================================
// Model (parsed from whatever the API returns; nothing is hardcoded)
// =========================================================================

enum _RideSource { booked, created }

class _UpcomingRide {
  final String id;
  final String rideId;
  final _RideSource source;
  String name;
  final String from;
  final String to;
  final DateTime? when;
  final DateTime? estimatedArrival;
  int? seatsLeft;
  final num? price;
  final double? rating;
  String? photoUrl;
  final String? status;
  final String? rideStatus;
  final bool isWomenOnly;
  bool nameKnown = false;

  _UpcomingRide({
    required this.id,
    required this.rideId,
    required this.source,
    required this.name,
    required this.from,
    required this.to,
    this.when,
    this.estimatedArrival,
    this.seatsLeft,
    this.price,
    this.rating,
    this.photoUrl,
    this.status,
    this.rideStatus,
    this.isWomenOnly = false,
  });

  static dynamic _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) return v;
    }
    return null;
  }

  /// journey_date ("2026-09-30T00:00:00Z") + departure_time
  /// ("0000-01-01T15:30:00Z" or "15:30"). Only the clock part of the time
  /// is used, so the placeholder year 0000 can never leak in.
  static DateTime? _parseWhen(Map<String, dynamic> m) {
    final dateRaw =
        _pick(m, const ['journey_date', 'ride_date', 'departure_date', 'date']);
    final timeRaw = _pick(m, const ['departure_time', 'ride_time', 'time']);

    if (dateRaw != null) {
      final d = DateTime.tryParse(
        dateRaw.toString().split('T').first.split(' ').first,
      );
      if (d != null) {
        int h = 0, min = 0;
        if (timeRaw != null) {
          var t = timeRaw.toString();
          if (t.contains('T')) t = t.split('T')[1];
          final parts = t.split(':');
          if (parts.length >= 2) {
            h = int.tryParse(parts[0]) ?? 0;
            min = int.tryParse(parts[1]) ?? 0;
          }
        }
        return DateTime(d.year, d.month, d.day, h, min);
      }
    }

    final combined = _pick(m, const [
      'departure_datetime',
      'departure_at',
      'ride_datetime',
      'start_time',
      'date_time',
      'datetime',
    ]);
    if (combined != null) {
      final p = DateTime.tryParse(combined.toString());
      if (p != null && p.year > 1) return p.toLocal();
    }
    return null;
  }
  
  static DateTime? _parseArrival(Map<String, dynamic> m, DateTime? departure) {
    final timeRaw = _pick(m, const ['estimated_arrival_time', 'arrival_time', 'arrival']);
    if (timeRaw != null && departure != null) {
        var t = timeRaw.toString();
        if (t.contains('T')) t = t.split('T')[1];
        final parts = t.split(':');
        if (parts.length >= 2) {
          int h = int.tryParse(parts[0]) ?? 0;
          int min = int.tryParse(parts[1]) ?? 0;
          return DateTime(departure.year, departure.month, departure.day, h, min);
        }
    }
    return null;
  }

  factory _UpcomingRide.fromJson(
    Map<String, dynamic> json,
    _RideSource source,
  ) {
    final Map<String, dynamic> m = {
      ...json,
      if (json['ride'] is Map) ...Map<String, dynamic>.from(json['ride']),
    };

    final Map<String, dynamic> driver = m['driver'] is Map
        ? Map<String, dynamic>.from(m['driver'])
        : <String, dynamic>{};

    final driverName = _pick(driver, const ['full_name', 'name']) ??
        _pick(m, const ['driver_name', 'driver_full_name']);

    final String name = source == _RideSource.created
        ? 'Your ride'
        : (driverName ?? 'Booked ride').toString();

    final rating = _pick(driver, const ['rating', 'average_rating']) ??
        _pick(m, const ['driver_rating']);

    // Ensure seats are extracted from the raw data
    final seats = _pick(m, const ['available_seats', 'seats_available', 'seats_left']);

    final price = source == _RideSource.created
        ? _pick(m, const [
            'user_amount',
            'price_per_seat',
            'fare_per_seat',
            'price',
            'fare',
          ])
        : _pick(m, const [
            'total_amount',
            'price_per_seat',
            'fare_per_seat',
            'price',
            'fare',
          ]);

    final ride = _UpcomingRide(
      id: (_pick(json, const ['id', 'booking_id']) ?? '').toString(),
      rideId: (_pick(m, const ['ride_id', 'id']) ?? '').toString(),
      source: source,
      name: name,
      from: (_pick(m, const [
                'from_location',
                'origin',
                'source',
                'from',
                'pickup_location',
                'start_location',
              ]) ??
              '')
          .toString(),
      to: (_pick(m, const [
                'to_location',
                'destination',
                'to',
                'drop_location',
                'end_location',
              ]) ??
              '')
          .toString(),
      when: _parseWhen(m),
      estimatedArrival: _parseArrival(m, _parseWhen(m)),
      seatsLeft: seats == null ? null : int.tryParse(seats.toString()),
      price: price == null ? null : num.tryParse(price.toString()),
      rating: rating == null ? null : double.tryParse(rating.toString()),
      photoUrl: (_pick(driver, const ['driver_selfie_url', 'profile_photo', 'avatar', 'photo_url']) ??
              _pick(m, const ['driver_selfie_url', 'driver_photo']))
          ?.toString(),
      status: _pick(m, const ['status'])?.toString().toLowerCase(),
      rideStatus: _pick(m, const ['ride_status'])?.toString().toLowerCase(),
      isWomenOnly: m['is_women_only'] == true,
    );
    ride.nameKnown = source == _RideSource.created || driverName != null;
    return ride;
  }
}


// =========================================================================
// Painters
// =========================================================================


class _HeaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Work in the reference coordinate system (935 wide) and scale.
    final s = size.width / 935;
    canvas.save();
    canvas.scale(s);

    final double totalH = size.height / s;

    // Soft background gradient
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 935, totalH),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAF3FF), Color(0xFFF3F7FD), Color(0xFFF6F9FF)],
        ).createShader(Rect.fromLTWH(0, 0, 935, totalH)),
    );

    // Decorative corner shapes
    canvas.drawCircle(
      const Offset(20, 40),
      120,
      Paint()..color = const Color(0xFFD9F1E6).withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      const Offset(900, 20),
      130,
      Paint()..color = const Color(0xFFD6E8FB).withValues(alpha: 0.8),
    );
    canvas.drawCircle(
      const Offset(728, 110),
      36,
      Paint()..color = const Color(0xFFCDEBDD).withValues(alpha: 0.75),
    );

    // Pale hill behind the skyline
    final hillBack = Path()
      ..moveTo(400, 280)
      ..cubicTo(540, 90, 780, 80, 935, 145)
      ..lineTo(935, 340)
      ..lineTo(400, 340)
      ..close();
    canvas.drawPath(
      hillBack,
      Paint()..color = const Color(0xFFDCEBFB).withValues(alpha: 0.7),
    );

    // Skyline modern towers
    final skyPaint = Paint()..color = const Color(0xFFA9CDF5).withValues(alpha: 0.85);
    final skyLight = Paint()..color = const Color(0xFFC6DDF7).withValues(alpha: 0.85);
    void tower(double x, double top, double w, Paint p) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, w, 335 - top),
          const Radius.circular(6),
        ),
        p,
      );
    }

    tower(475, 230, 44, skyLight);
    tower(530, 205, 50, skyLight);
    tower(592, 175, 58, skyPaint);
    tower(662, 145, 66, skyPaint);
    tower(740, 125, 62, skyPaint);
    tower(814, 160, 68, skyPaint);
    tower(892, 195, 43, skyLight);

    // Green hill under the road
    final greenRight = Path()
      ..moveTo(510, 328)
      ..cubicTo(660, 290, 800, 220, 935, 180)
      ..lineTo(935, 340)
      ..lineTo(510, 340)
      ..close();
    canvas.drawPath(
      greenRight,
      Paint()..color = const Color(0xFF5CC08A).withValues(alpha: 0.85),
    );

    // Green left hill
    final greenHill = Path()
      ..moveTo(0, 245)
      ..cubicTo(85, 250, 180, 290, 280, 324)
      ..lineTo(280, 335)
      ..lineTo(0, 335)
      ..close();
    canvas.drawPath(
      greenHill,
      Paint()..color = const Color(0xFFB9E6D3).withValues(alpha: 0.8),
    );

    // Blue left curved hill
    final blueHill = Path()
      ..moveTo(0, 285)
      ..cubicTo(110, 280, 210, 312, 380, 324)
      ..lineTo(380, 335)
      ..quadraticBezierTo(190, 332, 0, 335)
      ..close();
    canvas.drawPath(
      blueHill,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF1F7CE8), Color(0xFF6EC0F0)],
        ).createShader(const Rect.fromLTWH(0, 260, 400, 80)),
    );

    // Lush trees along the road and hillside
    final tree = Paint()..color = const Color(0xFF4DB57A);
    for (final o in const [
      Offset(390, 308),
      Offset(435, 298),
      Offset(505, 288),
      Offset(565, 276),
      Offset(635, 258),
      Offset(710, 238),
      Offset(795, 212),
      Offset(870, 190),
      Offset(915, 172),
    ]) {
      canvas.drawCircle(o, 20, tree);
    }

    final treeAccent = Paint()..color = const Color(0xFF3BA669);
    for (final o in const [
      Offset(465, 318),
      Offset(600, 298),
      Offset(755, 256),
      Offset(840, 230),
    ]) {
      canvas.drawCircle(o, 16, treeAccent);
    }

    // Winding Highway: wide smooth blue road
    final road = Path()
      ..moveTo(360, 322)
      ..cubicTo(540, 322, 740, 268, 935, 206);
    canvas.drawPath(
      road,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 44
        ..strokeCap = StrokeCap.butt
        ..color = const Color(0xFF1B5CD6),
    );

    // Dashed centre line
    for (final metric in road.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final seg = metric.extractPath(d, math.min(d + 24, metric.length));
        canvas.drawPath(
          seg,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.8
            ..color = Colors.white.withValues(alpha: 0.92),
        );
        d += 42;
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SparklinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _SparklinePainter({
    required this.color,
    this.strokeWidth = 2.4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(0, size.height * 0.70);
    path.cubicTo(
      size.width * 0.22, size.height * 0.85,
      size.width * 0.38, size.height * 0.15,
      size.width * 0.54, size.height * 0.35,
    );
    path.cubicTo(
      size.width * 0.70, size.height * 0.55,
      size.width * 0.84, size.height * 0.15,
      size.width, size.height * 0.10,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

class _MoneyBagPainter extends CustomPainter {
  final Color bagColor;
  const _MoneyBagPainter({required this.bagColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = bagColor
      ..style = PaintingStyle.fill;

    // Tied top ruffle
    final ruffle = Path()
      ..moveTo(w * 0.35, h * 0.14)
      ..lineTo(w * 0.28, 0)
      ..lineTo(w * 0.72, 0)
      ..lineTo(w * 0.65, h * 0.14)
      ..close();
    canvas.drawPath(ruffle, paint);

    // Tie knot
    final knotPaint = Paint()
      ..color = bagColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.32, h * 0.12, w * 0.36, h * 0.08),
        Radius.circular(h * 0.04),
      ),
      knotPaint,
    );

    // Pouch body
    final body = Path()
      ..moveTo(w * 0.38, h * 0.18)
      ..cubicTo(w * 0.12, h * 0.30, 0, h * 0.60, w * 0.06, h * 0.86)
      ..cubicTo(w * 0.10, h * 0.99, w * 0.90, h * 0.99, w * 0.94, h * 0.86)
      ..cubicTo(w, h * 0.60, w * 0.88, h * 0.30, w * 0.62, h * 0.18)
      ..close();
    canvas.drawPath(body, paint);

    // Rupee symbol centered on bag
    final tp = TextPainter(
      text: TextSpan(
        text: '₹',
        style: TextStyle(
          color: Colors.white,
          fontSize: h * 0.44,
          fontWeight: FontWeight.w800,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(
        (w - tp.width) / 2,
        h * 0.34,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _MoneyBagPainter oldDelegate) =>
      oldDelegate.bagColor != bagColor;
}