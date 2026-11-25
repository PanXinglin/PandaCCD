import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/design_system.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Camera texture → CCD shader → capture → edit → save', (
    tester,
  ) async {
    final app = AppState();
    await app.init();
    app.directSave = false; // Exercise the optional edit-first flow.
    final before = app.photos.length;
    await tester.pumpWidget(
      MaterialApp(
        theme: PandaDesign.theme(),
        home: CameraPage(state: app),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    for (
      var i = 0;
      i < 120 && find.byType(CameraPreview).evaluate().isEmpty;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    }
    expect(
      find.byType(CameraPreview),
      findsOneWidget,
      reason: 'Requires Impeller and granted camera permission',
    );
    final frameBefore = tester.getRect(
      find.byKey(const ValueKey('ccd-sensor-frame')),
    );
    await tester.tap(find.byTooltip('调一调'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('ccd-sensor-frame'))),
      frameBefore,
    );
    await tester.tap(find.byTooltip('关闭参数'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('纯净取景'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('ccd-sensor-frame'))),
      frameBefore,
    );
    await tester.tap(find.byTooltip('显示机型栏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择机型'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ccd-model-g12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ccd-shutter')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('编辑照片'), findsOneWidget);
    await tester.tap(find.text('构图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旋转 90°'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存成片'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(app.photos.length, before + 1);
    expect(app.photos.first.preset, 'g12');
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
