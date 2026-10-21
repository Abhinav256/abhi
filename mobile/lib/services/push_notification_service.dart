import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'chat_state.dart';
import 'notification_state.dart';
import '../screens/chat_screen.dart';
import '../screens/notification_detail_screen.dart';
import '../screens/notifications_screen.dart';
import '../main.dart' show rootNavigatorKey;
import '../screens/ride_details_screen.dart';

/// Top-level background message entrypoint for Firebase Cloud Messaging.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static GlobalKey<NavigatorState> get navigatorKey => rootNavigatorKey;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'abhishare_notifications',
    'AbhiShare Alerts',
    description: 'Ride, booking, chat, and transaction updates',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  bool _isInitialized = false;
  String? _lastToken;

  /// Initializes FCM, local notification heads-up display, and handlers.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 2. Initialize local notifications for heads-up display in foreground
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            try {
              final data = jsonDecode(payload);
              if (data is Map<String, dynamic>) {
                handleNotificationTap(data);
              }
            } catch (e) {
              debugPrint('[PushNotification] Error parsing payload: $e');
            }
          }
        },
      );

      // Create Android channel
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(_channel);
        await androidPlugin.requestNotificationsPermission();
      }

      // 3. Request permissions from OS
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('[PushNotification] User granted permission: ${settings.authorizationStatus}');

      // 4. Foreground notification presentation options (iOS)
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 5. Foreground message stream
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[PushNotification] Foreground message received: ${message.messageId}');
        _handleForegroundMessage(message);
      });

      // 6. Background message tap stream (when app opened from background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[PushNotification] App opened from notification: ${message.data}');
        handleNotificationTap(message.data);
      });

      // 7. Check if app was opened from terminated state by a notification
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[PushNotification] Terminated initial message: ${initialMessage.data}');
        // Delay slightly so the navigator tree is mounted
        Future.delayed(const Duration(milliseconds: 600), () {
          handleNotificationTap(initialMessage.data);
        });
      }

      // 8. Listen for token refresh
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        debugPrint('[PushNotification] Token refreshed: $newToken');
        _lastToken = newToken;
        syncDeviceToken(forceToken: newToken);
      });

      _isInitialized = true;

      // Sync initial token if logged in
      syncDeviceToken();
    } catch (e) {
      debugPrint('[PushNotification] Initialization error: $e');
    }
  }

  /// Synchronizes the device FCM token with the backend for the current user.
  Future<void> syncDeviceToken({String? forceToken}) async {
    try {
      // ignore: deprecated_member_use
      final token = forceToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      _lastToken = token;

      // Only sync if user is currently authenticated
      final api = ApiService.instance;
      if (!await api.isAuthenticated) return;

      final platform = defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : (defaultTargetPlatform == TargetPlatform.android ? 'android' : 'web');

      await api.registerDeviceToken(token: token, platform: platform);
      debugPrint('[PushNotification] Successfully synced device token to backend');
    } catch (e) {
      debugPrint('[PushNotification] Failed to sync device token: $e');
    }
  }

  /// Unregisters the device FCM token on logout.
  Future<void> clearDeviceToken() async {
    try {
      // ignore: deprecated_member_use
      final token = _lastToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService.instance.unregisterDeviceToken(token: token);
        debugPrint('[PushNotification] Successfully unregistered device token');
      }
    } catch (e) {
      debugPrint('[PushNotification] Error unregistering device token: $e');
    }
  }

  /// Displays foreground notifications cleanly via flutter_local_notifications.
  void _handleForegroundMessage(RemoteMessage message) {
    // 1. Refresh in-app badge/counter immediately
    NotificationState.instance.refresh();

    final data = message.data;
    if (data['type'] == 'chat_message') {
      ChatState.instance.refresh();
    }

    // 2. Display notification banner
    final notification = message.notification;
    final title = notification?.title ?? data['title'] ?? 'AbhiShare Update';
    final body = notification?.body ?? data['message'] ?? '';

    if (body.isEmpty && title.isEmpty) return;

    // Use a unique notification ID
    final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: jsonEncode(data),
    );
  }

  /// Handles user tapping a notification and navigates to the relevant screen.
  void handleNotificationTap(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final type = data['type']?.toString();
    final rideId = data['ride_id']?.toString();
    final bookingId = data['booking_id']?.toString();
    final notifId = data['notification_id']?.toString() ?? data['id']?.toString();

    debugPrint('[PushNotification] Routing tap: type=$type, rideId=$rideId, bookingId=$bookingId, notifId=$notifId');

    // 1. Chat message -> navigate to chat conversation
    if (type == 'chat_message' && bookingId != null && bookingId.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(bookingId: bookingId),
        ),
      );
      return;
    }

    // 2. Specific ride context -> navigate to ride details
    if (rideId != null && rideId.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RideDetailsScreen(rideId: rideId),
        ),
      );
      return;
    }

    // 3. Specific in-app notification detail
    if (notifId != null && notifId.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NotificationDetailScreen(
            notification: {
              'id': notifId,
              'title': data['title'] ?? 'Notification',
              'message': data['message'] ?? '',
              'type': type ?? 'general',
              'booking_id': bookingId,
              'ride_id': rideId,
              'created_at': DateTime.now().toIso8601String(),
            },
          ),
        ),
      );
      return;
    }

    // 4. Default -> notifications list
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NotificationsScreen(),
      ),
    );
  }
}
