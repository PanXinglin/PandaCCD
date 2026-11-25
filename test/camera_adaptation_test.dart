import 'package:panda_ccd/services/camera_orientation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/camera_stage.dart';

class _MemoryState extends AppState {
  @override
  Future<void> persist() async {}
}

void main() {
  testWidgets(
    'Complete 16:9 sensor frame stays large and undistorted on a short cover display',
    (tester) async {
      for (final size in [
        const Size(424, 622),
        const Size(390, 844),
        const Size(800, 800),
        const Size(844, 390),
      ]) {
        await tester.binding.setSurfaceSize(size);
        final ratio = size.width > size.height ? 16 / 9 : 9 / 16;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameraStage(
                aspectRatio: ratio,
                child: const ColoredBox(color: Colors.green),
              ),
            ),
          ),
        );
        final area = tester.getRect(
          find.byKey(const ValueKey('ccd-preview-area')),
        );
        final frame = tester.getRect(
          find.byKey(const ValueKey('ccd-sensor-frame')),
        );
        expect(area.size, size);
        expect(frame.width / frame.height, closeTo(ratio, .001));
        expect(frame.left, greaterThanOrEqualTo(area.left));
        expect(frame.right, lessThanOrEqualTo(area.right + .001));
        expect(frame.top, greaterThanOrEqualTo(area.top));
        expect(frame.bottom, lessThanOrEqualTo(area.bottom + .001));
        if (size == const Size(424, 622)) {
          // The old stacked layout left a narrow postcard in this exact class of window.
          expect(frame.width, greaterThan(size.width * .8));
          expect(frame.height, closeTo(size.height, .001));
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'Window resizing, large text and floating tools never shrink the preview',
    (tester) async {
      final app = _MemoryState();
      await tester.runAsync(() async {
        await app.engine.init();
        app.library.root = await Directory.systemTemp.createTemp(
          'panda-layout-',
        );
      });
      for (final size in [
        const Size(424, 622),
        const Size(320, 480),
        const Size(320, 568),
        const Size(390, 844),
        const Size(844, 390),
        const Size(800, 800),
        const Size(980, 700),
        const Size(600, 400),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  size == const Size(424, 622) ? 1.6 : 1,
                ),
              ),
              child: child!,
            ),
            home: CameraPage(
              state: app,
              orientation: CameraOrientation.disabled(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$size must not overflow',
        );
        expect(
          find.byKey(const ValueKey('ccd-control-rail')),
          usesCameraRail(size) ? findsOneWidget : findsNothing,
        );
        final before = tester.getRect(
          find.byKey(const ValueKey('ccd-preview-area')),
        );
        final frameBefore = tester.getRect(
          find.byKey(const ValueKey('ccd-sensor-frame')),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('ccd-preview-area'))).height,
          size.height,
          reason: 'Preview must use the complete available height',
        );
        await tester.tap(find.byTooltip('调一调'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('ccd-parameter-sheet')),
          findsOneWidget,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('ccd-sensor-frame'))),
          frameBefore,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('关闭参数'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('纯净取景'));
        await tester.pumpAndSettle();
        expect(find.byType(CompactPresetStrip), findsNothing);
        expect(
          find.byKey(const ValueKey('ccd-shutter')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('显示机型栏'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('ccd-preview-area'))),
          before,
        );
        await tester.pumpWidget(const SizedBox());
      }
      await tester.runAsync(() async {
        await app.library.root.delete(recursive: true);
      });
      app.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
}
