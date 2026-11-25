import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/live_capture.dart';
import 'package:panda_ccd/services/camera_session.dart';

class _Controller extends CameraController {
  final List<String> calls;
  final double minZoom, maxZoom;
  Future<void> Function(double)? zoomAcknowledgement;
  _Controller(
    CameraDescription description,
    this.calls, {
    this.minZoom = .5,
    this.maxZoom = 8,
  }) : super(description, ResolutionPreset.medium);
  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(1280, 720),
    );
    calls.add('init:${description.name}');
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {
    calls.add('flash:${description.name}:${mode.name}');
    if (description.lensDirection == CameraLensDirection.front &&
        mode != FlashMode.off) {
      throw CameraException('unsupported', 'no front flash');
    }
    value = value.copyWith(flashMode: mode);
  }

  @override
  Future<void> setExposureMode(ExposureMode mode) async {
    calls.add('exposure:${mode.name}');
  }

  @override
  Future<double> getMinZoomLevel() async => minZoom;

  @override
  Future<double> getMaxZoomLevel() async => maxZoom;

  @override
  Future<void> setZoomLevel(double value) async {
    calls.add('zoom:$value');
    await zoomAcknowledgement?.call(value);
  }

  @override
  Future<XFile> takePicture() async {
    calls.add('capture:${value.flashMode.name}');
    return XFile('sample.jpg');
  }

  @override
  Future<void> lockCaptureOrientation([DeviceOrientation? orientation]) async {
    calls.add('lock:${orientation?.name}');
    value = value.copyWith(
      lockedCaptureOrientation: Optional.of(
        orientation ?? value.deviceOrientation,
      ),
    );
  }

  @override
  Future<void> unlockCaptureOrientation() async {
    calls.add('unlock');
    value = value.copyWith(lockedCaptureOrientation: const Optional.absent());
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose:${description.name}');
    await super.dispose();
  }
}

class _RecordingController extends _Controller {
  _RecordingController(super.description, super.calls);
  @override
  Future<void> startVideoRecording({
    dynamic onAvailable,
    bool enablePersistentRecording = true,
  }) async {
    calls.add('record');
    value = value.copyWith(
      isRecordingVideo: true,
      recordingOrientation: Optional.of(value.deviceOrientation),
    );
  }

  @override
  Future<XFile> stopVideoRecording() async {
    calls.add('stop');
    value = value.copyWith(
      isRecordingVideo: false,
      recordingOrientation: const Optional.absent(),
    );
    return XFile('unused-test-live.mp4');
  }
}

