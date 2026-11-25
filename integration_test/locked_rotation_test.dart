import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:panda_ccd/ui/camera_page.dart';

// Host supplies gravity samples with emulator sensor commands, while OS
// accelerometer_rotation remains 0. See docs/CAMERA_ADAPTATION.md.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Locked portrait → physical left/right grip → landscape photo', (
    tester,
  ) async {
    final app = AppState();
    await app.init();
    app.directSave = false; // Exercise the optional edit-first flow.
    app.select(0);
    final grip = CameraOrientation();
    await tester.pumpWidget(
      MaterialApp(
        home: CameraPage(state: app, orientation: grip),
      ),
    );
    Future<void> waitFor(bool Function() predicate) async {
      for (var i = 0; i < 100 && !predicate(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
      }
      expect(predicate(), isTrue);
    }

    bool landscape() {
      final size = MediaQuery.sizeOf(tester.element(find.byType(CameraPage)));
      return size.width > size.height;
    }

    await waitFor(() => find.byType(CameraPreview).evaluate().isNotEmpty);
    debugPrint('ROTATION_READY_LEFT');
    await waitFor(
      () => grip.orientation == DeviceOrientation.landscapeLeft && landscape(),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugPrint('ROTATION_READY_RIGHT');
    await waitFor(
      () => grip.orientation == DeviceOrientation.landscapeRight && landscape(),
    );
    await tester.pumpAndSettle();
    final before = app.photos.length;
    await tester.tap(find.byKey(const ValueKey('ccd-shutter')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('编辑照片'), findsOneWidget);
    await tester.tap(find.text('保存成片'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(app.photos.length, before + 1);
    final codec = await ui.instantiateImageCodec(
      await File(app.photos.first.path).readAsBytes(),
    );
    final photo = (await codec.getNextFrame()).image;
    expect(photo.width, greaterThan(photo.height));
    debugPrint(
      'ROTATION_PHOTO ${photo.width}x${photo.height} ${app.photos.first.path}',
    );
    photo.dispose();
    codec.dispose();
    debugPrint('ROTATION_READY_PORTRAIT');
    await waitFor(
      () => grip.orientation == DeviceOrientation.portraitUp && !landscape(),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
