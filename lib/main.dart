import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
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
  } else if (Platform.isAndroid) {
    // Android: initialize background service first, then notifications.
    await initBackgroundService();
    await NotificationService.instance.initialize(
      backgroundHandler: onNotificationActionBackground,
    );

    // 请求豁免电池优化，防止 MIUI 等国产 ROM 节流后台服务
    const channel = MethodChannel('com.example.timer_doctor/battery');
    try {
      await channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  } else if (Platform.isIOS) {
    // iOS: initialize timezone + notifications.
    // No background service — we use pre-scheduled local notifications instead.
    tz_data.initializeTimeZones();
    try {
      final timezoneName = DateTime.now().timeZoneName;
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      // 降级：使用 UTC（通知时间可能有偏差）
    }
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (!mounted) return;
    final notifier =
        ProviderScope.containerOf(context, listen: false).read(timerProvider.notifier);

    if (lifecycleState == AppLifecycleState.resumed) {
      // Handle notification actions and sync timer state.
      notifier.checkPendingAction();
    } else if (lifecycleState == AppLifecycleState.paused &&
        Platform.isIOS) {
      // iOS going to background: pre-schedule local notifications.
      notifier.scheduleIosNotifications();
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
