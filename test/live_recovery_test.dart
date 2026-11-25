import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_media/panda_media.dart';
import 'package:panda_ccd/domain/live_capture.dart';
import 'package:panda_ccd/domain/photo_edit.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/library.dart';
import 'package:panda_ccd/ui/camera_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Only processed legacy Android sources need channel repair on re-edit',
    () async {
      final library = PhotoLibrary();
      library.root = await Directory.systemTemp.createTemp('legacy-live-');
      final photo = PhotoEntry(
        '${library.root.path}/test.png',
        'g12',
        DateTime(2026),
        live: true,
      );
      await Directory(photo.liveDirectory).create();
      final source = LiveSource(
        [LiveSegment('source.mp4', 1000000, DeviceOrientation.portraitUp)],
        0,
        1000000,
        500000,
        DeviceOrientation.portraitUp,
      );
      final manifest = File('${photo.liveDirectory}/manifest.json');
      await manifest.writeAsString(
        jsonEncode({...source.toJson(), 'rendered': true}),
      );
      expect(
        (await library.liveSource(photo))!.legacyRedBlueSwap,
        Platform.isAndroid,
      );
      await manifest.writeAsString(
        jsonEncode({...source.toJson(), 'rendered': false}),
      );
      expect((await library.liveSource(photo))!.legacyRedBlueSwap, false);
      await manifest.writeAsString(
        jsonEncode({
          ...source.toJson(),
          'rendered': true,
          'pixelLayoutVersion': 2,
        }),
      );
      expect((await library.liveSource(photo))!.legacyRedBlueSwap, false);
      final carried = LiveSource.decode({
        ...source.toJson(),
        'legacyRedBlueSwap': true,
      }, photo.liveDirectory);
      expect(
        LiveSource.decode(
          carried.toJson(),
          photo.liveDirectory,
        ).legacyRedBlueSwap,
        true,
      );
      await library.root.delete(recursive: true);
    },
  );
  test(
    'Failed Live processing retains cover, source, edit and permits complete local deletion',
    () async {
      final app = AppState();
      await app.engine.init();
      app.library.root = await Directory.systemTemp.createTemp('live-library-');
      final raw = File('${app.library.root.path}/camera-source.mp4');
      await raw.writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PandaMedia.channel, (call) async {
            if (call.method == 'openReader') {
              expect(
                call.arguments['path'],
                contains('.png.live/segment-0.mp4'),
              );
              throw PlatformException(
                code: 'DECODE_FAILED',
                message: 'forced failure',
              );
            }
            return null;
          });
      final bytes = await makeDemo();
      final edit = PhotoEdit(
        Recipe('jade', parameterDefaults),
        Watermark(),
        DateTime(2026),
      );
      final source = LiveSource(
        [LiveSegment(raw.path, 2000000, DeviceOrientation.portraitUp)],
        0,
        2000000,
        1000000,
        DeviceOrientation.portraitUp,
      );
      final message = await app.commitPhoto(
        bytes,
        edit,
        original: bytes,
        liveSource: source,
      );
      expect(message, isEmpty);
      await source
          .dispose(); // Camera cache may be cleared as soon as persistence succeeds.
      await app.finishLiveExports();
      final photo = app.photos.single;
      expect(photo.live, true);
      expect(await File(photo.path).exists(), true);
      final info = await app.library.liveInfo(photo);
      expect(info?['rendered'], false);
      expect(info?['error'], contains('DECODE_FAILED'));
      final kept = await app.library.liveSource(photo);
      expect(await File(kept!.segments.single.path).readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
      expect((await app.library.readEdit(photo))!.recipe.presetId, 'jade');
      expect((await app.library.list()).single.live, true);
      await app.library.delete(photo);
      expect(await Directory(photo.liveDirectory).exists(), false);
      expect(await File(photo.path).exists(), false);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PandaMedia.channel, null);
      await app.library.root.delete(recursive: true);
      app.dispose();
    },
  );
}
