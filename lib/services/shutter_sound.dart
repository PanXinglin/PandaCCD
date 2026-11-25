import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class ShutterSound {
  ShutterSound({AudioPlayer Function()? createPlayer, bool? systemCaptureSound})
    : _createPlayer = createPlayer ?? AudioPlayer.new,
      _systemCaptureSound = systemCaptureSound ?? Platform.isIOS;

  final bool _systemCaptureSound;

  final AudioPlayer Function() _createPlayer;
  AudioPlayer? _player;
  Future<void>? _ready;
  bool _closed = false, _prepared = false;
  bool get isReady => _prepared && !_closed;
  Future<void> prepare() => _ready ??= _prepare();
  Future<void> _prepare() async {
    // AVFoundation already supplies the iPhone shutter sound. A second audio
    // player can deactivate the shared recording session when its clip ends.
    if (_systemCaptureSound) {
      _prepared = true;
      return;
    }
    try {
      final player = _createPlayer()..positionUpdater = null;
      _player = player;
      await player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            // Use the device's media volume. Some Android devices mute UI
            // sonification separately even with media volume turned up.
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        ),
      );
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(.9);
      await player.setSource(AssetSource('audio/shutter.wav'));
      _prepared = true;
    } catch (_) {
      // The platform click remains available if the bundled sample cannot load.
    }
  }

  Future<void> play() async {
    if (_closed || _systemCaptureSound) return;
    await prepare();
    if (_closed) return;
    try {
      final player = _player;
      if (_prepared && player != null) {
        await player.stop();
        if (_closed) return;
        await player.resume();
        return;
      }
    } catch (_) {}
    if (!_closed) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _closed = true;
    try {
      await _ready;
      await _player?.dispose();
    } catch (_) {}
  }
}
