import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/ui/camera_turn.dart';
import 'package:panda_ccd/ui/camera_viewport.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  test('iOS metering reverses window rotation and front mirror', () {
    const tap = Offset(.25, .75);
    expect(
      portraitMeteringPoint(
        tap,
        DeviceOrientation.landscapeRight,
        mirrored: false,
      ),
      const Offset(.75, .75),
    );
    expect(
      portraitMeteringPoint(
        tap,
        DeviceOrientation.landscapeRight,
        mirrored: true,
      ),
      const Offset(.75, .25),
    );
    expect(
      portraitMeteringPoint(
        tap,
        DeviceOrientation.portraitDown,
        mirrored: false,
      ),
      const Offset(.75, .25),
    );
    expect(
      portraitMeteringPoint(tap, DeviceOrientation.portraitUp, mirrored: true),
      const Offset(.75, .75),
    );
  });
  testWidgets('An inner-screen crease does not push the camera to one side', (
    tester,
  ) async {
    const size = Size(820, 700);
    const content = ValueKey('camera-content');
    await tester.binding.setSurfaceSize(size);
    for (final state in [
      DisplayFeatureState.postureFlat,
      DisplayFeatureState.postureHalfOpened,
      DisplayFeatureState.postureFlat,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              displayFeatures: [
                DisplayFeature(
                  bounds: const Rect.fromLTWH(410, 0, 0, 700),
                  type: DisplayFeatureType.fold,
                  state: state,
                ),
              ],
            ),
            child: const CameraDisplayArea(
              child: SizedBox.expand(key: content),
            ),
          ),
        ),
      );
      expect(tester.getRect(find.byKey(content)), Offset.zero & size);
    }
    await tester.binding.setSurfaceSize(null);
  });

  test(
    'All four preview orientations survive window aspect classification',
    () {
      for (final device in DeviceOrientation.values) {
        final landscape =
            device == DeviceOrientation.landscapeLeft ||
            device == DeviceOrientation.landscapeRight;
        expect(
          cameraWindowOrientation(
            landscape ? const Size(820, 700) : const Size(700, 820),
            device,
          ),
          device,
        );
      }
      expect(
        cameraWindowOrientation(
          const Size(390, 700),
          DeviceOrientation.portraitDown,
          allowPortraitDown: false,
        ),
        DeviceOrientation.portraitUp,
      );
    },
  );
  testWidgets(
    'Upright fold window ignores sensor portraitDown for tool direction',
    (tester) async {
      final controller = CameraController(
        const CameraDescription(
          name: 'fold',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        ResolutionPreset.high,
      );
      controller.value = controller.value.copyWith(
        deviceOrientation: DeviceOrientation.portraitDown,
      );
      final orientation = CameraOrientation.disabled()..setExpanded(true);
      await tester.binding.setSurfaceSize(const Size(700, 820));
      await tester.pumpWidget(
        MaterialApp(
          home: CameraViewport(
            controller: controller,
            child: CameraTurn(
              orientation: orientation,
              controller: controller,
              child: const Icon(Icons.camera_alt),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CameraViewportScope>(find.byType(CameraViewportScope))
            .window,
        DeviceOrientation.portraitDown,
      );
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
        0,
      );
      await tester.pumpWidget(const SizedBox());
      orientation.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets('Physical left and right grip rotate icon toward world upright', (
    tester,
  ) async {
    final samples = StreamController<AccelerometerEvent>(sync: true);
    final orientation = CameraOrientation(
      samples: () => samples.stream,
      request: (_) async {},
    );
    orientation.start();
    await tester.pumpWidget(
      MaterialApp(
        home: CameraTurn(
          orientation: orientation,
          child: const Icon(Icons.camera_alt),
        ),
      ),
    );
    for (final pose in [(9.81, .25), (-9.81, -.25)]) {
      samples.add(AccelerometerEvent(pose.$1, 0, 0, DateTime.now()));
      await tester.pump(const Duration(milliseconds: 351));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
        pose.$2,
      );
    }
    await tester.pumpWidget(const SizedBox());
    orientation.dispose();
    unawaited(samples.close());
  });
  testWidgets(
    'Expanded window uses actual bounds, upright tools and retained touch state',
    (tester) async {
      final controller = CameraController(
        const CameraDescription(
          name: 'fake',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        ResolutionPreset.high,
      );
      final orientation = CameraOrientation.disabled()..setExpanded(true);
      var taps = 0;
      final sizes = <Size>[];
      await tester.binding.setSurfaceSize(const Size(700, 820));
      await tester.pumpWidget(
        MaterialApp(
          home: CameraViewport(
            controller: controller,
            child: Builder(
              builder: (context) {
                sizes.add(MediaQuery.sizeOf(context));
                return Stack(
                  children: [
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: IconButton(
                        key: const ValueKey('button'),
                        onPressed: () => taps++,
                        icon: CameraTurn(
                          orientation: orientation,
                          controller: controller,
                          child: const Icon(Icons.camera_alt),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final button = tester.element(find.byKey(const ValueKey('button')));
      for (final pose in [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]) {
        controller.value = controller.value.copyWith(deviceOrientation: pose);
        final landscape = pose != DeviceOrientation.portraitUp;
        await tester.binding.setSurfaceSize(
          landscape ? const Size(820, 700) : const Size(700, 820),
        );
        await tester.pumpAndSettle();
        expect(
          sizes.last,
          landscape ? const Size(820, 700) : const Size(700, 820),
        );
        expect(
          tester.element(find.byKey(const ValueKey('button'))),
          same(button),
        );
        await tester.tap(find.byKey(const ValueKey('button')));
        await tester.pump();
        final scene = tester.widget<CameraViewportScope>(
          find.byType(CameraViewportScope),
        );
        final icon = tester.widget<AnimatedRotation>(
          find.byType(AnimatedRotation),
        );
        expect(scene.turns, 0);
        expect(icon.turns, 0);
        expect(tester.takeException(), isNull);
      }
      expect(taps, 3);
      await tester.pumpWidget(const SizedBox());
      orientation.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
}
