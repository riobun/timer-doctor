import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/timer_state.dart';

const _builtInPresets = [
  TimerPreset(
    id: 'eye',
    name: '保护眼睛',
    intervalMinutes: 30,
    snoozeMinutes: 2,
    isBuiltIn: true,
  ),
  TimerPreset(
    id: 'pomodoro',
    name: '番茄钟',
    intervalMinutes: 25,
    snoozeMinutes: 5,
    isBuiltIn: true,
  ),
  TimerPreset(
    id: 'focus50',
    name: '专注 50',
    intervalMinutes: 50,
    snoozeMinutes: 10,
    isBuiltIn: true,
  ),
  TimerPreset(
    id: 'short',
    name: '短计时',
    intervalMinutes: 10,
    snoozeMinutes: 2,
    isBuiltIn: true,
  ),
  TimerPreset(
    id: 'long',
    name: '长专注',
    intervalMinutes: 90,
    snoozeMinutes: 15,
    isBuiltIn: true,
  ),
];

class PresetNotifier extends StateNotifier<List<TimerPreset>> {
  PresetNotifier() : super(_builtInPresets) {
    _loadUserPresets();
  }

  Future<void> _loadUserPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_presets');
    if (raw == null) return;
    try {
      final list = (json.decode(raw) as List)
          .map((e) => TimerPreset.fromJson(e as Map<String, dynamic>))
          .toList();
      state = [..._builtInPresets, ...list];
    } catch (_) {}
  }

  Future<void> _saveUserPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final userPresets = state.where((p) => !p.isBuiltIn).toList();
    await prefs.setString(
      'user_presets',
      json.encode(userPresets.map((p) => p.toJson()).toList()),
    );
  }

  void add(String name, int intervalMinutes, int snoozeMinutes) {
    final preset = TimerPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      intervalMinutes: intervalMinutes,
      snoozeMinutes: snoozeMinutes,
    );
    state = [...state, preset];
    _saveUserPresets();
  }

  void remove(String id) {
    state = state.where((p) => p.id != id).toList();
    _saveUserPresets();
  }
}

final presetProvider =
    StateNotifierProvider<PresetNotifier, List<TimerPreset>>(
  (ref) => PresetNotifier(),
);
