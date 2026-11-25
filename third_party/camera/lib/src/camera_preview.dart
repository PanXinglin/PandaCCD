// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../camera.dart';

/// A widget showing a live camera preview.
class CameraPreview extends StatelessWidget {
  /// Creates a preview widget for the given camera controller.
  const CameraPreview(
    this.controller, {
    super.key,
    this.child,
    this.previewOrientation,
  });

  /// The controller for the camera that the preview is shown for.
  final CameraController controller;

  /// Optional window presentation orientation, independent of photo capture.
  /// A fixed camera window must not rotate when the shutter temporarily locks
  /// the encoded photograph to the user's grip.
  final DeviceOrientation? previewOrientation;

  /// A widget to overlay on top of the camera preview
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return controller.value.isInitialized
        ? ValueListenableBuilder<CameraValue>(
            valueListenable: controller,
            builder: (BuildContext context, Object? value, Widget? child) {
              return AspectRatio(
                aspectRatio: _isLandscape()
                    ? controller.value.aspectRatio
                    : (1 / controller.value.aspectRatio),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _wrapInRotatedBox(child: controller.buildPreview()),
                    child ?? Container(),
                  ],
                ),
              );
            },
            child: child,
          )
        : Container();
  }

  Widget _wrapInRotatedBox({required Widget child}) {
    if (kIsWeb) return child;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Paired with our camera_avfoundation portrait-buffer patch. Front
      // buffers are mirrored before rotation, so conjugate the rotation.
      final front =
          controller.description.lensDirection == CameraLensDirection.front;
      return RotatedBox(
        quarterTurns: front ? -_getQuarterTurns() : _getQuarterTurns(),
        child: child,
      );
    }
    if (defaultTargetPlatform != TargetPlatform.android) return child;
    return RotatedBox(quarterTurns: _getQuarterTurns(), child: child);
  }

  bool _isLandscape() {
    return <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ].contains(_getApplicableOrientation());
  }

  int _getQuarterTurns() {
    final turns = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeRight: 1,
      DeviceOrientation.portraitDown: 2,
      DeviceOrientation.landscapeLeft: 3,
    };
    return turns[_getApplicableOrientation()]!;
  }

  DeviceOrientation _getApplicableOrientation() {
    if (previewOrientation != null) return previewOrientation!;
    return controller.value.isRecordingVideo
        ? controller.value.recordingOrientation!
        : (controller.value.previewPauseOrientation ??
              controller.value.lockedCaptureOrientation ??
              controller.value.deviceOrientation);
  }
}
