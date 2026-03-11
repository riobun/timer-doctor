import 'dart:io';

import 'package:flutter/services.dart';

class OverlayService {
  static const _channel = MethodChannel('timer_doctor/overlay');

  static bool get _supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isAndroid || Platform.isIOS;

  static Future<void> show(String text) async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('show', {'text': text});
  }

  static Future<void> hide() async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('hide');
  }

  static Future<void> updateText(String text) async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('updateText', {'text': text});
  }

  static Future<void> updateStyle({
    required double fontSize,
    required int textColor,
    required int bgColor,
    required double bgOpacity,
  }) async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('updateStyle', {
      'fontSize': fontSize,
      'textColor': textColor,
      'bgColor': bgColor,
      'bgOpacity': bgOpacity,
    });
  }

  /// Android only: whether SYSTEM_ALERT_WINDOW permission is granted.
  static Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return true;
    final result = await _channel.invokeMethod<bool>('checkPermission');
    return result ?? false;
  }

  /// Android only: open system settings to grant SYSTEM_ALERT_WINDOW.
  static Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('requestPermission');
  }
}
