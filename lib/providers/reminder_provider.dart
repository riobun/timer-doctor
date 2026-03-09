import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/overlay_service.dart';

class ReminderState {
  final bool enabled;
  final String text;
  final double fontSize;
  final int textColorValue; // ARGB
  final int bgColorValue;   // ARGB (alpha ignored, use bgOpacity)
  final double bgOpacity;

  const ReminderState({
    this.enabled = false,
    this.text = '保持专注！',
    this.fontSize = 14.0,
    this.textColorValue = 0xFFFFFFFF,
    this.bgColorValue = 0xFF141414,
    this.bgOpacity = 0.5,
  });

  ReminderState copyWith({
    bool? enabled,
    String? text,
    double? fontSize,
    int? textColorValue,
    int? bgColorValue,
    double? bgOpacity,
  }) =>
      ReminderState(
        enabled: enabled ?? this.enabled,
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
        textColorValue: textColorValue ?? this.textColorValue,
        bgColorValue: bgColorValue ?? this.bgColorValue,
        bgOpacity: bgOpacity ?? this.bgOpacity,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'text': text,
        'fontSize': fontSize,
        'textColorValue': textColorValue,
        'bgColorValue': bgColorValue,
        'bgOpacity': bgOpacity,
      };

  factory ReminderState.fromJson(Map<String, dynamic> json) => ReminderState(
        enabled: json['enabled'] as bool? ?? false,
        text: json['text'] as String? ?? '保持专注！',
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
        textColorValue: (json['textColorValue'] as num?)?.toInt() ?? 0xFFFFFFFF,
        bgColorValue: (json['bgColorValue'] as num?)?.toInt() ?? 0xFF141414,
        bgOpacity: (json['bgOpacity'] as num?)?.toDouble() ?? 0.5,
      );
}

class ReminderNotifier extends StateNotifier<ReminderState> {
  ReminderNotifier() : super(const ReminderState()) {
    _load();
  }

  static const _key = 'reminder_state';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final loaded =
            ReminderState.fromJson(json.decode(raw) as Map<String, dynamic>);
        // 每次启动默认关闭，只恢复文字和样式
        state = loaded.copyWith(enabled: false);
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(state.toJson()));
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
    if (enabled) {
      OverlayService.show(state.text);
      OverlayService.updateStyle(
        fontSize: state.fontSize,
        textColor: state.textColorValue,
        bgColor: state.bgColorValue,
        bgOpacity: state.bgOpacity,
      );
    } else {
      OverlayService.hide();
    }
    _save();
  }

  void setText(String text) {
    if (text.isEmpty) return;
    state = state.copyWith(text: text);
    if (state.enabled) OverlayService.updateText(text);
    _save();
  }

  void setStyle({
    double? fontSize,
    int? textColorValue,
    int? bgColorValue,
    double? bgOpacity,
  }) {
    state = state.copyWith(
      fontSize: fontSize,
      textColorValue: textColorValue,
      bgColorValue: bgColorValue,
      bgOpacity: bgOpacity,
    );
    if (state.enabled) {
      OverlayService.updateStyle(
        fontSize: state.fontSize,
        textColor: state.textColorValue,
        bgColor: state.bgColorValue,
        bgOpacity: state.bgOpacity,
      );
    }
    _save();
  }
}

final reminderProvider =
    StateNotifierProvider<ReminderNotifier, ReminderState>(
        (_) => ReminderNotifier());
