import 'dart:io';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../domain/preset.dart';
import '../services/app_state.dart';
import 'components.dart';
import 'watermark_controls.dart';
import 'frame_ratio_picker.dart';
import '../domain/frame_ratio.dart';
import 'design_system.dart';
import 'about_page.dart';
import '../services/motion_photo.dart';

enum _SettingsArea {
  live('实况选项', Icons.motion_photos_on_outlined),
  view('取景与快门', Icons.center_focus_weak),
  save('保存与水印', Icons.photo_outlined),
  models('机型与调色', Icons.tune);

  const _SettingsArea(this.title, this.icon);
  final String title;
  final IconData icon;
}

class SettingsPage extends StatefulWidget {
  final AppState state;
  final _SettingsArea? _area;
  const SettingsPage({super.key, required this.state}) : _area = null;
  const SettingsPage._detail(this.state, this._area);
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool busy = false;
  AppState get app => widget.state;
  Future<void> change(void Function() mutation) async {
    setState(mutation);
    await guarded(context, app.persist);
  }

  Future<void> action(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    await guarded(context, fn);
    if (mounted) setState(() => busy = false);
  }

  Widget _icon(IconData icon) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: PandaDesign.raised,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, color: ink, size: 19),
  );

  Future<void> _open(_SettingsArea area) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SettingsPage._detail(app, area)),
    );
    if (mounted) setState(() {});
  }

  Widget _areaTile(_SettingsArea area, String detail) => ListTile(
    leading: _icon(area.icon),
    title: Text(area.title),
    subtitle: Text(detail),
    trailing: const Icon(
      Icons.chevron_right,
      color: PandaDesign.muted,
      size: 20,
    ),
    onTap: () => _open(area),
  );

  List<Widget> _overview() => [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 22),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '设置',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
          const PandaMark(size: 40),
        ],
      ),
    ),
    SettingsSection(
      title: '常用',
      children: [
        SwitchListTile(
          secondary: _icon(Icons.motion_photos_on_outlined),
          title: const Text('Live 动态照片'),
          value: app.liveEnabled,
          onChanged: (value) => change(() => app.setLiveEnabled(value)),
        ),
        SwitchListTile(
          secondary: _icon(Icons.face_retouching_natural),
          title: const Text('一键美颜'),
          value: app.beautyEnabled,
          onChanged: (_) => change(app.toggleBeauty),
        ),
      ],
    ),
    SettingsSection(
      title: '拍摄与照片',
      children: [
        _areaTile(_SettingsArea.live, app.liveSound ? '保留现场声音' : '静音录制'),
        _areaTile(_SettingsArea.view, '画幅比例、音量键与快门声'),
        _areaTile(_SettingsArea.save, app.directSave ? '拍后直接保存' : '拍后打开编辑'),
      ],
    ),
    SettingsSection(
      title: '管理',
      children: [
        _areaTile(_SettingsArea.models, app.preset.name),
        ListTile(
          leading: _icon(Icons.info_outline),
          title: const Text('关于PandaCCD'),
          subtitle: const Text('版本、隐私与开源致谢'),
          trailing: const Icon(
            Icons.chevron_right,
            color: PandaDesign.muted,
            size: 20,
          ),
          onTap: () => Navigator.of(
            context,
          ).push<void>(MaterialPageRoute(builder: (_) => const AboutPage())),
        ),
      ],
    ),
  ];

  List<Widget> _detail(_SettingsArea area) => switch (area) {
    _SettingsArea.live => [
      SwitchListTile(
        title: const Text('Live 录制声音'),
        subtitle: const Text('为实况照片保留现场声音'),
        value: app.liveSound,
        onChanged: (v) => change(() => app.liveSound = v),
      ),
      if (!Platform.isIOS)
        ListTile(
          title: const Text('动态照片保存格式'),
          subtitle: Text(MotionPhoto.labels[app.liveFormat] ?? '自动选择'),
          trailing: PopupMenuButton<String>(
            initialValue: app.liveFormat,
            onSelected: (v) => change(() => app.liveFormat = v),
            itemBuilder: (_) => [
              for (final key in MotionPhoto.formats)
                PopupMenuItem(
                  value: key,
                  child: Text(MotionPhoto.labels[key]!),
                ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.expand_more),
            ),
          ),
        ),
      if (!Platform.isIOS)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('若系统相册仅显示静图，可在应用内播放。', style: TextStyle(fontSize: 12)),
        ),
    ],
    _SettingsArea.view => [
      if (Platform.isIOS)
        const ListTile(
          title: Text('快门声'),
          subtitle: Text('使用 iPhone 系统快门声，遵循设备静音和地区设置'),
        )
      else
        SwitchListTile(
          title: const Text('快门声'),
          subtitle: const Text('拍到照片时播放，音量及静音行为由系统控制'),
          value: app.shutterSound,
          onChanged: (value) => change(() => app.shutterSound = value),
        ),
      SwitchListTile(
        title: const Text('音量键拍照'),
        subtitle: const Text('按音量上键或下键拍照'),
        value: app.volumeShutter,
        onChanged: (value) => change(() => app.volumeShutter = value),
      ),
      ListTile(
        title: const Text('画幅比例'),
        subtitle: Text(frameRatioLabel(app.frameAspect)),
        trailing: const Icon(Icons.aspect_ratio),
        onTap: () => showFrameRatioPicker(
          context,
          app.frameAspect,
          (ratio) => change(() => app.frameAspect = ratio),
        ),
      ),
    ],
    _SettingsArea.save => [
      SwitchListTile(
        title: const Text('拍照后打开编辑'),
        subtitle: const Text('默认直接保存，可从相册编辑。'),
        value: !app.directSave,
        onChanged: (v) => change(() => app.directSave = !v),
      ),
      if (!app.directSave)
        SwitchListTile(
          title: const Text('同时保留原图'),
          subtitle: const Text('原图仅存于应用内相册。'),
          value: app.keepOriginal,
          onChanged: (v) => change(() => app.keepOriginal = v),
        ),
      SwitchListTile(
        title: const Text('相册删除联动'),
        subtitle: const Text('开启后，删除已关联的照片时也会从系统相册删除。'),
        value: app.syncAlbumDeletes,
        onChanged: (value) => change(() => app.syncAlbumDeletes = value),
      ),
      SwitchListTile(
        title: const Text('复古日期戳'),
        value: app.watermark.date,
        onChanged: (v) => change(() => app.watermark.date = v),
      ),
      SwitchListTile(
        title: const Text('文字水印'),
        value: app.watermark.model,
        onChanged: (v) => change(() => app.watermark.model = v),
      ),
      WatermarkChoices(stamp: app.watermark, onChanged: () => change(() {})),
    ],
    _SettingsArea.models => [
      ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: const Text('保存当前参数'),
        onTap: () => action(() async {
          await app.persist();
          if (mounted) toast(context, '参数已保存');
        }),
      ),
      ListTile(
        leading: const Icon(Icons.file_upload_outlined),
        title: const Text('导出预设'),
        subtitle: const Text('JSON，包含自定义 HALD LUT'),
        onTap: () => action(() async {
          final box = context.findRenderObject() as RenderBox;
          await SharePlus.instance.share(
            ShareParams(
              files: [
                XFile.fromData(
                  utf8.encode(app.recipe.encode()),
                  mimeType: 'application/json',
                ),
              ],
              fileNameOverrides: ['panda-${app.preset.id}.json'],
              sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
            ),
          );
        }),
      ),
      ListTile(
        leading: const Icon(Icons.file_download_outlined),
        title: const Text('导入预设'),
        onTap: () => action(() async {
          final file = await openFile(
            acceptedTypeGroups: [
              const XTypeGroup(
                label: 'PandaCCD预设',
                extensions: ['json'],
                uniformTypeIdentifiers: ['public.json'],
              ),
            ],
          );
          if (file == null) return;
          if (await file.length() > 24 * 1024 * 1024) {
            throw const FormatException('文件不能超过24MB');
          }
          await app.applyRecipe(Recipe.decode(await file.readAsString()));
          if (mounted) {
            setState(() {});
            toast(context, '预设已导入');
          }
        }),
      ),
      ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: const Text('载入自定义 HALD LUT'),
        subtitle: const Text('PNG，替换当前机型的色彩基底'),
        onTap: () => action(() async {
          final file = await openFile(
            acceptedTypeGroups: [
              const XTypeGroup(
                label: 'HALD PNG',
                extensions: ['png'],
                uniformTypeIdentifiers: ['public.png'],
              ),
            ],
          );
          if (file == null) return;
          if (await file.length() > 16 * 1024 * 1024) {
            throw const FormatException('LUT不能超过16MB');
          }
          await app.importLut(await file.readAsBytes());
          if (mounted) toast(context, 'HALD LUT 已载入');
        }),
      ),
      ListTile(
        leading: const Icon(Icons.restart_alt),
        title: const Text('重置当前机型'),
        onTap: () => action(() async {
          await app.reset();
          if (mounted) toast(context, '已恢复出厂参数和 LUT');
        }),
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final area = widget._area;
    return Scaffold(
      appBar: AppBar(title: area == null ? null : Text(area.title)),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: IgnorePointer(
              ignoring: busy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                children: [
                  if (area == null)
                    ..._overview()
                  else
                    SettingsSection(
                      title: area == _SettingsArea.models
                          ? app.preset.name
                          : null,
                      children: _detail(area),
                    ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
