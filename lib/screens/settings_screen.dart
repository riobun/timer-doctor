import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/timer_state.dart';
import '../providers/preset_provider.dart';
import '../providers/timer_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late int _intervalMinutes;
  late int _snoozeMinutes;

  @override
  void initState() {
    super.initState();
    final config = ref.read(timerProvider).config;
    _intervalMinutes = config.intervalMinutes;
    _snoozeMinutes = config.snoozeMinutes;
  }

  void _save() {
    ref.read(timerProvider.notifier).updateConfig(
          TimerConfig(
            intervalMinutes: _intervalMinutes,
            snoozeMinutes: _snoozeMinutes,
          ),
        );
    Navigator.pop(context);
  }

  void _applyPreset(TimerPreset preset) {
    setState(() {
      _intervalMinutes = preset.intervalMinutes;
      _snoozeMinutes = preset.snoozeMinutes;
    });
  }

  void _showAddPresetDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddPresetDialog(
        onAdd: (name, interval, snooze) {
          ref.read(presetProvider.notifier).add(name, interval, snooze);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(presetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SliderCard(
            title: '专注时长',
            value: _intervalMinutes.toDouble(),
            min: 1,
            max: 120,
            unit: '分钟',
            onChanged: (v) => setState(() => _intervalMinutes = v.round()),
          ),
          const SizedBox(height: 12),
          _SliderCard(
            title: '休息时长（稍后开始）',
            value: _snoozeMinutes.toDouble(),
            min: 1,
            max: 30,
            unit: '分钟',
            onChanged: (v) => setState(() => _snoozeMinutes = v.round()),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('快速预设', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _showAddPresetDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in presets)
                preset.isBuiltIn
                    ? ActionChip(
                        label: Text(
                          '${preset.name}  ${preset.intervalMinutes}/${preset.snoozeMinutes}',
                        ),
                        onPressed: () => _applyPreset(preset),
                      )
                    : InputChip(
                        label: Text(
                          '${preset.name}  ${preset.intervalMinutes}/${preset.snoozeMinutes}',
                        ),
                        onPressed: () => _applyPreset(preset),
                        onDeleted: () => _confirmDelete(preset),
                        deleteIcon: const Icon(Icons.close, size: 16),
                      ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(TimerPreset preset) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预设'),
        content: Text('确定删除「${preset.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(presetProvider.notifier).remove(preset.id);
              Navigator.pop(ctx);
            },
            child:
                Text('删除', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

// ─── Add Preset Dialog ────────────────────────────────────────────────────────

class _AddPresetDialog extends StatefulWidget {
  const _AddPresetDialog({required this.onAdd});

  final void Function(String name, int interval, int snooze) onAdd;

  @override
  State<_AddPresetDialog> createState() => _AddPresetDialogState();
}

class _AddPresetDialogState extends State<_AddPresetDialog> {
  final _nameController = TextEditingController();
  int _interval = 25;
  int _snooze = 5;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    widget.onAdd(name, _interval, _snooze);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加预设'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '预设名称',
                hintText: '例如：午后专注',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            _DialogSlider(
              label: '专注时长',
              value: _interval,
              min: 1,
              max: 120,
              onChanged: (v) => setState(() => _interval = v),
            ),
            const SizedBox(height: 12),
            _DialogSlider(
              label: '休息时长',
              value: _snooze,
              min: 1,
              max: 30,
              onChanged: (v) => setState(() => _snooze = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('添加'),
        ),
      ],
    );
  }
}

class _DialogSlider extends StatelessWidget {
  const _DialogSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(
              '$value 分钟',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}

// ─── Slider Card ──────────────────────────────────────────────────────────────

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${value.round()} $unit',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
