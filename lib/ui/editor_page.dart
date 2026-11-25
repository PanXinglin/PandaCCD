import 'design_system.dart';
import '../domain/live_capture.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../domain/photo_edit.dart';
import '../domain/face_region.dart';
import '../services/face_tracker.dart';
import 'dart:convert';
import '../domain/preset.dart';
import '../services/app_state.dart';
import '../services/filter_engine.dart';
import 'components.dart';
import 'preset_picker.dart';
import 'watermark_controls.dart';
import 'frame_ratio_picker.dart';
import '../domain/frame_ratio.dart';

class EditorPage extends StatefulWidget {
  final AppState state;
  final Uint8List bytes;
  final bool isDemo;
  final PhotoEdit? initialEdit;
  final String? initialPreset;
  final bool retainSource;
  final LiveSource? liveSource;
  final bool ownsLiveSource;
  const EditorPage({
    super.key,
    required this.state,
    required this.bytes,
    this.isDemo = false,
    this.initialEdit,
    this.initialPreset,
    this.retainSource = false,
    this.liveSource,
    this.ownsLiveSource = false,
  });
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  ui.Image? image;
  List<FaceRegion> faces = const [];
  String? error;
  int selected = 0, turns = 0;
  bool square = false, saving = false;
  double? frameAspect;
  late Map<String, double> values;
  late final Watermark stamp;
  late final DateTime date;
  LutImage? restoredLut;
  AppState get app => widget.state;
  @override
  void initState() {
    super.initState();
    final edit = widget.initialEdit;
    final id = edit?.recipe.presetId ?? widget.initialPreset;
    selected = id == null
        ? app.selected
        : presets.indexWhere((p) => p.id == id);
    if (selected < 0) selected = app.selected;
    values = {
      ...(edit?.recipe.values ??
          (id == null ? app.parameters : presets[selected].parameters)),
    };
    stamp = Watermark()..restore((edit?.stamp ?? app.watermark).toJson());
    date = edit?.date ?? DateTime.now();
    turns = edit?.turns ?? 0;
    square = edit?.square ?? false;
    frameAspect = edit?.frameAspect ?? (edit == null ? app.frameAspect : null);
    load();
  }

  Future<void> load() async {
    try {
      final hald = widget.initialEdit?.recipe.hald;
      if (hald != null) {
        final loaded = await LutImage.decode(base64Decode(hald));
        if (!mounted) {
          loaded.image.dispose();
          return;
        }
        restoredLut = loaded;
      }
      final decoded = await app.engine.decodePhoto(widget.bytes);
      if (!mounted) {
        decoded.dispose();
        return;
      }
      setState(() => image = decoded);
      final initial = widget.initialEdit;
      final found =
          initial != null &&
              initial.faces.isNotEmpty &&
              initial.faceGeometryVersion == FaceRegion.geometryVersion
          ? initial.faces
          : await FaceTracker.detect(decoded);
      if (mounted) setState(() => faces = found);
    } catch (e) {
      if (mounted) setState(() => error = '无法读取照片：$e');
    }
  }

  @override
  void dispose() {
    restoredLut?.image.dispose();
    image?.dispose();
    if (widget.ownsLiveSource) widget.liveSource?.dispose();
    super.dispose();
  }

  LutImage get lut =>
      restoredLut ??
      app.customLuts[presets[selected].id] ??
      app.engine.lut(presets[selected].id);
  void choose(int index) => setState(() {
    restoredLut?.image.dispose();
    restoredLut = null;
    selected = index;
    values = {
      ...(app.recipes[presets[index].id]?.values ?? presets[index].parameters),
    };
  });
  Future<void> save() async {
    if (image == null || saving) return;
    setState(() => saving = true);
    await guarded(context, () async {
      final model = presets[selected];
      final edit = PhotoEdit(
        Recipe(
          model.id,
          {...values},
          hald: restoredLut != null
              ? widget.initialEdit?.recipe.hald
              : app.recipes[model.id]?.hald,
        ),
        Watermark()..restore(stamp.toJson()),
        date,
        turns: turns,
        square: square,
        frameAspect: frameAspect,
        faces: faces,
      );
      final bytes = await app.engine.render(
        image!,
        edit.recipe.values,
        lut,
        edit.stamp,
        edit.date,
        model.stampLabel,
        turns: edit.turns,
        square: edit.square,
        frameAspect: edit.frameAspect,
        faces: edit.faces,
        trackFace: true,
      );
      final message = await app.commitPhoto(
        bytes,
        edit,
        original:
            app.keepOriginal || widget.retainSource || widget.liveSource != null
            ? widget.bytes
            : null,
        liveSource: widget.liveSource,
      );
      if (mounted) {
        if (message.isNotEmpty) toast(context, message);
        Navigator.pop(context);
      }
    });
    if (mounted) setState(() => saving = false);
  }