class _StableSession extends CameraSession {
  @override
  final bool finishLiveOnFocusLoss;
  _StableSession(List<String> calls, {this.finishLiveOnFocusLoss = false})
    : super(
        discover: () async {
          calls.add('discover');
          return [
            const CameraDescription(
              name: 'back',
              lensDirection: CameraLensDirection.back,
              sensorOrientation: 90,
            ),
          ];
        },
        create: (d, _, _) => _RecordingController(d, calls),
      );
  @override
  bool get usesStableLiveSession => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Android zoom follows the newest target before the old request finishes',
    () async {
      final camera = _StableSession([]);
      await camera.start();
      final controller = camera.controller! as _RecordingController;
      final firstSent = Completer<void>();
      final firstAck = Completer<void>();
      final latestSent = Completer<void>();
      controller.zoomAcknowledgement = (zoom) async {
        if (zoom == 1.3) {
          firstSent.complete();
          await firstAck.future;
        } else if (zoom == 1.8) {
          latestSent.complete();
        }
      };
      final first = camera.setZoom(1.3);
      expect(camera.zoom.value, 1.3);
      await firstSent.future.timeout(const Duration(seconds: 1));
      final latest = camera.setZoom(1.8);
      expect(camera.zoom.value, 1.8);
      await latestSent.future.timeout(const Duration(seconds: 1));
      firstAck.complete();
      await Future.wait([first, latest]);
      expect(camera.zoom.value, 1.8);
      await camera.pause();
      camera.dispose();
    },
  );
  test('Android rear flash modes retain one 30fps viewfinder', () async {
    final calls = <String>[];
    final camera = _StableSession(calls);
    await camera.start();
    final controller = camera.controller;
    for (final mode in [FlashMode.off, FlashMode.auto, FlashMode.always]) {
      expect(camera.flashRequiresRestart(mode), false);
      await camera.setFlash(mode);
      expect(camera.flash, mode);
      expect(camera.fps, 30);
      expect(camera.controller, same(controller));
    }
    expect(calls.where((v) => v.startsWith('init')).length, 1);
    await camera.pause();
    camera.dispose();
  });

  test(
    'Rear stops use main-relative zoom and 1× returns to uncropped main',
    () async {
      CameraDescription rear(String name, CameraLensType type) =>
          CameraDescription(
            name: name,
            lensDirection: CameraLensDirection.back,
            lensType: type,
            sensorOrientation: 90,
          );
      final calls = <String>[];
      final camera = CameraSession(
        discover: () async => [
          rear('tele', CameraLensType.telephoto),
          rear('ultra', CameraLensType.ultraWide),
          rear('main', CameraLensType.wide),
          const CameraDescription(
            name: 'front',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 90,
          ),
        ],
        readRearZoom: () async => (
          camera: null,
          mainLevel: 1.0,
          factors: {'ultra': .5, 'main': 1.0, 'tele': 3.0},
        ),
        create: (description, _, _) => _Controller(description, calls),
      );
      addTearDown(() async {
        await camera.pause();
        camera.dispose();
      });

      await camera.start();
      expect(camera.controller!.description.name, 'main');
      expect(camera.zoomStops.map((stop) => stop.factor), [.5, 1, 3]);
      await camera.setZoom(2);
      await camera.selectZoomStop(camera.zoomStops.first);
      expect(camera.controller!.description.name, 'ultra');
      expect(camera.zoomLabel(camera.zoom.value), '0.5×');
      await camera.selectZoomStop(camera.zoomStops.last);
      expect(camera.controller!.description.name, 'tele');
      expect(camera.zoomLabel(camera.zoom.value), '3×');
      await camera.setZoom(1.5);
      expect(camera.zoomLabel(camera.zoom.value), '4.5×');
      await camera.selectZoomStop(camera.mainZoomStop!);
      expect(camera.controller!.description.name, 'main');
      expect(camera.zoomLabel(camera.zoom.value), '1×');
      await camera.selectZoomStop(camera.zoomStops.last);
      await camera.switchLens();
      expect(camera.controller!.description.name, 'front');
      expect(camera.zoomStops.map((stop) => stop.factor), [.5, 1]);
      await camera.switchLens();
      expect(camera.controller!.description.name, 'main');
    },
  );

  test(
    'Multi-camera zoom crosses 3× and 1× in the same capture session',
    () async {
      CameraDescription rear(String name, CameraLensType type) =>
          CameraDescription(
            name: name,
            lensDirection: CameraLensDirection.back,
            lensType: type,
            sensorOrientation: 90,
          );
      final calls = <String>[];
      final camera = CameraSession(
        discover: () async => [
          rear('main', CameraLensType.wide),
          rear('ultra', CameraLensType.ultraWide),
          rear('tele', CameraLensType.telephoto),
        ],
        readRearZoom: () async => (
          camera: 'triple',
          mainLevel: 2.0,
          factors: {'ultra': .5, 'main': 1.0, 'tele': 3.0},
        ),
        create: (description, _, _) =>
            _Controller(description, calls, minZoom: 1, maxZoom: 16),
      );
      addTearDown(() async {
        await camera.pause();
        camera.dispose();
      });
      await camera.start();
      final controller = camera.controller;
      expect(controller!.description.name, 'triple');
      expect(camera.zoom.value, 1);
      expect(camera.zoomStops.map((stop) => stop.factor), [.5, 1, 2, 3]);
      expect(camera.zoomStops.every((stop) => stop.camera == 'triple'), isTrue);
      await camera.selectZoomStop(camera.zoomStops.last);
      expect(camera.zoom.value, 3);
      await camera.setZoom(2.7);
      expect(camera.zoom.value, 2.7);
      await camera.selectZoomStop(camera.mainZoomStop!);
      await camera.setZoom(.7);
      expect(camera.zoom.value, .7);
      await camera.setZoom(.3);
      expect(camera.zoom.value, .5);
      expect(camera.controller, same(controller));
      expect(calls.where((call) => call.startsWith('zoom:')), [
        'zoom:2.0',
        'zoom:6.0',
        'zoom:5.4',
        'zoom:2.0',
        'zoom:1.4',
        'zoom:1.0',
      ]);
    },
  );

  test(
    'Zoom applies to the camera, clamps, and survives a session restart',
    () async {
      final calls = <String>[];
      final camera = _StableSession(calls);
      await camera.start();
      expect(camera.zoomStops.map((stop) => stop.factor), [.5, 1, 2]);
      final initialController = camera.controller;
      await camera.selectZoomStop(camera.zoomStops.first);
      expect(camera.controller, same(initialController));
      await camera.setZoom(.1);
      expect(camera.zoom.value, .5);
      await camera.setZoom(99);
      expect(camera.zoom.value, 8);
      await camera.refreshGeometry();
      expect(camera.zoom.value, 8);
      await camera.setZoom(1);
      await camera.capture();
      expect(calls.where((c) => c.startsWith('zoom:')), [
        'zoom:0.5',
        'zoom:8.0',
        'zoom:8.0',
        'zoom:1.0',
      ]);
      await camera.pause();
      camera.dispose();
    },
  );

  testWidgets('iOS focus loss seals Live before releasing the camera', (
    tester,
  ) async {
    final calls = <String>[];
    final camera = _StableSession(calls, finishLiveOnFocusLoss: true);
    await camera.start();
    await camera.setModes(live: true, analysis: false);
    LiveShot? shot;
    final completion = camera
        .captureLive(
          onExposed: () {
            camera.didChangeAppLifecycleState(AppLifecycleState.inactive);
            camera.didChangeAppLifecycleState(AppLifecycleState.hidden);
          },
        )
        .then((value) => shot = value);
    await tester.pump(); // No advance through the 1.2s post-shutter timer.
    expect(shot?.source?.segments.single.path, 'unused-test-live.mp4');
    expect(shot?.warning, isNull);
    await completion;
    expect(
      calls.lastIndexOf('stop'),
      lessThan(calls.lastIndexOf('dispose:back')),
    );
    camera.dispose();
  });
  test(
    'Turning Live off or adjusting Android beauty retains the initialized preview even with sound configured',
    () async {
      final calls = <String>[];
      final camera = _StableSession(calls);
      await camera.start();
      expect(
        camera.liveModeMayInterruptPreview(live: true, sound: false),
        true,
        reason: 'The first VideoCapture bind can clear the preview texture',
      );
      await camera.setModes(live: true, analysis: true, sound: true);
      final ready = camera.controller;
      final initializations = calls.where((v) => v.startsWith('init')).length;
      for (var i = 0; i < 4; i++) {
        expect(
          camera.liveModeMayInterruptPreview(live: false, sound: true),
          false,
        );
        await camera.setModes(live: false, analysis: true, sound: true);
        expect(camera.controller, same(ready));
        expect(camera.controller!.value.isInitialized, true);
        expect(camera.controller!.value.isRecordingVideo, false);
        expect(camera.busy, false);
        expect(
          camera.liveModeMayInterruptPreview(live: true, sound: true),
          false,
        );
        await camera.setModes(live: true, analysis: false, sound: true);
        await camera.setModes(live: true, analysis: true, sound: true);
        expect(camera.controller, same(ready));
        expect(camera.controller!.value.isRecordingVideo, true);
      }
      expect(calls.where((v) => v.startsWith('init')).length, initializations);
      expect(calls.where((v) => v == 'discover').length, 1);
      await camera.pause();
      camera.dispose();
    },
  );
  test(
    'Flash survives front switch and geometry reset; capture never changes preview transform',
    () async {
      final calls = <String>[];
      final back = CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      final front = CameraDescription(
        name: 'front',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      );
      var descriptions = [back, front];
      final camera = CameraSession(
        discover: () async => descriptions,
        create: (description, _, _) => _Controller(description, calls),
      );
      await camera.start();
      expect(camera.flash, FlashMode.always);
      expect(camera.controller!.value.flashMode, FlashMode.always);
      expect(camera.fps, 30);
      await camera.switchLens();
      expect(camera.supportsFlashControl, isFalse);
      expect(camera.flash, FlashMode.off);
      await camera.setFlash(FlashMode.always);
      expect(camera.error, isNotNull);
      await camera.switchLens();
      expect(camera.flash, FlashMode.always);
      descriptions = [front, back];
      await camera.refreshGeometry();
      expect(camera.controller!.description.name, 'back');
      expect(camera.flash, FlashMode.always);
      await camera.capture();
      expect(calls.sublist(calls.length - 2), [
        'flash:back:always',
        'capture:always',
      ]);
      await camera.setFlash(FlashMode.auto);
      await camera.capture();
      expect(calls.last, 'capture:auto');
      await camera.setFlash(FlashMode.off);
      expect(camera.fps, 60);
      await camera.capture();
      expect(calls.last, 'capture:off');
      await camera.capture(orientation: DeviceOrientation.landscapeLeft);
      expect(calls.sublist(calls.length - 3), [
        'lock:landscapeLeft',
        'capture:off',
        'unlock',
      ]);
      camera.dispose();
    },
  );
  testWidgets(
    'Visible focus loss preserves texture regardless of duration; hidden releases it',
    (tester) async {
      final calls = <String>[];
      final camera = CameraSession(
        discover: () async => [
          const CameraDescription(
            name: 'back',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
          ),
        ],
        create: (description, _, _) => _Controller(description, calls),
      );
      await camera.start();
      final initial = camera.controller;
      camera.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 150));
      camera.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 500));
      expect(camera.controller, same(initial));
      expect(calls.where((c) => c.startsWith('init:')).length, 1);
      camera.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 3));
      expect(camera.controller, same(initial));
      camera.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(camera.controller, same(initial));
      camera.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump();
      expect(
        camera.controller,
        isNull,
        reason: 'A real hidden transition must release immediately',
      );
      camera.dispose();
      await tester.pump();
    },
  );
}
