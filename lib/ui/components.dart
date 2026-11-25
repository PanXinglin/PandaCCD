import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../domain/preset.dart';
import '../domain/face_region.dart';
import '../services/filter_engine.dart';

const ink = Color(0xff222831);

class PandaMark extends StatelessWidget {
  final double size;
  const PandaMark({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/panda-mark.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}

class PresetStrip extends StatefulWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const PresetStrip({
    super.key,
    required this.selected,
    required this.onSelect,
  });
  @override
  State<PresetStrip> createState() => _PresetStripState();
}

class _PresetStripState extends State<PresetStrip> {
  final keys = List.generate(presets.length, (_) => GlobalKey());
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    reveal();
  }

  @override
  void didUpdateWidget(PresetStrip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) reveal();
  }

  void reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !scroll.hasClients) return;
    final target = keys[widget.selected].currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        alignment: .5,
        duration: const Duration(milliseconds: 180),
      );
      return;
    }
    scroll.jumpTo(
      (widget.selected * _itemExtent).clamp(
        0.0,
        scroll.position.maxScrollExtent,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = keys[widget.selected].currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: .5,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  });
  static const _itemExtent = 128.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      itemExtent: _itemExtent,
      itemCount: presets.length,
      itemBuilder: (context, i) {
        final active = widget.selected == i;
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: Semantics(
            selected: active,
            button: true,
            child: InkWell(
              key: keys[i],
              onTap: () => widget.onSelect(i),
              borderRadius: BorderRadius.circular(12),
              child: Ink(
                decoration: BoxDecoration(
                  color: active
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 4,
                      backgroundColor: Color(presets[i].swatch),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        presets[i].compactName,
                        semanticsLabel: presets[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class ParameterPanel extends StatelessWidget {
  final Map<String, double> values;
  final void Function(String, double) onChanged;
  const ParameterPanel({
    super.key,
    required this.values,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: parameterLabels.entries
        .map(
          (entry) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
            child: Row(
              children: [
                SizedBox(
                  width: 76,
                  child: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: values[entry.key]!,
                    onChanged: (v) => onChanged(entry.key, v),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${(values[entry.key]! * 100).round()}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
}

class FilteredPhoto extends StatefulWidget {
  final FilterEngine engine;
  final ui.Image image;
  final LutImage lut;
  final Map<String, double> values;
  final List<FaceRegion> faces;
  const FilteredPhoto({
    super.key,
    required this.engine,
    required this.image,
    required this.lut,
    required this.values,
    this.faces = const [],
  });
  @override
  State<FilteredPhoto> createState() => _FilteredPhotoState();
}

class _FilteredPhotoState extends State<FilteredPhoto> {
  ui.FragmentShader? shader;
  @override
  Widget build(BuildContext context) {
    shader?.dispose();
    shader = widget.engine.shader(
      widget.values,
      widget.lut,
      source: widget.image,
      faces: widget.faces,
      trackFace: true,
      size: Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
    );
    return CustomPaint(
      size: Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
      painter: _PhotoPainter(shader!),
    );
  }

  @override
  void dispose() {
    shader?.dispose();
    super.dispose();
  }
}

class _PhotoPainter extends CustomPainter {
  final ui.FragmentShader shader;
  _PhotoPainter(this.shader);
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  @override
  bool shouldRepaint(_PhotoPainter oldDelegate) => true;
}

class StampOverlay extends StatelessWidget {
  final Watermark stamp;
  final DateTime date;
  final String model;
  const StampOverlay({
    super.key,
    required this.stamp,
    required this.date,
    required this.model,
  });
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _StampPainter(stamp, date, model),
      size: Size.infinite,
    ),
  );
}

class _StampPainter extends CustomPainter {
  final Watermark stamp;
  final DateTime date;
  final String model;
  _StampPainter(this.stamp, this.date, this.model);
  @override
  void paint(Canvas canvas, Size size) =>
      paintWatermark(canvas, size, stamp, date, model);
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
Future<void> guarded(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) toast(context, '操作未完成：$e');
  }
}
