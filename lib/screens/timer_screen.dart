import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/timer_state.dart';
import '../providers/timer_provider.dart';
import 'settings_screen.dart';

class TimerScreen extends ConsumerWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('循环计时'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatusChip(status: state.status),
                const SizedBox(height: 32),
                _TimerDisplay(state: state),
                const SizedBox(height: 12),
                Text(
                  _getSubtitle(state),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                if (state.cycleCount > 0) ...[
                  const SizedBox(height: 8),
                  _CycleCounter(count: state.cycleCount),
                ],
                const SizedBox(height: 48),
                _Controls(state: state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getSubtitle(TimerState state) {
    return switch (state.status) {
      TimerStatus.idle => '专注时长：${state.config.intervalMinutes} 分钟',
      TimerStatus.running => '健康生活！快乐生活！',
      TimerStatus.snoozed =>
        '${state.config.snoozeMinutes} 分钟后自动开始新一轮',
    };
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TimerStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      TimerStatus.idle => ('待机', Colors.grey),
      TimerStatus.running => ('专注中', const Color(0xFF6366F1)),
      TimerStatus.snoozed => ('休息中', Colors.orange),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _TimerDisplay extends StatelessWidget {
  const _TimerDisplay({required this.state});

  final TimerState state;

  @override
  Widget build(BuildContext context) {
    final text = state.isIdle
        ? '${state.config.intervalMinutes.toString().padLeft(2, '0')}:00'
        : state.formattedRemaining;

    return Text(
      text,
      style: const TextStyle(
        fontSize: 80,
        fontWeight: FontWeight.w200,
        letterSpacing: 6,
        height: 1.1,
      ),
    );
  }
}

class _CycleCounter extends StatelessWidget {
  const _CycleCounter({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, size: 16, color: Colors.green.shade600),
        const SizedBox(width: 4),
        Text(
          '已完成 $count 个周期',
          style: TextStyle(
            color: Colors.green.shade600,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.state});

  final TimerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(timerProvider.notifier);

    if (state.isIdle) {
      return FilledButton.icon(
        onPressed: notifier.startTimer,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('开始专注'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(200, 52),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: notifier.stopTimer,
      icon: const Icon(Icons.stop_rounded),
      label: const Text('停止计时'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: const BorderSide(color: Colors.red),
        minimumSize: const Size(200, 48),
      ),
    );
  }
}
