import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/camera_orientation.dart';

import 'camera_viewport.dart';

/// Undo the presentation transform of the iOS portrait texture for metering.
Offset portraitMeteringPoint(
  Offset point,
  DeviceOrientation window, {
  required bool mirrored,
}) {
  final turns = (cameraQuarterTurns(window) * (mirrored ? -1 : 1)) % 4;
  final upright = switch (turns) {
    1 => Offset(point.dy, 1 - point.dx),
    2 => Offset(1 - point.dx, 1 - point.dy),
    3 => Offset(1 - point.dy, point.dx),
    _ => point,
  };
  return mirrored ? Offset(1 - upright.dx, upright.dy) : upright;
}

class StableCameraPreview extends StatelessWidget {
  const StableCameraPreview({
    super.key,
    required this.controller,
    required this.window,
  });
  final CameraController controller;
  final DeviceOrientation window;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CameraValue>(
    valueListenable: controller,
    builder: (context, value, _) {
      final compensation = CameraViewportScope.maybeOf(context)?.turns ?? 0;
      final landscape = (cameraQuarterTurns(window) - compensation).isOdd;
      final ratio = landscape ? value.aspectRatio : 1 / value.aspectRatio;
      // Keep the official sensor/display transform. Undo only the enclosing
      // CameraViewport scene turn so the image remains upright in world space.
      // Swapped child constraints preserve the complete texture's aspect ratio.
      return SizedBox(
        key: const ValueKey('ccd-stable-preview-frame'),
        width: 720 * ratio,
        height: 720,
        child: RotatedBox(
          quarterTurns: -compensation,
          child: CameraPreview(controller, previewOrientation: window),
        ),
      );
    },
  );
}

/// Rotate the content within its existing touch target. Sensor updates do not
/// relayout the toolbars, rebuild the camera stage, or move the shutter.
class CameraTurn extends StatelessWidget {
  const CameraTurn({
    super.key,
    required this.orientation,
    required this.child,
    this.controller,
  });
  final CameraOrientation orientation;
  final CameraController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([orientation, ?controller]),
    child: child,
    builder: (context, child) {
      // Expanded controls already follow the OS window. Only the portrait-
      // locked cover screen needs a grip-driven turn inside each touch target.
      final device = orientation.orientation ?? DeviceOrientation.portraitUp;
      var turns = orientation.expanded ? 0 : -cameraQuarterTurns(device) % 4;
      if (turns == 3) turns = -1;
      return AnimatedRotation(
        turns: turns / 4,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: child,
      );
    },
  );
}
