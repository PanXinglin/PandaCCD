import 'package:panda_ccd/services/camera_orientation.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/filter_engine.dart';
import 'package:panda_ccd/ui/camera_page.dart';

class _MemoryState extends AppState {
  @override
  Future<void> persist() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Old selected indices and recipes preserve creative looks after model insertion',
    () {
      for (var index = 0; index < legacyPresetIds.length; index++) {
        final selected = presetIndexFromSettings({'selected': index});
        expect(presets[selected].id, legacyPresetIds[index]);
        final original = creativePresets[index];
        expect(
          Recipe.decode(
            Recipe(original.id, original.parameters).encode(),
          ).presetId,
          original.id,
        );
      }
      expect(
        presets[presetIndexFromSettings({'selectedId': 'w830', 'selected': 0})]
            .id,
        'w830',
      );
      expect(presets[presetIndexFromSettings({'selected': -1})].id, 'g12');
      expect(presets.map((p) => p.id).toSet().length, presets.length);
    },
  );
  test(
    'Six camera looks render distinct pixels, with controlled neutral color casts',
    () async {
      final engine = FilterEngine();
      await engine.init();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const colors = [
        Color(0xff333333),
        Color(0xff777777),
        Color(0xffbbbbbb),
        Color(0xffd19b7c),
        Color(0xff2479b5),
        Color(0xff3f8449),
      ];
      for (var i = 0; i < colors.length; i++) {
        canvas.drawRect(
          Rect.fromLTWH(i * 16, 0, 16, 32),
          Paint()..color = colors[i],
        );
      }
      final picture = recorder.endRecording();
      final source = await picture.toImage(96, 32);
      picture.dispose();
      final outputs = <String>{};
      for (final preset in presets.where((p) => p.isCamera)) {
        final data = await engine.render(
          source,
          preset.parameters,
          engine.lut(preset.id),
          Watermark()
            ..date = false
            ..model = false,
          DateTime(2026),
          preset.stampLabel,
        );
        final image = await engine.decodePhoto(data);
        final pixels = (await image.toByteData())!.buffer.asUint8List();
        outputs.add(base64Encode(pixels));
        final gray = (16 * 96 + 24) * 4;
        final channels = [pixels[gray], pixels[gray + 1], pixels[gray + 2]]
          ..sort();
        expect(
          channels.last - channels.first,
          lessThan(25),
          reason:
              '${preset.name} must not turn neutral midtones into a strong tint',
        );
        expect(
          Recipe.decode(Recipe(preset.id, preset.parameters).encode()).values,
          preset.parameters,
        );
        image.dispose();
      }
      expect(
        outputs.length,
        6,
        reason:
            'The camera presets must not be renamed copies of the same look',
      );
      source.dispose();
      engine.dispose();
    },
  );
  testWidgets(
    'Camera library explains models and selects beyond the first five presets',
    (tester) async {
      final app = _MemoryState();
      await tester.runAsync(() async {
        await app.engine.init();
        app.library.root = await Directory.systemTemp.createTemp(
          'panda-models-',
        );
      });
      await tester.binding.setSurfaceSize(const Size(390, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: CameraPage(
            state: app,
            orientation: CameraOrientation.disabled(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final frame = tester.getRect(
        find.byKey(const ValueKey('ccd-preview-area')),
      );
      await tester.tap(find.byTooltip('选择机型'));
      await tester.pumpAndSettle();
      expect(find.text('机型灵感'), findsOneWidget);
      expect(find.textContaining('非原厂色彩标定'), findsOneWidget);
      expect(find.text('自然肤色 · 通透日常'), findsWidgets);
      final target = find.byKey(const ValueKey('ccd-model-f200exr'));
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await Scrollable.ensureVisible(tester.element(target), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(app.preset.id, 'f200exr');
      expect(find.text('富士 F200EXR').last.hitTestable(), findsOneWidget);
      app.select(presets.indexWhere((p) => p.id == 'pixel'));
      await tester.pumpAndSettle();
      expect(find.text('像素日记').last.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('ccd-preview-area'))),
        frame,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await app.library.root.delete(recursive: true);
      });
      app.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
}
