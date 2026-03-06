class TimerPreset {
  final String id;
  final String name;
  final int intervalMinutes;
  final int snoozeMinutes;
  final bool isBuiltIn;

  const TimerPreset({
    required this.id,
    required this.name,
    required this.intervalMinutes,
    required this.snoozeMinutes,
    this.isBuiltIn = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'intervalMinutes': intervalMinutes,
        'snoozeMinutes': snoozeMinutes,
      };

  factory TimerPreset.fromJson(Map<String, dynamic> json) => TimerPreset(
        id: json['id'] as String,
        name: json['name'] as String,
        intervalMinutes: (json['intervalMinutes'] as num).toInt(),
        snoozeMinutes: (json['snoozeMinutes'] as num).toInt(),
      );
}

class TimerConfig {
  final int intervalMinutes;
  final int snoozeMinutes;

  const TimerConfig({
    this.intervalMinutes = 30,
    this.snoozeMinutes = 2,
  });

  TimerConfig copyWith({int? intervalMinutes, int? snoozeMinutes}) => TimerConfig(
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      );

  Map<String, dynamic> toJson() => {
        'intervalMinutes': intervalMinutes,
        'snoozeMinutes': snoozeMinutes,
      };

  factory TimerConfig.fromJson(Map<String, dynamic> json) => TimerConfig(
        intervalMinutes: (json['intervalMinutes'] as num?)?.toInt() ?? 25,
        snoozeMinutes: (json['snoozeMinutes'] as num?)?.toInt() ?? 5,
      );
}

enum TimerStatus { idle, running, snoozed }

class TimerState {
  final TimerStatus status;
  final int remainingSeconds;
  final TimerConfig config;
  final int cycleCount;

  const TimerState({
    this.status = TimerStatus.idle,
    this.remainingSeconds = 0,
    this.config = const TimerConfig(),
    this.cycleCount = 0,
  });

  bool get isIdle => status == TimerStatus.idle;
  bool get isRunning => status == TimerStatus.running;
  bool get isSnoozed => status == TimerStatus.snoozed;

  String get formattedRemaining {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  TimerState copyWith({
    TimerStatus? status,
    int? remainingSeconds,
    TimerConfig? config,
    int? cycleCount,
  }) =>
      TimerState(
        status: status ?? this.status,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        config: config ?? this.config,
        cycleCount: cycleCount ?? this.cycleCount,
      );
}
