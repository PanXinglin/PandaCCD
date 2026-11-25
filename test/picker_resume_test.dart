import 'package:panda_ccd/domain/live_capture.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/camera_session.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/services/shutter_sound.dart';
import 'package:panda_ccd/ui/camera_page.dart';

class _Sound extends ShutterSound {
  int plays = 0;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> dispose() async {}
}

class _State extends AppState {
  int saved = 0;
  @override
  Future<void> persist() async {}
  @override
  Future<String> saveCaptureFile(XFile file, {LiveSource? liveSource}) async {
    saved++;
    return '';
  }
}

class _Controller extends CameraController {
  _Controller(super.description, super.resolutionPreset);
  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(1280, 720),
    );
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {}
  @override
  Future<double> getMinZoomLevel() async => 1;
  @override
  Future<double> getMaxZoomLevel() async => 1;
  @override
  Future<void> setExposureMode(ExposureMode mode) async {}
  @override
  Future<XFile> takePicture() async =>
      XFile.fromData(Uint8List.fromList([1, 2, 3]));
}

void main() {
  for (final resumeFirst in [false, true]) {
    testWidgets(
      'Cancel picker restores camera when resumed arrives ${resumeFirst ? 'before' : 'after'} result',
      (tester) async {
        final app = _State()..directSave = true;
        final sound = _Sound();
        final camera = CameraSession(
          discover: () async => [
            const CameraDescription(
              name: 'back',
              lensDirection: CameraLensDirection.back,
              sensorOrientation: 90,
            ),
          ],
          create: (description, _, resolution) =>
              _Controller(description, resolution),
        );
        final picker = Completer<XFile?>();
        await tester.pumpWidget(
          MaterialApp(
            home: CameraPage(
              state: app,
              session: camera,
              sound: sound,
              orientation: CameraOrientation.disabled(),
              choosePhoto: () => picker.future,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('导入照片'));
        await tester.pump();
        expect(camera.enabled, isFalse);
        camera.didChangeAppLifecycleState(AppLifecycleState.inactive);
        await tester.pump();
        if (resumeFirst) {
          camera.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await tester.pump();
        }
        picker.complete(null);
        await tester.pumpAndSettle();
        expect(
          camera.enabled,
          isTrue,
          reason: 'Cancel must re-enable before checking foreground state',
        );
        if (!resumeFirst) {
          expect(camera.controller, isNull);
          camera.didChangeAppLifecycleState(AppLifecycleState.resumed);
        }
        await tester.pumpAndSettle();
        expect(camera.controller!.value.isInitialized, isTrue);
        await tester.tap(find.byKey(const ValueKey('ccd-shutter')));
        await tester.pumpAndSettle();
        expect(app.saved, 1);
        expect(sound.plays, 1);
        app.shutterSound = false;
        await tester.tap(find.byKey(const ValueKey('ccd-shutter')));
        await tester.pumpAndSettle();
        expect(app.saved, 2);
        expect(sound.plays, 1, reason: 'Disabled sound must not play again');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
}
