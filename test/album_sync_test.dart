import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/album_sync.dart';
import 'package:panda_ccd/services/library.dart';
import 'package:panda_ccd/services/system_gallery.dart';

class _System extends SystemGallery {
  GalleryAccess permission = GalleryAccess.full;
  final states = <String, SystemPhotoState>{};
  final deleted = <String>{};
  bool cancel = false;
  int saves = 0;
  int deleteCalls = 0;
  Set<String>? deleteOnly;
  Completer<void>? hold;
  final started = Completer<void>();
  Map<String, Set<String>> legacy = {};
  @override
  Future<GalleryAccess> access({bool request = false}) async => permission;
  @override
  Future<SystemPhotoState> state(String id, {PhotoEntry? photo}) async =>
      permission == GalleryAccess.full
      ? states[id] ?? SystemPhotoState.unknown
      : SystemPhotoState.unknown;
  @override
  Future<String> save(PhotoEntry photo) async {
    saves++;
    if (!started.isCompleted) started.complete();
    await hold?.future;
    states['asset-$saves'] = SystemPhotoState.present;
    return 'asset-$saves';
  }

  @override
  Future<Set<String>> delete(Set<String> ids) async {
    deleteCalls++;
    if (cancel) return {};
    ids = ids.intersection(deleteOnly ?? ids);
    deleted.addAll(ids);
    for (final id in ids) {
      states[id] = SystemPhotoState.missing;
    }
    return ids;
  }

  @override
  Future<Map<String, Set<String>>> findLegacyCopies(
    List<PhotoEntry> photos,
  ) async => legacy;
}

