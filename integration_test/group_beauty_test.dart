import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/domain/face_region.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/face_tracker.dart';
import 'package:panda_ccd/services/filter_engine.dart';
import 'package:panda_media/panda_media.dart';

import 'fixtures/media_assets.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Group portraits keep independent landmarks and effects', (
    _,
  ) async {
    final engine = FilterEngine();
    await engine.init();
    addTearDown(engine.dispose);
    final portrait = await engine.decodePhoto(base64Decode(qaPortrait));
    addTearDown(portrait.dispose);
    final single = (await FaceTracker.detect(portrait)).single;
    final box = single.box;
    final sourceBox = ui.Rect.fromLTRB(
      box.left * portrait.width,
      box.top * portrait.height,
      box.right * portrait.width,
      box.bottom * portrait.height,
    );
    const tile = 256, height = 320, width = tile * 3;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xff24496c), ui.BlendMode.src);
    final crop = sourceBox
        .inflate(sourceBox.width * .28)
        .intersect(
          ui.Rect.fromLTWH(
            0,
            0,
            portrait.width.toDouble(),
            portrait.height.toDouble(),
          ),
        );
    for (var i = 0; i < 3; i++) {
      final size = [220.0, 232.0, 202.0][i];
      canvas.drawImageRect(
        portrait,
        crop,
        ui.Rect.fromCenter(
          center: ui.Offset(tile * (i + .5), [160.0, 172.0, 150.0][i]),
          width: size,
          height: size * crop.height / crop.width,
        ),
        ui.Paint(),
      );
    }
    final picture = recorder.endRecording();
    final group = await picture.toImage(width, height);
    picture.dispose();
    addTearDown(group.dispose);
    void expectGroup(List<FaceRegion> faces) {
      expect(faces, hasLength(3));
      expect(faces.map((f) => (f.box.center.dx * 3).floor()).toSet(), {
        0,
        1,
        2,
      });
      for (final face in faces) {
        expect(face.outline, isNotEmpty);
        expect(face.box.contains(face.mouth!), isTrue);
      }
      // Vision's simulator CPU path can report an incomplete lower jaw.
      // Such a face should still receive skin effects without being reshaped.
      final validJaws = faces.where((f) => f.lowerJaw.length == 10);
      if (Platform.isAndroid) {
        expect(validJaws, hasLength(3));
      } else {
        expect(validJaws, isNotEmpty);
      }
    }

    final faces = await FaceTracker.detect(group);
    expectGroup(faces);
    final tracker = FaceTracker();
    addTearDown(tracker.dispose);
    await tracker.previewSnapshot(() async => group.clone(), mirrored: false);
    expectGroup(tracker.faces);
    if (Platform.isAndroid) {
      // Exercise the ordinary CameraX analysis route as well as Live snapshots.
      final rgba = (await group.toByteData())!.buffer.asUint8List();
      final nv21 = Uint8List(width * height * 3 ~/ 2)
        ..fillRange(width * height, width * height * 3 ~/ 2, 128);
      for (var i = 0; i < width * height; i++) {
        final p = i * 4;
        nv21[i] =
            16 + ((66 * rgba[p] + 129 * rgba[p + 1] + 25 * rgba[p + 2]) >> 8);
      }
      expectGroup(
        FaceTracker.parse(
          await PandaMedia.call<List>('detectFrame', {
            'width': width,
            'height': height,
            'rotation': 0,
            'bytes': nv21,
          }),
        ),
      );
    }
    Future<List<int>> render({required double skin, required double jaw}) =>
        engine.render(
          group,
          {
            ...parameterDefaults,
            'strength': 0,
            'beauty': .8,
            'beautySmooth': skin,
            'beautyWhiten': skin,
            'beautyEven': skin,
            'faceSlim': jaw,
          },
          engine.lut('g12'),
          Watermark()
            ..date = false
            ..model = false,
          DateTime(2026),
          '',
          faces: faces,
          trackFace: true,
          byteFormat: ui.ImageByteFormat.rawRgba,
        );
    final original = await render(skin: 0, jaw: 0);
    final skin = await render(skin: 1, jaw: 0);
    final jaw = await render(skin: 0, jaw: 1);
    for (var t = 0; t < 3; t++) {
      int changed(List<int> processed) {
        var count = 0;
        for (var y = 0; y < height; y++) {
          for (var x = t * tile; x < (t + 1) * tile; x++) {
            final i = (y * width + x) * 4;
            if ((processed[i] - original[i]).abs() > 4) count++;
          }
        }
        return count;
      }

      expect(changed(skin), greaterThan(100), reason: 'Skin in face ${t + 1}');
      final hasJaw = faces
          .singleWhere((f) => (f.box.center.dx * 3).floor() == t)
          .lowerJaw
          .isNotEmpty;
      expect(
        changed(jaw),
        hasJaw ? greaterThan(5) : 0,
        reason: 'Jaw in face ${t + 1}',
      );
    }
    expect(skin.sublist(0, width * 4), original.sublist(0, width * 4));
    expect(jaw.sublist(0, width * 4), original.sublist(0, width * 4));
  });
}
