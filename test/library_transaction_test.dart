import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/photo_edit.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/services/library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Failed edit write leaves no uncommitted photo resources', () async {
    final root = await Directory.systemTemp.createTemp(
      'audit-library-failure-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final library = PhotoLibrary()..root = root;
    final existingBytes = Uint8List.fromList([1, 2, 3]);
    final existing = await library.save(existingBytes, 'g12', DateTime(2026));
    final baseline = (await root.list().map((item) => item.path).toList())
      ..sort();

    final date = DateTime(2026, 11, 9, 12);
    final name = '${date.microsecondsSinceEpoch}_jade';
    // Block the final edit path with an unrelated directory.
    // This directory is only the injected obstacle, not an application resource.
    final obstacle = await Directory('${root.path}/$name.edit.json').create();
    final edit = PhotoEdit(
      Recipe('jade', parameterDefaults),
      Watermark(),
      date,
    );
    await expectLater(
      library.save(
        Uint8List.fromList([4, 5, 6]),
        'jade',
        date,
        original: Uint8List.fromList([7, 8, 9]),
        edit: edit,
      ),
      throwsA(isA<FileSystemException>()),
    );
    await obstacle.delete();

    // A failed submission must not expose a new work or alter an existing work.
    expect((await library.list()).map((photo) => photo.path), [existing.path]);
    expect(await File(existing.path).readAsBytes(), existingBytes);
    final afterFailure = (await root.list().map((item) => item.path).toList())
      ..sort();
    expect(
      afterFailure,
      baseline,
      reason: 'Failed local commit must roll back all newly written resources',
    );
  });

  test('A Live copy failure rolls back all staged photo resources', () async {
    final root = await Directory.systemTemp.createTemp('panda-save-copy-');
    addTearDown(() => root.delete(recursive: true));
    final library = PhotoLibrary()..root = root;
    await expectLater(
      library.save(
        Uint8List(1),
        'g12',
        DateTime(2026),
        original: Uint8List(1),
        liveDirectory: Directory('${root.path}/missing-live'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await root.list().toList(), isEmpty);
  });

  test(
    'Startup rolls back a moved sidecar but preserves a committed cover',
    () async {
      final root = await Directory.systemTemp.createTemp('panda-save-startup-');
      addTearDown(() => root.delete(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => root.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final library = PhotoLibrary();
      await library.init();
      final committed = await library.save(
        Uint8List.fromList([1]),
        'g12',
        DateTime(2026),
        original: Uint8List.fromList([2]),
      );
      final committedName = committed.path.replaceFirst(RegExp(r'\.png$'), '');
      final interruptedName =
          '${library.root.path}/${DateTime(2026, 1, 2).microsecondsSinceEpoch}_g12';
      for (final name in [committedName, interruptedName]) {
        final staging = await Directory('$name.save').create();
        await File('${staging.path}/ready').writeAsString('["original"]');
      }
      final moved = await File('$interruptedName.original').writeAsBytes([3]);
      await PhotoLibrary().init();
      expect(await moved.exists(), isFalse);
      expect(await File('$committedName.original').readAsBytes(), [2]);
      expect(await File(committed.path).readAsBytes(), [1]);
      expect(
        await library.root.list().any((file) => file.path.endsWith('.save')),
        isFalse,
      );
    },
  );
}
