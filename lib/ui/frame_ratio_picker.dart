import 'design_system.dart';
import 'package:flutter/material.dart';
import '../domain/frame_ratio.dart';

Future<void> showFrameRatioPicker(
  BuildContext context,
  double? current,
  ValueChanged<double?> select,
) => PandaDesign.sheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheet) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '画幅比例',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Text('按所选比例居中裁剪，保持图像等比。横竖拍自动对应。'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final ratio in <double?>[null, 1, 4 / 3, 3 / 2, 16 / 9])
                ChoiceChip(
                  label: Text(frameRatioLabel(ratio)),
                  selected: current == ratio,
                  onSelected: (_) {
                    select(ratio);
                    Navigator.pop(sheet);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('自定义宽高比'),
            onPressed: () async {
              final result = await showDialog<double>(
                context: sheet,
                builder: (_) => const _CustomRatio(),
              );
              if (result == null || !sheet.mounted) return;
              select(result);
              Navigator.pop(sheet);
            },
          ),
        ],
      ),
    ),
  ),
);

class _CustomRatio extends StatefulWidget {
  const _CustomRatio();
  @override
  State<_CustomRatio> createState() => _CustomRatioState();
}

class _CustomRatioState extends State<_CustomRatio> {
  final width = TextEditingController(text: '5');
  final height = TextEditingController(text: '4');
  String? error;
  @override
  void dispose() {
    width.dispose();
    height.dispose();
    super.dispose();
  }

  void finish() {
    final w = int.tryParse(width.text), h = int.tryParse(height.text);
    if (w == null || h == null || w < 1 || h < 1 || w > 99 || h > 99) {
      setState(() => error = '宽和高请输入1–99的整数');
      return;
    }
    final ratio = w > h ? w / h : h / w;
    if (validFrameRatio(ratio) == null) {
      setState(() => error = '长边与短边之比请不超过4:1');
      return;
    }
    Navigator.pop(context, ratio);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义宽高比'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('ratio-width'),
                controller: width,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '宽'),
              ),
            ),
            const Padding(padding: EdgeInsets.all(12), child: Text(':')),
            Expanded(
              child: TextField(
                key: const ValueKey('ratio-height'),
                controller: height,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '高'),
              ),
            ),
          ],
        ),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: finish, child: const Text('使用')),
    ],
  );
}
