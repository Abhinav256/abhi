import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/abhishare_splash_animation.dart';
import 'screens/login_screen.dart';
import 'screens/pin_setup_screen.dart';
import 'screens/unlock_screen.dart';
import 'services/push_notification_service.dart';
import 'services/security_service.dart';
import 'services/session_service.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Launch app immediately so the branded splash renders on frame 1 without delay
  runApp(const AbhiShareApp());
}

class AbhiShareApp extends StatefulWidget {
  const AbhiShareApp({super.key});

  @override
  State<AbhiShareApp> createState() => _AbhiShareAppState();
}

class _AbhiShareAppState extends State<AbhiShareApp> {
  final SessionService _sessionService = SessionService();
  final SecurityService _securityService = SecurityService();
  late final Future<Widget> _startupFuture;

  @override
  void initState() {
    super.initState();
    _startupFuture = _initApp();
  }

  Future<Widget> _initApp() async {
    // 1. Initialize Firebase and Push Notifications in the background while splash renders
    final servicesFuture = _initServices();

    // 2. Resolve initial target screen concurrently
    final screenFuture = _resolveInitialScreen();

    // 3. Ensure both complete before leaving splash screen
    final results = await Future.wait([screenFuture, servicesFuture]);
    return results[0] as Widget;
  }

  Future<void> _initServices() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await PushNotificationService.instance.initialize();
    } catch (e) {
      debugPrint('[Startup] Firebase / PushNotification init error: $e');
    }
  }

  Future<Widget> _resolveInitialScreen() async {
    try {
      final session = await _sessionService.getSession();
      final userId = session?['userId'];

      if (session == null || userId == null || userId.isEmpty) {
        return const LoginScreen();
      }

      final hasPin = await _securityService.hasPin(userId: userId);
      if (!hasPin) {
        return const PinSetupScreen(isReset: false);
      }

      final isBiometricEnabled = await _securityService.isBiometricEnabled(userId: userId);
      final hasBiometrics = await _securityService.canCheckBiometrics();
      final biometricLabel = await _securityService.getBiometricTypeLabel();

      return UnlockScreen(
        initialUserId: userId,
        initialIsBiometricEnabled: isBiometricEnabled,
        initialHasBiometrics: hasBiometrics,
        initialBiometricLabel: biometricLabel,
      );
    } catch (e) {
      debugPrint('[Startup] Screen resolution error: $e');
      return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'AbhiShare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: AbhiShareSplash(
        waitFor: _startupFuture,
        onFinished: (context) async {
          final targetScreen = await _startupFuture;
          if (!context.mounted) return;

          fadeReplace(context, targetScreen);
        },
      ),
    );
  }
}
