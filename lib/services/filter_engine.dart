import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/preset.dart';
import '../domain/frame_ratio.dart';
import '../domain/face_region.dart';

class LutImage {
  final ui.Image image;
  final int cube;
  LutImage(this.image, this.cube);
  static Future<LutImage> decode(Uint8List bytes) async {
    if (bytes.length > 16 * 1024 * 1024) {
      throw const FormatException('LUT PNG 不能超过 16MB');
    }
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 8 ||
        !List.generate(8, (i) => bytes[i] == signature[i]).every((v) => v)) {
      throw const FormatException('LUT 必须为 PNG 格式');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final side = descriptor.width;
      final level = math.pow(side, 1 / 3).round();
      if (side != descriptor.height ||
          level < 2 ||
          level > 8 ||
          level * level * level != side) {
        throw const FormatException(
          '需要正方形 HALD PNG（边长为 8、27、64、125、216、343、512；level 2–8）',
        );
      }
      final codec = await descriptor.instantiateCodec();
      try {
        return LutImage((await codec.getNextFrame()).image, level * level);
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }
}

class FilterEngine {
  // Diagnostic timings, not a device-independent frame-rate guarantee. The
  // second phase includes GPU readback as well as PNG encoding.
  ({Duration raster, Duration readbackAndEncode})? lastRenderTimings;
  late final ui.FragmentProgram program;
  final Map<String, LutImage> _luts = {};
  bool _disposed = false;
  Future<void> init() async {
    if (_luts.isNotEmpty) return;
    final compiled = await ui.FragmentProgram.fromAsset('shaders/ccd.frag');
    final loaded = await Future.wait(
      presets.map((preset) async {
        final bytes = await rootBundle.load('assets/luts/${preset.lut}.png');
        final lut = await LutImage.decode(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        return MapEntry(preset.id, lut);
      }),
      cleanUp: (entry) => entry.value.image.dispose(),
    );
    if (_disposed) {
      for (final entry in loaded) {
        entry.value.image.dispose();
      }
      return;
    }
    program = compiled;
    _luts.addEntries(loaded);
  }

  LutImage lut(String id) => _luts[id]!;
  ui.FragmentShader shader(
    Map<String, double> values,
    LutImage lut, {
    ui.Image? source,
    Size? size,
    List<FaceRegion> faces = const [],
    bool imageFilter = false,
    bool trackFace = false,
  }) {
    final shader = program.fragmentShader();
    if (size != null) {
      shader.setFloat(0, size.width);
      shader.setFloat(1, size.height);
    }
    var index = 2;
    for (final key in parameterDefaults.keys) {
      shader.setFloat(index++, values[key] ?? parameterDefaults[key]!);
    }
    shader.setFloat(index++, lut.image.width.toDouble());
    shader.setFloat(index++, lut.cube.toDouble());
    shader.setFloat(index++, imageFilter ? 1 : 0);
    shader.setFloat(index++, trackFace ? 1 : 0);
    for (var i = 0; i < FaceRegion.maxFaces; i++) {
      final data = i < faces.length ? faces[i] : null;
      for (final value in [
        data?.box.left ?? 0,
        data?.box.top ?? 0,
        data?.box.width ?? 0,
        data?.box.height ?? 0,
      ]) {
        shader.setFloat(index++, value.toDouble());
      }
      final points = data?.lowerJaw ?? const <Offset>[];
      for (var p = 0; p < 10; p++) {
        shader.setFloat(index++, points.length == 10 ? points[p].dx : 0);
        shader.setFloat(index++, points.length == 10 ? points[p].dy : 0);
      }
    }
    if (source != null) shader.setImageSampler(0, source);
    shader.setImageSampler(1, lut.image);
    return shader;
  }

  Future<ui.Image> decodePhoto(Uint8List bytes, {int maxEdge = 2560}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final scale = math.min(
        1.0,
        maxEdge / math.max(descriptor.width, descriptor.height),
      );
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round(),
        targetHeight: (descriptor.height * scale).round(),
      );
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

  Future<Uint8List> render(
    ui.Image source,
    Map<String, double> values,
    LutImage lut,
    Watermark watermark,
    DateTime date,
    String model, {
    int turns = 0,
    bool mirrorSource = false,
    bool square = false,
    double? frameAspect,
    List<FaceRegion> faces = const [],
    ui.ImageByteFormat byteFormat = ui.ImageByteFormat.png,
    bool trackFace = false,
  }) async {
    final crop = croppedFrameSize(
      Size(source.width.toDouble(), source.height.toDouble()),
      aspect: frameAspect,
      square: square,
    );
    final sw = crop.width, sh = crop.height;
    final size = Size(turns.isOdd ? sh : sw, turns.isOdd ? sw : sh);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(turns * math.pi / 2);
    if (mirrorSource) canvas.scale(-1, 1);
    canvas.translate(-sw / 2, -sh / 2);
    canvas.clipRect(Rect.fromLTWH(0, 0, sw, sh));
    canvas.translate(-(source.width - sw) / 2, -(source.height - sh) / 2);
    final shader = this.shader(
      values,
      lut,
      source: source,
      faces: faces,
      trackFace: trackFace,
      size: Size(source.width.toDouble(), source.height.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      Paint()..shader = shader,
    );
    canvas.restore();
    // Compose the watermark in the same GPU picture. Avoid rendering a full
    // intermediate image and then uploading/drawing it into a second image.
    paintWatermark(canvas, size, watermark, date, model);
    final picture = recorder.endRecording();
    ui.Image? result;
    final clock = Stopwatch()..start();
    try {
      result = await picture.toImage(size.width.round(), size.height.round());
      final rasterTime = clock.elapsed;
      clock.reset();
      final bytes = await result.toByteData(format: byteFormat);
      if (bytes == null) throw StateError('照片编码失败');
      lastRenderTimings = (
        raster: rasterTime,
        readbackAndEncode: clock.elapsed,
      );
      return bytes.buffer.asUint8List();
    } finally {
      result?.dispose();
      picture.dispose();
      shader.dispose();
    }
  }

  void dispose() {
    _disposed = true;
    for (final lut in _luts.values) {
      lut.image.dispose();
    }
    _luts.clear();
  }
}

String dateStamp(DateTime date) =>
    "'${(date.year % 100).toString().padLeft(2, '0')} ${date.month.toString().padLeft(2, '0')} ${date.day.toString().padLeft(2, '0')}";

void paintWatermark(
  Canvas canvas,
  Size size,
  Watermark stamp,
  DateTime date,
  String model,
) {
  if (!stamp.date && !stamp.model) return;
  final color = stamp.red ? const Color(0xffff534a) : const Color(0xffffc15b);
  final pixel = size.shortestSide * .0035;
  final dateText = dateStamp(date);
  final dateWidth = stamp.date ? dateText.length * 4 * pixel : 0.0;
  final painter = TextPainter(
    text: TextSpan(
      text: stamp.model ? watermarkLabel(stamp, model) : '',
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: size.shortestSide * .018,
        fontWeight: FontWeight.w700,
        letterSpacing: .8,
        color: color,
        shadows: const [
          Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(1, 1)),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: size.width * .88);
  final width = math.max(dateWidth, painter.width);
  final height = (stamp.date ? pixel * 8 : 0) + painter.height;
  final pad = size.shortestSide * .05;
  final origin = Offset(
    stamp.left ? pad : size.width - pad - width,
    stamp.top ? pad : size.height - pad - height,
  );
  if (stamp.date) {
    const glyphs = {
      '0': ['111', '101', '101', '101', '111'],
      '1': ['010', '110', '010', '010', '111'],
      '2': ['111', '001', '111', '100', '111'],
      '3': ['111', '001', '111', '001', '111'],
      '4': ['101', '101', '111', '001', '001'],
      '5': ['111', '100', '111', '001', '111'],
      '6': ['111', '100', '111', '101', '111'],
      '7': ['111', '001', '010', '010', '010'],
      '8': ['111', '101', '111', '101', '111'],
      '9': ['111', '101', '111', '001', '111'],
      "'": ['010', '010', '000', '000', '000'],
    };
    for (var i = 0; i < dateText.length; i++) {
      final rows = glyphs[dateText[i]];
      if (rows == null) continue;
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 3; x++) {
          if (rows[y][x] != '1') continue;
          final rect = Rect.fromLTWH(
            origin.dx + i * 4 * pixel + x * pixel,
            origin.dy + y * pixel,
            pixel * .88,
            pixel * .88,
          );
          canvas.drawRect(
            rect.shift(Offset(pixel * .35, pixel * .35)),
            Paint()..color = Colors.black54,
          );
          canvas.drawRect(rect, Paint()..color = color);
        }
      }
    }
  }
  if (stamp.model) {
    painter.paint(canvas, origin + Offset(0, stamp.date ? pixel * 8 : 0));
  }
  painter.dispose();
}
