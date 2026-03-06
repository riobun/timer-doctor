import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'timer_service.dart';

const kChannelId = 'timer_doctor_channel';
const kChannelName = 'Timer Notifications';

const kActionStop = 'action_stop';
const kActionStartNow = 'action_start_now';
const kActionSnooze = 'action_snooze';

/// Top-level function required by flutter_local_notifications for background handling.
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

  Future<void> initialize() async {
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
            DarwinNotificationAction.plain(kActionStop, '停止计时'),
            DarwinNotificationAction.plain(kActionStartNow, '立刻开始'),
            DarwinNotificationAction.plain(kActionSnooze, '稍后开始'),
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
        TimerService.instance.handleNotificationAction(
          response.actionId ?? '',
          response.payload,
        );
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await _requestPermissions();
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
    final androidDetails = AndroidNotificationDetails(
      kChannelId,
      kChannelName,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      actions: [
        const AndroidNotificationAction(kActionStop, '停止计时'),
        const AndroidNotificationAction(kActionStartNow, '立刻开始'),
        AndroidNotificationAction(kActionSnooze, '等 $snoozeMinutes 分钟'),
      ],
    );

    const darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: 'timer_category',
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
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}
