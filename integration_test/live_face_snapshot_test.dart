import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/services/face_tracker.dart';
import 'package:panda_ccd/services/filter_engine.dart';
import 'fixtures/media_assets.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Bounded Live snapshots detect real faces and preserve mirror coordinates',
    (tester) async {
      final engine = FilterEngine();
      await engine.init();
      final image = await engine.decodePhoto(
        base64Decode(qaPortrait),
        maxEdge: 480,
      );
      final tracker = FaceTracker();
      await tracker.previewSnapshot(() async => image.clone(), mirrored: false);
      expect(tracker.faces, isNotEmpty);
      expect(tracker.faces.first.lowerJaw.length, 10);
      final previewKey = GlobalKey();
      Future<List<int>> renderPreview(double level) async {
        final shader = engine.shader(
          {
            ...parameterDefaults,
            'strength': 0,
            'beauty': .55,
            'beautySmooth': 0,
            'beautyEven': 0,
            'beautyWhiten': 0,
            'faceSlim': level,
          },
          engine.lut('g12'),
          faces: tracker.faces,
          imageFilter: true,
          trackFace: true,
        );
        await tester.pumpWidget(
          Center(
            child: RepaintBoundary(
              key: previewKey,
              child: SizedBox(
                width: 320,
                height: 320 * image.height / image.width,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.shader(shader),
                  child: RawImage(image: image, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
        );
        final frame = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(previewKey))
            .toImage();
        final bytes = (await frame.toByteData())!.buffer.asUint8List();
        frame.dispose();
        await tester.pumpWidget(const SizedBox());
        shader.dispose();
        return bytes;
      }

      final unwarped = await renderPreview(0);
      final warped = await renderPreview(1);
      var changedPixels = 0;
      for (var i = 0; i < unwarped.length; i += 4) {
        if ((unwarped[i] - warped[i]).abs() > 4) changedPixels++;
      }
      expect(changedPixels, greaterThan(100), reason: 'Live preview jaw warp');
      final root = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/media-qa',
      );
      await root.create(recursive: true);
      for (final level in [0.0, .25, 1.0]) {
        final bytes = await engine.render(
          image,
          {
            ...parameterDefaults,
            'strength': 0,
            'beauty': .7,
            'beautySmooth': 0,
            'beautyEven': 0,
            'beautyWhiten': 0,
            'faceSlim': level,
          },
          engine.lut('g12'),
          Watermark()
            ..date = false
            ..model = false,
          DateTime(2026),
          '',
          faces: tracker.faces,
          trackFace: true,
        );
        await File(
          '${root.path}/jaw-${(level * 100).round()}.png',
        ).writeAsBytes(bytes);
      }
      final center = tracker.faces.first.box.center;
      tracker.clear();
      await tracker.previewSnapshot(() async => image.clone(), mirrored: true);
      expect(tracker.faces, isNotEmpty);
      expect(tracker.faces.first.box.center.dx, closeTo(1 - center.dx, .02));
      expect(tracker.faces.first.box.center.dy, closeTo(center.dy, .02));
      // A rotation/lens handoff invalidates the previous coordinate system while
      // the bounded snapshot is in flight; it must not reintroduce the old face.
      await tracker.previewSnapshot(() async {
        tracker.clear();
        return image.clone();
      }, mirrored: false);
      expect(tracker.faces, isEmpty);
      tracker.dispose();
      image.dispose();
      engine.dispose();
      // Keep the UI binding alive for native method completions before teardown.
      await tester.pump();
      // Native QA artifacts are test-only; the driver retains them before uninstall.
      // ignore: avoid_print
      print('MEDIA_ARTIFACT_READY');
      await Future<void>.delayed(const Duration(seconds: 3));
    },
  );
}
