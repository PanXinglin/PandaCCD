import 'dart:ui';

/// Normalized coordinates in the upright, unmirrored source image.
class FaceRegion {
  /// Shared capacity of the Android and iOS bridges and the GPU shader.
  static const maxFaces = 8;
  static const geometryVersion = 2;

  /// Match each old face at most once, independent of detector size ordering.
  static List<FaceRegion> stabilize(
    List<FaceRegion> previous,
    List<FaceRegion> next,
    double amount,
  ) {
    final matches = <({int old, int fresh, double overlap})>[];
    for (var i = 0; i < previous.length; i++) {
      for (var j = 0; j < next.length; j++) {
        final a = previous[i].box, b = next[j].box;
        final shared = a.intersect(b);
        if (shared.isEmpty) continue;
        final area = shared.width * shared.height;
        final overlap = area / (a.width * a.height + b.width * b.height - area);
        if (overlap >= .2) matches.add((old: i, fresh: j, overlap: overlap));
      }
    }
    matches.sort((a, b) => b.overlap.compareTo(a.overlap));
    final used = <int>{};
    final result = [...next];
    final updated = <int>{};
    for (final match in matches) {
      if (updated.contains(match.fresh) || !used.add(match.old)) continue;
      updated.add(match.fresh);
      result[match.fresh] = previous[match.old].lerp(next[match.fresh], amount);
    }
    return result;
  }

  final Rect box;
  final Offset leftJaw, rightJaw;
  final List<Offset> outline;
  final Offset? mouth;
  const FaceRegion(
    this.box,
    this.leftJaw,
    this.rightJaw, {
    this.outline = const [],
    this.mouth,
  });
  factory FaceRegion.fromJson(Map data) {
    final b = (data['box'] as List).cast<num>();
    final j = (data['jaw'] as List).cast<num>();
    if (b.length != 4 ||
        j.length != 4 ||
        [...b, ...j].any((x) => !x.isFinite) ||
        b[2] <= 0 ||
        b[3] <= 0) {
      throw const FormatException('Invalid face geometry');
    }
    return FaceRegion(
      Rect.fromLTWH(
        b[0].toDouble(),
        b[1].toDouble(),
        b[2].toDouble(),
        b[3].toDouble(),
      ),
      Offset(j[0].toDouble(), j[1].toDouble()),
      Offset(j[2].toDouble(), j[3].toDouble()),
      outline: (data['outline'] as List? ?? const []).take(64).map((p) {
        final v = (p as List).cast<num>();
        if (v.length != 2 || v.any((n) => !n.isFinite)) {
          throw const FormatException('Invalid face outline');
        }
        return Offset(v[0].toDouble(), v[1].toDouble());
      }).toList(),
      mouth: data['mouth'] is List && (data['mouth'] as List).length == 2
          ? Offset(
              (data['mouth'][0] as num).toDouble(),
              (data['mouth'][1] as num).toDouble(),
            )
          : null,
    );
  }
  Map<String, Object> toJson() => {
    'box': [box.left, box.top, box.width, box.height],
    'jaw': [leftJaw.dx, leftJaw.dy, rightJaw.dx, rightJaw.dy],
    if (outline.isNotEmpty)
      'outline': [
        for (final p in outline) [p.dx, p.dy],
      ],
    if (mouth != null) 'mouth': [mouth!.dx, mouth!.dy],
  };
  FaceRegion lerp(FaceRegion other, double t) => FaceRegion(
    Rect.lerp(box, other.box, t)!,
    Offset.lerp(leftJaw, other.leftJaw, t)!,
    Offset.lerp(rightJaw, other.rightJaw, t)!,
    outline: outline.length == other.outline.length
        ? [
            for (var i = 0; i < outline.length; i++)
              Offset.lerp(outline[i], other.outline[i], t)!,
          ]
        : other.outline,
    mouth: mouth != null && other.mouth != null
        ? Offset.lerp(mouth, other.mouth, t)
        : other.mouth,
  );
  FaceRegion transform(double sx, double sy, double dx, double dy) =>
      FaceRegion(
        Rect.fromLTWH(
          box.left * sx + dx,
          box.top * sy + dy,
          box.width * sx,
          box.height * sy,
        ),
        Offset(leftJaw.dx * sx + dx, leftJaw.dy * sy + dy),
        Offset(rightJaw.dx * sx + dx, rightJaw.dy * sy + dy),
        outline: [
          for (final p in outline) Offset(p.dx * sx + dx, p.dy * sy + dy),
        ],
        mouth: mouth == null
            ? null
            : Offset(mouth!.dx * sx + dx, mouth!.dy * sy + dy),
      );
  FaceRegion cropped(double sourceAspect, double frameAspect) {
    if (sourceAspect > frameAspect) {
      final sx = sourceAspect / frameAspect;
      return transform(sx, 1, (1 - sx) / 2, 0);
    }
    final sy = frameAspect / sourceAspect;
    return transform(1, sy, 0, (1 - sy) / 2);
  }

  FaceRegion mirrored() => FaceRegion(
    Rect.fromLTWH(1 - box.right, box.top, box.width, box.height),
    Offset(1 - rightJaw.dx, rightJaw.dy),
    Offset(1 - leftJaw.dx, leftJaw.dy),
    outline: [for (final p in outline) Offset(1 - p.dx, p.dy)],
    mouth: mouth == null ? null : Offset(1 - mouth!.dx, mouth!.dy),
  );

  /// Four symmetric pairs along the lower contour, then chin + lip centre.
  /// Never synthesize a lower jaw from two cheek points in an old edit record.
  List<Offset> get lowerJaw {
    if (outline.length < 8 ||
        mouth == null ||
        !mouth!.dx.isFinite ||
        !mouth!.dy.isFinite) {
      return const [];
    }
    final chin = outline.reduce((a, b) => a.dy > b.dy ? a : b);
    if (chin.dy - mouth!.dy < box.height * .08) return const [];
    // Keep the cheek-to-jaw segment above the lips as an interpolation anchor.
    // Sparse contours may only have one point below the lips on either side.
    final upperAnchor = mouth!.dy - box.height * .20;
    final left =
        outline.where((p) => p.dx < mouth!.dx && p.dy >= upperAnchor).toList()
          ..sort((a, b) => a.dy.compareTo(b.dy));
    final right =
        outline.where((p) => p.dx > mouth!.dx && p.dy >= upperAnchor).toList()
          ..sort((a, b) => a.dy.compareTo(b.dy));
    if (left.length < 2 || right.length < 2) return const [];
    Offset sample(List<Offset> side, double y) {
      final points = [...side, chin]..sort((a, b) => a.dy.compareTo(b.dy));
      for (var i = 1; i < points.length; i++) {
        if (points[i].dy >= y && points[i].dy > points[i - 1].dy) {
          return Offset.lerp(
            points[i - 1],
            points[i],
            ((y - points[i - 1].dy) / (points[i].dy - points[i - 1].dy)).clamp(
              0,
              1,
            ),
          )!;
        }
      }
      return chin;
    }

    return [
      for (final t in [.08, .35, .62, .85]) ...[
        sample(left, mouth!.dy + (chin.dy - mouth!.dy) * t),
        sample(right, mouth!.dy + (chin.dy - mouth!.dy) * t),
      ],
      chin,
      mouth!,
    ];
  }
}
