import 'dart:ui' show DisplayFeatureType;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/camera_orientation.dart';

int cameraQuarterTurns(DeviceOrientation orientation) => switch (orientation) {
  DeviceOrientation.portraitUp => 0,
  DeviceOrientation.landscapeRight => 1,
  DeviceOrientation.portraitDown => 2,
  DeviceOrientation.landscapeLeft => 3,
};

DeviceOrientation cameraWindowOrientation(
  Size size,
  DeviceOrientation device, {
  bool allowPortraitDown = true,
}) {
  if (size.width <= size.height) {
    return allowPortraitDown && device == DeviceOrientation.portraitDown
        ? DeviceOrientation.portraitDown
        : DeviceOrientation.portraitUp;
  }
  return device == DeviceOrientation.landscapeRight
      ? DeviceOrientation.landscapeRight
      : DeviceOrientation.landscapeLeft;
}

class CameraViewportScope extends InheritedWidget {
  const CameraViewportScope({
    super.key,
    required this.window,
    required this.turns,
    required super.child,
  });
  final DeviceOrientation window;
  final int turns;
  static CameraViewportScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CameraViewportScope>();
  @override
  bool updateShouldNotify(CameraViewportScope old) =>
      window != old.window || turns != old.turns;
}

/// Use the OS window coordinates on unfolded displays. Compact displays keep
/// their portrait window through CameraOrientation; only their controls turn.
/// Never counter-rotate the whole scene: a fold's sensor direction is not a
/// reliable indication of its window rotation or natural display orientation.
class CameraViewport extends StatelessWidget {
  const CameraViewport({
    super.key,
    required this.controller,
    required this.child,
    this.orientation,
  });
  final CameraOrientation? orientation;
  final CameraController? controller;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    Widget frame(DeviceOrientation device) => LayoutBuilder(
      builder: (context, bounds) {
        final window = cameraWindowOrientation(
          bounds.biggest,
          device,
          allowPortraitDown: orientation?.expanded ?? true,
        );
        return CameraViewportScope(
          window: window,
          turns: 0,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: bounds.biggest),
            child: child,
          ),
        );
      },
    );
    return ListenableBuilder(
      listenable: Listenable.merge([?controller, ?orientation]),
      child: child,
      builder: (context, _) => frame(
        controller?.value.deviceOrientation ?? DeviceOrientation.portraitUp,
      ),
    );
  }
}

// A bend in a continuous display is not an obstruction. Keep the camera's
// canvas centered while posture updates; still avoid physical hinges/cutouts.
class CameraDisplayArea extends StatelessWidget {
  const CameraDisplayArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        displayFeatures: media.displayFeatures
            .where((feature) => feature.type != DisplayFeatureType.fold)
            .toList(),
      ),
      child: DisplayFeatureSubScreen(anchorPoint: Offset.zero, child: child),
    );
  }
}
