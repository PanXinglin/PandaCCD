import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/album_sync.dart';
import 'package:panda_ccd/services/library.dart';
import 'package:panda_ccd/services/system_gallery.dart';

/// Only the OS gallery is replaced. AlbumSync and PhotoLibrary are real.
/// The first successful OS save injects a real filesystem write failure before
/// AlbumSync can persist the returned asset ID.
class _SavedAssetGallery extends SystemGallery {
  GalleryAccess permission = GalleryAccess.full;
  int saveCalls = 0;
  final assets = <String>{};
  late Directory blockedIdWrite;

  @override
  Future<String> save(PhotoEntry photo) async {
    saveCalls++;
    final id = 'already-saved-asset-$saveCalls';
    assets.add(id);
    if (saveCalls == 1) {
      // PhotoLibrary.linkSystem writes this path as a FILE. A directory at the
      // same path makes the actual File.writeAsString fail deterministically.
      blockedIdWrite = await Directory(
        '${photo.path}.system.json.tmp',
      ).create();
    }
    return id;
  }

  @override
  Future<GalleryAccess> access({bool request = false}) async => permission;

  @override
  Future<SystemPhotoState> state(String id, {PhotoEntry? photo}) async =>
      assets.contains(id) ? SystemPhotoState.present : SystemPhotoState.missing;
}

void main() {
  test(
    'Retry after successful system save and failed ID commit must not save twice',
    () async {
      final root = await Directory.systemTemp.createTemp('audit-album-id-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final library = PhotoLibrary()..root = root;
      final photo = await library.save(
        Uint8List.fromList([1, 2, 3]),
        'g12',
        DateTime(2026, 11, 9),
      );
      final gallery = _SavedAssetGallery();
      final sync = AlbumSync(library, gallery);

      // Prove the failure occurred AFTER the external save succeeded, while
      // committing the real local association file.
      await expectLater(
        sync.export(photo),
        throwsA(isA<FileSystemException>()),
      );
      expect(gallery.saveCalls, 1);
      expect(gallery.assets, {'already-saved-asset-1'});
      expect(await File(photo.path).exists(), isTrue);
      expect(await library.systemIds(photo), isEmpty);
      expect(await gallery.blockedIdWrite.exists(), isTrue);

      // Recover using a new instance with no in-memory state.
      await gallery.blockedIdWrite.delete();
      gallery.permission = GalleryAccess.limited;
      final reopened = PhotoLibrary()..root = root;
      await AlbumSync(reopened, gallery).export(photo);

      // Correct behavior is recovery/linking of the first saved asset.
      expect(
        gallery.saveCalls,
        1,
        reason:
            'The system asset already exists. Retrying only the failed ID '
            'commit must not create another external asset. '
            'Observed assets: ${gallery.assets}',
      );
      expect(gallery.assets, {'already-saved-asset-1'});
      expect(await library.systemIds(photo), {'already-saved-asset-1'});
    },
  );

  test('Interrupted system write without an ID never submits again', () async {
    final root = await Directory.systemTemp.createTemp('panda-album-intent-');
    addTearDown(() => root.delete(recursive: true));
    final library = PhotoLibrary()..root = root;
    final photo = await library.save(Uint8List(1), 'g12', DateTime(2026));
    await library.recordAlbumExport(photo, '');
    final gallery = _SavedAssetGallery()..permission = GalleryAccess.limited;
    await expectLater(
      AlbumSync(library, gallery).export(photo),
      throwsA(isA<AlbumSyncException>()),
    );
    expect(gallery.saveCalls, 0);
    expect(await File(photo.path).exists(), isTrue);
  });
}
