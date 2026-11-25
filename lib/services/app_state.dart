import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart' show XFile;
import '../domain/photo_edit.dart';
import '../domain/face_region.dart';
import '../domain/frame_ratio.dart';
import '../domain/preset.dart';
import 'filter_engine.dart';
import 'library.dart';
import 'system_gallery.dart';
import 'album_sync.dart';
import 'capture_draft.dart';
import 'face_tracker.dart';
import 'live_processor.dart';
import 'live_foreground.dart';
import '../domain/live_capture.dart';
import 'dart:io';

class AppState extends ChangeNotifier {
  final SystemGallery systemGallery;
  AppState({SystemGallery? systemGallery, LiveForeground? liveForeground})
    : systemGallery = systemGallery ?? SystemGallery(),
      _liveForeground =
          liveForeground ?? (Platform.isIOS ? LiveForeground() : null);
  final LiveForeground? _liveForeground;
  final engine = FilterEngine();
  final library = PhotoLibrary();
  late final albumSync = AlbumSync(library, systemGallery);
  final watermark = Watermark();
  final Map<String, Recipe> recipes = {};
  final Map<String, LutImage> customLuts = {};
  int selected = 0;
  bool keepOriginal = false;
  bool directSave = true;
  bool shutterSound = true, volumeShutter = true;
  bool syncAlbumDeletes = true;
  bool beautyEnabled = false;
  double beautyStrength = .55;
  final beautyValues = <String, double>{
    'beautySmooth': .7,
    'beautyEven': .45,
    'beautyWhiten': .3,
    'faceSlim': .25,
  };
  bool liveEnabled = false;
  bool liveSound = true;
  String liveFormat = 'auto';
  double? frameAspect;
  List<PhotoEntry> photos = [];
  Future<void> _writes = Future.value();
  CcdPreset get preset => presets[selected];
  Map<String, double> get parameters => {
    ...parameterDefaults,
    ...(recipes[preset.id]?.values ?? preset.parameters),
    ...beautyValues,
    'beauty': beautyEnabled ? beautyStrength : 0,
  };

  void setLiveEnabled(bool enabled) {
    liveEnabled = enabled;
    notifyListeners();
    unawaited(persist());
  }

  void toggleBeauty() {
    beautyEnabled = !beautyEnabled;
    if (beautyStrength <= 0) beautyStrength = .55;
    notifyListeners();
    unawaited(persist());
  }

  LutImage get lut => customLuts[preset.id] ?? engine.lut(preset.id);
  Future<void> init({VoidCallback? onCameraReady}) async {
    await Future.wait([engine.init(), _restoreSettings()]);
    if (_disposed) return;
    await _restoreCaptureDrafts();
    if (_disposed) return;
    onCameraReady?.call();
    await refresh();
    await albumSync.recoverLinks(photos);
    for (final photo in photos.where((photo) => photo.live)) {
      if (_disposed) return;
      final info = await library.liveInfo(photo);
      final format = info?['pendingFormat'];
      if (format is! String || info?['rendered'] == true) continue;
      final edit = await library.readEdit(photo);
      if (edit != null && !_disposed && !liveProgress.containsKey(photo.path)) {
        _enqueueLiveExport(photo, edit, format);
      }
    }
  }

  Future<void> _restoreSettings() async {
    await library.init();
    final settings = await library.readSettings();
    if (settings != null) {
      selected = presetIndexFromSettings(settings);
      keepOriginal = settings['keepOriginal'] == true;
      // Old versions saved their edit-first default as directSave: false.
      // Only an explicit opt-in to the new setting should open the editor.
      directSave = settings['editAfterCapture'] != true;
      shutterSound = settings['shutterSound'] != false;
      volumeShutter = settings['volumeShutter'] != false;
      syncAlbumDeletes = settings['syncAlbumDeletes'] != false;
      frameAspect = validFrameRatio(settings['frameAspect']);
      if (settings['watermark'] is Map) {
        watermark.restore(settings['watermark'] as Map);
      }
      for (final raw
          in (settings['recipes'] is List ? settings['recipes'] as List : [])) {
        if (_disposed) return;
        try {
          await applyRecipe(Recipe.decode(jsonEncode(raw)), persist: false);
        } on FormatException {
          /* Ignore malformed user settings; bundled presets remain usable. */
        }
      }
      selected = presetIndexFromSettings(settings);
      beautyEnabled = settings['beautyEnabled'] == true;
      liveEnabled = settings['liveEnabled'] == true;
      liveSound = settings['liveSound'] != false;
      liveFormat = settings['liveFormat'] is String
          ? settings['liveFormat'] as String
          : 'auto';
      final rawBeauty = settings['beautyValues'];
      if (rawBeauty is Map) {
        for (final key in beautyValues.keys) {
          final value = rawBeauty[key];
          if (value is num && value.isFinite && value >= 0 && value <= 1) {
            beautyValues[key] = value.toDouble();
          }
        }
      }
      final strength = settings['beautyStrength'];
      if (strength is num &&
          strength.isFinite &&
          strength > 0 &&
          strength <= 1) {
        beautyStrength = strength.toDouble();
      }
    }
  }

