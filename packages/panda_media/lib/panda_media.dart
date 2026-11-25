import 'package:flutter/services.dart';

/// System codecs/detectors only. All color and face warping lives in ccd.frag.
abstract final class PandaMedia {
  static const channel = MethodChannel('panda_ccd/media');
  static Future<T?> call<T>(String method, [Map<String, Object?>? args]) =>
      channel.invokeMethod<T>(method, args);
}
