import 'design_system.dart';
import 'package:flutter/material.dart';
import '../domain/preset.dart';

class WatermarkChoices extends StatelessWidget {
  final Watermark stamp;
  final VoidCallback onChanged;
  final EdgeInsetsGeometry? contentPadding;
  const WatermarkChoices({
    super.key,
    required this.stamp,
    required this.onChanged,
    this.contentPadding,
  });
  @override
  Widget build(BuildContext context) {
    final tilePadding =
        contentPadding ??
        ListTileTheme.of(context).contentPadding ??
        const EdgeInsets.symmetric(horizontal: 16);
    final sides = tilePadding.resolve(Directionality.of(context));
    Widget inset(Widget child) => Padding(
      padding: EdgeInsets.only(left: sides.left, right: sides.right),
      child: child,
    );
    return Column(
      children: [
        inset(
          DropdownButtonFormField<bool>(
            dropdownColor: PandaDesign.raised,
            borderRadius: BorderRadius.circular(16),
            isExpanded: true,
            key: ValueKey('watermark-color-${stamp.red}'),
            initialValue: stamp.red,
            decoration: const InputDecoration(
              labelText: '水印颜色',
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: false, child: Text('琥珀黄色')),
              DropdownMenuItem(value: true, child: Text('复古红色')),
            ],
            onChanged: stamp.date || stamp.model
                ? (value) {
                    stamp.red = value!;
                    onChanged();
                  }
                : null,
          ),
        ),
        const SizedBox(height: 12),
        inset(
          DropdownButtonFormField<int>(
            dropdownColor: PandaDesign.raised,
            borderRadius: BorderRadius.circular(16),
            isExpanded: true,
            key: ValueKey('watermark-position-${stamp.top}-${stamp.left}'),
            initialValue: (stamp.top ? 0 : 2) + (stamp.left ? 0 : 1),
            decoration: const InputDecoration(
              labelText: '水印位置',
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('左上角')),
              DropdownMenuItem(value: 1, child: Text('右上角')),
              DropdownMenuItem(value: 2, child: Text('左下角')),
              DropdownMenuItem(value: 3, child: Text('右下角')),
            ],
            onChanged: stamp.date || stamp.model
                ? (value) {
                    stamp.top = value! < 2;
                    stamp.left = value.isEven;
                    onChanged();
                  }
                : null,
          ),
        ),
        ListTile(
          contentPadding: tilePadding,
          title: const Text('自定义水印文字'),
          subtitle: Text(stamp.text.isEmpty ? 'PandaCCD（默认）' : stamp.text),
          trailing: const Icon(Icons.edit_outlined),
          enabled: stamp.model,
          onTap: () async {
            final value = await showDialog<String>(
              context: context,
              builder: (_) => _WatermarkDialog(text: stamp.text),
            );
            if (!context.mounted || value == null) return;
            stamp.text = cleanWatermarkText(value);
            onChanged();
          },
        ),
        SwitchListTile(
          contentPadding: tilePadding,
          title: const Text('附加机型名称'),
          subtitle: const Text('例如 G12 INSPIRED'),
          value: stamp.includeModel,
          onChanged: stamp.model
              ? (value) {
                  stamp.includeModel = value;
                  onChanged();
                }
              : null,
        ),
      ],
    );
  }
}

class _WatermarkDialog extends StatefulWidget {
  final String text;
  const _WatermarkDialog({required this.text});
  @override
  State<_WatermarkDialog> createState() => _WatermarkDialogState();
}

class _WatermarkDialogState extends State<_WatermarkDialog> {
  late final controller = TextEditingController(text: widget.text);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义水印文字'),
    content: TextField(
      controller: controller,
      maxLength: 32,
      autofocus: true,
      decoration: const InputDecoration(
        hintText: '留空使用PandaCCD',
        helperText: '支持中文、英文、数字，最多32字',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('完成'),
      ),
    ],
  );
}
