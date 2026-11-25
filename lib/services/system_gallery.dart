import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:gal/gal.dart';
import 'package:flutter/services.dart';
import 'package:panda_media/panda_media.dart';
import 'package:photo_manager/photo_manager.dart';
import 'library.dart';

enum GalleryAccess { full, limited, denied }

enum SystemPhotoState { present, missing, unknown }

/// The system asset creation request was never submitted.
class SystemGalleryNotCreated extends StateError {
  SystemGalleryNotCreated(super.message);
}

class SystemGalleryWriteDenied extends SystemGalleryNotCreated {
  SystemGalleryWriteDenied() : super('未允许写入系统相册');
}

/// All platform media access goes through federated Flutter plugins. Never
/// interpret an inaccessible asset (limited/revoked permission) as deleted.
class SystemGallery {
  static const permission = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: false,
    ),
  );
  Future<GalleryAccess> access({bool request = false}) async {
    final state = request
        ? await PhotoManager.requestPermissionExtend(requestOption: permission)
        : await PhotoManager.getPermissionState(requestOption: permission);
    return state == PermissionState.authorized
        ? GalleryAccess.full
        : state == PermissionState.limited
        ? GalleryAccess.limited
        : GalleryAccess.denied;
  }

  Future<({File image, File? video, String title})> _exportFiles(
    PhotoEntry photo,
  ) async {
    if (photo.live) {
      final manifest = File('${photo.liveDirectory}/manifest.json');
      final data = jsonDecode(await manifest.readAsString());
      if (data is! Map) throw const FormatException('Invalid Live manifest');
      if (data['rendered'] == true) {
        if (Platform.isIOS) {
          return (
            image: File('${photo.liveDirectory}/pair.jpg'),
            video: File('${photo.liveDirectory}/pair.mov'),
            title: photo.filename.replaceFirst(RegExp(r'\.png$'), '.jpg'),
          );
        }
        return (
          image: File('${photo.liveDirectory}/export.MP.jpg'),
          video: null,
          title: photo.filename.replaceFirst(RegExp(r'\.png$'), 'MP.jpg'),
        );
      }
    }
    return (image: File(photo.path), video: null, title: photo.filename);
  }

  Future<String> save(PhotoEntry photo) async {
    final ({File image, File? video, String title}) files;
    try {
      files = await _exportFiles(photo);
      for (final file in [files.image, ?files.video]) {
        final handle = await file.open();
        try {
          if (await handle.length() == 0) {
            throw SystemGalleryNotCreated('系统相册导出文件为空');
          }
        } finally {
          await handle.close();
        }
      }
    } on FileSystemException {
      throw SystemGalleryNotCreated('系统相册导出文件暂时无法读取');
    } on FormatException {
      throw SystemGalleryNotCreated('系统相册导出信息无法读取');
    }

    if (Platform.isIOS) {
      // The creation request returns the ID even with add-only access.
      final String? id;
      try {
        id = await PandaMedia.call<String>('savePhoto', {
          'imagePath': files.image.path,
          'videoPath': files.video?.path,
          'title': files.title,
          'dateMs': photo.date.millisecondsSinceEpoch,
        });
      } on PlatformException catch (error) {
        if (error.code == 'PHOTOS_WRITE_DENIED') {
          throw SystemGalleryWriteDenied();
        }
        if (error.code == 'PHOTOS_NOT_CREATED') {
          throw SystemGalleryNotCreated('系统相册导出文件暂时无法读取');
        }
        rethrow;
      }
      if (id == null || id.isEmpty) throw StateError('系统相册保存失败');
      return id;
    }
    final bool allowed;
    try {
      allowed = await Gal.hasAccess() || await Gal.requestAccess();
    } on Exception {
      throw SystemGalleryWriteDenied();
    }
    if (!allowed) throw SystemGalleryWriteDenied();
    final asset = await PhotoManager.editor.saveImageWithPath(
      files.image.path,
      title: files.title,
      creationDate: photo.date,
    );
    return asset.id;
  }

  /// Recover one interrupted export using its actual system filename and
  /// original bytes. On iOS a Live match also verifies the paired video.
  Future<String?> findExport(PhotoEntry photo) async {
    try {
      if (await access() != GalleryAccess.full) return null;
      final files = await _exportFiles(photo);
      if (Platform.isIOS) {
        final video = files.video;
        return await PandaMedia.call<String>('findPhotoExport', {
          'title': files.title,
          'dateMs': photo.date.millisecondsSinceEpoch,
          'imageHash': (await sha256.bind(files.image.openRead()).first)
              .toString(),
          'videoHash': video == null
              ? null
              : (await sha256.bind(video.openRead()).first).toString(),
        });
      }
      final matches = await _findCopies({
        files.title: (path: photo.path, image: files.image),
      });
      final ids = matches[photo.path];
      return ids?.length == 1 ? ids!.single : null;
    } catch (_) {
      return null;
    }
  }

  Future<SystemPhotoState> state(String id, {PhotoEntry? photo}) async {
    try {
      if (await access() != GalleryAccess.full) return SystemPhotoState.unknown;
      // fromId catches *all* plugin exceptions and returns null. Use the
      // throwing exists query instead so failures cannot erase local originals.
      final exists = await PhotoManager.plugin.assetExistsWithId(id);
      if (await access() != GalleryAccess.full) return SystemPhotoState.unknown;
      if (exists && photo != null) {
        final asset = await AssetEntity.fromId(id);
        final title = await asset?.titleAsync;
        final expected = {photo.filename};
        if (photo.live) expected.add((await _exportFiles(photo)).title);
        if (asset == null || !expected.contains(title)) {
          return SystemPhotoState.unknown;
        }
      }
      return exists ? SystemPhotoState.present : SystemPhotoState.missing;
    } catch (_) {
      return SystemPhotoState.unknown;
    }
  }

  Future<Set<String>> delete(Set<String> ids) async =>
      (await PhotoManager.editor.deleteWithIds(ids.toList())).toSet();

  /// Migration is explicitly requested, never part of shutter processing.
  /// Match the unique old export filename AND identical original PNG bytes.
  /// No match is not evidence of deletion, and never deletes a local photo.
  Future<Map<String, Set<String>>> findLegacyCopies(List<PhotoEntry> photos) =>
      _findCopies({
        for (final photo in photos)
          photo.filename: (path: photo.path, image: File(photo.path)),
      });

  Future<Map<String, Set<String>>> _findCopies(
    Map<String, ({String path, File image})> names,
  ) async {
    final result = <String, Set<String>>{};
    if (names.isEmpty || await access() != GalleryAccess.full) return result;
    final hashes = <String, Digest>{};
    Future<bool> matches(File local, File? assetFile) async {
      if (assetFile == null) return false;
      final localHash = hashes[local.path] ??= await sha256
          .bind(local.openRead())
          .first;
      return localHash == await sha256.bind(assetFile.openRead()).first;
    }

    final filter = FilterOptionGroup(
      imageOption: const FilterOption(needTitle: true),
    );
    for (var page = 0; ; page++) {
      if (await access() != GalleryAccess.full) return {};
      final assets = await PhotoManager.getAssetListPaged(
        page: page,
        pageCount: 100,
        type: RequestType.image,
        filterOption: filter,
      );
      for (final asset in assets) {
        final files = names[asset.title];
        if (files == null ||
            !await matches(files.image, await asset.originFile)) {
          continue;
        }
        (result[files.path] ??= <String>{}).add(asset.id);
      }
      if (assets.length < 100) break;
    }
    return await access() == GalleryAccess.full ? result : {};
  }
}
