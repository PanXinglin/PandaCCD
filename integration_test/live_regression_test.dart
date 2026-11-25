import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:panda_media/panda_media.dart';
import 'package:panda_ccd/domain/live_capture.dart';
import 'package:panda_ccd/domain/photo_edit.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/camera_session.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/services/live_processor.dart';
import 'package:panda_ccd/services/video_pixels.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/camera_preview_boundary.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Live preview axes and encoded frame effects', (tester) async {
    final app = AppState();
    await app.init();
    final root = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/live-regression',
    );
    await root.create(recursive: true);
    // Unequal RGB patches expose channel-order mistakes hidden by gray fixtures.
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawColor(const Color(0xffd05020), BlendMode.src);
    canvas.drawRect(
      const Rect.fromLTWH(0, 48, 64, 48),
      Paint()..color = const Color(0xff2070c0),
    );
    final pic = rec.endRecording();
    final sentinel = await pic.toImage(64, 96);
    pic.dispose();
    final png = (await sentinel.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    final path = '${root.path}/source.mp4';
    final writer = await PandaMedia.call<String>('openWriter', {
      'path': path,
      'width': 64,
      'height': 96,
      'fps': 24,
    });
    for (var f = 0; f < 24; f++) {
      await PandaMedia.call<void>('appendFrame', {
        'id': writer,
        'bytes': png,
        'timeUs': f * 1000000 ~/ 24,
      });
    }
    await PandaMedia.call<String>('finishWriter', {'id': writer});
    Future<ui.Image> read(String path, {int at = 300000}) async {
      final reader = (await PandaMedia.call<Map>('openReader', {
        'path': path,
      }))!;
      try {
        final pixels = VideoPixels.fromMap(
          (await PandaMedia.call<Map>('readPixels', {
            'id': reader['id'],
            'timeUs': at,
            'maxEdge': 1280,
          }))!,
        );
        return await pixels.decode();
      } finally {
        await PandaMedia.call<void>('closeReader', {'id': reader['id']});
      }
    }

    final decoded = await read(path);
    final bytes = (await decoded.toByteData())!;
    final top = (16 * decoded.width + 16) * 4;
    expect(
      bytes.getUint8(top),
      greaterThan(bytes.getUint8(top + 2) + 80),
      reason: 'Codec raw pixels must retain red, not swap red and blue',
    );
    final values = {
      ...parameterDefaults,
      'tint': 1.0,
      'saturation': .2,
      'brightness': .7,
      'vignette': .8,
      'grain': .6,
    };
    final stamp = Watermark()
      ..date = false
      ..model = false;
    final cover = await app.engine.render(
      decoded,
      values,
      app.engine.lut('jade'),
      stamp,
      DateTime(2026),
      '',
    );
    final source = LiveSource(
      [LiveSegment(path, 1000000, DeviceOrientation.portraitUp)],
      0,
      950000,
      400000,
      DeviceOrientation.portraitUp,
    );
    final out = await LiveProcessor(app.engine).prepare(
      source,
      PhotoEdit(Recipe('jade', values), stamp, DateTime(2026)),
      app.engine.lut('jade'),
      cover,
      'google',
    );
    final movie = await read('${out.path}/movie.mp4');
    final expected = await app.engine.decodePhoto(cover);
    Future<Uint8List> pixels(ui.Image image) async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(0, 0, 64, 96),
        Paint(),
      );
      final p = rec.endRecording();
      final scaled = await p.toImage(64, 96);
      p.dispose();
      try {
        return (await scaled.toByteData())!.buffer.asUint8List();
      } finally {
        scaled.dispose();
      }
    }

    double error(Uint8List a, Uint8List b) {
      var sum = 0.0;
      for (var i = 0; i < a.length; i++) {
        if (i % 4 != 3) sum += (a[i] - b[i]).abs();
      }
      return sum / (a.length / 4 * 3);
    }

    double turnedError(Uint8List a, Uint8List b, int transform) {
      var total = 0.0;
      for (var y = 0; y < 96; y++) {
        for (var x = 0; x < 64; x++) {
          final u = (x + .5) / 64, v = (y + .5) / 96;
          final sample = switch (transform) {
            1 => (v, 1 - u),
            2 => (1 - u, 1 - v),
            3 => (1 - v, u),
            4 => (1 - u, v),
            _ => (u, 1 - v),
          };
          final j =
              ((sample.$2 * 96).floor().clamp(0, 95) * 64 +
                  (sample.$1 * 64).floor().clamp(0, 63)) *
              4;
          final i = (y * 64 + x) * 4;
          for (var c = 0; c < 3; c++) {
            total += (a[i + c] - b[j + c]).abs();
          }
        }
      }
      return total / (64 * 96 * 3);
    }

    final actualPixels = await pixels(movie),
        expectedPixels = await pixels(expected),
        rawPixels = await pixels(decoded);
    final filteredError = error(actualPixels, expectedPixels),
        rawError = error(actualPixels, rawPixels);
    debugPrint('LIVE_EFFECT_MAE filtered=$filteredError raw=$rawError');
    expect(filteredError, lessThan(9));
    expect(
      rawError,
      greaterThan(filteredError + 10),
      reason: 'Every encoded motion frame must actually carry the CCD look',
    );
    for (final at in [0, 700000, 900000]) {
      final frame = await read('${out.path}/movie.mp4', at: at);
      final diff = error(await pixels(frame), expectedPixels);
      frame.dispose();
      debugPrint('LIVE_EFFECT_FRAME_$at $diff');
      expect(
        diff,
        lessThan(9),
        reason: 'The beginning and end must also carry the effect',
      );
    }
    await File('${root.path}/filtered.png').writeAsBytes(cover);
    await File('${out.path}/movie.mp4').copy('${root.path}/filtered.mp4');
    for (final i in [sentinel, decoded, movie, expected]) {
      i.dispose();
    }
    await out.delete(recursive: true);
    debugPrint('LIVE_EFFECT_PASS');

    app.liveEnabled = false;
    app.liveSound = true;
    app.beautyEnabled = true;
    final camera = CameraSession();
    final grip = CameraOrientation();
    await tester.pumpWidget(
      MaterialApp(
        home: CameraPage(state: app, session: camera, orientation: grip),
      ),
    );
    debugPrint('LIVE_ROTATION_PERMISSION');
    Future<void> waitFor(bool Function() ready) async {
      for (var i = 0; i < 400 && !ready(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
      expect(ready(), true, reason: camera.error ?? camera.liveError);
    }

    await waitFor(() => camera.controller?.value.isInitialized == true);
    Future<Uint8List> preview() async {
      for (var i = 0; i < 15; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
      for (var attempt = 0; attempt < 60; attempt++) {
        final boundary = tester.renderObject<CameraPreviewRenderBoundary>(
          find.byType(CameraPreviewBoundary),
        );
        final image = await boundary.toImage(pixelRatio: .3);
        late Uint8List data;
        try {
          data = await pixels(image);
        } finally {
          image.dispose();
        }
        // This AVD uses a known colorful camera pattern. Controller.initialize
        // can complete before its first texture buffer; never compare an empty
        // startup surface with a real frame and mislabel it as a rotation.
        var colorful = 0;
        for (var i = 0; i < data.length; i += 4) {
          final r = data[i], g = data[i + 1], b = data[i + 2];
          if ((r - g).abs() + (r - b).abs() + (g - b).abs() > 80) colorful++;
        }
        if (colorful > data.length / 4 * .25) return data;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      throw StateError('Camera texture did not deliver the test pattern');
    }

    for (final mode in [
      const bool.fromEnvironment('PANDA_QA_EXPANDED') ? 'expanded' : 'compact',
    ]) {
      for (final lens in ['back', 'front']) {
        if (lens == 'front') {
          await camera.switchLens();
          await tester.pump();
        }
        for (final direction in [
          ...DeviceOrientation.values,
          DeviceOrientation.landscapeRight,
          DeviceOrientation.landscapeRight,
        ]) {
          final key = '${mode}_${lens}_${direction.name}';
          final ack = File('${root.path}/$key.ack');
          debugPrint('LIVE_ROTATION_READY_$key');
          for (var i = 0; i < 400 && !await ack.exists(); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump();
          }
          expect(await ack.exists(), true);
          expect(grip.expanded, mode == 'expanded');
          final baseline = await preview();
          debugPrint(
            'LIVE_BASE_$key ${camera.controller!.value.deviceOrientation} ${tester.view.physicalSize}',
          );
          app.setLiveEnabled(true);
          await waitFor(() => camera.liveReady);
          expect(
            camera.controller!.value.isStreamingImages,
            false,
            reason:
                'Android Live must avoid the known StreamSharing/ImageAnalysis rotation combination',
          );
          final recording = await preview();
          debugPrint(
            'LIVE_RECORD_$key ${camera.controller!.value.deviceOrientation} ${camera.controller!.value.recordingOrientation} ${tester.view.physicalSize}',
          );
          final diff = error(baseline, recording);
          final alternatives = [
            for (var t = 1; t <= 5; t++) turnedError(baseline, recording, t),
          ]..sort();
          debugPrint(
            'LIVE_PREVIEW_DIFF_$key same=$diff nearestWrongAxis=${alternatives.first}',
          );
          for (final pair in [('base', baseline), ('record', recording)]) {
            final image = await VideoPixels(pair.$2, 64, 96).decode();
            await File('${root.path}/$key-${pair.$1}.png').writeAsBytes(
              (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!.buffer.asUint8List(),
            );
            image.dispose();
          }
          if (diff + 5 >= alternatives.first) {
            debugPrint('LIVE_FAILURE_ARTIFACT_READY');
            await Future<void>.delayed(const Duration(seconds: 3));
          }
          expect(
            diff + 5,
            lessThan(alternatives.first),
            reason:
                'Enabling Live must preserve preview axes and colors in $key',
          );
          final retainedController = camera.controller;
          app.setLiveEnabled(false);
          await waitFor(
            () =>
                !camera.busy &&
                camera.controller?.value.isRecordingVideo == false,
          );
          expect(
            camera.controller,
            same(retainedController),
            reason: 'Live off must retain its initialized preview',
          );
          await preview();
        }
        if (lens == 'front') {
          await camera.switchLens();
          await tester.pump();
        }
      }
    }
    debugPrint('LIVE_REGRESSION_ARTIFACT_READY');
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  }, timeout: const Timeout(Duration(minutes: 8)));
}
