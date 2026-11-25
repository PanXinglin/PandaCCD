import 'dart:ui';

/// Ratios are stored long-edge / short-edge. Portrait and landscape use the
/// same preference; only the source image determines its orientation.
double? validFrameRatio(Object? value) {
  if (value is! num || !value.isFinite || value < 1 || value > 4) return null;
  return value.toDouble();
}

Size croppedFrameSize(Size source, {double? aspect, bool square = false}) {
  final longRatio = square ? 1.0 : validFrameRatio(aspect);
  if (longRatio == null) return source;
  final target = source.width >= source.height ? longRatio : 1 / longRatio;
  return source.aspectRatio > target
      ? Size(source.height * target, source.height)
      : Size(source.width, source.width / target);
}

String frameRatioLabel(double? ratio) {
  if (ratio == null) return '原始';
  for (final pair in [(1, 1), (4, 3), (3, 2), (16, 9)]) {
    if ((ratio - pair.$1 / pair.$2).abs() < .00001) {
      return '${pair.$1}:${pair.$2}';
    }
  }
  for (var denominator = 1; denominator <= 99; denominator++) {
    final numerator = (ratio * denominator).round();
    if (numerator <= 99 && (ratio - numerator / denominator).abs() < .00001) {
      return '$numerator:$denominator';
    }
  }
  return '${ratio.toStringAsFixed(2)}:1';
}
