import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gal/gal.dart';
import 'package:panda_ccd/services/album_sync.dart';
import 'package:panda_ccd/services/library.dart';
import 'package:panda_ccd/services/system_gallery.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/ui/camera_page.dart';
import 'package:panda_ccd/ui/gallery_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native asset IDs, duplicate prevention, two-way deletion and legacy hash migration',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('相册联动验证'))),
      );
      final system = SystemGallery();
      Future<void> waitFor(Future<bool> Function() condition) async {
        for (var i = 0; i < 100; i++) {
          if (await condition()) return;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pump();
        }
        fail('Native album operation did not complete');
      }

      debugPrint('ALBUM_PERMISSION_READY');
      await waitFor(() async => await system.access() == GalleryAccess.full);
      final library = PhotoLibrary()
        ..root = await Directory.systemTemp.createTemp('panda-native-album-');
      final sync = AlbumSync(library, system);
      final bytes = await makeDemo();
      Future<PhotoEntry> create() =>
          library.save(bytes, 'g12', DateTime.now(), original: bytes);
      final first = await create();
      await sync.export(first);
      final id = (await library.systemIds(first)).single;
      expect(await system.state(id, photo: first), SystemPhotoState.present);
      final unrelated = await create();
      await library.linkSystem(unrelated, {id});
      await expectLater(sync.remove(unrelated, linked: true), throwsStateError);
      expect(await system.state(id), SystemPhotoState.present);
      await library.delete(unrelated);
      await sync.export(first);
      final allMatches = await system.findLegacyCopies([first]);
      expect(allMatches[first.path], {
        id,
      }, reason: 'Repeated export must not create duplicate system photos');
      await sync.remove(first, linked: true);
      expect(await system.state(id), SystemPhotoState.missing);
      expect(await File(first.path).exists(), isFalse);
      expect(
        await File(first.path.replaceAll('.png', '.original')).exists(),
        isFalse,
      );

      final second = await create();
      await sync.export(second);
      final secondId = (await library.systemIds(second)).single;
      final app = AppState()..library.root = library.root;
      await app.refresh();
      await tester.pumpWidget(MaterialApp(home: GalleryPage(state: app)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image).first);
      await tester.pumpAndSettle();
      expect(find.byType(PhotoPage), findsOneWidget);
      debugPrint('EXTERNAL_DELETE_READY_$secondId');
      await waitFor(() async => !await File(second.path).exists());
      await tester.pumpAndSettle();
      expect(find.byType(PhotoPage), findsNothing);
      expect(find.text('暂无照片'), findsOneWidget);
      expect(await File(second.path).exists(), isFalse);
      expect(
        await File(second.path.replaceAll('.png', '.original')).exists(),
        isFalse,
      );
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      app.dispose();

      final legacy = await create();
      await Gal.putImage(
        legacy.path,
      ); // Exact writer used in all previous APKs.
      final oldMatches = await system.findLegacyCopies([legacy]);
      expect(oldMatches[legacy.path], hasLength(1));
      final oldId = oldMatches[legacy.path]!.single;
      expect(await sync.linkLegacy(), 1);
      expect(await library.systemIds(legacy), {oldId});
      await sync.remove(legacy, linked: true);
      expect(await system.state(oldId), SystemPhotoState.missing);

      final changed = await create();
      await Gal.putImage(changed.path);
      final changedIds = (await system.findLegacyCopies([
        changed,
      ]))[changed.path]!;
      await File(changed.path).writeAsBytes([1, 2, 3]);
      expect(
        await system.findLegacyCopies([changed]),
        isEmpty,
        reason: 'Same filename but different content must never be linked',
      );
      await system.delete(changedIds);
      await library.root.delete(recursive: true);
    },
  );
}
