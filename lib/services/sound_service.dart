import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final _player = AudioPlayer();

  /// Plays the system alert sound when a timer session completes.
  Future<void> playAlert() async {
    try {
      if (Platform.isMacOS) {
        // macOS built-in sounds — no asset file needed
        await _player
            .play(DeviceFileSource('/System/Library/Sounds/Glass.aiff'));
      } else if (Platform.isWindows) {
        await _player.play(
            DeviceFileSource('C:\\Windows\\Media\\Windows Notify.wav'));
      }
      // Android / iOS: handled by the notification sound itself
    } catch (_) {}
  }
}
