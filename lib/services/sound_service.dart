import 'dart:ffi';
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
        // Use user32.dll MessageBeep — always available, no file dependency.
        // MB_ICONINFORMATION (0x40) plays the system "asterisk" sound.
        final user32 = DynamicLibrary.open('user32.dll');
        final messageBeep = user32.lookupFunction<
            Int32 Function(Uint32), int Function(int)>('MessageBeep');
        messageBeep(0x00000040);
      }
      // Android / iOS: handled by the notification sound itself
    } catch (_) {}
  }
}