  void setFrameAspect(double? ratio) {
    frameAspect = validFrameRatio(ratio);
    notifyListeners();
    unawaited(persist());
  }

  void select(int index) {
    selected = (index + presets.length) % presets.length;
    notifyListeners();
    unawaited(persist());
  }

  void update(String key, double value) {
    if (beautyValues.containsKey(key)) beautyValues[key] = value;
    if (key == 'beauty') {
      beautyEnabled = value > 0;
      beautyStrength = value;
    }
    recipes[preset.id] = Recipe(preset.id, {
      ...parameters,
      key: value,
    }, hald: recipes[preset.id]?.hald);
    notifyListeners();
  }

  Future<void> reset() async {
    recipes.remove(preset.id);
    customLuts.remove(preset.id)?.image.dispose();
    notifyListeners();
    await persist();
  }

  Future<void> applyRecipe(Recipe recipe, {bool persist = true}) async {
    LutImage? next;
    if (recipe.hald != null) {
      try {
        next = await LutImage.decode(base64Decode(recipe.hald!));
      } catch (_) {
        throw const FormatException('预设中的 HALD PNG 无效');
      }
    }
    if (_disposed) {
      next?.image.dispose();
      return;
    }
    customLuts.remove(recipe.presetId)?.image.dispose();
    if (next != null) customLuts[recipe.presetId] = next;
    recipes[recipe.presetId] = recipe;
    selected = presets.indexWhere((p) => p.id == recipe.presetId);
    beautyEnabled = (recipe.values['beauty'] ?? 0) > 0;
    if (beautyEnabled) beautyStrength = recipe.values['beauty']!;
    for (final key in beautyValues.keys) {
      beautyValues[key] = recipe.values[key] ?? parameterDefaults[key]!;
    }
    notifyListeners();
    if (persist) await this.persist();
  }

  Future<void> importLut(Uint8List bytes) async {
    final next = await LutImage.decode(bytes);
    customLuts.remove(preset.id)?.image.dispose();
    customLuts[preset.id] = next;
    recipes[preset.id] = Recipe(preset.id, {
      ...parameters,
    }, hald: base64Encode(bytes));
    notifyListeners();
    await persist();
  }

  Recipe get recipe =>
      Recipe(preset.id, parameters, hald: recipes[preset.id]?.hald);
  Future<void> persist() {
    final data = {
      'selected': selected,
      'selectedId': preset.id,
      'keepOriginal': keepOriginal,
      'editAfterCapture': !directSave,
      'shutterSound': shutterSound,
      'volumeShutter': volumeShutter,
      'syncAlbumDeletes': syncAlbumDeletes,
      'beautyEnabled': beautyEnabled,
      'beautyStrength': beautyStrength,
      'beautyValues': Map<String, double>.from(beautyValues),
      'liveEnabled': liveEnabled,
      'liveSound': liveSound,
      'liveFormat': liveFormat,
      'frameAspect': frameAspect,
      'watermark': watermark.toJson(),
      'recipes': recipes.values.map((r) => jsonDecode(r.encode())).toList(),
    };
    _writes = _writes
        .catchError((Object _) {})
        .then((_) => library.writeSettings(data));
    return _writes;
  }

  Future<void> refresh({bool syncSystem = false}) async {
    if (syncSystem && syncAlbumDeletes) {
      try {
        await albumSync.reconcile();
      } catch (_) {
        /* Keep local photos on read failures. */
      }
    }
    // A capture may finish while the initial library scan is still running.
    // Retry a snapshot that overlapped another change to the photo list.
    while (!_disposed) {
      final before = photos;
      final listed = await library.list();
      if (_disposed) return;
      if (!identical(before, photos)) continue;
      photos = listed;
      break;
    }
    notifyListeners();
  }

  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _captureSaves = Future.value();
  Future<void> _liveExports = Future.value();

  Future<void> finishLiveExports() async {
    await _captureSaves;
    await _liveExports;
  }

  void _reportLiveIssue(String message) {
    liveNotice = message;
    liveNoticeRevision++;
    notifyListeners();
  }

  String? liveNotice;
  int liveNoticeRevision = 0;
  final liveProgress = <String, double>{};

