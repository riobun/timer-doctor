import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'timer_service.dart';

/// iOS-specific timer service.
///
/// Strategy:
/// - Foreground: Dart [Timer.periodic] updates UI every second.
/// - Background: pre-scheduled local notifications fire at the right time.
///   • App goes to background → [scheduleNotificationsForBackground]
///   • App comes to foreground → [cancelScheduledNotifications] + [syncFromBackground]
class IosTimerService {
  IosTimerService._();
  static final IosTimerService instance = IosTimerService._();

  final _controller = StreamController<TimerEventData>.broadcast();
  Stream<TimerEventData> get events => _controller.stream;

  Timer? _ticker;

  // ── Persisted state keys ──────────────────────────────────────────────────
  static const _kEndTimeKey = 'ios_timer_end_ms';
  static const _kIsSnoozedKey = 'ios_timer_is_snoozed';
  static const _kSnoozeMinutesKey = 'ios_timer_snooze_minutes';
  static const _kIntervalSecsKey = 'ios_timer_interval_secs';

  // ── Runtime state (mirrors persisted state) ───────────────────────────────
  DateTime? _endTime;
  bool _isSnoozed = false;
  int _snoozeMinutes = 5;
  int _intervalSeconds = 25 * 60;

  bool get isRunning => _ticker != null;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Starts a work countdown timer.
  Future<void> startWork(int seconds, int snoozeMinutes) async {
    _ticker?.cancel();
    _ticker = null;
    _isSnoozed = false;
    _snoozeMinutes = snoozeMinutes;
    _intervalSeconds = seconds;
    _endTime = DateTime.now().add(Duration(seconds: seconds));
    await _saveState();
    _startTicker();
  }

  /// Starts a snooze countdown timer.
  /// [intervalSeconds] is the work timer duration for the upcoming round
  /// (used to compute work end time when app is in background).
  Future<void> startSnooze(
      int snoozeSeconds, int intervalSeconds, int snoozeMinutes) async {
    _ticker?.cancel();
    _ticker = null;
    _isSnoozed = true;
    _snoozeMinutes = snoozeMinutes;
    _intervalSeconds = intervalSeconds;
    _endTime = DateTime.now().add(Duration(seconds: snoozeSeconds));
    await _saveState();
    _startTicker();
  }

  /// Stops the timer and cancels any pre-scheduled notifications.
  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    _endTime = null;
    await NotificationService.instance.cancelAll();
    await _clearState();
  }

  /// Schedule background notifications based on current timer state.
  /// Call when the app is about to go to background.
  Future<void> scheduleNotificationsForBackground() async {
    if (_endTime == null) return;
    final remaining = _endTime!.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) return;

    // Cancel any stale notifications first.
    await NotificationService.instance.cancelScheduled();

    if (_isSnoozed) {
      // Schedule snooze-end notification.
      await NotificationService.instance.scheduleSnoozeEnd(_endTime!);
      // Pre-schedule work complete notification at snooze end + interval.
      final workEndTime = _endTime!.add(Duration(seconds: _intervalSeconds));
      await NotificationService.instance
          .scheduleTimerComplete(workEndTime, _snoozeMinutes);
    } else {
      await NotificationService.instance
          .scheduleTimerComplete(_endTime!, _snoozeMinutes);
    }
  }

  /// Cancel pre-scheduled notifications.
  /// Call when the app comes back to foreground.
  Future<void> cancelScheduledNotifications() async {
    await NotificationService.instance.cancelScheduled();
  }

  /// Sync timer state after the app returns to foreground.
  ///
  /// Returns `(isRunning, remainingSeconds, wasSnoozed)`:
  /// - `isRunning=true` → timer still ticking, caller should update UI.
  /// - `isRunning=false, wasSnoozed=true` → snooze ended while in background;
  ///   if the work interval also ended, both timers expired (idle).
  /// - `isRunning=false, wasSnoozed=false` → timer done or never started.
  Future<({bool isRunning, int remaining, bool wasSnoozed})>
      syncFromBackground() async {
    final prefs = await SharedPreferences.getInstance();
    final endMs = prefs.getInt(_kEndTimeKey);
    if (endMs == null) return (isRunning: false, remaining: 0, wasSnoozed: false);

    _endTime = DateTime.fromMillisecondsSinceEpoch(endMs);
    _isSnoozed = prefs.getBool(_kIsSnoozedKey) ?? false;
    _snoozeMinutes = prefs.getInt(_kSnoozeMinutesKey) ?? 5;
    _intervalSeconds = prefs.getInt(_kIntervalSecsKey) ?? 25 * 60;

    final remaining = _endTime!.difference(DateTime.now()).inSeconds;

    if (remaining > 0) {
      // Timer still running — resume foreground ticker.
      if (_ticker == null) _startTicker();
      return (isRunning: true, remaining: remaining, wasSnoozed: _isSnoozed);
    }

    // Timer ended while in background.
    if (_isSnoozed) {
      // Snooze ended — check if the work timer is still running.
      final workEndTime = _endTime!.add(Duration(seconds: _intervalSeconds));
      final workRemaining =
          workEndTime.difference(DateTime.now()).inSeconds;

      if (workRemaining > 0) {
        // Transition seamlessly to work timer.
        _isSnoozed = false;
        _endTime = workEndTime;
        await _saveState();
        if (_ticker == null) _startTicker();
        return (isRunning: true, remaining: workRemaining, wasSnoozed: false);
      }

      // Both snooze AND work ended while away — idle.
      await _clearState();
      return (isRunning: false, remaining: 0, wasSnoozed: false);
    }

    // Work timer ended while in background.
    await _clearState();
    return (isRunning: false, remaining: 0, wasSnoozed: false);
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _endTime!.difference(DateTime.now()).inSeconds;

      if (remaining > 0) {
        _controller.add(TimerEventData(TimerEvent.tick, remaining));
        return;
      }

      // Timer reached 0.
      _ticker?.cancel();
      _ticker = null;

      final wasSnooze = _isSnoozed;
      final snoozeMinutes = _snoozeMinutes;

      if (wasSnooze) {
        // Snooze ended in foreground: auto-transition to work timer.
        _isSnoozed = false;
        _endTime =
            DateTime.now().add(Duration(seconds: _intervalSeconds));
        _saveState();
        _startTicker();
      } else {
        _clearState();
      }

      _controller.add(TimerEventData(
        TimerEvent.complete,
        0,
        wasSnoozed: wasSnooze,
        snoozeMinutes: snoozeMinutes,
      ));
    });
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kEndTimeKey, _endTime!.millisecondsSinceEpoch);
    await prefs.setBool(_kIsSnoozedKey, _isSnoozed);
    await prefs.setInt(_kSnoozeMinutesKey, _snoozeMinutes);
    await prefs.setInt(_kIntervalSecsKey, _intervalSeconds);
  }

  Future<void> _clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEndTimeKey);
    await prefs.remove(_kIsSnoozedKey);
    await prefs.remove(_kSnoozeMinutesKey);
    await prefs.remove(_kIntervalSecsKey);
  }
}
