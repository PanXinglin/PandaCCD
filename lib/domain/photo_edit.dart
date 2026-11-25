import 'dart:convert';
import 'preset.dart';
import 'frame_ratio.dart';
import 'face_region.dart';

/// The non-destructive edit that produced a saved photo, independent of the
/// currently selected camera or any later changes to its custom LUT.
class PhotoEdit {
  final Recipe recipe;
  final Watermark stamp;
  final DateTime date;
  final int turns;
  final bool square;
  final double? frameAspect;
  final List<FaceRegion> faces;
  final int faceGeometryVersion;
  PhotoEdit(
    this.recipe,
    this.stamp,
    this.date, {
    this.turns = 0,
    this.square = false,
    this.frameAspect,
    this.faces = const [],
    this.faceGeometryVersion = FaceRegion.geometryVersion,
  });

  String encode() => jsonEncode({
    'version': 1,
    'recipe': jsonDecode(recipe.encode()),
    'watermark': stamp.toJson(),
    'date': date.toIso8601String(),
    'turns': turns % 4,
    'square': square,
    'frameAspect': frameAspect,
    if (faces.isNotEmpty) ...{
      'faces': faces.map((f) => f.toJson()).toList(),
      'faceGeometryVersion': faceGeometryVersion,
    },
  });

  static PhotoEdit decode(String text) {
    final data = jsonDecode(text);
    if (data is! Map ||
        data['version'] != 1 ||
        data['watermark'] is! Map ||
        data['date'] is! String ||
        data['turns'] is! int ||
        data['turns'] < 0 ||
        data['turns'] > 3) {
      throw const FormatException('照片编辑记录无效');
    }
    return PhotoEdit(
      Recipe.decode(jsonEncode(data['recipe'])),
      Watermark()..restore(data['watermark'] as Map),
      DateTime.parse(data['date'] as String),
      turns: data['turns'] as int,
      square: data['square'] == true,
      frameAspect: validFrameRatio(data['frameAspect']),
      faceGeometryVersion: data['faceGeometryVersion'] as int? ?? 1,
      faces: (data['faces'] as List? ?? const [])
          .whereType<Map>()
          .map(FaceRegion.fromJson)
          .take(FaceRegion.maxFaces)
          .toList(),
    );
  }
}
