// Regression coverage for the two Dart-only upstream preview patches.
// ignore_for_file: implementation_imports, depend_on_referenced_packages
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:camera_android_camerax/src/camerax_library.dart';
import 'package:camera_android_camerax/src/surface_texture_rotated_preview.dart';
import 'package:camera_android_camerax/src/image_reader_rotated_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/ui/camera_turn.dart';
import 'package:sensors_plus/sensors_plus.dart';

// Test double queues a different platform reply for each rotation.
// ignore: must_be_immutable
class _Display extends DeviceOrientationManager {
  _Display() : super.pigeon_detached(onDeviceOrientationChanged: (_, _) {});
  Completer<int> pending = Completer<int>();
  @override
  Future<int> getDefaultDisplayRotation() => pending.future;
}

class _PreviewController extends CameraController {
  _PreviewController()
    : super(
        const CameraDescription(
          name: 'test',
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
      const ColoredBox(key: ValueKey('sensor'), color: Colors.green);
}

void main() {
  testWidgets(
    'Landscape capture lock does not change the stable viewfinder transform',
    (tester) async {
      final controller = _PreviewController();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: StableCameraPreview(
              controller: controller,
              window: DeviceOrientation.portraitUp,
            ),
          ),
        ),
      );
      final sensor = tester.element(find.byKey(const ValueKey('sensor')));
      final before = tester.getRect(find.byKey(const ValueKey('sensor')));
      for (final device in [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]) {
        controller.value = controller.value.copyWith(
          lockedCaptureOrientation: Optional.of(device),
        );
        await tester.pump();
        expect(tester.getRect(find.byKey(const ValueKey('sensor'))), before);
        expect(
          tester.element(find.byKey(const ValueKey('sensor'))),
          same(sensor),
        );
        final rotation = tester.widget<RotatedBox>(
          find.byType(RotatedBox).last,
        );
        expect(rotation.quarterTurns, 0);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final imageReader in [false, true]) {
    testWidgets(
      'Live texture survives unresolved rotation query ($imageReader)',
      (tester) async {
        final display = _Display();
        final events = StreamController<DeviceOrientation>(sync: true);
        const texture = ColoredBox(
          key: ValueKey('live-texture'),
          color: Colors.green,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 300,
              height: 400,
              child: imageReader
                  ? ImageReaderRotatedPreview.backFacingCamera(
                      DeviceOrientation.portraitUp,
                      0,
                      events.stream,
                      90,
                      display,
                      child: texture,
                    )
                  : SurfaceTextureRotatedPreview(
                      DeviceOrientation.portraitUp,
                      0,
                      events.stream,
                      display,
                      child: texture,
                    ),
            ),
          ),
        );
        await tester.pump();
        final element = tester.element(
          find.byKey(const ValueKey('live-texture')),
        );
        for (final pose in [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
          DeviceOrientation.portraitUp,
        ]) {
          events.add(pose);
          for (var frame = 0; frame < 6; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(find.byKey(const ValueKey('live-texture')), findsOneWidget);
            expect(
              tester.element(find.byKey(const ValueKey('live-texture'))),
              same(element),
              reason:
                  'The texture must not unmount during even one pending frame',
            );
          }
          display.pending.complete(0);
          await tester.pump();
          expect(
            tester.element(find.byKey(const ValueKey('live-texture'))),
            same(element),
          );
          display.pending = Completer<int>();
        }
        await tester.pumpWidget(const SizedBox());
        unawaited(events.close());
      },
    );
  }
  testWidgets(
    'Grip rotates only icon content, keeping touch bounds and window stable',
    (tester) async {
      final samples = StreamController<AccelerometerEvent>(sync: true);
      final requests = <List<DeviceOrientation>>[];
      final orientation = CameraOrientation(
        samples: () => samples.stream,
        request: (value) async => requests.add(value),
      );
      orientation.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              key: const ValueKey('touch-target'),
              width: 48,
              height: 48,
              child: CameraTurn(
                orientation: orientation,
                child: const Icon(Icons.flash_on),
              ),
            ),
          ),
        ),
      );
      final bounds = tester.getRect(find.byKey(const ValueKey('touch-target')));
      for (final x in [9.81, -9.81, 0.0]) {
        samples.add(
          AccelerometerEvent(x, x == 0 ? 9.81 : 0, 0, DateTime.now()),
        );
        await tester.pump(const Duration(milliseconds: 360));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.getRect(find.byKey(const ValueKey('touch-target'))),
          bounds,
        );
        expect(requests, [
          [DeviceOrientation.portraitUp],
        ], reason: 'Grip events must never request native window rotation');
      }
      await tester.pumpWidget(const SizedBox());
      orientation.dispose();
      unawaited(samples.close());
    },
  );
}
