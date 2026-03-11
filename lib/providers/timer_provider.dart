import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/timer_state.dart';
import '../services/ios_timer_service.dart';
import '../services/notification_service.dart';
import '../services/sound_service.dart';
import '../services/timer_service.dart';
import '../services/tray_service.dart';

class TimerNotifier extends StateNotifier<TimerState> {
  TimerNotifier() : super(const TimerState()) {
    if (_isDesktop) {
      TimerService.instance.onNotificationAction = _handleNotificationAction;
      TrayService.instance.onAction = _handleTrayAction;
    }
    _loadConfig();
    _subscribeToEvents();
  }

  StreamSubscription<TimerEventData>? _subscription;
  final List<StreamSubscription> _mobileSubscriptions = [];

  bool get _isIOS => Platform.isIOS;
  bool get _isAndroid => Platform.isAndroid;
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;
  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('timer_config');
    if (raw != null) {
      try {
        final config =
            TimerConfig.fromJson(json.decode(raw) as Map<String, dynamic>);
        state = state.copyWith(config: config);
      } catch (_) {}
    }
  }

  Future<void> _saveConfig(TimerConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timer_config', json.encode(config.toJson()));
  }

  void _subscribeToEvents() {
    if (_isIOS) {
      _subscribeIos();
    } else if (_isAndroid) {
      _subscribeMobile();
    } else {
      _subscription = TimerService.instance.events.listen((event) {
        if (!mounted) return;
        if (event.event == TimerEvent.tick) {
          final prevMin = state.remainingSeconds ~/ 60;
          state = state.copyWith(remainingSeconds: event.remainingSeconds);
          if (_isDesktop) {
            TrayService.instance.setTitle(state.formattedRemaining);
            if (event.remainingSeconds ~/ 60 != prevMin) {
              TrayService.instance.updateStatus(
                isRunning: true,
                timeLeft: state.formattedRemaining,
              );
            }
          }
        } else if (event.event == TimerEvent.complete) {
          _onTimerComplete();
        }
      });
    }
  }

  void _subscribeMobile() {
    final svc = FlutterBackgroundService();

    // App 进入前台时同步后台服务的当前状态
    _mobileSubscriptions.add(svc.on('state').listen((data) {
      if (!mounted || data == null) return;
      final remaining = (data['remaining'] as num).toInt();
      final running = data['running'] as bool? ?? false;
      final isSnoozed = data['isSnoozed'] as bool? ?? false;
      if (running && remaining > 0) {
        state = state.copyWith(
          status: isSnoozed ? TimerStatus.snoozed : TimerStatus.running,
          remainingSeconds: remaining,
        );
      }
    }));

    // 启动时请求一次当前状态
    svc.isRunning().then((isRunning) {
      if (isRunning) svc.invoke('get_state', {});
    });

    // Live countdown ticks from background service
    _mobileSubscriptions.add(svc.on('tick').listen((data) {
      if (!mounted || data == null) return;
      state = state.copyWith(
          remainingSeconds: (data['remaining'] as num).toInt());
    }));

    // 倒计时结束：engine #2 通知我们，由 engine #1（主线程）展示通知。
    // engine #2 里 flutter_local_notifications 注册不稳定，不可在那边 show()。
    _mobileSubscriptions.add(svc.on('complete').listen((data) {
      if (!mounted) return;
      final wasSnoozed = data?['wasSnoozed'] as bool? ?? false;
      if (wasSnoozed) {
        // 休息结束，engine#2 已自动重启工作计时，只展示简单提醒、不计周期。
        SoundService.instance.playSnoozeAlert();
        NotificationService.instance.showSnoozeEnd();
        state = state.copyWith(
          status: TimerStatus.running,
          remainingSeconds: state.config.intervalMinutes * 60,
        );
      } else {
        // 工作计时自然结束，计入一个完成的周期。
        SoundService.instance.playWorkAlert();
        final snoozeMinutes =
            (data?['snoozeMinutes'] as num?)?.toInt() ?? state.config.snoozeMinutes;
        NotificationService.instance.showTimerComplete(snoozeMinutes);
        state = state.copyWith(
          status: TimerStatus.idle,
          remainingSeconds: 0,
          cycleCount: state.cycleCount + 1,
        );
      }
    }));

    // Notification action: user tapped "停止计时"
    _mobileSubscriptions.add(svc.on('ui_stop').listen((_) {
      if (!mounted) return;
      state = state.copyWith(
          status: TimerStatus.idle, remainingSeconds: 0, cycleCount: 0);
    }));

    // Notification action: user tapped "立刻开始"
    _mobileSubscriptions.add(svc.on('ui_start_now').listen((_) {
      if (!mounted) return;
      state = state.copyWith(
        status: TimerStatus.running,
        remainingSeconds: state.config.intervalMinutes * 60,
      );
    }));

    // Notification action: user tapped "稍后X分钟"
    _mobileSubscriptions.add(svc.on('ui_snooze').listen((_) {
      if (!mounted) return;
      state = state.copyWith(
        status: TimerStatus.snoozed,
        remainingSeconds: state.config.snoozeMinutes * 60,
      );
    }));
  }

  void _subscribeIos() {
    _subscription = IosTimerService.instance.events.listen((event) {
      if (!mounted) return;
      if (event.event == TimerEvent.tick) {
        state = state.copyWith(remainingSeconds: event.remainingSeconds);
      } else if (event.event == TimerEvent.complete) {
        final wasSnoozed = event.wasSnoozed ?? false;
        if (wasSnoozed) {
          // Snooze ended in foreground — IosTimerService auto-started work timer.
          SoundService.instance.playSnoozeAlert();
          NotificationService.instance.showSnoozeEnd();
          state = state.copyWith(
            status: TimerStatus.running,
            remainingSeconds: state.config.intervalMinutes * 60,
          );
        } else {
          SoundService.instance.playWorkAlert();
          NotificationService.instance
              .showTimerComplete(state.config.snoozeMinutes);
          state = state.copyWith(
            status: TimerStatus.idle,
            remainingSeconds: 0,
            cycleCount: state.cycleCount + 1,
          );
        }
      }
    });
  }

  void _onTimerComplete() {
    if (state.isSnoozed) {
      SoundService.instance.playSnoozeAlert();
      NotificationService.instance.showSnoozeEnd();
      _doStart();
    } else {
      SoundService.instance.playWorkAlert();
      NotificationService.instance.showTimerComplete(state.config.snoozeMinutes);
      state = state.copyWith(
        status: TimerStatus.idle,
        remainingSeconds: 0,
        cycleCount: state.cycleCount + 1,
      );
      if (_isDesktop) {
        TrayService.instance.setTitle(null);
        TrayService.instance.updateStatus(isRunning: false);
      }
    }
  }

  void _doStart() {
    final seconds = state.config.intervalMinutes * 60;
    TimerService.instance.start(seconds);
    state = state.copyWith(
      status: TimerStatus.running,
      remainingSeconds: seconds,
    );
  }

  Future<void> startTimer() async {
    if (_isIOS) {
      final seconds = state.config.intervalMinutes * 60;
      IosTimerService.instance.startWork(seconds, state.config.snoozeMinutes);
      state = state.copyWith(
        status: TimerStatus.running,
        remainingSeconds: seconds,
      );
    } else if (_isAndroid) {
      final seconds = state.config.intervalMinutes * 60;
      final svc = FlutterBackgroundService();
      final alreadyRunning = await svc.isRunning();
      if (alreadyRunning) {
        svc.invoke('start', {
          'intervalSeconds': seconds,
          'snoozeMinutes': state.config.snoozeMinutes,
        });
      } else {
        // 等 background isolate 注册好监听器再发 start，避免事件被静默丢弃
        StreamSubscription? readySub;
        readySub = svc.on('ready').listen((_) {
          readySub?.cancel();
          svc.invoke('start', {
            'intervalSeconds': seconds,
            'snoozeMinutes': state.config.snoozeMinutes,
          });
        });
        await svc.startService();
      }
      state = state.copyWith(
        status: TimerStatus.running,
        remainingSeconds: seconds,
      );
    } else {
      _doStart();
      if (_isDesktop) {
        TrayService.instance.updateStatus(
          isRunning: true,
          timeLeft: state.formattedRemaining,
        );
      }
    }
  }

  void stopTimer() {
    if (_isIOS) {
      IosTimerService.instance.stop();
    } else if (_isAndroid) {
      FlutterBackgroundService().invoke('stop', {});
      NotificationService.instance.cancelAll();
    } else {
      TimerService.instance.stop();
      NotificationService.instance.cancelAll();
    }
    state = state.copyWith(
      status: TimerStatus.idle,
      remainingSeconds: 0,
      cycleCount: 0,
    );
    if (_isDesktop) {
      TrayService.instance.setTitle(null);
      TrayService.instance.updateStatus(isRunning: false);
    }
  }

  void _handleNotificationAction(String actionId, String? payload) {
    switch (actionId) {
      case kActionStop:
        stopTimer();
        break;
      case kActionStartNow:
        startTimer();
        break;
      case kActionSnooze:
        _startSnooze();
        break;
    }
  }

  void _handleTrayAction(String action) {
    switch (action) {
      case 'start':
        if (state.isIdle) startTimer();
        break;
      case 'stop':
        stopTimer();
        break;
    }
  }

  void _startSnooze() {
    final snoozeSeconds = state.config.snoozeMinutes * 60;
    final intervalSeconds = state.config.intervalMinutes * 60;
    if (_isIOS) {
      IosTimerService.instance.startSnooze(
        snoozeSeconds,
        intervalSeconds,
        state.config.snoozeMinutes,
      );
    } else if (_isAndroid) {
      final svc = FlutterBackgroundService();
      svc.invoke('start', {
        'intervalSeconds': snoozeSeconds,
        'snoozeMinutes': state.config.snoozeMinutes,
      });
    } else {
      TimerService.instance.start(snoozeSeconds);
    }
    state = state.copyWith(
      status: TimerStatus.snoozed,
      remainingSeconds: snoozeSeconds,
    );
    if (_isDesktop) {
      TrayService.instance.updateStatus(
        isRunning: true,
        timeLeft: '休息中 ${state.formattedRemaining}',
      );
    }
  }

  void updateConfig(TimerConfig config) {
    state = state.copyWith(config: config);
    _saveConfig(config);
  }

  /// Call on app resume (mobile only) to handle notification actions
  /// that arrived while the app was fully killed.
  Future<void> checkPendingAction() async {
    if (!_isMobile) return;

    if (_isIOS) {
      // Cancel any pre-scheduled notifications (handled in-app now).
      await IosTimerService.instance.cancelScheduledNotifications();

      // Sync timer state from saved end time.
      final (:isRunning, :remaining, :wasSnoozed) =
          await IosTimerService.instance.syncFromBackground();

      if (!mounted) return;

      if (isRunning) {
        state = state.copyWith(
          status: wasSnoozed ? TimerStatus.snoozed : TimerStatus.running,
          remainingSeconds: remaining,
        );
      }

      // Handle any notification action tapped while app was in background.
      final prefs = await SharedPreferences.getInstance();
      final action = prefs.getString('pending_action');
      if (action != null && action.isNotEmpty) {
        await prefs.remove('pending_action');
        _handleNotificationAction(action, null);
      }
      return;
    }

    // Android: sync with background service.
    final svc = FlutterBackgroundService();
    if (await svc.isRunning()) {
      svc.invoke('get_state', {});
    }

    // 处理通知按钮点击时存下来的待处理 action
    final prefs = await SharedPreferences.getInstance();
    final action = prefs.getString('pending_action');
    if (action != null && action.isNotEmpty) {
      await prefs.remove('pending_action');
      _handleNotificationAction(action, null);
    }
  }

  /// Schedule background notifications for the current iOS timer state.
  /// Called when the app is about to go to background.
  Future<void> scheduleIosNotifications() async {
    if (!_isIOS) return;
    await IosTimerService.instance.scheduleNotificationsForBackground();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    for (final sub in _mobileSubscriptions) {
      sub.cancel();
    }
    if (_isDesktop) {
      TimerService.instance.onNotificationAction = null;
    }
    super.dispose();
  }
}

final timerProvider =
    StateNotifierProvider<TimerNotifier, TimerState>((ref) => TimerNotifier());
