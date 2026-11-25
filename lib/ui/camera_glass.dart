import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Neutral glass for the controls that float above the live camera image.
class CameraGlass extends StatelessWidget {
  static const backdrop = Color(0xff111316);
  static const foreground = Color(0xfffafafb);
  static const secondary = Color(0xffe0e1e5);
  static const selection = Color(0x24ffffff);

  final Widget child;
  final double radius;
  final bool panel;
  final bool border;
  final bool edgeFade;

  const CameraGlass({
    super.key,
    required this.child,
    this.radius = 22,
    this.panel = false,
    this.border = true,
    this.edgeFade = false,
  });

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    final shape = BorderRadius.circular(radius);
    final tint = backdrop.withValues(
      alpha: highContrast ? .97 : (panel ? .71 : .61),
    );
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter.grouped(
        enabled: !highContrast && !edgeFade,
        filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: edgeFade
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00111316), Color(0xd1111316), backdrop],
                    stops: [0, .13, .92],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(const Color(0x08ffffff), tint),
                      tint,
                    ],
                  ),
          ),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: shape,
              border: border
                  ? Border.all(color: const Color(0x42ffffff), width: .8)
                  : null,
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}
