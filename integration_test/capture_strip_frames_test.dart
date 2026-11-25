import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/main.dart' as panda;
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/camera_stage.dart';
import 'package:panda_ccd/ui/capture_feedback.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Real app capture keeps strip geometry stable at display-frame intervals',
    (tester) async {
      panda.main();
      for (
        var i = 0;
        i < 100 && find.byType(CameraPage).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      final app = tester.widget<CameraPage>(find.byType(CameraPage)).state;
      app.directSave = true;
      app.select(2);
      await app.persist();
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final strip = find.byType(CompactPresetStrip);
      final scrollable = find.descendant(
        of: strip,
        matching: find.byType(Scrollable),
      );
      final scroll = tester.state<ScrollableState>(scrollable).position;
      final original = tester.state(strip);
      final before = tester.getRect(find.text('佳能 IXUS 130').last);
      final pixels = scroll.pixels;
      Future<Uint8List> stripPixels() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('ccd-preset-strip-layer')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return Uint8List.fromList(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }

      final referencePixels = await stripPixels();
      var shutterEvents = 0;
      final shots = tester
          .widget<ShutterPulse>(find.byType(ShutterPulse))
          .shots;
      void onShot() {
        shutterEvents++;
        final fade = tester.widget<FadeTransition>(
          find.descendant(
            of: find.byType(ShutterPulse),
            matching: find.byType(FadeTransition),
          ),
        );
        expect(fade.opacity.value, greaterThan(.3));
      }

      shots.addListener(onShot);
      final count = app.photos.length;
      final semantics = tester.ensureSemantics();
      final rect = tester.getRect(
        find.byKey(const ValueKey('ccd-preset-strip-layer')),
      );
      final ratio = View.of(tester.element(strip)).devicePixelRatio;
      debugPrint(
        'STRIP_VIDEO_REGION ${(rect.left * ratio).round()} ${(rect.top * ratio).round()} ${(rect.width * ratio).round()} ${(rect.height * ratio).round()}',
      );
      debugPrint('STRIP_VIDEO_READY');
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('ccd-shutter')));
      var frame = 0;
      final clock = Stopwatch()..start();
      while (clock.elapsed < const Duration(seconds: 8)) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        await tester.pump();
        expect(
          tester.state(strip),
          same(original),
          reason: 'strip state at frame $frame',
        );
        expect(
          scroll.pixels,
          closeTo(pixels, .01),
          reason: 'scroll at frame $frame',
        );
        expect(
          tester.getRect(find.text('佳能 IXUS 130').last),
          before,
          reason: 'text geometry at frame $frame',
        );
        expect(
          await stripPixels(),
          referencePixels,
          reason: 'rendered strip pixels at frame $frame',
        );
        frame++;
      }
      expect(frame, greaterThan(60));
      debugPrint('STRIP_PIXEL_FRAMES $frame');
      expect(app.photos.length, count + 1);
      expect(shutterEvents, 1);
      shots.removeListener(onShot);
      debugPrint('STRIP_VIDEO_DONE');
      await Future<void>.delayed(const Duration(seconds: 2));
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
