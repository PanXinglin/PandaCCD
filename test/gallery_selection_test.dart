import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/ui/gallery_page.dart';
import 'package:panda_ccd/ui/design_system.dart';

class _EmptyState extends AppState {
  @override
  Future<void> refresh({bool syncSystem = false}) async {}
}

void main() {
  testWidgets(
    'Long press, select all, cancel, and confirm batch removal in the gallery',
    (tester) async {
      final app = AppState()..syncAlbumDeletes = false;
      await tester.runAsync(() async {
        app.library.root = await Directory.systemTemp.createTemp(
          'panda-gallery-select-',
        );
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        for (var i = 1; i <= 3; i++) {
          await app.library.save(
            png,
            'g12',
            DateTime(2026, 10, i),
            original: png,
          );
        }
        await app.refresh();
      });
      final paths = app.photos.map((p) => p.path).toList();
      await tester.pumpWidget(
        MaterialApp(
          theme: PandaDesign.theme(),
          home: GalleryPage(state: app),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(ValueKey('gallery-photo-${paths[0]}')));
      await tester.pump();
      expect(find.text('已选 1 张'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('gallery-photo-${paths[1]}')));
      await tester.pump();
      expect(find.text('已选 2 张'), findsOneWidget);
      expect(find.byType(PhotoPage), findsNothing);
      await tester.tap(find.text('全选'));
      await tester.pump();
      expect(find.text('已选 3 张'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gallery-delete-selected')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('删除这 3 张照片？'), findsOneWidget);
      await tester.tap(find.text('保留'));
      await tester.pumpAndSettle();
      expect(app.photos.length, 3);
      await tester.tap(find.byKey(const ValueKey('gallery-delete-selected')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('删除 3 张'));
      for (var i = 0; i < 100 && app.photos.isNotEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(app.photos, isEmpty);
      expect(find.text('暂无照片'), findsOneWidget);
      for (final path in paths) {
        expect(await tester.runAsync(() => File(path).exists()), isFalse);
        expect(
          await tester.runAsync(
            () => File(path.replaceAll('.png', '.original')).exists(),
          ),
          isFalse,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => app.library.root.delete(recursive: true));
      app.dispose();
    },
  );
  testWidgets('Swipe from the selected work and delete the visible page', (
    tester,
  ) async {
    final app = AppState()..syncAlbumDeletes = false;
    await tester.runAsync(() async {
      app.library.root = await Directory.systemTemp.createTemp(
        'panda-gallery-page-',
      );
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      for (var i = 1; i <= 3; i++) {
        await app.library.save(png, 'g12', DateTime(2026, 10, i));
      }
      await app.refresh();
    });
    final paths = app.photos.map((p) => p.path).toList();
    await tester.pumpWidget(MaterialApp(home: GalleryPage(state: app)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('gallery-photo-${paths[1]}')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    for (final label in ['分享照片', '再次编辑', '删除照片']) {
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('存入相册'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(650, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byTooltip('删除照片'));
    for (var i = 0; i < 50 && find.text('删除这张照片？').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅从应用内删除'));
    for (var i = 0; i < 50 && app.photos.length == 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(app.photos.map((p) => p.path), [paths[0], paths[2]]);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => app.library.root.delete(recursive: true));
    app.dispose();
  });

  testWidgets(
    'Gallery remains usable on short and wide windows with large text',
    (tester) async {
      final app = _EmptyState();
      for (final size in [
        const Size(320, 480),
        const Size(650, 320),
        const Size(980, 700),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            theme: PandaDesign.theme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.6),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: GalleryPage(state: app),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$size must not overflow',
        );
        expect(find.text('授权并关联'), findsNothing);
        expect(find.text('关联旧照片'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      app.dispose();
    },
  );
}
