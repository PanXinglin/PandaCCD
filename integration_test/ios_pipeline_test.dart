import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_media/panda_media.dart';
import 'package:panda_ccd/domain/live_capture.dart';
import 'package:panda_ccd/domain/photo_edit.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/filter_engine.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/album_sync.dart';
import 'package:panda_ccd/services/library.dart';
import 'package:panda_ccd/services/live_foreground.dart';
import 'package:panda_ccd/services/live_processor.dart';
import 'package:panda_ccd/services/system_gallery.dart';
import 'package:panda_ccd/services/video_pixels.dart';

class _VerifyApplePair extends SystemGallery {
  int saves = 0;

  @override
  Future<String> save(PhotoEntry photo) async {
    expect(await File('${photo.liveDirectory}/pair.jpg').exists(), isTrue);
    expect(await File('${photo.liveDirectory}/pair.mov').exists(), isTrue);
    saves++;
    return 'test-system-live';
  }
}

/// Runs on iOS Simulator as well as iPhone: Metal + real Apple codecs/pairing.
/// Camera/flash/microphone/Photos prompts still require the device checklist.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Apple Live renders CCD on every frame, four orientations and front mirror',
    (tester) async {
      expect(Platform.isIOS, true, reason: 'Run this test on an iOS device');
      final engine = FilterEngine();
      await engine.init();
      final root = await Directory.systemTemp.createTemp('panda-ios-test-');
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xff779999), ui.BlendMode.src);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 80, 80),
        ui.Paint()..color = const ui.Color(0xffcc4433),
      );
      canvas.drawRect(
        const ui.Rect.fromLTWH(80, 80, 80, 160),
        ui.Paint()..color = const ui.Color(0xff3366bb),
      );
      final picture = recorder.endRecording();
      final sourceImage = await picture.toImage(160, 240);
      picture.dispose();
      final stamp = Watermark()
        ..date = false
        ..model = false;
      final plain = {...parameterDefaults, 'strength': 0.0, 'beauty': 0.0};
      final effect = {
        ...parameterDefaults,
        'strength': 1.0,
        'tint': 0.8,
        'saturation': 0.2,
        'beauty': 0.0,
      };
      try {
        for (final mirrored in [false, true]) {
          final raw = await engine.render(
            sourceImage,
            plain,
            engine.lut('g12'),
            stamp,
            DateTime(2026),
            '',
            mirrorSource: mirrored,
            byteFormat: ui.ImageByteFormat.rawRgba,
          );
          final movie = '${root.path}/raw-$mirrored.mp4';
          final writer = await PandaMedia.call<String>('openWriter', {
            'path': movie,
            'width': 160,
            'height': 240,
            'fps': 24,
          });
          for (var i = 0; i < 24; i++) {
            await PandaMedia.call<void>('appendPixels', {
              'id': writer,
              'bytes': raw,
              'width': 160,
              'height': 240,
              'bgra': false,
              'timeUs': i * 1000000 ~/ 24,
            });
          }
          await PandaMedia.call<String>('finishWriter', {'id': writer});
          if (!mirrored) {
            final gate = LiveForeground();
            final gallery = _VerifyApplePair();
            final app = AppState(liveForeground: gate, systemGallery: gallery);
            try {
              await app.engine.init();
              app.library.root = await Directory(
                '${root.path}/library',
              ).create();
              final original = (await sourceImage.toByteData(
                format: ui.ImageByteFormat.png,
              ))!.buffer.asUint8List();
              gate.didChangeAppLifecycleState(AppLifecycleState.paused);
              final queued = app.saveCapture(
                original,
                liveSource: LiveSource(
                  [LiveSegment(movie, 1000000, DeviceOrientation.portraitUp)],
                  0,
                  950000,
                  500000,
                  DeviceOrientation.portraitUp,
                ),
              );
              await tester.pump(const Duration(milliseconds: 50));
              expect(app.photos, isEmpty);
              expect(gallery.saves, 0);
              gate.didChangeAppLifecycleState(AppLifecycleState.resumed);
              expect(await queued, isEmpty);
              await app.finishLiveExports();
              expect(gallery.saves, 1);
              expect(app.liveNotice, isNull);
              expect(
                (await app.library.liveInfo(app.photos.single))?['rendered'],
                isTrue,
              );
            } finally {
              app.dispose();
            }
          }
          for (final pair in [
            (DeviceOrientation.portraitUp, 0),
            (DeviceOrientation.landscapeRight, 1),
            (DeviceOrientation.portraitDown, 2),
            (DeviceOrientation.landscapeLeft, 3),
          ]) {
            final rawUpright = await engine.render(
              sourceImage,
              plain,
              engine.lut('g12'),
              stamp,
              DateTime(2026),
              '',
              turns: pair.$2,
            );
            final upright = await engine.decodePhoto(rawUpright);
            final cover = await engine.render(
              upright,
              effect,
              engine.lut('g12'),
              stamp,
              DateTime(2026),
              '',
            );
            upright.dispose();
            final edit = PhotoEdit(
              Recipe('g12', effect),
              stamp,
              DateTime(2026),
            );
            final source = LiveSource(
              [
                LiveSegment(
                  movie,
                  1000000,
                  DeviceOrientation.portraitUp,
                  mirrored: mirrored,
                ),
              ],
              0,
              950000,
              500000,
              pair.$1,
            );
            final output = await LiveProcessor(
              engine,
            ).prepare(source, edit, engine.lut('g12'), cover, 'auto');
            try {
              expect(await File('${output.path}/pair.jpg').exists(), true);
              expect(await File('${output.path}/pair.mov').exists(), true);
              if (const bool.fromEnvironment('PANDA_VERIFY_SYSTEM_ALBUM') &&
                  !mirrored &&
                  pair.$2 == 0) {
                final library = PhotoLibrary()..root = root;
                final system = SystemGallery();
                final photo = await library.save(
                  cover,
                  'g12',
                  DateTime.now(),
                  liveDirectory: output,
                );
                expect(await system.access(), GalleryAccess.full);
                await expectLater(
                  PandaMedia.call<String>('savePhoto', {
                    'imagePath': '${root.path}/missing.jpg',
                    'title': photo.filename,
                  }),
                  throwsA(
                    isA<PlatformException>().having(
                      (error) => error.code,
                      'code',
                      'PHOTOS_NOT_CREATED',
                    ),
                  ),
                );
                await library.recordAlbumExport(photo, '');
                final id = await system.save(photo);
                final reopened = AlbumSync(library, system);
                await reopened.export(photo);
                expect(await library.systemIds(photo), {id});
                expect(await library.albumExport(photo), isNull);
                expect(await system.findExport(photo), id);
                expect(
                  await system.state(id, photo: photo),
                  SystemPhotoState.present,
                );
                debugPrint('PHOTOS_PENDING_LIVE_RECOVERED');
              }
              final reference = await engine.decodePhoto(cover);
              final expected = (await reference.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              final reader = (await PandaMedia.call<Map>('openReader', {
                'path': '${output.path}/movie.mp4',
              }))!;
              try {
                for (final time in [100000, 450000, 800000]) {
                  final pixels = VideoPixels.fromMap(
                    (await PandaMedia.call<Map>('readPixels', {
                      'id': reader['id'],
                      'timeUs': time,
                      'maxEdge': 1280,
                    }))!,
                  );
                  final frame = await pixels.decode();
                  expect(frame.width, reference.width);
                  expect(frame.height, reference.height);
                  final actual = (await frame.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!.buffer.asUint8List();
                  var difference = 0;
                  for (var i = 0; i < expected.length; i += 4) {
                    for (var c = 0; c < 3; c++) {
                      difference += (expected[i + c] - actual[i + c]).abs();
                    }
                  }
                  expect(
                    difference / (expected.length / 4 * 3),
                    lessThan(12),
                    reason: '$mirrored/${pair.$1}/$time CCD and orientation',
                  );
                  frame.dispose();
                }
              } finally {
                await PandaMedia.call<void>('closeReader', {
                  'id': reader['id'],
                });
                reference.dispose();
              }
            } finally {
              await output.delete(recursive: true);
            }
          }
        }
      } finally {
        sourceImage.dispose();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
