import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/face_region.dart';
import 'package:panda_ccd/domain/photo_edit.dart';
import 'package:panda_ccd/domain/preset.dart';

void main() {
  test(
    'Face geometry preserves normalized coordinates through crop, mirror and edit records',
    () {
      const f = FaceRegion(
        Rect.fromLTWH(.2, .1, .4, .6),
        Offset(.22, .48),
        Offset(.58, .5),
      );
      final mirror = f.mirrored();
      expect(mirror.leftJaw.dx, closeTo(.42, .0001));
      expect(mirror.leftJaw.dy, .5);
      expect(mirror.rightJaw.dx, closeTo(.78, .0001));
      expect(f.cropped(16 / 9, 4 / 3).box.width, closeTo(.4 * 4 / 3, .0001));
      final edit = PhotoEdit(
        Recipe('jade', parameterDefaults),
        Watermark(),
        DateTime(2026),
        faces: [f],
      );
      expect(PhotoEdit.decode(edit.encode()).faces.single.toJson(), f.toJson());
      expect(
        () => FaceRegion.fromJson({
          'box': [0, 0, 0, 1],
          'jaw': [0, 0, 1, 1],
        }),
        throwsFormatException,
      );
    },
  );

  test('Group edits keep eight faces and older face data can be refreshed', () {
    final faces = [
      for (var i = 0; i < FaceRegion.maxFaces; i++)
        FaceRegion(Rect.fromLTWH(i / 8, .2, .1, .2), Offset.zero, Offset.zero),
    ];
    final edit = PhotoEdit(
      Recipe('jade', parameterDefaults),
      Watermark(),
      DateTime(2026),
      faces: faces,
    );
    final current = PhotoEdit.decode(edit.encode());
    expect(
      current.faces.map((face) => face.box),
      faces.map((face) => face.box),
    );
    expect(current.faceGeometryVersion, FaceRegion.geometryVersion);
    final old = jsonDecode(edit.encode()) as Map<String, dynamic>
      ..remove('faceGeometryVersion');
    expect(PhotoEdit.decode(jsonEncode(old)).faceGeometryVersion, 1);
  });

  test(
    'Tracking follows overlapping boxes and never shares a previous face',
    () {
      const left = FaceRegion(
        Rect.fromLTWH(.1, .2, .20, .28),
        Offset.zero,
        Offset.zero,
      );
      const right = FaceRegion(
        Rect.fromLTWH(.22, .2, .20, .28),
        Offset.zero,
        Offset.zero,
      );
      final nextRight = right.transform(1, 1, -.01, .01);
      final nextLeft = left.transform(1, 1, .01, .01);
      final matched = FaceRegion.stabilize(
        [left, right],
        [nextRight, nextLeft],
        .5,
      );
      expect(matched.map((f) => f.box), [
        right.lerp(nextRight, .5).box,
        left.lerp(nextLeft, .5).box,
      ]);
      final unmatched = FaceRegion.stabilize([left], [nextRight, nextLeft], .5);
      expect(identical(unmatched.first, nextRight), isTrue);
    },
  );
}
