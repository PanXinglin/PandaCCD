import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/domain/photo_edit.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/services/camera_session.dart';
import 'package:panda_ccd/services/system_gallery.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/camera_stage.dart';
import 'package:panda_ccd/ui/design_system.dart';
import 'package:panda_ccd/ui/gallery_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native batch cancel/confirm and live rotation retain preview and controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: PandaDesign.theme(), home: const Scaffold()),
      );
      final app = AppState();
      await app.init();
      app.library.root = await Directory.systemTemp.createTemp(
        'panda-batch-rotation-',
      );
      await app.refresh();
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 150 && !condition(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
        expect(condition(), isTrue);
      }

      debugPrint('BATCH_PERMISSIONS_READY');
      for (
        var i = 0;
        i < 100 && await app.systemGallery.access() != GalleryAccess.full;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(await app.systemGallery.access(), GalleryAccess.full);
      final bytes = await makeDemo();
      for (var i = 0; i < 3; i++) {
        await app.commitPhoto(
          bytes,
          PhotoEdit(
            Recipe(app.preset.id, app.parameters),
            Watermark(),
            DateTime.now(),
          ),
          original: bytes,
        );
      }
      final originals = app.photos.toList();
      await tester.pumpWidget(
        MaterialApp(
          theme: PandaDesign.theme(),
          home: GalleryPage(state: app),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tap(find.text('全选'));
      await tester.pump();
      expect(find.text('已选 3 张'), findsOneWidget);
      Future<void> confirmAppDialog() async {
        await tester.tap(find.byKey(const ValueKey('gallery-delete-selected')));
        await waitFor(() => find.text('删除这 3 张照片？').evaluate().isNotEmpty);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('删除 3 张'));
      }

      debugPrint('BATCH_DENY_READY');
      await confirmAppDialog();
      await waitFor(() => find.text('照片未删除').evaluate().isNotEmpty);
      expect(app.photos.length, 3);
      for (final photo in originals) {
        expect(await File(photo.path).exists(), isTrue);
      }
      debugPrint('BATCH_ALLOW_READY');
      await confirmAppDialog();
      await waitFor(() => app.photos.isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('暂无照片'), findsOneWidget);
      for (final photo in originals) {
        expect(await File(photo.path).exists(), isFalse);
        expect(
          await File(photo.path.replaceAll('.png', '.original')).exists(),
          isFalse,
        );
      }
      final camera = CameraSession();
      await camera
          .downgrade(); // Hold 30fps to isolate rotation from adaptive FPS.
      app.select(2);
      await tester.pumpWidget(
        MaterialApp(
          theme: PandaDesign.theme(),
          home: CameraPage(
            state: app,
            session: camera,
            orientation: CameraOrientation.disabled(),
          ),
        ),
      );
      await waitFor(
        () =>
            camera.controller?.value.isInitialized == true &&
            find.byType(CameraPreview).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      final controller = camera.controller;
      final preview = tester.element(find.byType(CameraPreview));
      final shutter = tester.element(find.byKey(const ValueKey('ccd-shutter')));
      final strip = tester.state(find.byType(CompactPresetStrip));
      void retained() {
        expect(camera.controller, same(controller));
        expect(tester.element(find.byType(CameraPreview)), same(preview));
        expect(
          tester.element(find.byKey(const ValueKey('ccd-shutter'))),
          same(shutter),
        );
        expect(tester.state(find.byType(CompactPresetStrip)), same(strip));
        expect(app.selected, 2);
      }

      expect(find.byKey(const ValueKey('ccd-control-rail')), findsNothing);
      debugPrint('ROTATE_LANDSCAPE_READY');
      await waitFor(
        () => find
            .byKey(const ValueKey('ccd-control-rail'))
            .evaluate()
            .isNotEmpty,
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      retained();
      debugPrint('ROTATE_PORTRAIT_READY');
      await waitFor(
        () => find.byKey(const ValueKey('ccd-control-rail')).evaluate().isEmpty,
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      retained();
      final shot = await camera.capture();
      expect(await shot.length(), greaterThan(100));
      await tester.pumpWidget(const SizedBox());
      await app.persist();
      await app.library.root.delete(recursive: true);
      app.dispose();
    },
  );
}