  /// Returns a message only when the saved work needs attention.
  Future<String> commitPhoto(
    Uint8List rendered,
    PhotoEdit edit, {
    Uint8List? original,
    LiveSource? liveSource,
    String? motionFormat,
    DateTime? captureDate,
    Directory? retainedMotion,
  }) async {
    final chosenFormat = motionFormat ?? liveFormat;
    // Commit the cover and original motion first. A killed/backgrounded export
    // must leave a recoverable work in the library, never an imaginary success.
    var pending = retainedMotion;
    if (liveSource != null && pending == null) {
      pending = await LiveProcessor.retainFailed(
        liveSource,
        '正在处理动态照片',
        pendingFormat: chosenFormat,
      );
    }
    late final PhotoEntry photo;
    try {
      photo = await library.save(
        rendered,
        edit.recipe.presetId,
        captureDate ?? DateTime.now(),
        original: original,
        edit: edit,
        liveDirectory: pending,
      );
    } finally {
      if (retainedMotion == null) await cleanupCaptureResource(pending);
    }
    photos = [photo, ...photos];
    if (liveSource != null) {
      _enqueueLiveExport(photo, edit, chosenFormat);
      return '';
    }
    notifyListeners();
    try {
      await albumSync.export(photo);
      return '';
    } on AlbumSyncException catch (error) {
      return error.message;
    } catch (_) {
      return '照片已保存在应用内，未能确认系统相册同步';
    }
  }

  void _enqueueLiveExport(
    PhotoEntry photo,
    PhotoEdit edit,
    String chosenFormat,
  ) {
    liveProgress[photo.path] = 0;
    notifyListeners();
    _liveExports = _liveExports.catchError((Object _) {}).then((_) async {
      Directory? finished;
      LutImage? custom;
      try {
        if (!await File(photo.path).exists()) {
          return;
        }
        final retained = await library.liveSource(photo);
        if (retained == null) throw StateError('原始动态资源不存在');
        Future<Directory> prepare() async {
          final hald = edit.recipe.hald;
          if (hald != null) {
            custom ??= await LutImage.decode(base64Decode(hald));
          }
          return LiveProcessor(engine).prepare(
            retained,
            edit,
            custom ?? engine.lut(edit.recipe.presetId),
            await File(photo.path).readAsBytes(),
            chosenFormat,
            waitForForeground: _liveForeground?.wait,
            progress: (value) {
              liveProgress[photo.path] = value;
            },
          );
        }

        final prepared =
            await (_liveForeground?.run<Directory>(prepare) ?? prepare());
        finished = prepared;
        if (!await File(photo.path).exists()) {
          return;
        }
        await library.replaceLive(photo, prepared);
        try {
          await _liveForeground?.wait();
          final lease = _liveForeground == null
              ? null
              : await LiveFinishLease.begin();
          try {
            await albumSync.export(photo);
          } finally {
            if (lease != null) unawaited(lease.end());
          }
        } catch (_) {
          _reportLiveIssue('Live 已保存在作品库，未写入系统相册');
        }
      } catch (e) {
        try {
          if (await File(photo.path).exists()) {
            final info = await library.liveInfo(photo);
            if (info != null) {
              await File('${photo.liveDirectory}/manifest.json').writeAsString(
                jsonEncode(
                  {...info, 'error': e.toString(), 'rendered': false}
                    ..remove('pendingFormat'),
                ),
                flush: true,
              );
            }
          }
        } catch (_) {}
        if (await File(photo.path).exists()) {
          _reportLiveIssue('Live 生成失败，原始动态已保留');
        }
      } finally {
        custom?.image.dispose();
        if (finished != null && await finished.exists()) {
          await finished.delete(recursive: true);
        }
        liveProgress.remove(photo.path);
        notifyListeners();
      }
    });
  }

  final _failedCaptures = <int, CaptureDraft>{};
  final _cameraInputs = <int, CaptureDraft>{};
  final _recoveringCaptures = <int>{};
  List<CaptureDraft> get failedCaptures => _failedCaptures.values.toList();
  bool captureRecoveryBusy(int id) => _recoveringCaptures.contains(id);

  Future<void> _restoreCaptureDrafts() async {
    await for (final draft in CaptureDraft.restore(library.root)) {
      if (_disposed) return;
      final path =
          '${library.root.path}/${draft.id}_${draft.edit.recipe.presetId}.png';
      if (await File(path).exists()) {
        // The last run committed the cover before it could clear the draft.
        await cleanupCaptureResource(draft.directory);
      } else {
        _failedCaptures[draft.id] = draft;
      }
    }
    notifyListeners();
  }

  PhotoEdit _snapshotCapture() => PhotoEdit(
    recipe,
    Watermark()..restore(watermark.toJson()),
    DateTime.now(),
    frameAspect: frameAspect,
  );

  LutImage _captureLut() {
    final current = lut;
    return LutImage(current.image.clone(), current.cube);
  }

