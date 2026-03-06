import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app_keys.dart';

typedef TrayActionCallback = void Function(String action);

class TrayService with TrayListener, WindowListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  TrayActionCallback? onAction;

  Future<void> initialize() async {
    // Intercept window close → hide to tray instead of quit
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    trayManager.addListener(this);
    final iconPath = await _buildIconFile();
    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('Timer Doctor');
    await _rebuildMenu(null);
  }

  /// Draws a small indigo clock icon at runtime — no asset file needed.
  Future<String> _buildIconFile() async {
    const size = 22.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Background circle
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2),
      size / 2 - 1,
      ui.Paint()..color = const ui.Color(0xFF6366F1),
    );

    // Clock hands
    final hand = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..strokeWidth = 1.8
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawLine(
        const ui.Offset(11, 11), const ui.Offset(11, 5), hand); // 12 o'clock
    canvas.drawLine(
        const ui.Offset(11, 11), const ui.Offset(15, 13), hand); // 3 o'clock

    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/td_tray_icon.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file.path;
  }

  Future<void> updateStatus({required bool isRunning, String? timeLeft}) async {
    await _rebuildMenu(isRunning ? (timeLeft ?? '运行中') : null);
  }

  /// Shows [text] next to the tray icon in the menu bar. Pass null to clear.
  Future<void> setTitle(String? text) async {
    await trayManager.setTitle(text ?? '');
  }

  Future<void> _rebuildMenu(String? statusText) async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(label: 'Timer Doctor', disabled: true),
      MenuItem.separator(),
      if (statusText != null) ...[
        MenuItem(label: '⏱  $statusText', disabled: true),
        MenuItem.separator(),
      ],
      MenuItem(key: 'show', label: '显示窗口'),
      MenuItem.separator(),
      MenuItem(key: 'start', label: '开始专注'),
      MenuItem(key: 'stop', label: '停止计时'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: '退出应用'),
    ]));
  }

  // ── TrayListener ──────────────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
        break;
      case 'quit':
        exit(0);
        break;
      default:
        if (item.key != null) onAction?.call(item.key!);
    }
  }

  // ── WindowListener ────────────────────────────────────────────────────────

  @override
  void onWindowClose() async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      await windowManager.hide();
      return;
    }

    final shouldQuit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关闭'),
        content: const Text('要最小化到菜单栏，还是退出应用？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('最小化到菜单栏'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('退出应用'),
          ),
        ],
      ),
    );

    if (shouldQuit == true) {
      exit(0);
    } else {
      await windowManager.hide();
    }
  }
}
