import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/filter_engine.dart';
import 'package:panda_ccd/ui/camera_page.dart';

// Reference for the former two-image compositor. The filter itself is shared;
// this checks that removing the intermediate image preserves color/geometry.
Future<Uint8List> legacy(
  FilterEngine engine,
  ui.Image source,
  CcdPreset preset,
  Watermark stamp, {
  int turns = 0,
  bool square = false,
}) async {
  final edge = math.min(source.width, source.height).toDouble();
  final sw = square ? edge : source.width.toDouble();
  final sh = square ? edge : source.height.toDouble();
  final size = Size(turns.isOdd ? sh : sw, turns.isOdd ? sw : sh);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(size.width / 2, size.height / 2)
    ..rotate(turns * math.pi / 2)
    ..translate(-sw / 2, -sh / 2)
    ..clipRect(Rect.fromLTWH(0, 0, sw, sh))
    ..translate(-(source.width - sw) / 2, -(source.height - sh) / 2);
  final shader = engine.shader(
    preset.parameters,
    engine.lut(preset.id),
    source: source,
    size: Size(source.width.toDouble(), source.height.toDouble()),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  picture.dispose();
  shader.dispose();
  final sr = ui.PictureRecorder();
  final sc = Canvas(sr)..drawImage(image, Offset.zero, Paint());
  paintWatermark(sc, size, stamp, DateTime(2026, 10, 27), preset.stampLabel);
  final sp = sr.endRecording();
  final output = await sp.toImage(size.width.round(), size.height.round());
  final bytes = (await output.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  output.dispose();
  image.dispose();
  sp.dispose();
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Single image compositor matches previous colors, watermark and rotation',
    (tester) async {
      final engine = FilterEngine();
      await engine.init();
      final source = await engine.decodePhoto(await makeDemo());
      for (var index = 0; index < presets.length; index++) {
        final preset = presets[index];
        final stamp = Watermark()
          ..red = index.isEven
          ..top = index % 3 == 0
          ..left = index % 4 == 0;
        if (index == 3) stamp.text = '今天也要开心';
        final turns = index % 4;
        final square = index % 3 == 0;
        final expected = await legacy(
          engine,
          source,
          preset,
          stamp,
          turns: turns,
          square: square,
        );
        final png = await engine.render(
          source,
          preset.parameters,
          engine.lut(preset.id),
          stamp,
          DateTime(2026, 10, 27),
          preset.stampLabel,
          turns: turns,
          square: square,
        );
        final decoded = await engine.decodePhoto(png);
        final actual = (await decoded.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(actual.length, expected.length);
        var maxDifference = 0, changed = 0;
        for (var p = 0; p < actual.length; p++) {
          final difference = (actual[p] - expected[p]).abs();
          if (difference > maxDifference) maxDifference = difference;
          if (difference > 0) changed++;
        }
        debugPrint(
          'CCD_EQUIV ${preset.id} max=$maxDifference changed=$changed total=${actual.length}',
        );
        expect(maxDifference, lessThanOrEqualTo(1), reason: preset.id);
        decoded.dispose();
      }
      source.dispose();
      engine.dispose();
    },
  );
}
