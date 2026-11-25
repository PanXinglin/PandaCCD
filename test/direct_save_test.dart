import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/editor_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Existing settings adopt direct save and a new opt-in survives restart',
    () async {
      final root = await Directory.systemTemp.createTemp('panda-save-default-');
      const path = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(path, (_) async => root.path);
      final original = AppState();
      final upgraded = AppState();
      final reopened = AppState();
      try {
        await original.library.init();
        await original.library.writeSettings({
          'directSave': false,
          'frameAspect': 1.25,
        });
        await upgraded.init();
        expect(upgraded.directSave, isTrue);
        expect(upgraded.frameAspect, 1.25);
        upgraded.directSave = false;
        await upgraded.persist();
        await reopened.init();
        expect(reopened.directSave, isFalse);
        expect(reopened.frameAspect, 1.25);
      } finally {
        original.dispose();
        upgraded.dispose();
        reopened.dispose();
        messenger.setMockMethodCallHandler(path, null);
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'Direct capture retains source; reopening after changing model reproduces the photo without doubled effects',
    (tester) async {
      late final AppState app;
      late Uint8List original, firstRender;
      await tester.runAsync(() async {
        app = AppState();
        expect(app.directSave, isTrue);
        await app.engine.init();
        app.library.root = await Directory.systemTemp.createTemp(
          'panda-direct-',
        );
        app.frameAspect = 5 / 4;
        app.watermark.text = '我的小日子';
        app.watermark.includeModel = false;
        app.update('grain', .73);
        app.toggleBeauty();
        await app.persist();
        original = await makeDemo();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('gal'),
          (_) async => throw PlatformException(code: 'ACCESS_DENIED'),
        );

        final message = await app.saveCapture(original);

        expect(message, contains('未能确认系统相册同步'));
        expect(
          (await app.library.readSettings())!['editAfterCapture'],
          isFalse,
        );
        firstRender = await File(app.photos.first.path).readAsBytes();
        expect(
          await File(
            app.photos.first.path.replaceAll('.png', '.original'),
          ).readAsBytes(),
          original,
        );
      });

      final photo = app.photos.first;
      final edit = await tester.runAsync(() => app.library.readEdit(photo));
      expect(edit!.recipe.presetId, 'g12');
      expect(edit.recipe.values['grain'], .73);
      expect(edit.recipe.values['beauty'], .55);
      app.toggleBeauty();
      expect(edit.stamp.text, '我的小日子');
      expect(edit.stamp.includeModel, isFalse);

      app.selected = 2;
      await tester.binding.setSurfaceSize(const Size(844, 390));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => EditorPage(
                      state: app,
                      bytes: original,
                      initialEdit: edit,
                      retainSource: true,
                    ),
                  ),
                ),
                child: const Text('编辑原图'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑原图'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.text('编辑照片'), findsOneWidget);
      expect(find.text('佳能 G12'), findsWidgets);

      await tester.runAsync(() async {
        await tester.tap(find.text('保存成片'));
        for (var i = 0; i < 100 && app.photos.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect(app.photos.length, 2);
        expect(await File(app.photos.first.path).readAsBytes(), firstRender);
        for (final entry in [...app.photos]) {
          await app.library.delete(entry);
        }
        expect(
          await app.library.root
              .list()
              .where(
                (file) =>
                    file.path.endsWith('.original') ||
                    file.path.endsWith('.edit.json'),
              )
              .length,
          0,
        );
      });
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      await tester.runAsync(() => app.library.root.delete(recursive: true));
      app.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('gal'),
        null,
      );
    },
  );
}
