// Optional local visual QA. Source photograph stays outside the app/assets.
// PANDA_BEAUTY_PHOTO=/absolute/photo.jpg flutter test tool/beauty_portrait_qa.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/filter_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Render portrait comparison with actual shared beauty shader', () async {
    final path = Platform.environment['PANDA_BEAUTY_PHOTO'];
    if (path == null) fail('Set PANDA_BEAUTY_PHOTO to a local portrait');
    final engine = FilterEngine();
    await engine.init();
    final photo = await engine.decodePhoto(
      await File(path).readAsBytes(),
      maxEdge: 1200,
    );
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const cellWidth = 600.0, cellHeight = 430.0;
    c.drawColor(Colors.white, BlendMode.src);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 3; col++) {
        final level = [0.0, .55, 1.0][col];
        final params = row == 0
            ? {...parameterDefaults, 'strength': 0.0, 'beauty': level}
            : {...presets.first.parameters, 'beauty': level};
        final bytes = await engine.render(
          photo,
          params,
          engine.lut(presets.first.id),
          Watermark()
            ..date = false
            ..model = false,
          DateTime(2026),
          'qa',
        );
        final rendered = await engine.decodePhoto(bytes);
        c.drawImageRect(
          rendered,
          Rect.fromLTWH(
            0,
            0,
            rendered.width.toDouble(),
            rendered.height.toDouble(),
          ),
          Rect.fromLTWH(col * cellWidth, row * cellHeight + 30, 600, 400),
          Paint(),
        );
        final text = TextPainter(
          text: TextSpan(
            text: '${row == 0 ? "Neutral" : "G12"} / beauty $level',
            style: const TextStyle(color: Colors.black, fontSize: 20),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(c, Offset(col * cellWidth + 10, row * cellHeight + 4));
        text.dispose();
        rendered.dispose();
      }
    }
    final picture = rec.endRecording();
    final result = await picture.toImage(1800, 860);
    await File('/tmp/panda-beauty-portrait-comparison.png').writeAsBytes(
      (await result.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List(),
    );
    result.dispose();
    picture.dispose();
    photo.dispose();
    engine.dispose();
  });
}
