import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// One bounded codec frame. RGBA transfer avoids per-frame PNG compression.
class VideoPixels {
  final Uint8List bytes;
  final int width, height;
  final bool bgra;
  const VideoPixels(this.bytes, this.width, this.height, {this.bgra = false});
  factory VideoPixels.fromMap(Map data) {
    final bytes = data['bytes'] as Uint8List,
        w = data['width'] as int,
        h = data['height'] as int;
    if (w <= 0 || h <= 0 || w > 2048 || h > 2048 || bytes.length != w * h * 4) {
      throw const FormatException('Invalid codec frame');
    }
    return VideoPixels(bytes, w, h, bgra: data['bgra'] == true);
  }
  Map<String, Object> get arguments => {
    'bytes': bytes,
    'width': width,
    'height': height,
    'bgra': bgra,
  };
  Future<ui.Image> decode() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      rowBytes: width * 4,
      pixelFormat: bgra ? ui.PixelFormat.bgra8888 : ui.PixelFormat.rgba8888,
    );
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
