import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app_keys.dart';
import 'screens/home_screen.dart';
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
  }

  await NotificationService.instance.initialize();
  runApp(const ProviderScope(child: TimerDoctorApp()));
}

class TimerDoctorApp extends StatefulWidget {
  const TimerDoctorApp({super.key});

  @override
  State<TimerDoctorApp> createState() => _TimerDoctorAppState();
}

class _TimerDoctorAppState extends State<TimerDoctorApp> {
  @override
  void initState() {
    super.initState();
    // Initialize tray after Flutter rendering engine is ready
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      TrayService.instance.initialize();
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
