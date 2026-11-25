import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum CapturePhase { idle, capturing, saving }

/// A brief dark shutter blink acknowledges an actual successful capture.
/// It is UI-only, never appears in the saved photo and never intercepts taps.
class ShutterPulse extends StatefulWidget {
  final ValueListenable<int> shots;
  const ShutterPulse({super.key, required this.shots});
  @override
  State<ShutterPulse> createState() => _ShutterPulseState();
}

class _ShutterPulseState extends State<ShutterPulse>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  late final opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: .38,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 20,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: .38,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 80,
    ),
  ]).animate(controller);
  @override
  void initState() {
    super.initState();
    widget.shots.addListener(pulse);
  }

  @override
  void didUpdateWidget(ShutterPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shots != widget.shots) {
      oldWidget.shots.removeListener(pulse);
      widget.shots.addListener(pulse);
    }
  }

  void pulse() {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
    controller.forward(from: .2);
  }

  @override
  void dispose() {
    widget.shots.removeListener(pulse);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: FadeTransition(
        opacity: opacity,
        child: const ColoredBox(color: Colors.black),
      ),
    ),
  );
}

/// The shutter stays plain at rest. Longer operations show a progress ring.
class CaptureButtonFace extends StatefulWidget {
  final ValueListenable<CapturePhase> phase;
  final Color color;
  const CaptureButtonFace({
    super.key,
    required this.phase,
    required this.color,
  });
  @override
  State<CaptureButtonFace> createState() => _CaptureButtonFaceState();
}

class _CaptureButtonFaceState extends State<CaptureButtonFace> {
  Timer? timer;
  bool progress = false;
  @override
  void initState() {
    super.initState();
    widget.phase.addListener(changed);
    changed();
  }

  @override
  void didUpdateWidget(CaptureButtonFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      oldWidget.phase.removeListener(changed);
      widget.phase.addListener(changed);
      changed();
    }
  }

  void changed() {
    if (widget.phase.value == CapturePhase.idle) {
      timer?.cancel();
      timer = null;
      if (progress) setState(() => progress = false);
    } else if (!progress && timer == null) {
      timer = Timer(const Duration(milliseconds: 250), () {
        timer = null;
        if (mounted && widget.phase.value != CapturePhase.idle) {
          setState(() => progress = true);
        }
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.phase.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: progress
        ? SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: widget.color,
              strokeWidth: 1.5,
            ),
          )
        : null,
  );
}
