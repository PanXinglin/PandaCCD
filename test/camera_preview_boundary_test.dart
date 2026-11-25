import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/ui/camera_preview_boundary.dart';

void main() {
  testWidgets(
    'Resizing can retain the last painted frame while a new texture frame is pending',
    (tester) async {
      final key = GlobalKey();
      Widget scene(Color color) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 12,
            height: 8,
            child: CameraPreviewBoundary(
              key: key,
              child: ColoredBox(color: color),
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene(const Color(0xffff0000)));
      final boundary =
          key.currentContext!.findRenderObject()!
              as CameraPreviewRenderBoundary;
      // Window metrics can invalidate layout before a camera texture is ready.
      boundary.markNeedsLayout();
      boundary.markNeedsPaint();
      final image = boundary.lastPaintedFrame()!;
      expect(image.width, 12);
      expect(image.height, 8);
      await tester.pumpWidget(scene(const Color(0xff0000ff)));
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      expect(bytes!.getUint8(0), 255);
      expect(bytes.getUint8(1), 0);
      expect(
        bytes.getUint8(2),
        0,
        reason: 'The held frame must remain the previous red image',
      );
      await tester.pumpWidget(const SizedBox());
      image.dispose();
    },
  );
}
