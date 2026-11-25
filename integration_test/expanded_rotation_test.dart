import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/services/camera_session.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/camera_viewport.dart';
import 'package:panda_ccd/ui/camera_stage.dart';
import 'package:panda_ccd/ui/design_system.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Expanded OS rotation and prolonged visible focus loss preserve live camera',
    (tester) async {
      final app = AppState();
      await app.init();
      debugPrint('EXPANDED_PERMISSION_READY');
      final camera = CameraSession();
      await camera.downgrade();
      final orientation = CameraOrientation();
      await tester.pumpWidget(
        MaterialApp(
          theme: PandaDesign.theme(),
          home: CameraPage(
            state: app,
            session: camera,
            orientation: orientation,
          ),
        ),
      );
      Future<void> waitFor(
        bool Function() ready, {
        void Function()? during,
      }) async {
        for (var i = 0; i < 300 && !ready(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 32));
          await tester.pump();
          during?.call();
        }
        expect(ready(), isTrue);
      }

      await waitFor(() => camera.controller?.value.isInitialized == true);
      await tester.pumpAndSettle();
      expect(orientation.expanded, isTrue);
      final controller = camera.controller;
      final texture = tester.element(find.byType(Texture));
      final preview = tester.element(find.byType(CameraPreview));
      final shutter = tester.element(find.byKey(const ValueKey('ccd-shutter')));
      final strip = tester.state(find.byType(CompactPresetStrip));
      final logical = MediaQuery.sizeOf(
        tester.element(find.byKey(const ValueKey('ccd-camera-canvas'))),
      );
      void retained() {
        expect(camera.controller, same(controller));
        expect(tester.element(find.byType(Texture)), same(texture));
        expect(tester.element(find.byType(CameraPreview)), same(preview));
        expect(
          tester.element(find.byKey(const ValueKey('ccd-shutter'))),
          same(shutter),
        );
        expect(tester.state(find.byType(CompactPresetStrip)), same(strip));
      }

      for (final pose in [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]) {
        debugPrint('EXPANDED_ROTATE_${pose.name}');
        await waitFor(
          () =>
              controller!.value.deviceOrientation == pose &&
              CameraViewportScope.maybeOf(
                    tester.element(
                      find.byKey(const ValueKey('ccd-camera-canvas')),
                    ),
                  )!.window ==
                  pose,
          during: retained,
        );
        for (var frame = 0; frame < 20; frame++) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
          await tester.pump();
          retained();
        }
        final current = MediaQuery.sizeOf(
          tester.element(find.byKey(const ValueKey('ccd-camera-canvas'))),
        );
        final landscape = pose != DeviceOrientation.portraitUp;
        expect(current.width > current.height, landscape);
        expect(
          (current.shortestSide - logical.shortestSide).abs(),
          lessThan(40),
        );
        expect((current.longestSide - logical.longestSide).abs(), lessThan(40));
        expect(
          CameraViewportScope.maybeOf(
            tester.element(find.byType(CameraPreview)),
          )!.turns,
          0,
        );
        final shot = await camera.capture();
        final codec = await ui.instantiateImageCodec(
          await File(shot.path).readAsBytes(),
        );
        final image = (await codec.getNextFrame()).image;
        debugPrint(
          'EXPANDED_PHOTO_${pose.name} ${image.width}x${image.height}',
        );
        expect(
          image.width > image.height,
          pose != DeviceOrientation.portraitUp,
        );
        image.dispose();
        codec.dispose();
      }
      debugPrint('EXPANDED_FOCUS_READY');
      await waitFor(() => !camera.active, during: retained);
      await waitFor(() => camera.active, during: retained);
      retained();
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
