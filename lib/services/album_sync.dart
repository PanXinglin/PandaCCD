import 'dart:async';
import 'dart:io';
import 'library.dart';
import 'system_gallery.dart';

class AlbumSyncException extends StateError {
  AlbumSyncException(super.message);
  @override
  String toString() => message;
}

class BatchDeleteResult {
  final Set<String> deleted, kept;
  const BatchDeleteResult(this.deleted, this.kept);
}

/// Serializes export/link/delete so refreshing a gallery cannot race a save.
class AlbumSync {
  final PhotoLibrary library;
  final SystemGallery system;
  Future<void> _queue = Future.value();
  final _receipts = <String, String>{};
  AlbumSync(this.library, this.system);

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String> export(PhotoEntry photo) => _serial(() async {
    final receipt = await _receipt(photo);
    if (receipt != null) {
      final ids = receipt.isEmpty ? await _resolvePending(photo) : {receipt};
      await _finishLink(photo, ids);
      return '已存入系统相册';
    }
    final ids = await library.systemIds(photo);
    if (ids.isNotEmpty) {
      final states = await Future.wait(
        ids.map((id) => system.state(id, photo: photo)),
      );
      if (states.contains(SystemPhotoState.present)) return '已在系统相册中，无需重复保存';
      if (states.contains(SystemPhotoState.unknown)) {
        return '这张作品已存过系统相册；请允许相册访问后核对，未重复保存';
      }
    }
    await library.recordAlbumExport(photo, '');
    final String id;
    try {
      id = await system.save(photo);
    } on SystemGalleryNotCreated {
      await library.markAlbumRetry(photo);
      await library.clearAlbumExport(photo);
      rethrow;
    }
    _receipts[photo.path] = id;
    await library.recordAlbumExport(photo, id);
    await _finishLink(photo, {id});
    return '已存入系统相册';
  });

  Future<String?> _receipt(PhotoEntry photo) async =>
      _receipts[photo.path] ?? await library.albumExport(photo);

  Future<Set<String>> _resolvePending(PhotoEntry photo) async {
    final id = await system.findExport(photo);
    if (id == null) {
      throw AlbumSyncException('系统相册同步结果待确认，应用内照片已保留。');
    }
    return {...await library.systemIds(photo), id};
  }

  Future<void> _finishLink(PhotoEntry photo, Set<String> ids) async {
    await library.linkSystem(photo, ids);
    _receipts.remove(photo.path);
    try {
      await library.clearAlbumRetry(photo);
      await library.clearAlbumExport(photo);
    } on FileSystemException {
      // The durable receipt can be reused if cleanup did not finish.
    }
  }

  Future<Set<String>> linkedIds(PhotoEntry photo) async {
    final ids = await library.systemIds(photo);
    final receipt = await _receipt(photo);
    return {...ids, if (receipt != null && receipt.isNotEmpty) receipt};
  }

  Future<bool> mayHaveSystemCopy(PhotoEntry photo) async =>
      await _receipt(photo) != null ||
      (await library.systemIds(photo)).isNotEmpty;

  Future<bool> needsSystemSync(PhotoEntry photo) async =>
      await _receipt(photo) != null || await library.canRetryAlbumExport(photo);

  Future<void> recoverLinks(List<PhotoEntry> photos) => _serial(() async {
    for (final photo in photos) {
      await _recoverLink(photo);
    }
  });

  Future<void> _recoverLink(PhotoEntry photo) async {
    try {
      final receipt = await _receipt(photo);
      if (receipt != null && receipt.isNotEmpty) {
        await _finishLink(photo, {receipt});
      }
    } on FileSystemException {
      // A single inaccessible link should not block the remaining photos.
    }
  }

  Future<int> linkLegacy() => _serial(() async {
    final photos = await library.list();
    final unlinked = <PhotoEntry>[];
    for (final photo in photos) {
      if (!await mayHaveSystemCopy(photo)) unlinked.add(photo);
    }
    final matches = await system.findLegacyCopies(unlinked);
    var count = 0;
    for (final photo in unlinked) {
      final ids = matches[photo.path];
      if (ids != null && ids.isNotEmpty) {
        await _finishLink(photo, ids);
        count++;
      }
    }
    return count;
  });

  Future<int> reconcile() => _serial(() async {
    if (await system.access() != GalleryAccess.full) return 0;
    var removed = 0;
    for (final photo in await library.list()) {
      if (await _receipt(photo) == '') continue;
      await _recoverLink(photo);
      final ids = await linkedIds(photo);
      if (ids.isEmpty) continue;
      final states = await Future.wait(
        ids.map((id) => system.state(id, photo: photo)),
      );
      if (states.every((s) => s == SystemPhotoState.missing) &&
          await system.access() == GalleryAccess.full) {
        await library.delete(photo);
        _receipts.remove(photo.path);
        removed++;
      }
    }
    return removed;
  });

  Future<void> remove(PhotoEntry photo, {required bool linked}) =>
      _serial(() async {
        final present = linked ? await _planDeletion(photo) : <String>{};
        if (present.isNotEmpty &&
            !(await system.delete(present)).containsAll(present)) {
          throw AlbumSyncException('系统相册删除未完成或已取消，应用内作品已保留。');
        }
        await library.delete(photo);
        _receipts.remove(photo.path);
      });

  Future<Set<String>> _planDeletion(PhotoEntry photo) async {
    final pending = await _receipt(photo) == '';
    final ids = pending ? await _resolvePending(photo) : await linkedIds(photo);
    final present = <String>{};
    for (final id in ids) {
      switch (await system.state(id, photo: photo)) {
        case SystemPhotoState.present:
          present.add(id);
        case SystemPhotoState.unknown:
          throw AlbumSyncException('暂时无法读取对应的系统照片，作品已保留。请允许完整相册访问后重试。');
        case SystemPhotoState.missing:
          break;
      }
    }
    // Preserve the verified association if the user cancels system deletion
    // or if deleting the local files later fails.
    if (pending) await _finishLink(photo, ids);
    return present;
  }

  Future<BatchDeleteResult> removeMany(
    List<PhotoEntry> photos, {
    required bool linked,
  }) => _serial(() async {
    final unique = {for (final photo in photos) photo.path: photo};
    final plans = <String, Set<String>>{};
    final kept = <String>{};
    for (final photo in unique.values) {
      try {
        plans[photo.path] = linked ? await _planDeletion(photo) : <String>{};
      } on AlbumSyncException {
        kept.add(photo.path);
      }
    }
    final allIds = plans.values.expand((ids) => ids).toSet();
    final removedIds = allIds.isEmpty
        ? <String>{}
        : await system.delete(allIds);
    // A cancelled system batch prompt leaves *all* selected local files intact,
    // including local-only photos mixed into the same selection.
    if (allIds.isNotEmpty && removedIds.isEmpty) {
      return BatchDeleteResult({}, unique.keys.toSet());
    }
    final deleted = <String>{};
    for (final entry in plans.entries) {
      if (removedIds.containsAll(entry.value)) {
        await library.delete(unique[entry.key]!);
        _receipts.remove(entry.key);
        deleted.add(entry.key);
      } else {
        kept.add(entry.key);
      }
    }
    return BatchDeleteResult(deleted, kept);
  });
}
