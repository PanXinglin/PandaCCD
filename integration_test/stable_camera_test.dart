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
import 'package:panda_ccd/ui/design_system.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Real grip keeps compact window and live texture stable; capture follows grip',
    (tester) async {
      final app = AppState();
      await app.init();
      final camera = CameraSession();
      final grip = CameraOrientation();
      await tester.pumpWidget(
        MaterialApp(
          theme: PandaDesign.theme(),
          home: CameraPage(state: app, session: camera, orientation: grip),
        ),
      );
      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 200 && !ready(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
        expect(ready(), isTrue);
      }

      debugPrint('STABLE_PERMISSION_READY');
      await waitFor(() => camera.controller?.value.isInitialized == true);
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();
      final controller = camera.controller!;
      final preview = tester.element(find.byType(CameraPreview));
      final shutter = tester.getRect(find.byKey(const ValueKey('ccd-shutter')));
      final window = MediaQuery.sizeOf(
        tester.element(find.byType(CameraPreview)),
      );
      final initialTexture = tester.element(find.byType(Texture).first);
      for (final pose in [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]) {
        debugPrint('STABLE_GRIP_${pose.name}');
        await waitFor(() => grip.orientation == pose);
        for (var frame = 0; frame < 30; frame++) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
          await tester.pump();
          expect(camera.controller, same(controller));
          expect(tester.element(find.byType(CameraPreview)), same(preview));
          expect(find.byType(Texture), findsOneWidget);
          expect(tester.element(find.byType(Texture)), same(initialTexture));
          expect(
            tester.getRect(find.byKey(const ValueKey('ccd-shutter'))),
            shutter,
          );
          expect(
            MediaQuery.sizeOf(tester.element(find.byType(CameraPreview))),
            window,
          );
        }
        final shot = await camera.capture(orientation: grip.orientation);
        final codec = await ui.instantiateImageCodec(
          await File(shot.path).readAsBytes(),
        );
        final image = (await codec.getNextFrame()).image;
        debugPrint('STABLE_PHOTO_${pose.name} ${image.width}x${image.height}');
        expect(
          image.width > image.height,
          pose != DeviceOrientation.portraitUp,
        );
        image.dispose();
        codec.dispose();
      }
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
