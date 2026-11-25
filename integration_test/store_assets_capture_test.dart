// Material production only: real app widgets and GLSL, AI-labelled demo input.
// Never uses a physical camera, user's album or user's saved settings.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/camera_session.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/domain/photo_edit.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/gallery_page.dart';
import 'package:panda_ccd/ui/settings_page.dart';
import 'package:panda_ccd/ui/editor_page.dart';
import 'package:panda_ccd/ui/design_system.dart';
import '../tool/store_capture/generated_data.dart';

class _StoreState extends AppState {
  @override
  Future<void> persist() async {}
  @override
  Future<void> refresh({bool syncSystem = false}) async {}
}

class _DemoController extends CameraController {
  final ui.Image image;
  _DemoController(this.image)
    : super(
        const CameraDescription(
          name: 'demo-input',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        ResolutionPreset.high,
      ) {
    value = value.copyWith(
      isInitialized: true,
      previewSize: Size(image.height.toDouble(), image.width.toDouble()),
    );
  }
  @override
  Widget buildPreview() => RawImage(image: image, fit: BoxFit.cover);
}

class _DemoSession extends CameraSession {
  _DemoSession(ui.Image image) {
    controller = _DemoController(image);
    minZoom = 1;
    maxZoom = 4;
    flash = FlashMode.always;
  }
  @override
  bool get usesPreviewFaceSnapshots => true;
  @override
  Future<void> start() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> setModes({
    required bool live,
    required bool analysis,
    bool sound = true,
  }) async {
    liveRequested = live;
    analysisRequested = analysis;
    liveSoundRequested = sound;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Render App Store materials from shipping widgets', (
    tester,
  ) async {
    final app = _StoreState();
    await app.engine.init();
    final root = Directory(
      '${(await getTemporaryDirectory()).path}/panda-store-capture',
    );
    await root.create(recursive: true);
    app.library.root = await Directory('${root.path}/library').create();
    app.volumeShutter = false;
    app.shutterSound = false;
    app.syncAlbumDeletes = false;
    app.watermark.model = false;
    final cafeBytes = base64Decode(storeCafe),
        portraitBytes = base64Decode(storePortrait);
    final cafe = await app.engine.decodePhoto(cafeBytes, maxEdge: 1800);
    final portrait = await app.engine.decodePhoto(portraitBytes, maxEdge: 1800);
    for (var i = 0; i < 9; i++) {
      final p = presets[i % presets.length];
      final face = i % 3 == 2;
      final date = DateTime(2026, 11, 12, 14, 0, i);
      final bytes = await app.engine.render(
        face ? portrait : cafe,
        p.parameters,
        app.engine.lut(p.id),
        app.watermark,
        date,
        p.stampLabel,
      );
      app.photos.add(
        await app.library.save(
          bytes,
          p.id,
          date,
          original: face ? portraitBytes : cafeBytes,
          edit: PhotoEdit(Recipe(p.id, p.parameters), app.watermark, date),
        ),
      );
    }
    for (final layout in [
      ('phone', const Size(430, 932), 3.0),
      ('ipad', const Size(1032, 1376), 2.0),
    ]) {
      final key = GlobalKey();
      Future<void> mount(Widget home) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            theme: PandaDesign.theme(),
            builder: (context, child) => OverflowBox(
              minWidth: layout.$2.width,
              maxWidth: layout.$2.width,
              minHeight: layout.$2.height,
              maxHeight: layout.$2.height,
              child: SizedBox.fromSize(
                size: layout.$2,
                child: RepaintBoundary(
                  key: key,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: layout.$2,
                      padding: const EdgeInsets.only(top: 14, bottom: 18),
                      viewPadding: const EdgeInsets.only(top: 14, bottom: 18),
                      devicePixelRatio: layout.$3,
                      textScaler: TextScaler.noScaling,
                    ),
                    child: child!,
                  ),
                ),
              ),
            ),
            home: KeyedSubtree(key: UniqueKey(), child: home),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(seconds: 2));
        await tester.pump();
      }

      Future<void> snap(String name) async {
        await tester.pump(const Duration(milliseconds: 350));
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: layout.$3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${root.path}/${layout.$1}-$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
        debugPrint('STORE_SAVED ${layout.$1}-$name');
        expect(tester.takeException(), isNull);
      }

      app.selected = 0;
      app.beautyEnabled = false;
      app.frameAspect = 16 / 9;
      await mount(
        Theme(
          data: PandaDesign.cameraTheme,
          child: CameraPage(
            state: app,
            session: _DemoSession(cafe),
            orientation: CameraOrientation.disabled(),
          ),
        ),
      );
      await snap('01-camera');
      tester
          .widget<InkWell>(
            find
                .descendant(
                  of: find.byTooltip('选择机型'),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .onTap!();
      await tester.pumpAndSettle();
      await snap('02-styles');
      app.beautyEnabled = true;
      await mount(
        Theme(
          data: PandaDesign.cameraTheme,
          child: CameraPage(
            state: app,
            session: _DemoSession(portrait),
            orientation: CameraOrientation.disabled(),
          ),
        ),
      );
      tester
          .widgetList<IconButton>(find.byType(IconButton))
          .singleWhere((button) => button.tooltip == '美颜')
          .onPressed!();
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();
      tester
          .widget<TextButton>(
            find
                .ancestor(
                  of: find.text('磨皮').last,
                  matching: find.byType(TextButton),
                )
                .first,
          )
          .onPressed!();
      await snap('03-beauty');
      app.beautyEnabled = false;
      await mount(
        EditorPage(state: app, bytes: cafeBytes, initialPreset: 'g12'),
      );
      DefaultTabController.of(tester.element(find.byType(TabBar))).animateTo(3);
      await tester.pumpAndSettle();
      await snap('04-editor');
      await mount(GalleryPage(state: app));
      await snap('05-album');
      await mount(SettingsPage(state: app));
      await snap('06-settings');
    }
    await tester.pumpWidget(const SizedBox());
    debugPrint('STORE_CAPTURE_READY ${root.path}');
    // Host copies the material directory while the test app still exists.
    for (var i = 0; i < 90; i++) {
      if (await File('${root.path}/copied').exists()) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    cafe.dispose();
    portrait.dispose();
    app.dispose();
  }, timeout: const Timeout(Duration(minutes: 8)));
}
