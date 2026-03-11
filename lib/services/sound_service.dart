import 'package:audioplayers/audioplayers.dart';

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final _player = AudioPlayer();

  /// 专注结束时播放（欢快的铃声）
  Future<void> playWorkAlert() => _play('sounds/alert_work.mp3');

  /// 休息结束时播放（舒缓的铃声）
  Future<void> playSnoozeAlert() => _play('sounds/alert_snooze.mp3');

  Future<void> _play(String asset) async {
    try {
      await _player.play(AssetSource(asset));
    } catch (_) {}
  }
}
