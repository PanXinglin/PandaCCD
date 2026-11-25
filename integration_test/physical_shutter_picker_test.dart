import 'dart:ui' as ui;
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/camera_session.dart';
import 'package:panda_ccd/services/shutter_sound.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/settings_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Cancel real picker then shoot using both physical volume keys and a custom frame',
    (tester) async {
      final app = AppState();
      await app.init();
      app.directSave = true;
      app.frameAspect = 5 / 4;
      app.volumeShutter = true;
      app.shutterSound = true;
      final camera = CameraSession();
      final sound = ShutterSound();
      await tester.pumpWidget(
        MaterialApp(
          home: CameraPage(state: app, session: camera, sound: sound),
        ),
      );
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 100 && !condition(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pump();
        }
        expect(condition(), isTrue);
      }

      bool ready() =>
          camera.controller?.value.isInitialized == true &&
          !camera.busy &&
          tester
                  .widget<GestureDetector>(
                    find.byKey(const ValueKey('ccd-shutter')),
                  )
                  .onTap !=
              null;
      await waitFor(ready);
      await sound.prepare();
      expect(
        sound.isReady,
        isTrue,
        reason: 'Native audio asset must be preloaded',
      );
      for (var cancel = 0; cancel < 2; cancel++) {
        await tester.tap(find.byTooltip('导入照片'));
        await tester.pump();
        debugPrint('PICKER_CANCEL_READY_$cancel');
        await waitFor(
          () =>
              camera.controller?.value.isInitialized == true &&
              camera.enabled &&
              !camera.busy,
        );
        await waitFor(ready);
        expect(find.byType(CameraPreview), findsOneWidget);
      }
      var photos = app.photos.length;
      debugPrint('VOLUME_UP_READY');
      await waitFor(() => app.photos.length == photos + 1);
      await tester.pumpAndSettle();
      final codec = await ui.instantiateImageCodec(
        await File(app.photos.first.path).readAsBytes(),
      );
      final image = (await codec.getNextFrame()).image;
      final ratio = image.width > image.height
          ? image.width / image.height
          : image.height / image.width;
      expect(ratio, closeTo(5 / 4, .005));
      image.dispose();
      codec.dispose();
      expect(
        (await app.library.readEdit(app.photos.first))!.frameAspect,
        5 / 4,
      );
      photos = app.photos.length;
      debugPrint('VOLUME_DOWN_READY');
      await waitFor(() => app.photos.length == photos + 1);
      await tester.pumpAndSettle();
      photos = app.photos.length;
      debugPrint('VOLUME_LONG_READY');
      await waitFor(() => app.photos.length == photos + 1);
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        app.photos.length,
        photos + 1,
        reason: 'Holding volume must not burst',
      );
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      photos = app.photos.length;
      debugPrint('VOLUME_SETTINGS_READY');
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();
      expect(app.photos.length, photos);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
