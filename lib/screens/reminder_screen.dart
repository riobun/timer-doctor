import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/reminder_provider.dart';
import '../services/overlay_service.dart';

// ─── Presets ─────────────────────────────────────────────────────────────────

const _textColorPresets = [
  Color(0xFFFFFFFF), // 白
  Color(0xFF000000), // 黑
  Color(0xFFF06292), // 马卡龙粉
  Color(0xFFFFEB3B), // 黄
  Color(0xFF80DEEA), // 青
  Color(0xFFFF9800), // 橙
  Color(0xFFE0E0E0), // 浅灰
];

const _bgColorPresets = [
  Color(0xFF141414), // 近黑
  Color(0xFF1A237E), // 深蓝
  Color(0xFF1B5E20), // 深绿
  Color(0xFF7F0000), // 深红
  Color(0xFF4A148C), // 深紫
  Color(0xFF37474F), // 深灰蓝
  Color(0xFFFFFFFF), // 白
];

// ─── Screen ──────────────────────────────────────────────────────────────────

class ReminderScreen extends ConsumerStatefulWidget {
  const ReminderScreen({super.key});

  @override
  ConsumerState<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends ConsumerState<ReminderScreen> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(reminderProvider).text);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _saveText();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _saveText() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) ref.read(reminderProvider.notifier).setText(text);
  }

  @override
  Widget build(BuildContext context) {
    final reminder = ref.watch(reminderProvider);
    final colorScheme = Theme.of(context).colorScheme;

    ref.listen<ReminderState>(reminderProvider, (prev, next) {
      if (prev?.text != next.text && !_focusNode.hasFocus) {
        _controller.text = next.text;
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('提醒文字'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Feature description
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.sticky_note_2_rounded,
                        size: 28,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '提醒文字浮窗',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            Platform.isMacOS || Platform.isWindows
                                ? '开启后，文字悬浮在所有窗口之上\n可拖动到屏幕任意位置'
                                : Platform.isAndroid
                                    ? '开启后，文字将悬浮在其他应用上方\n首次使用需授予悬浮窗权限'
                                    : '当前平台暂不支持系统级悬浮窗',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Toggle
            Card(
              child: SwitchListTile(
                title: Text(
                  reminder.enabled ? '悬浮提醒已开启' : '悬浮提醒已关闭',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  reminder.enabled
                      ? '「${reminder.text}」正在显示'
                      : '开启后文字将立即出现',
                  style: TextStyle(
                    color: reminder.enabled
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                value: reminder.enabled,
                onChanged: (v) async {
                  if (v && Platform.isAndroid) {
                    final ok = await OverlayService.hasOverlayPermission();
                    if (!ok) {
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('需要悬浮窗权限'),
                          content: const Text(
                              '请在系统设置中开启"在其他应用上层显示"权限，'
                              '才能让提醒文字浮在其他应用之上。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                OverlayService.requestOverlayPermission();
                              },
                              child: const Text('去设置'),
                            ),
                          ],
                        ),
                      );
                      return;
                    }
                  }
                  ref.read(reminderProvider.notifier).setEnabled(v);
                },
                activeThumbColor: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),

            // Text editing
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('提醒内容',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: const InputDecoration(
                        hintText: '输入想时刻提醒自己的一句话',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 40,
                      onSubmitted: (_) => _saveText(),
                    ),
                    if (reminder.enabled)
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: _saveText,
                          child: const Text('立即更新'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Style settings
            _StyleCard(
              fontSize: reminder.fontSize,
              textColorValue: reminder.textColorValue,
              bgColorValue: reminder.bgColorValue,
              bgOpacity: reminder.bgOpacity,
              onChanged: ({fontSize, textColorValue, bgColorValue, bgOpacity}) {
                ref.read(reminderProvider.notifier).setStyle(
                      fontSize: fontSize,
                      textColorValue: textColorValue,
                      bgColorValue: bgColorValue,
                      bgOpacity: bgOpacity,
                    );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Style Card ──────────────────────────────────────────────────────────────

class _StyleCard extends StatefulWidget {
  const _StyleCard({
    required this.fontSize,
    required this.textColorValue,
    required this.bgColorValue,
    required this.bgOpacity,
    required this.onChanged,
  });

  final double fontSize;
  final int textColorValue;
  final int bgColorValue;
  final double bgOpacity;
  final void Function({
    double? fontSize,
    int? textColorValue,
    int? bgColorValue,
    double? bgOpacity,
  }) onChanged;

  @override
  State<_StyleCard> createState() => _StyleCardState();
}

class _StyleCardState extends State<_StyleCard> {
  late double _fontSize;
  late double _bgOpacity;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.fontSize;
    _bgOpacity = widget.bgOpacity;
  }

  @override
  void didUpdateWidget(_StyleCard old) {
    super.didUpdateWidget(old);
    if (old.fontSize != widget.fontSize) _fontSize = widget.fontSize;
    if (old.bgOpacity != widget.bgOpacity) _bgOpacity = widget.bgOpacity;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('外观设置', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 16),

            // Font size
            _SliderRow(
              label: '字体大小',
              value: _fontSize,
              min: 10,
              max: 28,
              display: '${_fontSize.round()} pt',
              onChanged: (v) => setState(() => _fontSize = v),
              onChangeEnd: (v) => widget.onChanged(fontSize: v),
            ),
            const SizedBox(height: 14),

            // Text color
            _ColorRow(
              label: '文字颜色',
              presets: _textColorPresets,
              selected: Color(widget.textColorValue),
              onSelect: (c) => widget.onChanged(textColorValue: c.value),
              showBorder: true,
            ),
            const SizedBox(height: 14),

            // Background color
            _ColorRow(
              label: '背景颜色',
              presets: _bgColorPresets,
              selected: Color(widget.bgColorValue),
              onSelect: (c) => widget.onChanged(bgColorValue: c.value),
              showBorder: false,
            ),
            const SizedBox(height: 14),

            // Background opacity
            _SliderRow(
              label: '背景透明度',
              value: _bgOpacity,
              min: 0.05,
              max: 1.0,
              display: '${(_bgOpacity * 100).round()}%',
              onChanged: (v) => setState(() => _bgOpacity = v),
              onChangeEnd: (v) => widget.onChanged(bgOpacity: v),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

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
              display,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.presets,
    required this.selected,
    required this.onSelect,
    required this.showBorder,
  });

  final String label;
  final List<Color> presets;
  final Color selected;
  final ValueChanged<Color> onSelect;
  final bool showBorder; // 亮色建议显示边框

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((c) {
            final isSelected = c.value == selected.value;
            // 白/浅色需要灰边，深色不需要
            final needsBorder = c.computeLuminance() > 0.5;
            return GestureDetector(
              onTap: () => onSelect(c),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : needsBorder
                            ? Colors.grey.shade400
                            : Colors.transparent,
                    width: isSelected ? 2.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.4),
                            blurRadius: 4,
                          )
                        ]
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 14,
                        color: c.computeLuminance() > 0.5
                            ? Colors.black87
                            : Colors.white,
                      )
                    : null,
              ),
            );
          }).toList(),
          ),
        ),
      ],
    );
  }
}
