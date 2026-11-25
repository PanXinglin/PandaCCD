import 'package:flutter/material.dart';
import '../domain/preset.dart';
import 'components.dart';

class PresetPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const PresetPicker({
    super.key,
    required this.selected,
    required this.onSelect,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '选择 CCD',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: '关闭机型库',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Text(
          '按机型和拍摄场景选择。机型预设为灵感调色，非原厂色彩标定。',
          style: TextStyle(fontSize: 12, height: 1.5),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: presets.length,
          itemBuilder: (context, index) {
            final preset = presets[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (index == 0 ||
                    (index > 0 &&
                        preset.isCamera != presets[index - 1].isCamera))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Text(
                      preset.isCamera ? '机型灵感' : '创意风格',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Material(
                    color: selected == index
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .045),
                    borderRadius: BorderRadius.circular(18),
                    child: ListTile(
                      key: ValueKey('ccd-model-${preset.id}'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: Color(preset.swatch),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          color: ink,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        preset.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            preset.subtitle,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (preset.isCamera) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${preset.year} · ${preset.sensor}',
                              style: const TextStyle(fontSize: 10),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              preset.description!,
                              style: const TextStyle(fontSize: 11, height: 1.5),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '适合：${preset.scene}',
                              style: const TextStyle(fontSize: 11, height: 1.5),
                            ),
                          ],
                        ],
                      ),
                      trailing: selected == index
                          ? Icon(
                              Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            )
                          : null,
                      onTap: () => onSelect(index),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      const SafeArea(top: false, child: SizedBox(height: 8)),
    ],
  );
}