  Future<String> saveCapture(Uint8List original, {LiveSource? liveSource}) {
    final edit = _snapshotCapture(), lease = _captureLut(), format = liveFormat;
    return _queueCapture(() async {
      try {
        return await _renderCapture(original, edit, lease, liveSource, format);
      } finally {
        lease.image.dispose();
      }
    });
  }

  /// Do not give up the camera input until the library has committed a cover.
  Future<String> saveCaptureFile(XFile file, {LiveSource? liveSource}) {
    final draft = CaptureDraft(
      File(file.path),
      _snapshotCapture(),
      liveFormat,
      motion: liveSource,
    );
    final lease = _captureLut();
    return _queueCapture(() async {
      try {
        return await _saveDraft(draft, lease);
      } finally {
        lease.image.dispose();
      }
    });
  }

  Future<String> _saveDraft(CaptureDraft draft, LutImage lut) async {
    var retained = draft;
    try {
      retained = await draft.retain(library.root);
      if (!identical(retained, draft)) _cameraInputs[draft.id] = draft;
      final result = await _renderCapture(
        await retained.original.readAsBytes(),
        retained.edit,
        lut,
        retained.motion,
        retained.motionFormat,
        retainedMotion: retained.motionDirectory,
        captureDate: retained.edit.date,
      );
      _failedCaptures.remove(draft.id);
      await cleanupCaptureResource(retained.directory);
      final input = _cameraInputs.remove(draft.id);
      if (input != null) await input.discard();
      return result;
    } catch (_) {
      _failedCaptures[draft.id] = retained;
      notifyListeners();
      rethrow;
    }
  }

  Future<String> retryCapture(int id) => _recoverCapture(id, (draft) async {
    return _queueCapture(() async {
      final edit = draft.edit;
      final hald = edit.recipe.hald;
      final custom = hald == null
          ? null
          : await LutImage.decode(base64Decode(hald));
      try {
        return await _saveDraft(
          draft,
          custom ?? engine.lut(edit.recipe.presetId),
        );
      } finally {
        custom?.image.dispose();
      }
    });
  });

  Future<void> discardCapture(int id) => _recoverCapture(id, (draft) async {
    await draft.discard();
    await _cameraInputs.remove(id)?.discard();
    _failedCaptures.remove(id);
  });

  Future<T> _recoverCapture<T>(
    int id,
    Future<T> Function(CaptureDraft) action,
  ) async {
    final draft = _failedCaptures[id];
    if (draft == null || !_recoveringCaptures.add(id)) {
      throw StateError('这张照片已处理或正在处理');
    }
    notifyListeners();
    try {
      return await action(draft);
    } finally {
      _recoveringCaptures.remove(id);
      notifyListeners();
    }
  }

  Future<T> _queueCapture<T>(Future<T> Function() work) {
    final job = _captureSaves.then((_) => work());
    _captureSaves = job.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return job;
  }

  Future<String> _renderCapture(
    Uint8List original,
    PhotoEdit snapshot,
    LutImage lut,
    LiveSource? liveSource,
    String motionFormat, {
    Directory? retainedMotion,
    DateTime? captureDate,
  }) async {
    final values = snapshot.recipe.values;
    Future<({Uint8List rendered, PhotoEdit edit})> render() async {
      final image = await engine.decodePhoto(original);
      try {
        final faces = (values['beauty'] ?? 0) > 0
            ? await FaceTracker.detect(image)
            : const <FaceRegion>[];
        final edit = PhotoEdit(
          snapshot.recipe,
          snapshot.stamp,
          snapshot.date,
          frameAspect: snapshot.frameAspect,
          faces: faces,
        );
        if (liveSource != null) await _liveForeground?.wait();
        final rendered = await engine.render(
          image,
          values,
          lut,
          edit.stamp,
          edit.date,
          presets.firstWhere((p) => p.id == edit.recipe.presetId).stampLabel,
          frameAspect: edit.frameAspect,
          faces: faces,
          trackFace: true,
        );
        return (rendered: rendered, edit: edit);
      } finally {
        image.dispose();
      }
    }

    final result = await (liveSource == null
        ? render()
        : _liveForeground?.run(render) ?? render());
    return commitPhoto(
      result.rendered,
      result.edit,
      original: original,
      liveSource: liveSource,
      motionFormat: motionFormat,
      retainedMotion: retainedMotion,
      captureDate: captureDate,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _liveForeground?.dispose();
    // Let queued covers and motion exports finish before disposing the engine.
    unawaited(
      finishLiveExports().whenComplete(() {
        for (final lut in customLuts.values) {
          lut.image.dispose();
        }
        engine.dispose();
      }),
    );
    super.dispose();
  }
}
