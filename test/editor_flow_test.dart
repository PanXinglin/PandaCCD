import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/editor_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Editing saves locally when system Photos permission is denied', (
    tester,
  ) async {
    final app = AppState()..keepOriginal = true;
    late Uint8List bytes;
    await tester.runAsync(() async {
      await app.engine.init();
      app.library.root = await Directory.systemTemp.createTemp('panda-editor-');
      bytes = await makeDemo();
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('gal'),
      (call) async {
        if (call.method == 'requestAccess') return false;
        throw PlatformException(code: 'ACCESS_DENIED');
      },
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
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
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('IXUS 95 IS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('构图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旋转 90°'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('风格'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存成片'));
    for (var i = 0; i < 150 && find.text('打开').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(app.photos.length, 1);
    expect(app.photos.single.preset, 'ixus95');
    await tester.runAsync(() async {
      final photo = app.photos.single;
      expect(await File(photo.path).exists(), isTrue);
      expect(
        await File(photo.path.replaceAll('.png', '.original')).exists(),
        isTrue,
      );
      final decoded = await app.engine.decodePhoto(
        await File(photo.path).readAsBytes(),
      );
      expect(decoded.width, 1200);
      expect(decoded.height, 900);
      decoded.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await app.library.root.delete(recursive: true);
    });
    app.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('gal'),
      null,
    );
    await tester.binding.setSurfaceSize(null);
  });
}
