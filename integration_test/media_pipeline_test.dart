import 'fixtures/media_assets.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/album_sync.dart';
import 'package:panda_ccd/services/camera_session.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/services/face_tracker.dart';
import 'package:panda_ccd/services/live_processor.dart';
import 'package:panda_ccd/services/shutter_sound.dart';
import 'package:panda_ccd/domain/live_capture.dart';
import 'package:panda_ccd/domain/photo_edit.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/camera_preview_boundary.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native landmarks, hardware codec, audio, pre/post Live and MediaStore preservation',
    (tester) async {
      final app = AppState();
      await app.init();
      final root = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/media-qa',
      );
      if (await root.exists()) await root.delete(recursive: true);
      await root.create(recursive: true);
      app.library.root = root;
      debugPrint('MEDIA_READY_FOR_PERMISSIONS');
      await Future<void>.delayed(const Duration(seconds: 3));
      final portrait = await app.engine.decodePhoto(
        base64Decode(qaPortrait),
        maxEdge: 960,
      );
      final faces = await FaceTracker.detect(portrait);
      expect(faces, isNotEmpty);
      expect(faces.first.box.width, greaterThan(.1));
      expect(faces.first.lowerJaw.length, 10);
      await File(
        '${root.path}/face-geometry.json',
      ).writeAsString(jsonEncode(faces.first.toJson()));
      debugPrint('MEDIA_FACE_COUNT ${faces.length}');
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 64, 48),
        Paint()..color = Colors.red,
      );
      canvas.drawRect(
        const Rect.fromLTWH(0, 48, 64, 48),
        Paint()..color = Colors.blue,
      );
      final picture = recorder.endRecording();
      final sentinel = await picture.toImage(64, 96);
      picture.dispose();
      final sentinelBytes = await app.engine.render(
        sentinel,
        {...parameterDefaults, 'strength': 0, 'beauty': 0},
        app.engine.lut('g12'),
        Watermark()
          ..date = false
          ..model = false,
        DateTime(2026),
        '',
      );
      final check = await app.engine.decodePhoto(sentinelBytes);
      final pixels = (await check.toByteData())!;
      expect(
        pixels.getUint8((8 * 64 + 8) * 4),
        greaterThan(200),
        reason: 'OpenGLES export must keep red at the top',
      );
      expect(
        pixels.getUint8((80 * 64 + 8) * 4 + 2),
        greaterThan(200),
        reason: 'OpenGLES export must keep blue at the bottom',
      );
      check.dispose();
      sentinel.dispose();
      debugPrint('MEDIA_GL_ORIENTATION_PASS');

      final params = {...parameterDefaults, 'beauty': .65, 'faceSlim': .8};
      final slim = await app.engine.render(
        portrait,
        params,
        app.engine.lut('g12'),
        Watermark()
          ..date = false
          ..model = false,
        DateTime(2026),
        'test',
        faces: faces,
      );
      await File('${root.path}/slim.png').writeAsBytes(slim);
      for (final level in [0.0, .25, 1.0]) {
        final rendered = await app.engine.render(
          portrait,
          {
            ...parameterDefaults,
            'strength': 0,
            'beauty': .7,
            'beautySmooth': 0,
            'beautyEven': 0,
            'beautyWhiten': 0,
            'faceSlim': level,
          },
          app.engine.lut('g12'),
          Watermark()
            ..date = false
            ..model = false,
          DateTime(2026),
          '',
          faces: faces,
          trackFace: true,
        );
        await File(
          '${root.path}/jaw-${(level * 100).round()}.png',
        ).writeAsBytes(rendered);
      }
      portrait.dispose();
      final input = '${root.path}/fixture.mp4';
      await File(input).writeAsBytes(base64Decode(qaAudio));
      final now = DateTime.now().microsecondsSinceEpoch;
      final source = LiveSource(
        [LiveSegment(input, now, DeviceOrientation.landscapeLeft)],
        now - 1800000,
        now - 200000,
        now - 1000000,
        DeviceOrientation.landscapeLeft,
      );
      final edit = PhotoEdit(
        Recipe('g12', {...parameterDefaults, 'beauty': .5}),
        Watermark()
          ..date = false
          ..model = false,
        DateTime(2026),
      );
      final output = await LiveProcessor(
        app.engine,
      ).prepare(source, edit, app.engine.lut('g12'), slim, 'samsung');
      final manifest =
          jsonDecode(await File('${output.path}/manifest.json').readAsString())
              as Map;
      expect(manifest['rendered'], true);
      expect(manifest['muted'], false);
      expect(manifest['keyUs'], inInclusiveRange(0, 1600000));
      for (final name in [
        'movie.mp4',
        'segment-0.mp4',
        'export.MP.jpg',
        'manifest.json',
      ]) {
        await File('${output.path}/$name').copy('${root.path}/fixture-$name');
      }
      await output.delete(recursive: true);
      debugPrint('MEDIA_CODEC_AND_AUDIO_PASS');
      final camera = CameraSession();
      final player = AudioPlayer();
      final shutterSound = ShutterSound(createPlayer: () => player);
      var shutterCompletions = 0;
      final completions = player.onPlayerComplete.listen((_) {
        shutterCompletions++;
      });
      app.liveEnabled = false;
      app.liveSound = false;
      app.beautyEnabled = true;
      app.directSave = true;
      final orientation = CameraOrientation();
      await tester.pumpWidget(
        MaterialApp(
          home: CameraPage(
            state: app,
            session: camera,
            orientation: orientation,
            sound: shutterSound,
          ),
        ),
      );
      var analysisFrames = 0;
      final analyse = camera.onFrame;
      camera.onFrame = (frame) {
        analysisFrames++;
        analyse?.call(frame);
      };
      for (var i = 0; i < 100 && analysisFrames == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      expect(camera.controller?.value.isStreamingImages, true);
      expect(analysisFrames, greaterThan(0));
      app.setLiveEnabled(true);
      for (var i = 0; i < 300 && !camera.liveReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      expect(camera.liveReady, true, reason: camera.liveError ?? camera.error);
      await shutterSound.prepare();
      expect(shutterSound.isReady, true);
      void playShutter() => unawaited(shutterSound.play());
      final shot = await camera.captureLive(onExposed: playShutter);
      expect(shot.source, isNotNull);
      expect(shot.warning, isNull);
      final firstSave = app.saveCaptureFile(
        shot.photo,
        liveSource: shot.source,
      );
      expect(
        camera.liveReady,
        true,
        reason: 'The next shutter is immediately armed',
      );
      final burst = await camera.captureLive(
        orientation: DeviceOrientation.landscapeLeft,
        onExposed: playShutter,
      );
      expect(
        shutterCompletions,
        2,
        reason: 'Both bundled shutter samples played',
      );
      await completions.cancel();
      debugPrint('MEDIA_SHUTTER_SOUND_REPEAT_PASS');
      expect(await firstSave, isEmpty);
      final firstPhoto = app.photos.first;
      expect(app.liveProgress, contains(firstPhoto.path));
      final burstResult = await app.saveCaptureFile(
        burst.photo,
        liveSource: burst.source!,
      );
      expect(burstResult, isEmpty);
      expect(await File(burst.photo.path).exists(), false);
      final burstPhoto = app.photos.first;
      await app.finishLiveExports();
      expect(app.photos.length, greaterThanOrEqualTo(2));
      expect((await app.library.liveInfo(burstPhoto))?['rendered'], true);
      await File(burstPhoto.path).copy('${root.path}/landscapeLeft.png');
      await File(
        '${burstPhoto.liveDirectory}/movie.mp4',
      ).copy('${root.path}/landscapeLeft.mp4');
      debugPrint('MEDIA_BURST_AND_LANDSCAPE_LEFT_PASS');
      debugPrint('MEDIA_LIVE_SAVED');
      final photo = firstPhoto;
      expect(photo.live, true);
      final info = await app.library.liveInfo(photo);
      expect(info?['rendered'], true, reason: info?['error']?.toString());
      final ids = await app.library.systemIds(photo);
      expect(ids, isNotEmpty);
      final asset = await AssetEntity.fromId(ids.first);
      expect(asset, isNotNull);
      final file = await asset!.originFile;
      expect(file, isNotNull);
      final expected = await File(
        '${photo.liveDirectory}/export.MP.jpg',
      ).readAsBytes();
      expect(
        await file!.readAsBytes(),
        expected,
        reason: 'MediaStore must preserve the appended video byte-for-byte',
      );
      debugPrint('MEDIA_STORE_PASS ${asset.id} ${await asset.titleAsync}');
      await app.library.recordAlbumExport(photo, '');
      await File('${photo.path}.system.json').delete();
      final reopened = AlbumSync(app.library, app.systemGallery);
      await reopened.export(photo);
      expect(await app.library.systemIds(photo), {asset.id});
      expect(await app.library.albumExport(photo), isNull);
      expect(await app.systemGallery.findExport(photo), asset.id);
      debugPrint('MEDIA_STORE_PENDING_EXPORT_RECOVERED ${asset.id}');
      for (final pose in [
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeRight,
      ]) {
        for (var i = 0; i < 100 && !camera.liveReady; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
        final capture = await camera.captureLive(orientation: pose);
        expect(capture.source, isNotNull, reason: capture.warning);
        final started = Stopwatch()..start();
        final saved = await app.saveCapture(
          await capture.photo.readAsBytes(),
          liveSource: capture.source,
        );
        expect(saved, isEmpty);
        debugPrint(
          'MEDIA_BACKGROUND_${pose.name} ${started.elapsedMilliseconds}ms',
        );
        await capture.source!.dispose();
        await app.finishLiveExports();
        final entry = app.photos.first;
        final data = await app.library.liveInfo(entry);
        expect(data?['rendered'], true, reason: data?['error']?.toString());
        await File(entry.path).copy('${root.path}/${pose.name}.png');
        await File(
          '${entry.liveDirectory}/movie.mp4',
        ).copy('${root.path}/${pose.name}.mp4');
        debugPrint('MEDIA_ORIENTATION_${pose.name} PASS');
      }

      app.liveSound = true;
      await camera.setModes(live: true, analysis: true, sound: true);
      await camera.switchLens();
      for (var i = 0; i < 150 && !camera.liveReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      expect(camera.liveReady, true, reason: camera.liveError ?? camera.error);
      final front = await camera.captureLive(
        orientation: DeviceOrientation.portraitUp,
      );
      await app.saveCapture(
        await front.photo.readAsBytes(),
        liveSource: front.source,
      );
      await front.source!.dispose();
      await app.finishLiveExports();
      final frontPhoto = app.photos.first;
      final frontInfo = await app.library.liveInfo(frontPhoto);
      expect(
        frontInfo?['rendered'],
        true,
        reason: frontInfo?['error']?.toString(),
      );
      await File(frontPhoto.path).copy('${root.path}/frontPortraitUp.png');
      await File(
        '${frontPhoto.liveDirectory}/movie.mp4',
      ).copy('${root.path}/frontPortraitUp.mp4');
      debugPrint('MEDIA_FRONT_LIVE_AUDIO muted=${frontInfo?['muted']}');
      final beforeStop = camera.controller;
      await camera.setModes(live: false, analysis: true, sound: true);
      app.setLiveEnabled(false);
      await tester.pump();
      expect(camera.controller, same(beforeStop));
      expect(camera.controller!.value.isRecordingVideo, false);
      final platform = CameraPlatform.instance as AndroidCameraCameraX;
      expect(platform.recording, isNull);
      expect(
        await platform.processCameraProvider!.isBound(platform.videoCapture!),
        true,
      );
      for (var second = 0; second < 15; second++) {
        for (var frame = 0; frame < 25; frame++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          await tester.pump();
        }
        final boundary = tester.renderObject<CameraPreviewRenderBoundary>(
          find.byType(CameraPreviewBoundary),
        );
        final frame = await boundary.toImage(pixelRatio: .12);
        final rgba = (await frame.toByteData())!;
        var colored = 0;
        for (var i = 0; i < rgba.lengthInBytes; i += 4) {
          final r = rgba.getUint8(i),
              g = rgba.getUint8(i + 1),
              b = rgba.getUint8(i + 2);
          if ((r - g).abs() + (g - b).abs() + (r - b).abs() > 80) colored++;
        }
        if (second == 14) {
          await File('${root.path}/live-off-preview.png').writeAsBytes(
            (await frame.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List(),
          );
        }
        frame.dispose();
        expect(
          colored / (rgba.lengthInBytes / 4),
          greaterThan(.12),
          reason:
              'Live off preview must keep real camera pixels, second=$second',
        );
        expect(camera.controller, same(beforeStop));
      }
      final still = await camera.capture(
        orientation: DeviceOrientation.landscapeRight,
      );
      expect(await File(still.path).length(), greaterThan(100));
      debugPrint('MEDIA_LIVE_OFF_15_SECONDS_PREVIEW_AND_STILL_PASS');
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      debugPrint('MEDIA_ARTIFACT_READY');
      await Future<void>.delayed(const Duration(seconds: 4));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
