import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

const _kFgChannelId = 'timer_foreground';
const _kFgChannelName = '计时器服务';
const _kFgNotifId = 888;

// ── Top-level functions (required by flutter_background_service) ─────────────

/// Main background service entry point. Runs the countdown timer,
/// updates the foreground notification, and handles notification actions.
@pragma('vm:entry-point')
Future<void> onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // ── State ──────────────────────────────────────────────────────────────────
  int remainingSeconds = 0;
  int intervalSeconds = 25 * 60;
  int snoozeMinutes = 5;
  bool isSnoozed = false;
  Timer? ticker;
  String fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  // Forward declaration so actionPoller can reference handleAction.
  late void Function(String) handleAction;

  // ── 独立轮询 Timer：服务生命周期内持续运行，每秒检查通知按钮的待处理 action ──
  // 倒计时结束后 ticker 会被 cancel，但 actionPoller 继续运行，
  // 确保通知弹出后用户点击按钮依然有效。
  Timer.periodic(const Duration(seconds: 1), (_) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // 刷新内存缓存，获取其他 Engine 写入的最新值
    final pending = prefs.getString('pending_action');
    if (pending != null && pending.isNotEmpty) {
      await prefs.remove('pending_action');
      handleAction(pending);
    }
  });

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
            content: '${isSnoozed ? '休息中' : '专注中'}  ${fmt(remainingSeconds)}',
          );
        }
      }

      if (remainingSeconds <= 0) {
        ticker?.cancel();
        ticker = null;
        if (isSnoozed) {
          // 休息结束：自动开始下一轮工作计时，通知 engine#1 展示简单提醒。
          isSnoozed = false;
          startCountdown(intervalSeconds);
          service.invoke('complete', {'snoozeMinutes': snoozeMinutes, 'wasSnoozed': true});
        } else {
          // 工作计时结束：通知 engine#1 展示带操作按钮的通知。
          service.invoke('complete', {'snoozeMinutes': snoozeMinutes, 'wasSnoozed': false});
        }
      }
    });
  }

  handleAction = (String actionId) {
    switch (actionId) {
      case kActionStop:
        ticker?.cancel();
        service.invoke('ui_stop', {});
        service.stopSelf();
        break;
      case kActionStartNow:
        isSnoozed = false;
        startCountdown(intervalSeconds);
        service.invoke('ui_start_now', {});
        break;
      case kActionSnooze:
        isSnoozed = true;
        startCountdown(snoozeMinutes * 60);
        service.invoke('ui_snooze', {});
        break;
    }
  };

  // ── 先注册所有事件监听器，再初始化 plugin ──────────────────────────────────
  // 必须在 plugin.initialize() 之前注册，否则主线程 invoke('start') 到达时
  // 监听器还未就绪，事件会被静默丢弃，导致倒计时延迟 10 秒才启动。

  service.on('start').listen((data) {
    if (data == null) return;
    intervalSeconds = (data['intervalSeconds'] as num).toInt();
    snoozeMinutes = (data['snoozeMinutes'] as num).toInt();
    isSnoozed = false;
    startCountdown(intervalSeconds);
  });

  // 前台通知按钮点击：NotificationService 通过 invoke('action') 直接发过来
  service.on('action').listen((data) {
    if (data == null) return;
    final actionId = data['id'] as String? ?? '';
    if (actionId.isNotEmpty) handleAction(actionId);
  });

  service.on('stop').listen((_) {
    ticker?.cancel();
    service.stopSelf();
  });

  // 所有监听器注册完毕，通知主线程可以安全发送 'start'
  service.invoke('ready', {});

  // UI 重新进入前台时查询当前状态
  service.on('get_state').listen((_) {
    service.invoke('state', {
      'remaining': remainingSeconds,
      'running': ticker != null,
      'isSnoozed': isSnoozed,
    });
  });

  // engine #2 不再调用 plugin.initialize()。
  // 原因：flutter_background_service_android 在 engine #2 里抛异常，
  // 可能导致 flutter_local_notifications 注册不完整，反而干扰 engine #1
  // 的通知回调处理。通知由 engine #1 负责展示和响应。
}

/// Called when user taps a notification action while the app is in background.
/// Stores the action in SharedPreferences; the running background service
/// will pick it up on the next tick (within 1 second).
///
/// ⚠️ 必须先初始化插件注册表，否则 SharedPreferences 的 Platform Channel
/// 不可用，setString 会静默失败，action 就此丢失。
@pragma('vm:entry-point')
void onNotificationActionBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final actionId = response.actionId ?? '';
  debugPrint('[Notif] onNotificationActionBackground: actionId=$actionId');
  if (actionId.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('pending_action', actionId);
  debugPrint('[Notif] onNotificationActionBackground: saved pending_action=$actionId');
}

/// iOS background handler — keeps service alive briefly.
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
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
