import 'package:flutter/services.dart';

typedef PreviewStatus = ({int frame, int stable, int ageMs});

class PreviewHandoff {
  PreviewHandoff({this.stableFrames = 3});
  static const _channel = MethodChannel('panda_ccd/preview_status');

  final int stableFrames;
  int? _initialFrame;

  static Future<PreviewStatus?> read(int textureId) async {
    try {
      final status = await _channel.invokeMapMethod<String, int>(
        'get',
        textureId,
      );
      if (status == null) return null;
      return (
        frame: status['frame'] ?? 0,
        stable: status['stable'] ?? 0,
        ageMs: status['ageMs'] ?? 1000,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Require new frames from this texture, with optical settings settled. Native
  /// reports capture metadata only; this check never reads image pixels.
  bool observe(PreviewStatus? status) {
    if (status == null) return false;
    _initialFrame ??= status.frame;
    return status.frame - _initialFrame! >= 3 &&
        status.stable >= stableFrames &&
        status.ageMs < 150;
  }
}
