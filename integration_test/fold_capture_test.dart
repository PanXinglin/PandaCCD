import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/camera_session.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/editor_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Display handoff recalibrates camera; direct capture stays ready and reopens original edit',
    (tester) async {
      final app = AppState();
      await app.init();
      app.directSave = true;
      app.keepOriginal = false;
      app.select(0);
      app.update('grain', .73);
      await app.persist();
      expect((await app.library.readSettings())!['editAfterCapture'], isFalse);
      final session = CameraSession();
      await tester.pumpWidget(
        MaterialApp(
          home: CameraPage(state: app, session: session),
        ),
      );
      var frozenFrames = 0;
      Future<void> waitFor(bool Function() predicate) async {
        for (var i = 0; i < 120 && !predicate(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await tester.pump();
          expect(find.text('体验示例照片'), findsNothing);
          if (find
              .byKey(const ValueKey('ccd-frozen-preview'))
              .evaluate()
              .isNotEmpty) {
            frozenFrames++;
          }
        }
        expect(predicate(), isTrue);
      }

      await waitFor(
        () => session.controller?.value.isInitialized == true && !session.busy,
      );
      final old = session.controller;
      debugPrint('FOLD_READY_EXPAND');
      await waitFor(
        () =>
            MediaQuery.sizeOf(
                  tester.element(find.byType(CameraPage)),
                ).shortestSide >=
                600 &&
            session.controller != null &&
            !identical(old, session.controller) &&
            !session.busy,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(session.controller!.value.lockedCaptureOrientation, isNull);
      expect(frozenFrames, greaterThan(0));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      debugPrint(
        'FOLD_EXPANDED ${session.controller!.value.previewSize} ${session.controller!.value.deviceOrientation}',
      );
      final before = app.photos.length;
      await tester.tap(find.byKey(const ValueKey('ccd-shutter')));
      await waitFor(() => app.photos.length == before + 1);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(EditorPage), findsNothing);
      expect(find.byType(CameraPreview), findsOneWidget);
      final photo = app.photos.first;
      expect(
        await File(photo.path.replaceAll('.png', '.original')).exists(),
        isTrue,
      );
      final edit = await app.library.readEdit(photo);
      expect(edit!.recipe.presetId, 'g12');
      expect(edit.recipe.values['grain'], .73);
      app.select(1);
      await tester.tap(find.byTooltip('相册'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('再次编辑'));
      await tester.pumpAndSettle();
      final editor = tester.widget<EditorPage>(find.byType(EditorPage));
      expect(editor.initialEdit!.recipe.presetId, 'g12');
      expect(editor.initialEdit!.recipe.values['grain'], .73);
      expect(editor.retainSource, isTrue);
      expect(find.text('佳能 G12'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await waitFor(
        () => session.controller?.value.isInitialized == true && !session.busy,
      );
      final expanded = session.controller;
      debugPrint('FOLD_READY_CLOSE');
      await waitFor(
        () =>
            MediaQuery.sizeOf(
                  tester.element(find.byType(CameraPage)),
                ).shortestSide <
                600 &&
            session.controller != null &&
            !identical(expanded, session.controller) &&
            !session.busy,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        session.cameras.any(
          (camera) => camera.lensDirection == CameraLensDirection.front,
        ),
        isTrue,
      );
      await tester.tap(find.byTooltip('切换前后镜头'));
      await waitFor(
        () =>
            session.controller?.description.lensDirection ==
                CameraLensDirection.front &&
            !session.busy,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byTooltip('闪光灯'), findsNothing);
      await tester.tap(find.byTooltip('切换前后镜头'));
      await waitFor(
        () =>
            session.controller?.description.lensDirection ==
                CameraLensDirection.back &&
            !session.busy,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byTooltip('闪光灯'), findsOneWidget);
      app.directSave = false;
      await app.persist();
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
