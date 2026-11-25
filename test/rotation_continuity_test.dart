import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/camera_session.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/camera_stage.dart';

class _State extends AppState {
  @override
  Future<void> persist() async {}
}

class _Camera extends CameraSession {
  int restarts = 0;
  _Camera() {
    controller = CameraController(
      const CameraDescription(
        name: 'test',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
      ResolutionPreset.high,
    );
    controller!.value = controller!.value.copyWith(
      isInitialized: true,
      previewSize: const Size(1280, 720),
    );
  }
  @override
  int get fps => 30;
  @override
  Future<void> refreshGeometry() async {
    restarts++;
  }
}

void main() {
  testWidgets(
    'Rotation preserves preview, shutter and preset elements without session restart',
    (tester) async {
      final app = _State()..selected = 2;
      final camera = _Camera();
      await tester.binding.setSurfaceSize(const Size(390, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: CameraPage(
            state: app,
            session: camera,
            orientation: CameraOrientation.disabled(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final strip = tester.state(find.byType(CompactPresetStrip));
      final shutter = tester.element(find.byKey(const ValueKey('ccd-shutter')));
      final preview = tester.renderObject(
        find.byKey(const ValueKey('ccd-camera-canvas')),
      );
      for (final size in [
        const Size(700, 390),
        const Size(390, 700),
        const Size(820, 710),
        const Size(390, 700),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(CompactPresetStrip)), same(strip));
        expect(
          tester.element(find.byKey(const ValueKey('ccd-shutter'))),
          same(shutter),
        );
        expect(
          tester.renderObject(find.byKey(const ValueKey('ccd-camera-canvas'))),
          same(preview),
        );
        expect(camera.restarts, 0);
        expect(app.selected, 2);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      app.dispose();
    },
  );
}
