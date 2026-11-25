import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/album_sync.dart';
import 'package:panda_ccd/services/library.dart';
import 'package:panda_ccd/services/system_gallery.dart';

class _PendingGallery extends SystemGallery {
  GalleryAccess permission = GalleryAccess.full;
  bool failBeforeCreate = false;
  int saveCalls = 0;
  int deleteCalls = 0;
  bool cancelDelete = false;
  String? recoveredId;
  final assets = <String>{};

  @override
  Future<GalleryAccess> access({bool request = false}) async => permission;

  @override
  Future<String> save(PhotoEntry photo) async {
    saveCalls++;
    if (failBeforeCreate) {
      failBeforeCreate = false;
      throw SystemGalleryNotCreated(
        'Injected validation failure before any asset creation',
      );
    }
    assets.add('asset-1');
    return 'asset-1';
  }

  @override
  Future<SystemPhotoState> state(String id, {PhotoEntry? photo}) async =>
      permission != GalleryAccess.full
      ? SystemPhotoState.unknown
      : assets.contains(id)
      ? SystemPhotoState.present
      : SystemPhotoState.missing;

  @override
  Future<String?> findExport(PhotoEntry photo) async =>
      permission == GalleryAccess.full ? recoveredId : null;

  @override
  Future<Set<String>> delete(Set<String> ids) async {
    deleteCalls++;
    if (cancelDelete || permission != GalleryAccess.full) return <String>{};
    final removed = assets.intersection(ids);
    assets.removeAll(removed);
    return removed;
  }
}

Future<PhotoLibrary> _library() async {
  final root = await Directory.systemTemp.createTemp('audit-album-pending-');
  addTearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  return PhotoLibrary()..root = root;
}

Future<PhotoEntry> _photo(PhotoLibrary library) => library.save(
  Uint8List.fromList([1, 2, 3]),
  'g12',
  DateTime(2026, 11, 9),
  original: Uint8List.fromList([4, 5, 6]),
);

void main() {
  test('R01: known pre-create failure can recover across instances', () async {
    final library = await _library();
    final photo = await _photo(library);
    final gallery = _PendingGallery()..failBeforeCreate = true;
    await expectLater(
      AlbumSync(library, gallery).export(photo),
      throwsA(isA<StateError>()),
    );
    expect(gallery.assets, isEmpty);
    expect(gallery.saveCalls, 1);
    expect(await library.albumExport(photo), isNull);
    expect(await library.canRetryAlbumExport(photo), isTrue);
    expect(await File(photo.path).exists(), isTrue);

    // The injected fault has ended. Full read/write access is available.
    gallery.permission = GalleryAccess.full;
    final reopened = PhotoLibrary()..root = library.root;
    Object? retryError;
    try {
      await AlbumSync(reopened, gallery).export(photo);
    } catch (error) {
      retryError = error;
    }
    expect(
      {
        'retrySucceeded': retryError == null,
        'saveCalls': gallery.saveCalls,
        'assets': gallery.assets,
        'linkedIds': await reopened.systemIds(photo),
        'receiptCleared': await reopened.albumExport(photo) == null,
        'retryCleared': !await reopened.canRetryAlbumExport(photo),
      },
      {
        'retrySucceeded': true,
        'saveCalls': 2,
        'assets': {'asset-1'},
        'linkedIds': {'asset-1'},
        'receiptCleared': true,
        'retryCleared': true,
      },
      reason:
          'Only one asset may be created after recovery. The first call '
          'failed before creating anything. Retry error: $retryError. '
          'This proves a host API state-classification gap, not an OS failure.',
    );
  });

  test('R03: pending single linked deletion preserves local recovery', () async {
    final library = await _library();
    final photo = await _photo(library);
    // Model interruption after system creation but before recording its ID.
    await library.recordAlbumExport(photo, '');
    final gallery = _PendingGallery()
      ..permission = GalleryAccess.limited
      ..assets.add('asset-1');
    final reopened = PhotoLibrary()..root = library.root;
    Object? deletionError;
    try {
      await AlbumSync(reopened, gallery).remove(photo, linked: true);
    } catch (error) {
      deletionError = error;
    }
    expect(
      {
        'pendingReported': deletionError is AlbumSyncException,
        'coverRetained': await File(photo.path).exists(),
        'originalRetained': await File(
          photo.path.replaceAll('.png', '.original'),
        ).exists(),
        'intentRetained': await reopened.albumExport(photo) == '',
        'assets': gallery.assets,
        'deleteCalls': gallery.deleteCalls,
      },
      {
        'pendingReported': true,
        'coverRetained': true,
        'originalRetained': true,
        'intentRetained': true,
        'assets': {'asset-1'},
        'deleteCalls': 0,
      },
      reason:
          'Unknown pending export must not be treated as never exported. '
          'Single linked deletion should report pending and preserve recovery. '
          'Observed error: $deletionError. OS gallery is a substitute.',
    );
  });

  test('Recovered ID survives a cancelled deletion and is reused', () async {
    final library = await _library();
    final photo = await _photo(library);
    await library.recordAlbumExport(photo, '');
    final gallery = _PendingGallery()
      ..recoveredId = 'asset-1'
      ..cancelDelete = true
      ..assets.addAll({'asset-1', 'unrelated'});
    final sync = AlbumSync(library, gallery);
    await expectLater(sync.remove(photo, linked: true), throwsStateError);
    expect(await File(photo.path).exists(), isTrue);
    expect(await library.systemIds(photo), {'asset-1'});
    expect(gallery.assets, {'asset-1', 'unrelated'});

    gallery.cancelDelete = false;
    await AlbumSync(library, gallery).remove(photo, linked: true);
    expect(gallery.assets, {'unrelated'});
    expect(gallery.saveCalls, 0);
    expect(await File(photo.path).exists(), isFalse);
  });

  test(
    'A missing export file fails before invoking the system writer',
    () async {
      final library = await _library();
      final photo = await _photo(library);
      await File(photo.path).delete();
      await expectLater(
        AlbumSync(library, SystemGallery()).export(photo),
        throwsA(isA<SystemGalleryNotCreated>()),
      );
      expect(await library.albumExport(photo), isNull);
    },
  );

  test(
    'R03: pending batch linked deletion returns kept and preserves intent',
    () async {
      final library = await _library();
      final photo = await _photo(library);
      await library.recordAlbumExport(photo, '');
      final gallery = _PendingGallery()
        ..permission = GalleryAccess.limited
        ..assets.add('asset-1');
      final reopened = PhotoLibrary()..root = library.root;
      final result = await AlbumSync(
        reopened,
        gallery,
      ).removeMany([photo], linked: true);
      expect(
        {
          'deleted': result.deleted,
          'kept': result.kept,
          'coverRetained': await File(photo.path).exists(),
          'originalRetained': await File(
            photo.path.replaceAll('.png', '.original'),
          ).exists(),
          'intentRetained': await reopened.albumExport(photo) == '',
          'assets': gallery.assets,
          'deleteCalls': gallery.deleteCalls,
        },
        {
          'deleted': <String>{},
          'kept': {photo.path},
          'coverRetained': true,
          'originalRetained': true,
          'intentRetained': true,
          'assets': {'asset-1'},
          'deleteCalls': 0,
        },
        reason:
            'Batch kept is the explicit incomplete outcome for a pending '
            'export with limited permission. OS gallery is a substitute.',
      );
    },
  );
}
