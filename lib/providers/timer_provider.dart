import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/timer_state.dart';
import '../services/notification_service.dart';
import '../services/sound_service.dart';
import '../services/timer_service.dart';
import '../services/tray_service.dart';

class TimerNotifier extends StateNotifier<TimerState> {
  TimerNotifier() : super(const TimerState()) {
    TimerService.instance.onNotificationAction = _handleNotificationAction;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      TrayService.instance.onAction = _handleTrayAction;
    }
    _loadConfig();
    _subscribeToEvents();
  }

  StreamSubscription<TimerEventData>? _subscription;

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
    _subscription = TimerService.instance.events.listen((event) {
      if (!mounted) return;
      if (event.event == TimerEvent.tick) {
        final prevMin = state.remainingSeconds ~/ 60;
        state = state.copyWith(remainingSeconds: event.remainingSeconds);
        if (_isDesktop) {
          // Title updates every second — shows live countdown in menu bar
          TrayService.instance.setTitle(state.formattedRemaining);
          // Rebuild the menu only once per minute to avoid flicker
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

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

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
    _doStart();
    if (_isDesktop) {
      TrayService.instance.updateStatus(
        isRunning: true,
        timeLeft: state.formattedRemaining,
      );
    }
  }

  void stopTimer() {
    TimerService.instance.stop();
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
    TimerService.instance.start(seconds);
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

  @override
  void dispose() {
    _subscription?.cancel();
    TimerService.instance.onNotificationAction = null;
    super.dispose();
  }
}

final timerProvider =
    StateNotifierProvider<TimerNotifier, TimerState>((ref) => TimerNotifier());
