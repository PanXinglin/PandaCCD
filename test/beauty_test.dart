import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/filter_engine.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/beauty_panel.dart';

class _MemoryState extends AppState {
  @override
  Future<void> persist() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Beauty is opt-in, survives model changes and exports with the recipe',
    () {
      final app = _MemoryState();
      expect(app.parameters['beauty'], 0);
      app.toggleBeauty();
      expect(app.parameters['beauty'], .55);
      app.select(1);
      expect(app.parameters['beauty'], .55);
      expect(Recipe.decode(app.recipe.encode()).values['beauty'], .55);
      app.toggleBeauty();
      expect(app.parameters['beauty'], 0);
      // Recipes saved before beauty was introduced remain unchanged by default.
      expect(
        Recipe.decode(
          '{"version":1,"preset":"jade","parameters":{}}',
        ).values['beauty'],
        0,
      );
      app.dispose();
    },
  );

  testWidgets('Viewfinder beauty can be explicitly enabled and disabled', (
    tester,
  ) async {
    final app = _MemoryState();
    await tester.binding.setSurfaceSize(const Size(424, 622));
    await tester.pumpWidget(
      MaterialApp(
        home: CameraPage(state: app, orientation: CameraOrientation.disabled()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('美颜'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.byTooltip('美颜'));
    await tester.pumpAndSettle();
    expect(app.parameters['beauty'], 0);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(app.parameters['beauty'], .55);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(app.parameters['beauty'], 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
    app.dispose();
  });
  testWidgets(
    'Beauty controls stay outside the live canvas in portrait, short and unfolded windows',
    (tester) async {
      final app = _MemoryState();
      for (final size in [
        const Size(320, 480),
        const Size(390, 844),
        const Size(844, 390),
        const Size(820, 710),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.4)),
              child: child!,
            ),
            home: CameraPage(
              state: app,
              orientation: CameraOrientation.disabled(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('美颜'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        final canvas = tester.getRect(
          find.byKey(const ValueKey('ccd-camera-canvas')),
        );
        final panel = tester.getRect(find.byType(BeautyPanel));
        expect(
          canvas.overlaps(panel),
          false,
          reason:
              'A user must see the entire viewfinder while adjusting beauty',
        );
        final slider = find.byKey(const ValueKey('ccd-beauty-slider'));
        await tester.drag(slider, const Offset(24, 0));
        await tester.pumpAndSettle();
        expect(app.beautyEnabled, true);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('收起美颜调节'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
      await tester.binding.setSurfaceSize(null);
      app.dispose();
    },
  );
  test(
    'GPU beauty softens skin texture while preserving non-skin color and a hard edge',
    () async {
      final engine = FilterEngine();
      await engine.init();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final delta = (x + y).isEven ? 7 : -7;
          final color = x < 32
              ? Color.fromARGB(255, 184 + delta, 128 + delta, 100 + delta)
              : const Color(0xff2080d0);
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
            Paint()..color = color,
          );
        }
      }
      final picture = rec.endRecording();
      final source = await picture.toImage(64, 64);
      picture.dispose();
      Future<ui.Image> render(double beauty, {bool trackFace = false}) async =>
          engine.decodePhoto(
            await engine.render(
              source,
              {...parameterDefaults, 'strength': 0, 'beauty': beauty},
              engine.lut('jade'),
              Watermark()
                ..date = false
                ..model = false,
              DateTime(2026),
              'jade',
              trackFace: trackFace,
            ),
          );
      final off = await render(0);
      final on = await render(1);
      final noFace = await render(1, trackFace: true);
      final a = (await off.toByteData())!;
      final b = (await on.toByteData())!;
      expect(
        (await noFace.toByteData())!.buffer.asUint8List(),
        a.buffer.asUint8List(),
        reason:
            'Production face tracking must not smooth skin-colored backgrounds without a face',
      );
      int red(ByteData data, int x, int y) => data.getUint8((y * 64 + x) * 4);
      final originalTexture = (red(a, 8, 8) - red(a, 9, 8)).abs();
      final softenedTexture = (red(b, 8, 8) - red(b, 9, 8)).abs();
      expect(originalTexture, greaterThan(10));
      expect(softenedTexture, lessThan(originalTexture * .7));
      for (var channel = 0; channel < 4; channel++) {
        final i = (8 * 64 + 48) * 4 + channel;
        expect(b.getUint8(i), closeTo(a.getUint8(i), 1));
      }
      expect((red(b, 31, 20) - red(b, 32, 20)).abs(), greaterThan(100));
      off.dispose();
      on.dispose();
      noFace.dispose();
      source.dispose();
      engine.dispose();
    },
  );
  test(
    'Default beauty remains visible after CCD grain and preserves non-skin grain',
    () async {
      final engine = FilterEngine();
      await engine.init();
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(
        const Rect.fromLTWH(0, 0, 48, 96),
        Paint()..color = const Color(0xffb88064),
      );
      c.drawRect(
        const Rect.fromLTWH(48, 0, 48, 96),
        Paint()..color = const Color(0xff2080d0),
      );
      final picture = rec.endRecording();
      final source = await picture.toImage(96, 96);
      picture.dispose();
      Future<ui.Image> render(double beauty) async => engine.decodePhoto(
        await engine.render(
          source,
          {
            ...parameterDefaults,
            'grain': .8,
            'beauty': beauty,
            'vignette': 0,
            'bloom': 0,
          },
          engine.lut('jade'),
          Watermark()
            ..date = false
            ..model = false,
          DateTime(2026),
          'jade',
        ),
      );
      final off = await render(0);
      final on = await render(.55);
      final a = (await off.toByteData())!;
      final b = (await on.toByteData())!;
      double variance(ByteData data, int startX) {
        final samples = <double>[];
        for (var y = 16; y < 80; y++) {
          for (var x = startX; x < startX + 24; x++) {
            samples.add(data.getUint8((y * 96 + x) * 4).toDouble());
          }
        }
        final mean = samples.reduce((x, y) => x + y) / samples.length;
        return samples
                .map((x) => (x - mean) * (x - mean))
                .reduce((x, y) => x + y) /
            samples.length;
      }

      expect(variance(b, 12), lessThan(variance(a, 12) * .3));
      expect(variance(b, 60), closeTo(variance(a, 60), 1));
      off.dispose();
      on.dispose();
      source.dispose();
      engine.dispose();
    },
  );
}
