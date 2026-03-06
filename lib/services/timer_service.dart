import 'dart:async';

enum TimerEvent { tick, complete }

class TimerEventData {
  final TimerEvent event;
  final int remainingSeconds;

  TimerEventData(this.event, this.remainingSeconds);
}

class TimerService {
  TimerService._();
  static final TimerService instance = TimerService._();

  Timer? _timer;
  int _remainingSeconds = 0;
  final _controller = StreamController<TimerEventData>.broadcast();

  Stream<TimerEventData> get events => _controller.stream;
  int get remainingSeconds => _remainingSeconds;

  /// Set by TimerProvider to handle notification action button taps.
  void Function(String actionId, String? payload)? onNotificationAction;

  void handleNotificationAction(String actionId, String? payload) {
    onNotificationAction?.call(actionId, payload);
  }

  void start(int durationSeconds) {
    stop();
    _remainingSeconds = durationSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _remainingSeconds = 0;
  }

  void _tick(Timer timer) {
    if (_remainingSeconds > 0) {
      _remainingSeconds--;
      _controller.add(TimerEventData(TimerEvent.tick, _remainingSeconds));
    }
    if (_remainingSeconds <= 0) {
      stop();
      _controller.add(TimerEventData(TimerEvent.complete, 0));
    }
  }
}
