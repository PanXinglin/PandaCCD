import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/live_capture.dart';
import 'package:panda_ccd/domain/photo_edit.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/capture_draft.dart';
import 'package:panda_ccd/services/system_gallery.dart';

class _Album extends SystemGallery {
  int saves = 0;
  @override
  Future<String> save(photo) async => 'asset-${++saves}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'A valid camera source survives a real local storage failure for retry',
    (tester) async {
      await tester.runAsync(() async {
        final temp = await Directory.systemTemp.createTemp(
          'panda-audit-source-',
        );
        final album = _Album();
        final app = AppState(systemGallery: album);
        try {
          await app.engine.init();
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawRect(
            const ui.Rect.fromLTWH(0, 0, 32, 24),
            ui.Paint()..color = const ui.Color(0xff4285a4),
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(32, 24);
          late final List<int> png;
          try {
            final encoded = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            expect(encoded, isNotNull);
            png = encoded!.buffer.asUint8List();
          } finally {
            image.dispose();
            picture.dispose();
          }

          final source = File('${temp.path}/camera-source.png');
          await source.writeAsBytes(png, flush: true);
          final decoded = await app.engine.decodePhoto(
            await source.readAsBytes(),
          );
          try {
            expect(decoded.width, 32);
            expect(decoded.height, 24);
          } finally {
            decoded.dispose();
          }

          // The photo is valid. Only the destination is unusable: a file cannot
          // serve as the parent directory for PhotoLibrary's pending output.
          final blockedRoot = File('${temp.path}/blocked-library');
          await blockedRoot.writeAsString(
            'existing-file-must-remain',
            flush: true,
          );
          app.library.root = Directory(blockedRoot.path);
          Object? failure;
          try {
            await app.saveCaptureFile(XFile(source.path));
          } catch (error) {
            failure = error;
          }
          expect(failure, isA<FileSystemException>());
          expect(
            (failure as FileSystemException).path,
            contains(blockedRoot.path),
          );
          expect(app.photos, isEmpty);
          expect(await blockedRoot.readAsString(), 'existing-file-must-remain');
          expect(
            await source.exists(),
            isTrue,
            reason:
                'No photo was committed; retain the valid captured input for retry.',
          );
          expect(await source.readAsBytes(), png);
          final draft = app.failedCaptures.single;
          app.selected = 1;
          await blockedRoot.delete();
          await app.library.root.create();
          expect(await app.retryCapture(draft.id), isEmpty);
          expect(app.photos.single.preset, draft.edit.recipe.presetId);
          expect(app.failedCaptures, isEmpty);
          expect(album.saves, 1);
          expect(await source.exists(), isFalse);
        } finally {
          await app.finishLiveExports();
          app.dispose();
          await temp.delete(recursive: true);
        }
      });
    },
  );

  test(
    'Restart restores Live draft and discarding it frees both inputs',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'panda-capture-restart-',
      );
      addTearDown(() => temp.delete(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final root = await Directory('${temp.path}/panda_ccd').create();
      final original = await File(
        '${temp.path}/capture.jpg',
      ).writeAsBytes([1, 2]);
      final segment = await File('${temp.path}/live.mp4').writeAsBytes([3, 4]);
      final draft = CaptureDraft(
        original,
        PhotoEdit(
          Recipe('g12', parameterDefaults),
          Watermark(),
          DateTime(2026),
        ),
        'auto',
        motion: LiveSource(
          [LiveSegment(segment.path, 2, DeviceOrientation.portraitUp)],
          0,
          2,
          1,
          DeviceOrientation.portraitUp,
        ),
      );
      final retained = await draft.retain(root);
      await draft.discard(); // Simulate the OS clearing the camera cache.
      final app = AppState();
      addTearDown(app.dispose);
      await app.init();
      final restored = app.failedCaptures.single;
      expect(restored.id, draft.id);
      expect(await restored.original.readAsBytes(), [1, 2]);
      expect(await File(restored.motion!.segments.single.path).readAsBytes(), [
        3,
        4,
      ]);
      await app.discardCapture(restored.id);
      expect(app.failedCaptures, isEmpty);
      expect(await retained.directory!.exists(), isFalse);
    },
  );
}
