import 'package:flutter/material.dart';
import '../domain/preset.dart';
import 'camera_glass.dart';

/// An in-dock editor: no modal scrim, and never covers the viewfinder.
class BeautyPanel extends StatefulWidget {
  final Map<String, double> values;
  final ValueChanged<bool> onEnabled;
  final void Function(String, double) onChanged;
  final VoidCallback onReset, onClose;
  final String? status;
  const BeautyPanel({
    super.key,
    required this.values,
    required this.onEnabled,
    required this.onChanged,
    required this.onReset,
    required this.onClose,
    this.status,
  });
  @override
  State<BeautyPanel> createState() => _BeautyPanelState();
}

class _BeautyPanelState extends State<BeautyPanel> {
  String selected = 'faceSlim';
  static const names = {
    'faceSlim': '下颌',
    'beautySmooth': '磨皮',
    'beautyEven': '匀肤',
    'beautyWhiten': '提亮',
    'beauty': '强度',
  };
  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
    ),
    child: Column(
      key: const ValueKey('ccd-beauty-dock'),
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 4),
              const Text(
                '美颜',
                style: TextStyle(
                  color: CameraGlass.foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(
                width: 44,
                child: Transform.scale(
                  scale: .72,
                  child: Switch(
                    value: (widget.values['beauty'] ?? 0) > 0,
                    onChanged: widget.onEnabled,
                    activeThumbColor: CameraGlass.backdrop,
                    activeTrackColor: CameraGlass.foreground,
                    inactiveThumbColor: CameraGlass.secondary,
                    inactiveTrackColor: CameraGlass.selection,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '恢复推荐美颜',
                onPressed: widget.onReset,
                color: CameraGlass.foreground,
                icon: const Icon(Icons.restart_alt, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: '收起美颜调节',
                onPressed: widget.onClose,
                color: CameraGlass.foreground,
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 16,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.status ?? '实时预览',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  color: CameraGlass.secondary,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final e in names.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: TextButton(
                      onPressed: () => setState(() => selected = e.key),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(40, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        backgroundColor: selected == e.key
                            ? CameraGlass.selection
                            : Colors.transparent,
                        foregroundColor: CameraGlass.foreground,
                      ),
                      child: Text(
                        e.value,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  key: const ValueKey('ccd-beauty-slider'),
                  label: parameterLabels[selected],
                  activeColor: CameraGlass.foreground,
                  inactiveColor: CameraGlass.selection,
                  value:
                      widget.values[selected] ?? parameterDefaults[selected]!,
                  onChanged: (v) => widget.onChanged(selected, v),
                ),
              ),
              SizedBox(
                width: 35,
                child: Text(
                  '${((widget.values[selected] ?? parameterDefaults[selected]!) * 100).round()}',
                  style: const TextStyle(
                    color: CameraGlass.foreground,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
