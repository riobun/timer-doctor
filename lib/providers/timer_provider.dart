import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/timer_state.dart';
import '../services/notification_service.dart';
import '../services/sound_service.dart';
import '../services/timer_service.dart';
import '../services/tray_service.dart';

class TimerNotifier extends StateNotifier<TimerState> {
  TimerNotifier() : super(const TimerState()) {
    if (!_isMobile) {
      TimerService.instance.onNotificationAction = _handleNotificationAction;
    }
    if (_isDesktop) {
      TrayService.instance.onAction = _handleTrayAction;
    }
    _loadConfig();
    _subscribeToEvents();
  }

  StreamSubscription<TimerEventData>? _subscription;
  final List<StreamSubscription> _mobileSubscriptions = [];

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
    if (_isMobile) {
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
      if (running && remaining > 0) {
        state = state.copyWith(
          status: TimerStatus.running,
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

    // Timer finished (background service already showed the notification)
    _mobileSubscriptions.add(svc.on('complete').listen((_) {
      if (!mounted) return;
      SoundService.instance.playAlert();
      state = state.copyWith(status: TimerStatus.idle, remainingSeconds: 0);
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
        cycleCount: state.cycleCount + 1,
        remainingSeconds: state.config.intervalMinutes * 60,
      );
    }));

    // Notification action: user tapped "稍后X分钟"
    _mobileSubscriptions.add(svc.on('ui_snooze').listen((_) {
      if (!mounted) return;
      state = state.copyWith(
        status: TimerStatus.snoozed,
        cycleCount: state.cycleCount + 1,
        remainingSeconds: state.config.snoozeMinutes * 60,
      );
    }));
  }

  void _onTimerComplete() {
    SoundService.instance.playAlert();
    if (state.isSnoozed) {
      NotificationService.instance.showSnoozeEnd();
      _doStart();
    } else {
      NotificationService.instance.showTimerComplete(state.config.snoozeMinutes);
      state = state.copyWith(status: TimerStatus.idle, remainingSeconds: 0);
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

  void startTimer() {
    if (_isMobile) {
      final seconds = state.config.intervalMinutes * 60;
      final svc = FlutterBackgroundService();
      svc.startService().then((_) {
        svc.invoke('start', {
          'intervalSeconds': seconds,
          'snoozeMinutes': state.config.snoozeMinutes,
        });
      });
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
    if (_isMobile) {
      FlutterBackgroundService().invoke('stop', {});
    } else {
      TimerService.instance.stop();
    }
    NotificationService.instance.cancelAll();
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
        state = state.copyWith(cycleCount: state.cycleCount + 1);
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
    final seconds = state.config.snoozeMinutes * 60;
    if (_isMobile) {
      final svc = FlutterBackgroundService();
      svc.invoke('start', {
        'intervalSeconds': seconds,
        'snoozeMinutes': state.config.snoozeMinutes,
      });
    } else {
      TimerService.instance.start(seconds);
    }
    state = state.copyWith(
      status: TimerStatus.snoozed,
      remainingSeconds: seconds,
      cycleCount: state.cycleCount + 1,
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

    // 同步后台服务当前状态
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

  @override
  void dispose() {
    _subscription?.cancel();
    for (final sub in _mobileSubscriptions) {
      sub.cancel();
    }
    if (!_isMobile) {
      TimerService.instance.onNotificationAction = null;
    }
    super.dispose();
  }
}

final timerProvider =
    StateNotifierProvider<TimerNotifier, TimerState>((ref) => TimerNotifier());
