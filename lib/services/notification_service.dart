import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:timezone/timezone.dart' as tz;
import 'timer_service.dart';

// Native channel for Android timer-complete notification (bypasses
// flutter_local_notifications action-button broadcast issues).
const _androidNotifChannel = MethodChannel('timer_doctor/notification');

const kChannelId = 'timer_doctor_channel';
const kChannelName = 'Timer Notifications';

const kActionStop = 'action_stop';
const kActionStartNow = 'action_start_now';
const kActionSnooze = 'action_snooze';

/// Top-level function required by flutter_local_notifications for background handling.
/// On mobile this is never actually reached — onNotificationActionBackground in
/// background_timer.dart is used instead. Kept as a safety fallback.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  TimerService.instance.handleNotificationAction(
    response.actionId ?? '',
    response.payload,
  );
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize({
    DidReceiveBackgroundNotificationResponseCallback? backgroundHandler,
  }) async {
    if (Platform.isWindows) {
      await localNotifier.setup(appName: 'Timer Doctor');
      return;
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          'timer_category',
          actions: [
            DarwinNotificationAction.plain(kActionStartNow, '立刻开始'),
            DarwinNotificationAction.plain(kActionSnooze, '稍后休息'),
          ],
        ),
      ],
    );

    const linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open');

    await _plugin.initialize(
      InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        final actionId = response.actionId ?? '';
        if (actionId.isEmpty) return;
        if (Platform.isAndroid || Platform.isIOS) {
          // 前台时直接通过 flutter_background_service 事件通道发给后台服务，可靠且即时。
          // 后台/被杀场景走 onNotificationActionBackground → SharedPreferences fallback。
          FlutterBackgroundService().invoke('action', {'id': actionId});
        } else {
          TimerService.instance.handleNotificationAction(
            actionId,
            response.payload,
          );
        }
      },
      onDidReceiveBackgroundNotificationResponse:
          backgroundHandler ?? notificationTapBackground,
    );

    await _requestPermissions();
    await _ensureAndroidChannels();
  }

  /// 确保 Android 通知渠道以最高优先级存在。
  /// 必须在 initialize() 之后调用，否则 resolvePlatformSpecificImplementation 返回 null。
  Future<void> _ensureAndroidChannels() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return;

    // 删除旧渠道（可能以低优先级缓存），强制重建
    await androidImpl.deleteNotificationChannel(kChannelId);
    await androidImpl.createNotificationChannel(
      const AndroidNotificationChannel(
        kChannelId,
        kChannelName,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  Future<void> _requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Shows the "time's up" notification with 3 action buttons.
  Future<void> showTimerComplete(int snoozeMinutes) async {
    // Android: use native notification so action button broadcasts are
    // delivered via TimerActionReceiver → SharedPreferences → actionPoller.
    if (Platform.isAndroid) {
      await _androidNotifChannel.invokeMethod(
        'showTimerComplete',
        {'snoozeMinutes': snoozeMinutes},
      );
      return;
    }

    if (Platform.isWindows) {
      final notification = LocalNotification(
        title: '⏰ 时间到！',
        body: '休息一下，或者继续专注？',
        actions: [
          LocalNotificationAction(text: '立刻开始'),
          LocalNotificationAction(text: '休息 $snoozeMinutes 分钟'),
        ],
      );
      notification.onClickAction = (actionIndex) {
        final actionId = switch (actionIndex) {
          0 => kActionStartNow,
          _ => kActionSnooze,
        };
        TimerService.instance.handleNotificationAction(actionId, null);
      };
      await notification.show();
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      kChannelId,
      kChannelName,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      actions: [
        const AndroidNotificationAction(kActionStartNow, '立刻开始'),
        AndroidNotificationAction(kActionSnooze, '休息 $snoozeMinutes 分钟'),
      ],
    );

    const darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: 'timer_category',
      presentAlert: true,
      presentSound: true,
    );

    await _plugin.show(
      1,
      '⏰ 时间到！',
      '休息一下，或者继续专注？',
      NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      ),
    );
  }

  /// Simple notification when snooze ends and work timer auto-starts.
  Future<void> showSnoozeEnd() async {
    if (Platform.isWindows) {
      await LocalNotification(
        title: '🎯 开始专注！',
        body: '休息结束，新一轮专注已开始',
      ).show();
      return;
    }

    await _plugin.show(
      2,
      '🎯 开始专注！',
      '休息结束，新一轮专注已开始',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kChannelId,
          kChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        macOS: DarwinNotificationDetails(),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  // ── iOS scheduled notifications ───────────────────────────────────────────

  /// Schedule a work-complete notification at [fireAt] (iOS only).
  Future<void> scheduleTimerComplete(DateTime fireAt, int snoozeMinutes) async {
    if (!Platform.isIOS) return;
    await _plugin.zonedSchedule(
      1,
      '⏰ 时间到！',
      '休息一下，或者继续专注？',
      tz.TZDateTime.from(fireAt, tz.local),
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          categoryIdentifier: 'timer_category',
          presentAlert: true,
          presentSound: true,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedule a simple snooze-end notification at [fireAt] (iOS only).
  Future<void> scheduleSnoozeEnd(DateTime fireAt) async {
    if (!Platform.isIOS) return;
    await _plugin.zonedSchedule(
      2,
      '🎯 开始专注！',
      '休息结束，新一轮专注已开始',
      tz.TZDateTime.from(fireAt, tz.local),
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancel only the scheduled iOS notifications (IDs 1 and 2).
  Future<void> cancelScheduled() async {
    if (!Platform.isIOS) return;
    await _plugin.cancel(1);
    await _plugin.cancel(2);
  }

  Future<void> cancelAll() async {
    if (Platform.isWindows) return;
    if (Platform.isAndroid) {
      try {
        await _androidNotifChannel.invokeMethod('cancelTimerNotification');
      } catch (_) {}
      return;
    }
    await _plugin.cancelAll();
  }
}
