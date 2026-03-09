import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

const _kFgChannelId = 'timer_foreground';
const _kFgChannelName = '计时器服务';
const _kFgNotifId = 888;

/// IsolateNameServer 中注册的端口名，用于跨 isolate 传递通知按钮事件
const _kActionPortName = 'timer_doctor_action_port';

// ── Top-level functions (required by flutter_background_service) ─────────────

/// Main background service entry point. Runs the countdown timer,
/// updates the foreground notification, and handles notification actions.
@pragma('vm:entry-point')
Future<void> onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // 注册端口，让 onNotificationActionBackground 可以跨 isolate 发送 action
  IsolateNameServer.removePortNameMapping(_kActionPortName);
  final receivePort = ReceivePort();
  IsolateNameServer.registerPortWithName(receivePort.sendPort, _kActionPortName);

  // Initialize flutter_local_notifications in this isolate
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        notificationCategories: [
          DarwinNotificationCategory('timer_category', actions: [
            DarwinNotificationAction.plain(kActionStop, '停止'),
            DarwinNotificationAction.plain(kActionStartNow, '立刻开始'),
            DarwinNotificationAction.plain(kActionSnooze, '稍后'),
          ]),
        ],
      ),
    ),
    onDidReceiveBackgroundNotificationResponse: onNotificationActionBackground,
  );

  // ── State ──────────────────────────────────────────────────────────────────
  int remainingSeconds = 0;
  int intervalSeconds = 25 * 60;
  int snoozeMinutes = 5;
  Timer? ticker;

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> showCompleteNotification() async {
    final androidDetails = AndroidNotificationDetails(
      kChannelId,
      kChannelName,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      actions: [
        const AndroidNotificationAction(kActionStop, '停止'),
        const AndroidNotificationAction(kActionStartNow, '立刻开始'),
        AndroidNotificationAction(kActionSnooze, '$snoozeMinutes分后'),
      ],
    );
    await plugin.show(
      1,
      '⏰ 时间到！',
      '休息一下，或者继续专注？',
      NotificationDetails(android: androidDetails),
    );
  }

  void startCountdown(int seconds) {
    ticker?.cancel();
    remainingSeconds = seconds;
    ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (remainingSeconds > 0) {
        remainingSeconds--;
        service.invoke('tick', {'remaining': remainingSeconds});

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'Timer Doctor',
            content: '专注中  ${_fmt(remainingSeconds)}',
          );
        }
      }

      if (remainingSeconds <= 0) {
        ticker?.cancel();
        ticker = null;
        service.invoke('complete', {});
        await showCompleteNotification();
      }
    });
  }

  void handleAction(String actionId) {
    switch (actionId) {
      case kActionStop:
        ticker?.cancel();
        service.invoke('ui_stop', {});
        receivePort.close();
        IsolateNameServer.removePortNameMapping(_kActionPortName);
        service.stopSelf();
        break;
      case kActionStartNow:
        startCountdown(intervalSeconds);
        service.invoke('ui_start_now', {});
        break;
      case kActionSnooze:
        startCountdown(snoozeMinutes * 60);
        service.invoke('ui_snooze', {});
        break;
    }
  }

  // 接收来自 onNotificationActionBackground 的跨 isolate 消息
  receivePort.listen((message) {
    if (message is String) handleAction(message);
  });

  // ── Listen for commands from main isolate ──────────────────────────────────

  service.on('start').listen((data) {
    if (data == null) return;
    intervalSeconds = (data['intervalSeconds'] as num).toInt();
    snoozeMinutes = (data['snoozeMinutes'] as num).toInt();
    startCountdown(intervalSeconds);
  });

  service.on('stop').listen((_) {
    ticker?.cancel();
    receivePort.close();
    IsolateNameServer.removePortNameMapping(_kActionPortName);
    service.stopSelf();
  });

  // UI 重新进入前台时查询当前状态
  service.on('get_state').listen((_) {
    service.invoke('state', {
      'remaining': remainingSeconds,
      'running': ticker != null,
    });
  });
}

/// Called when user taps a notification action while the app is in background.
/// Uses IsolateNameServer to forward the action to the running background service.
/// Falls back to SharedPreferences if the service is not running.
@pragma('vm:entry-point')
void onNotificationActionBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  final actionId = response.actionId ?? '';
  if (actionId.isEmpty) return;

  // 优先通过 IsolateNameServer 转发给后台服务 isolate
  final port = IsolateNameServer.lookupPortByName(_kActionPortName);
  if (port != null) {
    port.send(actionId);
    return;
  }

  // 后台服务不在运行（App 被杀死），存入 SharedPreferences 等 App 恢复时处理
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('pending_action', actionId);
}

/// iOS background handler — keeps service alive briefly.
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ── Setup ─────────────────────────────────────────────────────────────────────

/// Call once at app startup on Android/iOS to configure the background service.
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  // 前台服务渠道（低优先级，不需要弹出）
  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kFgChannelId,
          _kFgChannelName,
          importance: Importance.low,
        ),
      );
  // kChannelId（计时结束渠道）由 NotificationService.initialize() 在插件初始化后管理

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _kFgChannelId,
      initialNotificationTitle: 'Timer Doctor',
      initialNotificationContent: '准备就绪',
      foregroundServiceNotificationId: _kFgNotifId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onServiceStart,
      onBackground: onIosBackground,
    ),
  );
}
