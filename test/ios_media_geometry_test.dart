import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/live_capture.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/filter_engine.dart';
import 'package:panda_ccd/services/shutter_sound.dart';

class _PortraitCamera extends CameraController {
  _PortraitCamera(bool front)
    : super(
        CameraDescription(
          name: 'ios',
          lensDirection: front
              ? CameraLensDirection.front
              : CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        ResolutionPreset.high,
      ) {
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(640, 480),
    );
  }
  @override
  Widget buildPreview() => const SizedBox(key: ValueKey('portrait-buffer'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'iPhone sound does not create a player that can deactivate Live audio',
    () async {
      final sound = ShutterSound(
        systemCaptureSound: true,
        createPlayer: () => throw StateError('Must use system camera sound'),
      );
      await sound.prepare();
      expect(sound.isReady, true);
      await sound.play();
      await sound.dispose();
    },
  );

  test('Retained front Live buffers keep mirror metadata for re-editing', () {
    final source = LiveSource(
      [
        const LiveSegment(
          'capture.mp4',
          3000000,
          DeviceOrientation.portraitUp,
          mirrored: true,
        ),
      ],
      0,
      2500000,
      1300000,
      DeviceOrientation.landscapeLeft,
    );
    final restored = LiveSource.decode(source.toJson(), '/library');
    expect(restored.segments.single.mirrored, true);
    final old = source.toJson();
    (old['segments'] as List).first.remove('mirrored');
    expect(LiveSource.decode(old, '/library').segments.single.mirrored, false);
  });

  testWidgets(
    'iOS portrait buffer presentation is independent of capture lock and Live',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final front in [false, true]) {
        final camera = _PortraitCamera(front);
        for (final window in DeviceOrientation.values) {
          for (final recording in [false, true]) {
            camera.value = camera.value.copyWith(
              deviceOrientation: DeviceOrientation.landscapeRight,
              lockedCaptureOrientation: const Optional.of(
                DeviceOrientation.portraitDown,
              ),
              recordingOrientation: const Optional.of(
                DeviceOrientation.landscapeLeft,
              ),
              isRecordingVideo: recording,
            );
            await tester.pumpWidget(
              MaterialApp(
                home: Center(
                  child: SizedBox(
                    width: 300,
                    child: CameraPreview(camera, previewOrientation: window),
                  ),
                ),
              ),
            );
            final expected = switch (window) {
              DeviceOrientation.portraitUp => 0,
              DeviceOrientation.landscapeRight => 1,
              DeviceOrientation.portraitDown => 2,
              DeviceOrientation.landscapeLeft => 3,
            };
            expect(
              tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns,
              front ? -expected : expected,
            );
            expect(tester.takeException(), isNull);
          }
        }
        await tester.pumpWidget(const SizedBox());
        await camera.dispose();
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test(
    'GPU normalizes mirrored portrait Live before all four rotations',
    () async {
      final engine = FilterEngine();
      await engine.init();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final colors = [Colors.red, Colors.green, Colors.blue, Colors.yellow];
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          canvas.drawRect(
            Rect.fromLTWH(x * 16, y * 24, 16, 24),
            Paint()..color = colors[y * 2 + x],
          );
        }
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 48);
      picture.dispose();
      final stamp = Watermark()
        ..date = false
        ..model = false;
      Future<List<int>> corners(int turn, bool mirrored) async {
        final pixels = await engine.render(
          image,
          {...parameterDefaults, 'strength': 0, 'beauty': 0},
          engine.lut('g12'),
          stamp,
          DateTime(2026),
          '',
          turns: turn,
          mirrorSource: mirrored,
          byteFormat: ui.ImageByteFormat.rawRgba,
        );
        final w = turn.isOdd ? 48 : 32, h = turn.isOdd ? 32 : 48;
        return [
          for (final p in [
            Offset(w * .25, h * .25),
            Offset(w * .75, h * .25),
            Offset(w * .25, h * .75),
            Offset(w * .75, h * .75),
          ])
            (pixels[(p.dy.floor() * w + p.dx.floor()) * 4] << 16) |
                (pixels[(p.dy.floor() * w + p.dx.floor()) * 4 + 1] << 8) |
                pixels[(p.dy.floor() * w + p.dx.floor()) * 4 + 2],
        ];
      }

      final normal = await corners(0, false);
      final expected = [
        [1, 0, 3, 2],
        [3, 1, 2, 0],
        [2, 3, 0, 1],
        [0, 2, 1, 3],
      ];
      for (var turn = 0; turn < 4; turn++) {
        expect(await corners(turn, true), [
          for (final index in expected[turn]) normal[index],
        ]);
      }
      image.dispose();
      engine.dispose();
    },
  );
}
