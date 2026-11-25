import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/ui/camera_stage.dart';

class _Preview extends CameraController {
  _Preview()
    : super(
        const CameraDescription(
          name: 'fold',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        ResolutionPreset.high,
      ) {
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(1280, 720),
    );
  }
  @override
  Widget buildPreview() =>
      const ColoredBox(key: ValueKey('texture'), color: Colors.green);
  @override
  Future<void> dispose() async {
    await super.dispose();
  }
}

void main() {
  testWidgets(
    'Real CameraPreview retains uniform scaling during mismatched frame/texture rotations across fold shapes',
    (tester) async {
      final camera = _Preview();
      for (final window in [
        const Size(424, 622),
        const Size(360, 800),
        const Size(841, 701),
        const Size(701, 841),
        const Size(980, 700),
        const Size(1056, 1056),
        const Size(600, 400),
      ]) {
        await tester.binding.setSurfaceSize(window);
        for (final direction in [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
          DeviceOrientation.portraitDown,
        ]) {
          camera.value = camera.value.copyWith(deviceOrientation: direction);
          // Deliberately keep the outer frame landscape while the plugin preview
          // changes direction; display and camera events arrive independently.
          await tester.pumpWidget(
            MaterialApp(
              home: CameraStage(
                aspectRatio: 16 / 9,
                child: CameraTextureFit(child: CameraPreview(camera)),
              ),
            ),
          );
          await tester.pump();
          final texture = tester.renderObject<RenderBox>(
            find.byKey(const ValueKey('texture')),
          );
          final matrix = texture.getTransformTo(null);
          final origin = MatrixUtils.transformPoint(matrix, Offset.zero);
          final x =
              MatrixUtils.transformPoint(matrix, const Offset(1, 0)) - origin;
          final y =
              MatrixUtils.transformPoint(matrix, const Offset(0, 1)) - origin;
          expect(x.distance, closeTo(y.distance, .0001));
          expect(x.dx * y.dx + x.dy * y.dy, closeTo(0, .0001));
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      await camera.dispose();
    },
  );
}
