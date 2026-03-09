import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app_keys.dart';
import 'providers/timer_provider.dart';
import 'screens/home_screen.dart';
import 'services/background_timer.dart';
import 'services/notification_service.dart';
import 'services/tray_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(400, 620),
        minimumSize: Size(320, 500),
        center: true,
        title: 'Timer Doctor',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await NotificationService.instance.initialize();
  } else {
    // Android / iOS: initialize background service first, then notifications
    // with the background-isolate handler from background_timer.dart
    await initBackgroundService();
    await NotificationService.instance.initialize(
      backgroundHandler: onNotificationActionBackground,
    );
  }

  runApp(const ProviderScope(child: TimerDoctorApp()));
}

class TimerDoctorApp extends StatefulWidget {
  const TimerDoctorApp({super.key});

  @override
  State<TimerDoctorApp> createState() => _TimerDoctorAppState();
}

class _TimerDoctorAppState extends State<TimerDoctorApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      TrayService.instance.initialize();
    }
    if (Platform.isAndroid || Platform.isIOS) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid || Platform.isIOS) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  // Check for notification actions that arrived while app was killed
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed && mounted) {
      ProviderScope.containerOf(context, listen: false)
          .read(timerProvider.notifier)
          .checkPendingAction();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Timer Doctor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
