import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Exposes the last painted layer while a window resize has already scheduled
/// a new layout. The returned GPU image is owned and disposed by the caller.
class CameraPreviewBoundary extends SingleChildRenderObjectWidget {
  const CameraPreviewBoundary({super.key, required super.child});
  @override
  CameraPreviewRenderBoundary createRenderObject(BuildContext context) =>
      CameraPreviewRenderBoundary();
}

class CameraPreviewRenderBoundary extends RenderRepaintBoundary {
  ui.Image? lastPaintedFrame() {
    final paintedLayer = layer;
    return paintedLayer is OffsetLayer && hasSize && !size.isEmpty
        ? paintedLayer.toImageSync(Offset.zero & size)
        : null;
  }
}
