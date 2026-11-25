import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/design_system.dart';
import 'package:panda_ccd/ui/editor_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Device GPU editor saves a stamped, rotated photo locally', (
    tester,
  ) async {
    // Grant Photos permission before running. This does not exercise a physical camera.
    final app = AppState();
    await app.init();
    final before = app.photos.length;
    final bytes = await makeDemo();
    await tester.pumpWidget(
      MaterialApp(
        theme: PandaDesign.theme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      EditorPage(state: app, bytes: bytes, isDemo: true),
                ),
              ),
              child: const Text('打开暗房'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开暗房'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IXUS 95 IS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('构图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旋转 90°'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存成片'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(app.photos.length, before + 1);
    expect(app.photos.first.preset, 'ixus95');
    // Only remove the test's own artifact, never existing user photos.
    await app.library.delete(app.photos.first);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
