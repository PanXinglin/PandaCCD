import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/main.dart';

const _window = Size(820, 700);
const _probe = ValueKey<String>('audit-root-fold-probe');

Widget _rootWithFeature(DisplayFeature feature) => MaterialApp(
  builder: (context, child) => MediaQuery(
    // Inject before the first root sub-screen, where platform features arrive.
    data: MediaQuery.of(
      context,
    ).copyWith(size: _window, displayFeatures: [feature]),
    child: pandaAppFrame(context, child),
  ),
  home: const SizedBox.expand(key: _probe),
);

void main() {
  testWidgets(
    'Continuous fold stays full width through flat-half-flat at the app root',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(_window);
      final observed = <Rect>[];
      for (final posture in [
        DisplayFeatureState.postureFlat,
        DisplayFeatureState.postureHalfOpened,
        DisplayFeatureState.postureFlat,
      ]) {
        await tester.pumpWidget(
          _rootWithFeature(
            DisplayFeature(
              bounds: const Rect.fromLTWH(410, 0, 0, 700),
              type: DisplayFeatureType.fold,
              state: posture,
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        observed.add(tester.getRect(find.byKey(_probe)));
      }
      // Collect every transition before asserting so the return-to-flat path
      // is exercised even when the current half-open implementation is wrong.
      expect(
        observed,
        const [
          Rect.fromLTWH(0, 0, 820, 700),
          Rect.fromLTWH(0, 0, 820, 700),
          Rect.fromLTWH(0, 0, 820, 700),
        ],
        reason:
            'A continuous crease must not split the camera canvas; '
            'the root must apply the same fold policy as CameraDisplayArea.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('A horizontal fold also leaves both rows available', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(_window);
    await tester.pumpWidget(
      _rootWithFeature(
        const DisplayFeature(
          bounds: Rect.fromLTWH(0, 350, 820, 0),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ),
    );
    expect(tester.getRect(find.byKey(_probe)), Offset.zero & _window);
  });

  testWidgets(
    'Physical obstructing hinge keeps root content in the left 400dp pane',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(_window);
      for (final posture in [
        DisplayFeatureState.postureFlat,
        DisplayFeatureState.postureHalfOpened,
      ]) {
        await tester.pumpWidget(
          _rootWithFeature(
            DisplayFeature(
              bounds: const Rect.fromLTWH(400, 0, 20, 700),
              type: DisplayFeatureType.hinge,
              state: posture,
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byKey(_probe)),
          const Rect.fromLTWH(0, 0, 400, 700),
          reason:
              'Removing continuous fold splitting must preserve '
              'avoidance of a real 20dp obstructing hinge.',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
