import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:panda_media/panda_media.dart';
import '../domain/face_region.dart';

class FaceTracker extends ChangeNotifier {
  List<FaceRegion> faces = const [];
  bool _busy = false, _closed = false;
  int _last = 0, _missed = 0, _generation = 0;
  String? error;
  static List<FaceRegion> parse(Object? raw) => (raw as List? ?? const [])
      .whereType<Map>()
      .map(FaceRegion.fromJson)
      .take(FaceRegion.maxFaces)
      .toList();
  static Future<List<FaceRegion>> detect(ui.Image image) async {
    final lease = image.clone();
    try {
      // Detection uses a bounded copy, never a full-resolution per-preview readback.
      final scale = lease.width > lease.height
          ? 960 / lease.width
          : 960 / lease.height;
      ui.Image? small;
      if (scale < 1) {
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec);
        c.scale(scale);
        c.drawImage(lease, ui.Offset.zero, ui.Paint());
        final pic = rec.endRecording();
        small = await pic.toImage(
          (lease.width * scale).round(),
          (lease.height * scale).round(),
        );
        pic.dispose();
      }
      try {
        final data = await (small ?? lease).toByteData(
          format: ui.ImageByteFormat.png,
        );
        return parse(
          await PandaMedia.call<List>('detectPhoto', {
            'bytes': data!.buffer.asUint8List(),
          }),
        );
      } finally {
        small?.dispose();
      }
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    } finally {
      lease.dispose();
    }
  }

  static Future<List<FaceRegion>> detectPixels(
    Map<String, Object> pixels,
  ) async {
    try {
      return parse(await PandaMedia.call<List>('detectPixels', pixels));
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Low-resolution unfiltered preview sampling for CameraX Live. Never combine
  /// video + ImageAnalysis on affected devices; image effects still run on GPU.
  Future<void> previewSnapshot(
    Future<ui.Image?> Function() capture, {
    required bool mirrored,
  }) async {
    if (_busy || _closed) return;
    _busy = true;
    final generation = _generation;
    ui.Image? image;
    try {
      image = await capture();
      if (image == null || _closed || generation != _generation) return;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return;
      var next = await detectPixels({
        'bytes': bytes.buffer.asUint8List(),
        'width': image.width,
        'height': image.height,
        'bgra': false,
      });
      if (mirrored) next = next.map((f) => f.mirrored()).toList();
      _accept(next, generation);
    } catch (_) {
      if (!_closed && generation == _generation) {
        error = '人脸识别暂不可用';
        faces = const [];
        notifyListeners();
      }
    } finally {
      image?.dispose();
      _busy = false;
    }
  }

  void _accept(List<FaceRegion> next, int generation) {
    if (_closed || generation != _generation) return;
    error = null;
    if (next.isEmpty) {
      if (++_missed < 2) return;
      faces = const [];
    } else {
      _missed = 0;
      faces = FaceRegion.stabilize(faces, next, .55);
    }
    notifyListeners();
  }

  Future<void> frame(
    CameraImage image,
    CameraDescription lens,
    DeviceOrientation orientation,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_busy || _closed || now - _last < 180) return;
    _busy = true;
    final generation = _generation;
    _last = now;
    try {
      final compensation = switch (orientation) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 90,
        DeviceOrientation.portraitDown => 180,
        DeviceOrientation.landscapeRight => 270,
      };
      final rotation = Platform.isAndroid
          ? (lens.sensorOrientation +
                    (lens.lensDirection == CameraLensDirection.front
                        ? compensation
                        : -compensation) +
                    360) %
                360
          : switch (orientation) {
              DeviceOrientation.portraitUp => 0,
              DeviceOrientation.landscapeRight => 90,
              DeviceOrientation.portraitDown => 180,
              DeviceOrientation.landscapeLeft => 270,
            };
      final Uint8List bytes;
      if (Platform.isIOS || image.planes.length == 1) {
        bytes = image.planes.first.bytes;
      } else {
        // CameraX may label a three-plane NV21 buffer YUV420; honor plane strides.
        bytes = Uint8List(image.width * image.height * 3 ~/ 2);
        final y = image.planes[0], u = image.planes[1], v = image.planes[2];
        for (var row = 0; row < image.height; row++) {
          bytes.setRange(
            row * image.width,
            (row + 1) * image.width,
            y.bytes,
            row * y.bytesPerRow,
          );
        }
        var out = image.width * image.height;
        for (var row = 0; row < image.height ~/ 2; row++) {
          for (var col = 0; col < image.width ~/ 2; col++) {
            bytes[out++] =
                v.bytes[row * v.bytesPerRow + col * (v.bytesPerPixel ?? 1)];
            bytes[out++] =
                u.bytes[row * u.bytesPerRow + col * (u.bytesPerPixel ?? 1)];
          }
        }
      }
      final next = parse(
        await PandaMedia.call<List>('detectFrame', {
          'bytes': bytes,
          'width': image.width,
          'height': image.height,
          'stride': image.planes.first.bytesPerRow,
          'rotation': rotation,
          'mirrored':
              Platform.isIOS && lens.lensDirection == CameraLensDirection.front,
        }),
      );
      _accept(next, generation);
    } catch (e) {
      if (!_closed && generation == _generation) {
        error = '人脸识别暂不可用';
        faces = const [];
        notifyListeners();
      }
    } finally {
      _busy = false;
    }
  }

  void clear() {
    _generation++;
    _last = 0;
    faces = const [];
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
