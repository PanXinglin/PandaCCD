import 'package:flutter/material.dart';
import 'camera_glass.dart';
import '../domain/preset.dart';

/// Let the preview compute its own ratio during asynchronous rotation events.
/// Fitting that intrinsic rectangle avoids squeezing a stale portrait texture
/// into the new landscape frame (or the reverse) during a display handoff.
class CameraTextureFit extends StatelessWidget {
  final Widget child;
  final BoxFit fit;
  const CameraTextureFit({
    super.key,
    required this.child,
    this.fit = BoxFit.contain,
  });
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: fit,
    child: SizedBox(height: 720, child: child),
  );
}

/// Fits the complete sensor image into the available canvas. Controls are drawn
/// by the parent as overlays, so opening tools never resizes the viewfinder.
class CameraStage extends StatelessWidget {
  final double aspectRatio;
  final Widget child;
  final Widget? overlay;
  const CameraStage({
    super.key,
    required this.aspectRatio,
    required this.child,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: CameraGlass.backdrop,
    child: SizedBox.expand(
      key: const ValueKey('ccd-preview-area'),
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            key: const ValueKey('ccd-sensor-frame'),
            fit: StackFit.expand,
            children: [
              child,
              if (overlay != null) Positioned.fill(child: overlay!),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One responsive rule for windows, cover screens, unfolded devices and tablets.
/// It deliberately does not look up device models or assume a physical rotation.
bool usesCameraRail(Size bounds) =>
    (bounds.width >= 560 && bounds.width / bounds.height >= 1.15) ||
    (bounds.width >= 700 && bounds.width / bounds.height >= .85);

class CompactPresetStrip extends StatefulWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final bool vertical;
  const CompactPresetStrip({
    super.key,
    required this.selected,
    required this.onSelect,
    this.vertical = false,
  });
  @override
  State<CompactPresetStrip> createState() => _CompactPresetStripState();
}

class _CompactPresetStripState extends State<CompactPresetStrip> {
  final keys = List.generate(presets.length, (_) => GlobalKey());
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  double labelWidth(String text, double size, FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(
          context,
        ).style.copyWith(fontSize: size, fontWeight: weight),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  void initState() {
    super.initState();
    reveal();
  }

  @override
  void didUpdateWidget(CompactPresetStrip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected || old.vertical != widget.vertical) {
      reveal(animate: old.vertical == widget.vertical);
    }
  }

  void reveal({bool animate = true}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scroll.hasClients) return;
        if (widget.selected == 0) {
          if (scroll.offset != 0) scroll.jumpTo(0);
          return;
        }
        final target = keys[widget.selected].currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: .5,
            duration: animate && !MediaQuery.disableAnimationsOf(context)
                ? const Duration(milliseconds: 180)
                : Duration.zero,
          );
          return;
        }
        var offset = 8.0;
        for (var index = 0; index < widget.selected; index++) {
          final preset = presets[index];
          if (widget.vertical) {
            offset += 56;
            continue;
          }
          final name = labelWidth(preset.name, 12, FontWeight.w600);
          final style = labelWidth(preset.subtitle, 11, FontWeight.normal);
          offset += (name > style ? name : style) + 49;
        }
        scroll.jumpTo(offset.clamp(0.0, scroll.position.maxScrollExtent));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final target = keys[widget.selected].currentContext;
          if (target != null) {
            Scrollable.ensureVisible(
              target,
              alignment: .5,
              duration: animate && !MediaQuery.disableAnimationsOf(context)
                  ? const Duration(milliseconds: 180)
                  : Duration.zero,
            );
          }
        });
      });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.vertical
        ? null
        : 56 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
    child: ListView.separated(
      controller: scroll,
      scrollDirection: widget.vertical ? Axis.vertical : Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: presets.length,
      separatorBuilder: (_, _) => widget.vertical
          ? const SizedBox(height: 8)
          : const SizedBox(width: 6),
      itemBuilder: (context, index) => Center(
        child: Semantics(
          selected: widget.selected == index,
          button: true,
          child: Tooltip(
            message: '${presets[index].name} · ${presets[index].subtitle}',
            child: InkWell(
              key: keys[index],
              onTap: () => widget.onSelect(index),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: widget.vertical ? double.infinity : null,
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: widget.selected == index
                      ? CameraGlass.selection
                      : widget.vertical
                      ? const Color(0x0fffffff)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Color(presets[index].swatch),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      fit: FlexFit.loose,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            presets[index].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: CameraGlass.foreground,
                            ),
                          ),
                          Text(
                            presets[index].subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              color: CameraGlass.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
