import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/frame_ratio.dart';
import 'package:panda_ccd/domain/photo_edit.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/ui/frame_ratio_picker.dart';

void main() {
  test('Frame crop stays within source and follows source orientation', () {
    for (final source in [
      const Size(900, 1200),
      const Size(1200, 900),
      const Size(800, 800),
    ]) {
      for (final ratio in [1.0, 4 / 3, 3 / 2, 16 / 9, 5 / 4, 4.0]) {
        final crop = croppedFrameSize(source, aspect: ratio);
        expect(crop.width, lessThanOrEqualTo(source.width));
        expect(crop.height, lessThanOrEqualTo(source.height));
        expect(crop.longestSide / crop.shortestSide, closeTo(ratio, .000001));
      }
      expect(croppedFrameSize(source), source);
    }
    expect(
      croppedFrameSize(const Size(900, 1200), aspect: 5 / 4),
      const Size(900, 1125),
    );
    expect(
      croppedFrameSize(const Size(1280, 720), aspect: 4 / 3),
      const Size(960, 720),
    );
    expect(validFrameRatio(double.nan), isNull);
    expect(validFrameRatio(0), isNull);
    expect(validFrameRatio(5), isNull);
    expect(frameRatioLabel(5 / 4), '5:4');
  });
  test('Photo edit preserves custom frame and old records still restore', () {
    final edit = PhotoEdit(
      Recipe('g12', parameterDefaults),
      Watermark(),
      DateTime(2026, 10, 27),
      frameAspect: 5 / 4,
    );
    expect(PhotoEdit.decode(edit.encode()).frameAspect, 5 / 4);
    final old = edit.encode().replaceAll(',"frameAspect":1.25', '');
    expect(PhotoEdit.decode(old).frameAspect, isNull);
  });
  testWidgets('Custom ratio validates dimensions and selects 5:4', (
    tester,
  ) async {
    double? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFrameRatioPicker(
                context,
                null,
                (value) => selected = value,
              ),
              child: const Text('设置画幅'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('设置画幅'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义宽高比'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ratio-width')), '0');
    await tester.tap(find.text('使用'));
    await tester.pumpAndSettle();
    expect(find.text('宽和高请输入1–99的整数'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('ratio-width')), '5');
    await tester.enterText(find.byKey(const ValueKey('ratio-height')), '4');
    await tester.tap(find.text('使用'));
    await tester.pumpAndSettle();
    expect(selected, 5 / 4);
    expect(find.text('设置画幅'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
