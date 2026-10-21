import 'package:flutter/widgets.dart';
import 'api_service.dart';

/// Lightweight singleton that tracks total unread in-app chat messages.
///
/// Any screen needing unread indicators (e.g. badge on Home, bottom nav, etc.)
/// listens to this via [addListener] or [ListenableBuilder], and calls [refresh]
/// when appropriate (on app resume, after reading messages, receiving notifications, etc.).
class ChatState extends ChangeNotifier with WidgetsBindingObserver {
  ChatState._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final ChatState instance = ChatState._();

  final ApiService _api = ApiService();

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;
  bool get hasUnread => _unreadCount > 0;

  bool _loading = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  /// Fetches unread count from the backend. Safe to call repeatedly.
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final count = await _api.getUnreadChatCount();
      if (count != _unreadCount) {
        _unreadCount = count;
        notifyListeners();
      }
    } catch (_) {
      // Keep previous count on network interruption
    } finally {
      _loading = false;
    }
  }

  /// Optimistically update unread count
  void setCount(int count) {
    if (count != _unreadCount) {
      _unreadCount = count < 0 ? 0 : count;
      notifyListeners();
    }
  }

  /// Manually clears unread count (e.g. on logout)
  void clear() {
    if (_unreadCount != 0) {
      _unreadCount = 0;
      notifyListeners();
    }
  }
}
