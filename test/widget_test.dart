import 'package:panda_ccd/services/camera_orientation.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/filter_engine.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/design_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Portable recipes round-trip and reject corrupt values', () {
    final source = Recipe('jade', parameterDefaults).encode();
    expect(Recipe.decode(source).values, parameterDefaults);
    expect(() => Recipe.decode('{"version":2}'), throwsFormatException);
    expect(
      () => Recipe.decode(
        '{"version":1,"preset":"jade","parameters":{"grain":4}}',
      ),
      throwsFormatException,
    );
    expect(
      () => Recipe.decode(
        '{"version":1,"preset":"jade","parameters":{"unknown":0}}',
      ),
      throwsFormatException,
    );
  });
  test('HALD validation and identity shader preserve colors', () async {
    final engine = FilterEngine();
    await engine.init();
    final identity = await LutImage.decode(
      (await rootBundle.load('assets/luts/identity.png')).buffer.asUint8List(),
    );
    expect(identity.cube, 16);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(
      const Rect.fromLTWH(0, 0, 8, 4),
      Paint()..color = const Color(0xff4080c0),
    );
    c.drawRect(
      const Rect.fromLTWH(0, 4, 8, 4),
      Paint()..color = const Color(0xffd04080),
    );
    final picture = rec.endRecording();
    final source = await picture.toImage(8, 8);
    picture.dispose();
    final params = {
      ...parameterDefaults,
      'grain': 0.0,
      'bloom': 0.0,
      'vignette': 0.0,
    };
    final result = await engine.render(
      source,
      params,
      identity,
      Watermark()
        ..date = false
        ..model = false,
      DateTime(2026),
      'jade',
    );
    final decoded = await engine.decodePhoto(result);
    final data = (await decoded.toByteData())!;
    expect(data.getUint8(0), closeTo(64, 2));
    expect(data.getUint8(1), closeTo(128, 2));
    expect(data.getUint8(2), closeTo(192, 2));
    expect(data.getUint8(8 * 7 * 4), closeTo(208, 2));
    decoded.dispose();
    source.dispose();
    identity.image.dispose();
    engine.dispose();
  });
  test(
    'Export rotates and crops without changing output dimensions incorrectly',
    () async {
      final engine = FilterEngine();
      await engine.init();
      final rec = ui.PictureRecorder();
      Canvas(rec).drawColor(Colors.green, BlendMode.src);
      final pic = rec.endRecording();
      final image = await pic.toImage(12, 8);
      pic.dispose();
      for (final square in [false, true]) {
        final bytes = await engine.render(
          image,
          parameterDefaults,
          engine.lut('jade'),
          Watermark(),
          DateTime(2026),
          'jade',
          turns: 1,
          square: square,
        );
        final result = await engine.decodePhoto(bytes);
        expect(result.width, 8);
        expect(result.height, square ? 8 : 12);
        result.dispose();
      }
      image.dispose();
      engine.dispose();
    },
  );
  test(
    'Every frame ratio exports cropped pixels in both orientations',
    () async {
      final engine = FilterEngine();
      await engine.init();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.green, BlendMode.src);
      final picture = recorder.endRecording();
      final source = await picture.toImage(120, 160);
      picture.dispose();
      for (final entry in <double?, Size>{
        null: const Size(120, 160),
        1: const Size(120, 120),
        4 / 3: const Size(120, 160),
        3 / 2: const Size(107, 160),
        16 / 9: const Size(90, 160),
        5 / 4: const Size(120, 150),
      }.entries) {
        for (final turns in [0, 1]) {
          final bytes = await engine.render(
            source,
            parameterDefaults,
            engine.lut('jade'),
            Watermark(),
            DateTime(2026),
            'jade',
            frameAspect: entry.key,
            turns: turns,
          );
          final result = await engine.decodePhoto(bytes);
          expect(
            result.width,
            turns == 0 ? entry.value.width : entry.value.height,
          );
          expect(
            result.height,
            turns == 0 ? entry.value.height : entry.value.width,
          );
          result.dispose();
        }
      }
      source.dispose();
      engine.dispose();
    },
  );
  testWidgets('Camera UI supports portrait and landscape without overflow', (
    tester,
  ) async {
    final app = _TransientState();
    await tester.runAsync(() async {
      await app.engine.init();
      app.library.root = await Directory.systemTemp.createTemp('panda-test-');
    });
    for (final size in [
      const Size(390, 844),
      const Size(844, 390),
      const Size(320, 568),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: PandaDesign.theme(),
          home: CameraPage(
            state: app,
            orientation: CameraOrientation.disabled(),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('PandaCCD'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('佳能 IXUS 95 IS').last);
      await tester.pump();
      expect(app.selected, 1);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.runAsync(() async {
      await app.persist();
      await app.library.root.delete(recursive: true);
    });
    app.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}

class _TransientState extends AppState {
  @override
  Future<void> persist() async {}
}
