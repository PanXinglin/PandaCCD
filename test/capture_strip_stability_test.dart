import 'package:panda_ccd/domain/live_capture.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/services/camera_session.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/camera_stage.dart';
import 'package:panda_ccd/ui/capture_feedback.dart';

class _State extends AppState {
  Completer<void>? pending;
  final stillSaves = <Completer<void>>[];
  final liveSaves = <Completer<String>>[];
  @override
  Future<String> saveCaptureFile(XFile file, {LiveSource? liveSource}) async {
    if (liveSource != null) {
      final save = Completer<String>();
      liveSaves.add(save);
      return save.future;
    }
    pending = Completer<void>();
    stillSaves.add(pending!);
    await pending!.future;
    notifyListeners();
    return '';
  }

  @override
  Future<void> persist() async {}
}

class _Camera extends CameraSession {
  final bool failCapture;
  _Camera({this.failCapture = false}) {
    controller = CameraController(
      const CameraDescription(
        name: 'test',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
      ResolutionPreset.medium,
    );
    controller!.value = controller!.value.copyWith(
      isInitialized: true,
      previewSize: const Size(1280, 720),
    );
  }
  @override
  int get fps => 30;
  @override
  bool get liveReady => true;
  @override
  Future<void> setZoom(double value) async => zoom.value = value;
  @override
  Future<LiveShot> captureLive({
    DeviceOrientation? orientation,
    VoidCallback? onExposed,
  }) async {
    final photo = await capture(orientation: orientation);
    onExposed?.call();
    return LiveShot(
      photo,
      const LiveSource([], 0, 2500000, 1300000, DeviceOrientation.portraitUp),
    );
  }

  @override
  Future<XFile> capture({DeviceOrientation? orientation}) async {
    if (failCapture) throw StateError('模拟拍摄失败');
    return XFile.fromData(Uint8List.fromList([1, 2, 3]));
  }
}

void main() {
  testWidgets('Pinching changes zoom without selecting another CCD preset', (
    tester,
  ) async {
    final app = _State();
    final camera = _Camera()
      ..minZoom = .6
      ..maxZoom = 8;
    await tester.binding.setSurfaceSize(const Size(390, 844));
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
    final bar = find.byKey(const ValueKey('ccd-zoom-bar'));
    final dock = find.byKey(const ValueKey('ccd-floating-dock'));
    final frame = find.byKey(const ValueKey('ccd-frame-ratio-chip'));
    final beauty = find.byKey(const ValueKey('ccd-beauty-toggle'));
    expect(tester.getCenter(bar).dx, closeTo(195, 1));
    expect(tester.getCenter(frame).dy, tester.getCenter(bar).dy);
    expect(tester.getCenter(beauty).dy, tester.getCenter(bar).dy);
    expect(tester.getBottomLeft(bar).dy, lessThan(tester.getTopLeft(dock).dy));
    await tester.tap(find.text('0.6×'));
    await tester.pumpAndSettle();
    expect(camera.zoom.value, .6);
    await tester.tap(find.byKey(const ValueKey('ccd-zoom-main')));
    await tester.pumpAndSettle();
    expect(camera.zoom.value, 1);
    double x(String label) => tester.getCenter(find.text(label)).dx;
    final mainX = x('1×');
    final secondX = x('2×');
    await tester.tap(find.byKey(const ValueKey('ccd-zoom-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ccd-zoom-slider')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ccd-zoom-toggle')));
    await tester.pumpAndSettle();
    final a = await tester.startGesture(const Offset(145, 360));
    final b = await tester.startGesture(const Offset(245, 360));
    await a.moveBy(const Offset(-25, 0));
    await b.moveBy(const Offset(25, 0));
    await a.moveBy(const Offset(-25, 0));
    await b.moveBy(const Offset(25, 0));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(camera.zoom.value, greaterThan(1.2));
    expect(app.selected, 0);
    await camera.setZoom(1.3);
    await tester.pumpAndSettle();
    expect(x('1.3×'), mainX);
    expect(x('2×'), secondX);
    expect(find.text('1×'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ccd-zoom-main')));
    await tester.pumpAndSettle();
    expect(camera.zoom.value, 1);
    await tester.flingFrom(const Offset(250, 355), const Offset(-120, 0), 800);
    await tester.pumpAndSettle();
    expect(app.selected, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
    app.dispose();
  });
  testWidgets(
    'Camera controls reach the bottom edge and keep the shutter safe',
    (tester) async {
      final app = _State();
      await tester.binding.setSurfaceSize(const Size(390, 600));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(bottom: 24)),
            child: child!,
          ),
          home: CameraPage(
            state: app,
            session: _Camera(),
            orientation: CameraOrientation.disabled(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dock = tester.getRect(
        find.byKey(const ValueKey('ccd-floating-dock')),
      );
      final shutter = tester.getRect(find.byKey(const ValueKey('ccd-shutter')));
      expect(dock.left, 0);
      expect(dock.right, 390);
      expect(dock.bottom, 600);
      expect(shutter.bottom, lessThanOrEqualTo(576));
      await tester.binding.setSurfaceSize(const Size(844, 390));
      await tester.pumpAndSettle();
      final tools = tester.getRect(
        find.byKey(const ValueKey('ccd-quick-controls')),
      );
      expect(tools.bottom, lessThanOrEqualTo(366));
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      app.dispose();
    },
  );
  testWidgets(
    'Failed camera capture never plays a successful shutter pulse or starts saving',
    (tester) async {
      final app = _State();
      await tester.pumpWidget(
        MaterialApp(
          home: CameraPage(
            state: app,
            session: _Camera(failCapture: true),
            orientation: CameraOrientation.disabled(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ccd-shutter')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ShutterPulse>(find.byType(ShutterPulse)).shots.value,
        0,
      );
      expect(
        tester
            .widget<CaptureButtonFace>(find.byType(CaptureButtonFace))
            .phase
            .value,
        CapturePhase.idle,
      );
      expect(app.pending, isNull);
      expect(find.text('照片已拍好，正在保存…'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
  testWidgets(
    'Quiet capture completion preserves the manually scrolled model strip',
    (tester) async {
      final app = _State()..selected = 2;
      await tester.binding.setSurfaceSize(const Size(424, 622));
      await tester.pumpWidget(
        MaterialApp(
          home: CameraPage(
            state: app,
            session: _Camera(),
            orientation: CameraOrientation.disabled(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final strip = find.byType(CompactPresetStrip);
      final list = find.descendant(
        of: strip,
        matching: find.byType(Scrollable),
      );
      await tester.drag(list, const Offset(-47, 0));
      await tester.pumpAndSettle();
      final original = tester.state(strip);
      final scroll = tester.state<ScrollableState>(list).position;
      final offset = scroll.pixels;
      expect(offset, greaterThan(0));
      void unchanged() {
        expect(tester.state(strip), same(original));
        expect(tester.state<ScrollableState>(list).position, same(scroll));
        expect(scroll.pixels, closeTo(offset, .001));
        expect(app.selected, 2);
      }

      for (var shot = 0; shot < 2; shot++) {
        await tester.tap(find.byKey(const ValueKey('ccd-shutter')));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        unchanged();
        expect(app.pending, isNotNull);
        expect(find.text('照片已拍好，正在保存…'), findsNothing);
        expect(
          tester.widget<ShutterPulse>(find.byType(ShutterPulse)).shots.value,
          shot + 1,
        );
        final shutter = tester.widget<GestureDetector>(
          find.byKey(const ValueKey('ccd-shutter')),
        );
        expect(
          shutter.onTap,
          isNotNull,
          reason: 'Saving must not own the shutter',
        );
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          unchanged();
        }
      }
      expect(app.stillSaves, hasLength(2));
      for (final save in app.stillSaves) {
        save.complete();
      }
      await tester.pumpAndSettle();
      final widgetBeforeNoticeExpiry = tester.widget(strip);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      unchanged();
      expect(
        tester.widget(strip),
        same(widgetBeforeNoticeExpiry),
        reason: 'No delayed status should rebuild the model strip',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      app.dispose();
    },
  );
  testWidgets('Live shutter keeps accepting shots while saves are pending', (
    tester,
  ) async {
    final app = _State()..liveEnabled = true;
    await tester.pumpWidget(
      MaterialApp(
        home: CameraPage(
          state: app,
          session: _Camera(),
          orientation: CameraOrientation.disabled(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const ValueKey('ccd-shutter')));
      await tester.pumpAndSettle();
      expect(app.liveSaves, hasLength(i + 1));
    }
    expect(
      tester.widget<ShutterPulse>(find.byType(ShutterPulse)).shots.value,
      4,
    );
    expect(find.textContaining('正在保存'), findsNothing);
    expect(find.textContaining('请稍候'), findsNothing);
    for (final save in app.liveSaves) {
      save.complete('');
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('已保存'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
