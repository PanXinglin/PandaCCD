import 'dart:convert';
import 'dart:io';
import '../domain/live_capture.dart';
import '../domain/photo_edit.dart';
import 'live_processor.dart';

/// Owns the input and the capture-time settings until a cover is committed.
class CaptureDraft {
  const CaptureDraft(
    this.original,
    this.edit,
    this.motionFormat, {
    this.motion,
    this.directory,
  });

  final File original;
  final PhotoEdit edit;
  final String motionFormat;
  final LiveSource? motion;
  final Directory? directory;
  int get id => edit.date.microsecondsSinceEpoch;
  Directory? get motionDirectory => motion == null || directory == null
      ? null
      : Directory('${directory!.path}/live');

  static Directory _folder(Directory root) =>
      Directory('${root.path}/.captures');

  Future<CaptureDraft> retain(Directory root) async {
    if (directory != null) return this;
    final folder = await _folder(root).create();
    final staging = await Directory('${folder.path}/$id.next').create();
    try {
      await original.copy('${staging.path}/original');
      if (motion != null) {
        await LiveProcessor.retainFailed(
          motion!,
          '正在处理动态照片',
          pendingFormat: motionFormat,
          destination: Directory('${staging.path}/live'),
        );
      }
      await File('${staging.path}/draft.json').writeAsString(
        jsonEncode({
          'edit': edit.encode(),
          'motionFormat': motionFormat,
          if (motion != null) 'live': motion!.toJson(),
        }),
        flush: true,
      );
      final ready = await staging.rename('${folder.path}/$id');
      return CaptureDraft(
        File('${ready.path}/original'),
        edit,
        motionFormat,
        motion: motion == null
            ? null
            : LiveSource.decode(motion!.toJson(), '${ready.path}/live'),
        directory: ready,
      );
    } finally {
      await cleanupCaptureResource(staging);
    }
  }

  static Stream<CaptureDraft> restore(Directory root) async* {
    final folder = _folder(root);
    if (!await folder.exists()) return;
    await for (final item in folder.list(followLinks: false)) {
      if (item is! Directory) continue;
      final name = item.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (RegExp(r'^\d+\.next$').hasMatch(name)) {
        await cleanupCaptureResource(item);
        continue;
      }
      final id = int.tryParse(name);
      if (id == null) continue;
      try {
        final data =
            jsonDecode(await File('${item.path}/draft.json').readAsString())
                as Map<String, dynamic>;
        final edit = PhotoEdit.decode(data['edit'] as String);
        final original = File('${item.path}/original');
        if (edit.date.microsecondsSinceEpoch != id ||
            !await original.exists()) {
          continue;
        }
        final live = data['live'];
        yield CaptureDraft(
          original,
          edit,
          data['motionFormat'] as String,
          motion: live == null
              ? null
              : LiveSource.decode(live as Map, '${item.path}/live'),
          directory: item,
        );
      } on Exception {
        // An unreadable draft must not block access to the rest of the library.
      } on TypeError {
        // Leave malformed files alone.
      } on ArgumentError {
        // Leave malformed files alone.
      }
    }
  }

  Future<void> discard() async {
    final stored = directory;
    if (stored != null && await stored.exists()) {
      await stored.delete(recursive: true);
    }
    await cleanupCaptureResource(original);
    for (final segment in motion?.segments ?? const <LiveSegment>[]) {
      await cleanupCaptureResource(File(segment.path));
    }
  }
}

Future<void> cleanupCaptureResource(FileSystemEntity? resource) async {
  try {
    if (resource != null && await resource.exists()) {
      await resource.delete(recursive: resource is Directory);
    }
  } on FileSystemException {
    // Cache cleanup is best-effort and must never mask a save result.
  }
}