void main() {
  late PhotoLibrary library;
  late _System system;
  late AlbumSync sync;
  late PhotoEntry photo;
  setUp(() async {
    library = PhotoLibrary()
      ..root = await Directory.systemTemp.createTemp('panda-sync-');
    system = _System();
    sync = AlbumSync(library, system);
    photo = await library.save(
      Uint8List.fromList([1, 2]),
      'g12',
      DateTime(2026),
      original: Uint8List.fromList([3]),
    );
  });
  tearDown(() async => library.root.delete(recursive: true));

  test(
    'Export persists system ID across reload and repeated export creates no copy',
    () async {
      await sync.export(photo);
      final reloaded = PhotoLibrary()..root = library.root;
      expect(await reloaded.systemIds(photo), {'asset-1'});
      await AlbumSync(reloaded, system).export(photo);
      expect(system.saves, 1);
    },
  );
  test(
    'App deletion deletes the linked system asset and local original',
    () async {
      await sync.export(photo);
      await sync.remove(photo, linked: true);
      expect(system.deleted, {'asset-1'});
      expect(await library.list(), isEmpty);
      expect(
        await File(photo.path.replaceAll('.png', '.original')).exists(),
        isFalse,
      );
      expect(await library.systemIds(photo), isEmpty);
    },
  );
  test(
    'Cancelled system confirmation retains photo and source, then retry succeeds',
    () async {
      await sync.export(photo);
      system.cancel = true;
      await expectLater(sync.remove(photo, linked: true), throwsStateError);
      expect(await File(photo.path).exists(), isTrue);
      expect(
        await File(photo.path.replaceAll('.png', '.original')).exists(),
        isTrue,
      );
      system.cancel = false;
      await sync.remove(photo, linked: true);
      expect(await library.list(), isEmpty);
    },
  );
  test(
    'Confirmed external deletion removes local entry; unlinked older photo survives',
    () async {
      await sync.export(photo);
      final older = await library.save(Uint8List(1), 'g12', DateTime(2025));
      system.states['asset-1'] = SystemPhotoState.missing;
      expect(await sync.reconcile(), 1);
      expect((await library.list()).single.path, older.path);
    },
  );
  test(
    'Limited, revoked and unknown reads never imply external deletion',
    () async {
      await sync.export(photo);
      system.states['asset-1'] = SystemPhotoState.missing;
      for (final permission in [GalleryAccess.limited, GalleryAccess.denied]) {
        system.permission = permission;
        expect(await sync.reconcile(), 0);
        await expectLater(sync.remove(photo, linked: true), throwsStateError);
        expect(await File(photo.path).exists(), isTrue);
      }
      system.permission = GalleryAccess.full;
      system.states['asset-1'] = SystemPhotoState.unknown;
      expect(await sync.reconcile(), 0);
      await sync.export(photo);
      expect(system.saves, 1);
    },
  );
  test(
    'Multiple known copies require all missing; delete targets only linked IDs',
    () async {
      await library.linkSystem(photo, {'one', 'two'});
      system.states.addAll({
        'one': SystemPhotoState.missing,
        'two': SystemPhotoState.present,
        'unrelated': SystemPhotoState.present,
      });
      expect(await sync.reconcile(), 0);
      await sync.remove(photo, linked: true);
      expect(system.deleted, {'two'});
      expect(system.states['unrelated'], SystemPhotoState.present);
    },
  );
  test('Switching deletion linkage off preserves the system photo', () async {
    await sync.export(photo);
    await sync.remove(photo, linked: false);
    expect(system.deleted, isEmpty);
    expect(system.states['asset-1'], SystemPhotoState.present);
    expect(await library.list(), isEmpty);
  });
  test(
    'Legacy linking adds verified IDs, but no match never erases local data',
    () async {
      expect(await sync.linkLegacy(), 0);
      expect(await File(photo.path).exists(), isTrue);
      system.legacy = {
        photo.path: {'verified'},
      };
      expect(await sync.linkLegacy(), 1);
      expect(await library.systemIds(photo), {'verified'});
    },
  );
  test(
    'Reconciliation waits for an in-flight export and link commit',
    () async {
      system.hold = Completer<void>();
      final saving = sync.export(photo);
      final checking = sync.reconcile();
      await system.started.future;
      expect(system.saves, 1);
      system.hold!.complete();
      await saving;
      expect(await checking, 0);
      expect(await File(photo.path).exists(), isTrue);
    },
  );
  Future<PhotoEntry> another(int day) => library.save(
    Uint8List.fromList([day]),
    'g12',
    DateTime(2026, 1, day),
    original: Uint8List.fromList([day + 1]),
  );

  test(
    'Batch delete uses one system confirmation for multiple linked photos',
    () async {
      final second = await another(2), third = await another(3);
      for (final p in [photo, second, third]) {
        await sync.export(p);
      }
      final result = await sync.removeMany([
        photo,
        second,
        third,
        photo,
      ], linked: true);
      expect(system.deleteCalls, 1);
      expect(system.deleted, {'asset-1', 'asset-2', 'asset-3'});
      expect(result.deleted, {photo.path, second.path, third.path});
      expect(await library.list(), isEmpty);
    },
  );
  test(
    'Cancelling a batch also preserves local-only photos mixed into it',
    () async {
      final local = await another(2);
      await sync.export(photo);
      system.cancel = true;
      final result = await sync.removeMany([photo, local], linked: true);
      expect(result.deleted, isEmpty);
      expect(result.kept, {photo.path, local.path});
      expect(await File(local.path).exists(), isTrue);
      expect(
        await File(photo.path.replaceAll('.png', '.original')).exists(),
        isTrue,
      );
    },
  );
  test(
    'Partial system batch failure retains only unconfirmed local entries',
    () async {
      final second = await another(2);
      await sync.export(photo);
      await sync.export(second);
      system.deleteOnly = {'asset-1'};
      final result = await sync.removeMany([photo, second], linked: true);
      expect(result.deleted, {photo.path});
      expect(result.kept, {second.path});
      expect(await File(second.path).exists(), isTrue);
    },
  );
  test(
    'Unknown batch assets are retained and unrelated system IDs are untouched',
    () async {
      final second = await another(2);
      await sync.export(photo);
      await sync.export(second);
      system.states['asset-2'] = SystemPhotoState.unknown;
      system.states['unrelated'] = SystemPhotoState.present;
      final result = await sync.removeMany([photo, second], linked: true);
      expect(result.deleted, {photo.path});
      expect(result.kept, {second.path});
      expect(system.deleted, {'asset-1'});
    },
  );
  test(
    'Local-only batch with linkage disabled never calls the system deleter',
    () async {
      final second = await another(2);
      await sync.export(photo);
      final result = await sync.removeMany([photo, second], linked: false);
      expect(result.deleted.length, 2);
      expect(system.deleteCalls, 0);
      expect(system.states['asset-1'], SystemPhotoState.present);
    },
  );
}