  Widget photo() {
    final source = image!;
    final crop = croppedFrameSize(
      Size(source.width.toDouble(), source.height.toDouble()),
      aspect: frameAspect,
      square: square,
    );
    final w = crop.width, h = crop.height;
    final output = Size(turns.isOdd ? h : w, turns.isOdd ? w : h);
    return LayoutBuilder(
      builder: (context, bounds) {
        final scale = math.min(
          bounds.maxWidth / output.width,
          bounds.maxHeight / output.height,
        );
        return Center(
          child: SizedBox(
            width: output.width * scale,
            height: output.height * scale,
            child: Stack(
              children: [
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RotatedBox(
                      quarterTurns: turns,
                      child: ClipRect(
                        child: SizedBox(
                          width: w,
                          height: h,
                          child: OverflowBox(
                            maxWidth: source.width.toDouble(),
                            maxHeight: source.height.toDouble(),
                            child: FilteredPhoto(
                              engine: app.engine,
                              image: source,
                              lut: lut,
                              values: values,
                              faces: faces,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: StampOverlay(
                    stamp: stamp,
                    date: date,
                    model: presets[selected].stampLabel,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> showModels() => PandaDesign.sheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: PresetPicker(
        selected: selected,
        onSelect: (index) {
          choose(index);
          Navigator.pop(context);
        },
      ),
    ),
  );

  Future<void> _parameterAction(String action) async {
    if (action == 'reset') {
      setState(() => values = presets[selected].parameters);
      return;
    }
    await guarded(context, () async {
      await app.applyRecipe(
        Recipe(
          presets[selected].id,
          values,
          hald: app.recipes[presets[selected].id]?.hald,
        ),
      );
      if (mounted) toast(context, '参数已保存为当前机型预设');
    });
  }

  Widget _toolPage(String name, List<Widget> children) => ListView(
    key: PageStorageKey('editor-$name'),
    padding: const EdgeInsets.only(top: 10, bottom: 16),
    children: children,
  );

  Widget tools({bool sidePanel = false}) {
    final model = presets[selected];
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(
          top: sidePanel
              ? BorderSide.none
              : const BorderSide(color: PandaDesign.line),
          left: sidePanel
              ? const BorderSide(color: PandaDesign.line)
              : BorderSide.none,
        ),
      ),
      child: Material(
        color: PandaDesign.paper,
        child: Column(
          children: [
            const TabBar(
              labelPadding: EdgeInsets.symmetric(horizontal: 2),
              labelColor: ink,
              unselectedLabelColor: PandaDesign.muted,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: PandaDesign.line,
              tabs: [
                Tab(text: '风格'),
                Tab(text: '细调'),
                Tab(text: '构图'),
                Tab(text: '水印'),
              ],
            ),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _toolPage('style', [
                    ListTile(
                      leading: const Icon(Icons.camera_alt_outlined),
                      title: Text(model.name),
                      subtitle: Text(model.subtitle),
                      trailing: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '机型库',
                            style: TextStyle(color: PandaDesign.muted),
                          ),
                          Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                      onTap: showModels,
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 10, 20, 8),
                      child: Text(
                        '快速切换',
                        style: TextStyle(
                          color: PandaDesign.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    PresetStrip(selected: selected, onSelect: choose),
                  ]),
                  _toolPage('adjust', [
                    ListTile(
                      title: const Text('照片参数'),
                      trailing: PopupMenuButton<String>(
                        tooltip: '参数操作',
                        onSelected: _parameterAction,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'reset', child: Text('重置参数')),
                          PopupMenuItem(
                            value: 'save',
                            child: Text('保存为我的机型参数'),
                          ),
                        ],
                      ),
                    ),
                    ParameterPanel(
                      values: values,
                      onChanged: (key, value) => setState(() {
                        values = {
                          ...values,
                          if (key == 'faceSlim' &&
                              value > 0 &&
                              (values['beauty'] ?? 0) == 0)
                            'beauty': .55,
                          key: value,
                        };
                      }),
                    ),
                  ]),
                  _toolPage('frame', [
                    ListTile(
                      leading: const Icon(Icons.aspect_ratio),
                      title: const Text('画幅比例'),
                      trailing: Text(frameRatioLabel(square ? 1 : frameAspect)),
                      onTap: () => showFrameRatioPicker(
                        context,
                        square ? 1 : frameAspect,
                        (value) => setState(() {
                          square = false;
                          frameAspect = value;
                        }),
                      ),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.rotate_right),
                      title: const Text('旋转 90°'),
                      trailing: Text('${turns * 90}°'),
                      onTap: () => setState(() => turns = (turns + 1) % 4),
                    ),
                  ]),
                  _toolPage('watermark', [
                    SwitchListTile(
                      title: const Text('日期戳'),
                      value: stamp.date,
                      onChanged: (value) => setState(() => stamp.date = value),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('文字水印'),
                      value: stamp.model,
                      onChanged: (value) => setState(() => stamp.model = value),
                    ),
                    if (stamp.date || stamp.model)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: WatermarkChoices(
                          stamp: stamp,
                          contentPadding: EdgeInsets.zero,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.isDemo ? '编辑示例照片' : '编辑照片'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: image == null || saving ? null : save,
              child: Text(saving ? '正在冲洗…' : '保存成片'),
            ),
          ),
        ],
      ),
      body: IgnorePointer(
        ignoring: saving,
        child: SafeArea(
          child: image == null
              ? Center(
                  child: error == null
                      ? const CircularProgressIndicator()
                      : Text(error!),
                )
              : DefaultTabController(
                  length: 4,
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      if (bounds.maxWidth > 700 ||
                          bounds.maxWidth / bounds.maxHeight > 1.15) {
                        return Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: photo(),
                              ),
                            ),
                            SizedBox(
                              width: (bounds.maxWidth * .42).clamp(
                                240.0,
                                360.0,
                              ),
                              child: tools(sidePanel: true),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                              child: photo(),
                            ),
                          ),
                          Expanded(flex: 3, child: tools()),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ),
    ),
  );
}
