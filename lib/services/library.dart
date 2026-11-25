import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../domain/photo_edit.dart';
import '../domain/live_capture.dart';

class PhotoEntry {
  final String path, preset;
  final DateTime date;
  final bool live;
  const PhotoEntry(this.path, this.preset, this.date, {this.live = false});
  String get liveDirectory => '$path.live';
  String get filename => File(path).uri.pathSegments.last;
}

class PhotoLibrary {
  late Directory root;
  final _saving = <String>{};
  Future<void> init() async {
    root = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/panda_ccd',
    );
    await root.create(recursive: true);
    await for (final item in root.list(followLinks: false)) {
      if (item is Directory && item.path.endsWith('.save')) {
        final name = item.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last
            .replaceFirst(RegExp(r'\.save$'), '');
        if (RegExp(r'^\d+_[a-zA-Z0-9_-]+$').hasMatch(name)) {
          await _recoverSave(item, _saveTargets(name));
        }
      }
      if (item is Directory && item.path.endsWith('.live.backup')) {
        final target = Directory(
          item.path.replaceFirst(RegExp(r'\.backup$'), ''),
        );
        if (await target.exists()) {
          await item.delete(recursive: true);
        } else {
          await item.rename(target.path);
        }
      }
      if (item is Directory && item.path.endsWith('.png.live.next')) {
        await item.delete(recursive: true);
      }
    }
  }

  Future<Map<String, dynamic>?> readSettings() async {
    final file = File('${root.path}/settings.json');
    if (!await file.exists()) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeSettings(Map<String, dynamic> value) async {
    final temp = File('${root.path}/settings.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    await temp.rename('${root.path}/settings.json');
  }

  Future<PhotoEntry> save(
    Uint8List bytes,
    String preset,
    DateTime date, {
    Uint8List? original,
    PhotoEdit? edit,
    Directory? liveDirectory,
  }) async {
    final name = '${date.microsecondsSinceEpoch}_$preset';
    if (!_saving.add(name)) {
      throw FileSystemException('Photo is already being saved', name);
    }
    try {
      final targets = _saveTargets(name);
      final staging = Directory('${root.path}/$name.save');
      await _recoverSave(staging, targets);
      for (final path in targets.values) {
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw FileSystemException('Photo destination already exists', path);
        }
      }
      await staging.create();
      final staged = <String, FileSystemEntity>{};
      try {
        final cover = File('${staging.path}/cover');
        await cover.writeAsBytes(bytes, flush: true);
        if (original != null) {
          staged['original'] = await File(
            '${staging.path}/original',
          ).writeAsBytes(original, flush: true);
          if (edit != null) {
            staged['edit'] = await File(
              '${staging.path}/edit',
            ).writeAsString(edit.encode(), flush: true);
          }
        }
        if (liveDirectory != null) {
          final live = await Directory('${staging.path}/live').create();
          await for (final item in liveDirectory.list()) {
            if (item is File) {
              await item.copy('${live.path}/${item.uri.pathSegments.last}');
            }
          }
          staged['live'] = live;
        }
        // Publish the manifest atomically before moving any sidecars. A missing
        // staged sidecar then identifies a move owned by this transaction.
        final manifest = await File(
          '${staging.path}/ready.tmp',
        ).writeAsString(jsonEncode(staged.keys.toList()), flush: true);
        await manifest.rename('${staging.path}/ready');
        for (final entry in staged.entries) {
          await entry.value.rename(targets[entry.key]!);
        }
        await cover.rename(targets['cover']!);
      } finally {
        // If cleanup is interrupted, init can repeat it. A committed cover
        // must still be reported as a success.
        try {
          await _recoverSave(staging, targets);
        } on FileSystemException {
          // Leave the manifest for recovery.
        }
      }
      return PhotoEntry(
        targets['cover']!,
        preset,
        date,
        live: liveDirectory != null,
      );
    } finally {
      _saving.remove(name);
    }
  }

  Map<String, String> _saveTargets(String name) => {
    'cover': '${root.path}/$name.png',
    'original': '${root.path}/$name.original',
    'edit': '${root.path}/$name.edit.json',
    'live': '${root.path}/$name.png.live',
  };

  Future<void> _recoverSave(
    Directory staging,
    Map<String, String> targets,
  ) async {
    if (!await staging.exists()) return;
    final manifest = File('${staging.path}/ready');
    if (await manifest.exists() && !await File(targets['cover']!).exists()) {
      final moved = (jsonDecode(await manifest.readAsString()) as List)
          .whereType<String>();
      for (final key in moved) {
        if (key == 'cover' || !targets.containsKey(key)) continue;
        if (await FileSystemEntity.type('${staging.path}/$key') !=
            FileSystemEntityType.notFound) {
          continue;
        }
        final target = key == 'live'
            ? Directory(targets[key]!)
            : File(targets[key]!);
        if (await target.exists()) {
          await target.delete(recursive: key == 'live');
        }
      }
    }
    await staging.delete(recursive: true);
  }

  Future<PhotoEdit?> readEdit(PhotoEntry photo) async {
    final file = File(photo.path.replaceAll('.png', '.edit.json'));
    if (!await file.exists()) return null;
    try {
      return PhotoEdit.decode(await file.readAsString());
    } on FormatException {
      return null;
    }
  }

  Future<List<PhotoEntry>> list() async {
    final items = <PhotoEntry>[];
    await for (final file in root.list()) {
      if (file is! File || !file.path.endsWith('.png')) continue;
      final name = file.uri.pathSegments.last.replaceAll('.png', '').split('_');
      final stamp = int.tryParse(name.first);
      if (stamp != null) {
        items.add(
          PhotoEntry(
            file.path,
            name.last,
            DateTime.fromMicrosecondsSinceEpoch(stamp),
            live: await File('${file.path}.live/manifest.json').exists(),
          ),
        );
      }
    }
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Future<void> replaceLive(PhotoEntry photo, Directory ready) async {
    final target = Directory(photo.liveDirectory),
        staging = Directory('${photo.liveDirectory}.next'),
        backup = Directory('${photo.liveDirectory}.backup');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create();
    try {
      await for (final item in ready.list()) {
        if (item is File) {
          await item.copy('${staging.path}/${item.uri.pathSegments.last}');
        }
      }
      if (await backup.exists()) await backup.delete(recursive: true);
      if (await target.exists()) await target.rename(backup.path);
      await staging.rename(target.path);
      if (await backup.exists()) await backup.delete(recursive: true);
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    } finally {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } on FileSystemException {
        // Startup will remove any remaining staging directory.
      }
    }
  }

  Future<Map<String, dynamic>?> liveInfo(PhotoEntry photo) async {
    final file = File('${photo.liveDirectory}/manifest.json');
    if (!await file.exists()) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  Future<LiveSource?> liveSource(PhotoEntry photo) async {
    final info = await liveInfo(photo);
    return info == null
        ? null
        : LiveSource.decode({
            ...info,
            'legacyRedBlueSwap':
                info['legacyRedBlueSwap'] == true ||
                (Platform.isAndroid &&
                    info['rendered'] == true &&
                    !info.containsKey('pixelLayoutVersion')),
          }, photo.liveDirectory);
  }

  Future<void> delete(PhotoEntry photo) async {
    final live = Directory(photo.liveDirectory);
    if (await live.exists()) await live.delete(recursive: true);
    final original = File(photo.path.replaceAll('.png', '.original'));
    if (await original.exists()) await original.delete();
    final edit = File(photo.path.replaceAll('.png', '.edit.json'));
    if (await edit.exists()) await edit.delete();
    final link = File('${photo.path}.system.json');
    if (await link.exists()) await link.delete();
    final file = File(photo.path);
    if (await file.exists()) await file.delete();
    await clearAlbumExport(photo);
    await clearAlbumRetry(photo);
  }

  File _albumExport(PhotoEntry photo) => File('${photo.path}.album-export');

  File _albumRetry(PhotoEntry photo) => File('${photo.path}.album-retry');

  Future<bool> canRetryAlbumExport(PhotoEntry photo) =>
      _albumRetry(photo).exists();

  Future<void> markAlbumRetry(PhotoEntry photo) async {
    await _albumRetry(photo).create();
  }

  Future<void> clearAlbumRetry(PhotoEntry photo) async {
    final file = _albumRetry(photo);
    if (await file.exists()) await file.delete();
  }

  // Null means no operation. An empty receipt means the system call may
  // have happened, but there is no verified ID to link yet.
  Future<String?> albumExport(PhotoEntry photo) async {
    final file = _albumExport(photo);
    return await file.exists() ? await file.readAsString() : null;
  }

  Future<void> recordAlbumExport(PhotoEntry photo, String id) async {
    final file = _albumExport(photo);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(id, flush: true);
    await temp.rename(file.path);
  }

  Future<void> clearAlbumExport(PhotoEntry photo) async {
    final file = _albumExport(photo);
    for (final item in [File('${file.path}.tmp'), file]) {
      if (await item.exists()) await item.delete();
    }
  }

  Future<Set<String>> systemIds(PhotoEntry photo) async {
    final file = File('${photo.path}.system.json');
    if (!await file.exists()) return {};
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || data['version'] != 1 || data['ids'] is! List) {
        return {};
      }
      return (data['ids'] as List)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
    } on FormatException {
      return {};
    }
  }

  Future<void> linkSystem(PhotoEntry photo, Set<String> ids) async {
    final file = File('${photo.path}.system.json');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({'version': 1, 'ids': ids.toList()}),
      flush: true,
    );
    await temp.rename(file.path);
  }
}
