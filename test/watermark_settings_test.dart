import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/ui/design_system.dart';
import 'package:panda_ccd/ui/watermark_controls.dart';

void main() {
  test(
    'Old watermarks keep branding and new custom text survives snapshot roundtrip',
    () {
      final stamp = Watermark()
        ..restore({'date': true, 'model': true, 'red': true});
      expect(watermarkLabel(stamp, 'G12 INSPIRED'), 'PandaCCD / G12 INSPIRED');
      stamp.text = cleanWatermarkText('  我的小日子\n2026  ');
      stamp.includeModel = false;
      final restored = Watermark()..restore(stamp.toJson());
      expect(watermarkLabel(restored, 'IXUS95'), '我的小日子 2026');
      expect(restored.red, isTrue);
      expect(cleanWatermarkText('字' * 100).runes.length, 32);
    },
  );
  testWidgets(
    'Color and corner are explicit selections; custom text can be applied or reset',
    (tester) async {
      final stamp = Watermark();
      await tester.pumpWidget(
        MaterialApp(
          theme: PandaDesign.theme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SettingsSection(
                    title: '照片与水印',
                    children: [
                      SwitchListTile(
                        title: const Text('文字水印'),
                        value: stamp.model,
                        onChanged: (value) => update(() => stamp.model = value),
                      ),
                      WatermarkChoices(
                        stamp: stamp,
                        onChanged: () => update(() {}),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final leadingEdge = tester.getTopLeft(find.text('文字水印')).dx;
      for (final label in ['水印颜色', '水印位置', '自定义水印文字', '附加机型名称']) {
        expect(
          tester.getTopLeft(find.text(label)).dx,
          closeTo(leadingEdge, 0.01),
          reason: label,
        );
      }
      await tester.tap(find.byKey(const ValueKey('watermark-color-false')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复古红色').last);
      await tester.pumpAndSettle();
      expect(stamp.red, isTrue);
      await tester.tap(
        find.byKey(const ValueKey('watermark-position-false-false')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('左上角').last);
      await tester.pumpAndSettle();
      expect(stamp.top && stamp.left, isTrue);
      await tester.tap(find.text('自定义水印文字'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '今天也要开心');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(stamp.text, '今天也要开心');
      await tester.tap(find.text('自定义水印文字'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(stamp.text, isEmpty);
      expect(find.text('PandaCCD（默认）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
