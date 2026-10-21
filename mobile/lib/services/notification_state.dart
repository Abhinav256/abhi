import 'package:flutter/widgets.dart';
import 'api_service.dart';

/// Lightweight singleton that tracks whether the user has unread notifications.
///
/// All screens that need the dot indicator listen to this via [addListener] /
/// [ListenableBuilder] / [AnimatedBuilder], and call [refresh] when appropriate
/// (on init, after marking notifications read, on booking/ride actions, etc.).
class NotificationState extends ChangeNotifier with WidgetsBindingObserver {
  NotificationState._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final NotificationState instance = NotificationState._();

  final ApiService _api = ApiService();

  bool _hasUnread = false;
  bool get hasUnread => _hasUnread;

  bool _loading = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  /// Fetches notifications from the existing API and updates [hasUnread].
  /// Safe to call repeatedly — concurrent calls are coalesced.
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final notifs = await _api.getNotifications();
      updateFromNotifications(notifs);
    } catch (_) {
      // If the fetch fails, keep the previous state.
    } finally {
      _loading = false;
    }
  }

  /// Updates [hasUnread] directly from an existing notifications list without
  /// an extra network round-trip.
  void updateFromNotifications(List<dynamic> notifs) {
    final unread = notifs.any((n) => n is Map && n['is_read'] != true);
    if (unread != _hasUnread) {
      _hasUnread = unread;
      notifyListeners();
    }
  }

  /// Manually clears the unread state (e.g. on logout).
  void clearUnread() {
    if (_hasUnread) {
      _hasUnread = false;
      notifyListeners();
    }
  }
}
