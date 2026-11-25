import 'dart:async';
import 'dart:io';
import '../domain/live_capture.dart';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:panda_media/panda_media.dart';

typedef CameraZoomStop = ({
  String camera,
  double level,
  double? factor,
  String name,
});

typedef RearZoomConfiguration = ({
  String? camera,
  double mainLevel,
  Map<String, double> factors,
});

// Capture stays behind Flutter's endorsed camera plugin.
class CameraSession extends ChangeNotifier with WidgetsBindingObserver {
  CameraController? controller;
  void Function(CameraImage)? onFrame;
  bool liveRequested = false, analysisRequested = false;
  bool liveSoundRequested = true, audioDenied = false;
  bool _audioConfigured = false;
  bool _keepLiveSession = false;
  bool _liveVideoBound = false;
  bool _analysisStreamUnavailable = false;
  bool get usesStableLiveSession => Platform.isAndroid;
  bool get finishLiveOnFocusLoss => Platform.isIOS;
  Completer<void>? _liveTail;
  // CameraX StreamSharing can pre-rotate the preview when video and analysis
  // run together. Keep the Live session intact after recording stops as well.
  bool get usesPreviewFaceSnapshots =>
      usesStableLiveSession &&
      analysisRequested &&
      (liveRequested || _keepLiveSession || _analysisStreamUnavailable);
  Timer? _roll;
  int? _recordingStart;
  DeviceOrientation _recordedOrientation = DeviceOrientation.portraitUp;
  final _segments = <LiveSegment>[];
  DeviceOrientation _movieOrientation(CameraController c) => Platform.isIOS
      ? DeviceOrientation.portraitUp
      : (c.value.recordingOrientation ?? _recordedOrientation);
  String? liveError;
  bool get liveReady =>
      liveRequested &&
      !busy &&
      active &&
      enabled &&
      controller?.value.isRecordingVideo == true &&
      _recordingStart != null;

  bool _liveModeNeedsRestart(bool live, bool sound) {
    final keep = _keepLiveSession || (live && usesStableLiveSession);
    final nextFps = _fpsForFlash(flash, live: live, retainLive: keep);
    return _configuredFps != nextFps ||
        ((live || !usesStableLiveSession) &&
            _audioConfigured != (live && sound && !audioDenied));
  }

  /// A retained CameraX video use case can start and stop recording without
  /// replacing the preview surface. Only its first bind needs a cover.
  bool liveModeMayInterruptPreview({required bool live, required bool sound}) =>
      _liveModeNeedsRestart(live, sound) ||
      (live && usesStableLiveSession && !_liveVideoBound);

  Future<void> setModes({
    required bool live,
    required bool analysis,
    bool sound = true,
  }) {
    final changed =
        live != liveRequested ||
        analysis != analysisRequested ||
        sound != liveSoundRequested;
    final wasLive = liveRequested;
    if (sound && !liveSoundRequested) audioDenied = false;
    liveRequested = live;
    if (live && usesStableLiveSession) _keepLiveSession = true;
    analysisRequested = analysis;
    liveSoundRequested = sound;
    if (!changed) return Future.value();
    return _serialize(() async {
      if (!active || !enabled || closed) return;
      // Toggling beauty must not stop a healthy rolling recording or change
      // the retained VideoCapture session after Live is turned off.
      if (usesStableLiveSession &&
          (liveRequested || _keepLiveSession) &&
          wasLive == liveRequested &&
          liveRequested == (controller?.value.isRecordingVideo ?? false) &&
          (!liveRequested ||
              _audioConfigured == (liveSoundRequested && !audioDenied))) {
        _notify();
        return;
      }
      busy = true;
      _notify();
      try {
        if (_liveModeNeedsRestart(liveRequested, liveSoundRequested)) {
          await _start(reuseCameraList: true);
        } else {
          try {
            await _stopMotion();
            await _configureStreams();
            if (!liveRequested) await _discardSegments();
          } catch (_) {
            await _start();
          }
        }
      } finally {
        busy = false;
      }
      _notify();
    });
  }

  Future<void> _configureStreams() async {
    final c = controller;
    if (c == null || !c.value.isInitialized || closed || !active || !enabled) {
      return;
    }
    liveError = null;
    try {
      if (c.value.isStreamingImages && !c.value.isRecordingVideo) {
        await c.stopImageStream();
      }
      if (liveRequested) {
        _recordedOrientation =
            c.value.lockedCaptureOrientation ?? c.value.deviceOrientation;
        _recordingStart = DateTime.now().microsecondsSinceEpoch;
        await c.startVideoRecording(
          onAvailable: analysisRequested && !usesPreviewFaceSnapshots
              ? (image) => onFrame?.call(image)
              : null,
        );
        _liveVideoBound = true;
        _recordingStart = DateTime.now().microsecondsSinceEpoch;
        _recordedOrientation = _movieOrientation(c);
        _scheduleMotion();
      } else if (analysisRequested && !usesPreviewFaceSnapshots) {
        await c.startImageStream((image) => onFrame?.call(image));
      }
    } catch (e) {
      _recordingStart = null;
      liveError = liveRequested ? '此镜头暂不支持Live拍摄，请关闭Live或切换镜头' : null;
      if (!liveRequested && analysisRequested && usesStableLiveSession) {
        _analysisStreamUnavailable = true;
      }
      // Unsupported stream combinations must leave ordinary still capture usable.
      if (liveRequested &&
          analysisRequested &&
          c.value.isRecordingVideo == false) {
        try {
          _recordedOrientation = c.value.deviceOrientation;
          _recordingStart = DateTime.now().microsecondsSinceEpoch;
          if (c.value.isStreamingImages) await c.stopImageStream();
          await c.startVideoRecording();
          _liveVideoBound = true;
          _recordingStart = DateTime.now().microsecondsSinceEpoch;
          _recordedOrientation = _movieOrientation(c);
          _scheduleMotion();
          liveError = 'Live取景不支持同时跟踪人脸，成片会单独识别人脸';
        } catch (_) {
          _recordingStart = null;
        }
      }
    }
  }

  void _scheduleMotion() {
    _roll?.cancel();
    _roll = Timer(
      const Duration(seconds: 30),
      () => unawaited(
        _serialize(() async {
          if (!liveRequested || busy || closed) return;
          await _stopMotion();
          await _configureStreams();
        }),
      ),
    );
  }

  Future<void> _stopMotion() async {
    _roll?.cancel();
    _roll = null;
    _recordingStart = null;
    final c = controller;
    if (c?.value.isRecordingVideo == true) {
      final end = DateTime.now().microsecondsSinceEpoch;
      final movie = await c!.stopVideoRecording();
      _segments.add(
        LiveSegment(
          movie.path,
          end,
          _recordedOrientation,
          mirrored:
              Platform.isIOS &&
              c.description.lensDirection == CameraLensDirection.front,
        ),
      );
    }
    _recordingStart = null;
    while (_segments.length > 2) {
      final old = _segments.removeAt(0);
      try {
        await File(old.path).delete();
      } catch (_) {}
    }
  }

  Future<void> _discardSegments() async {
    for (final old in _segments) {
      try {
        await File(old.path).delete();
      } catch (_) {}
    }
    _segments.clear();
  }

  Future<LiveShot> captureLive({
    DeviceOrientation? orientation,
    VoidCallback? onExposed,
  }) {
    final result = Completer<LiveShot>();
    unawaited(
      _serialize(() async {
        XFile? photo;
        LiveShot? shot;
        final recordMotion = liveReady;
        Timer? tail;
        try {
          if (busy ||
              !active ||
              !enabled ||
              controller?.value.isInitialized != true) {
            throw StateError('相机还未就绪');
          }
          busy = true;
          if (recordMotion) {
            _roll?.cancel();
            _liveTail = Completer<void>();
          }
          _notify();
          final requestedAt = DateTime.now().microsecondsSinceEpoch;
          final direction = orientation ?? controller!.value.deviceOrientation;
          photo = await _takeStill(orientation);
          final at = (requestedAt + DateTime.now().microsecondsSinceEpoch) ~/ 2;
          onExposed?.call();
          if (recordMotion) {
            // If the user shoots again immediately, export the available
            // pre-roll. The processor clips the time window to actual media.
            final wait = _liveTail!;
            tail = Timer(const Duration(milliseconds: 1200), _finishLiveTail);
            await wait.future;
            try {
              await _stopMotion();
            } catch (_) {
              // On interruption, a previously sealed rolling segment can
              // still cover the shutter window even if the last writer fails.
              if (active ||
                  !finishLiveOnFocusLoss ||
                  !_segments.any((segment) => segment.endedUs > at - 1300000)) {
                rethrow;
              }
            }
            shot = LiveShot(
              photo,
              LiveSource(
                List.of(_segments),
                at - 1300000,
                at + 1200000,
                at,
                direction,
              ),
            );
            _segments.clear();
          } else {
            shot = LiveShot(photo, null, warning: 'Live 未就绪，已保留照片');
          }
        } catch (e, stack) {
          if (photo != null) {
            shot = LiveShot(photo, null, warning: 'Live 录制中断，已保留照片');
          } else {
            result.completeError(e, stack);
          }
        } finally {
          tail?.cancel();
          _liveTail = null;
          if (recordMotion &&
              active &&
              enabled &&
              !closed &&
              controller?.value.isRecordingVideo == false) {
            await _configureStreams();
          } else if (recordMotion && _recordingStart != null && liveRequested) {
            _scheduleMotion();
          }
          busy = false;
          _notify();
        }
        if (shot != null) result.complete(shot);
      }),
    );
    return result.future;
  }

  void _finishLiveTail() {
    final tail = _liveTail;
    if (tail != null && !tail.isCompleted) tail.complete();
  }

  Future<XFile> _takeStill(DeviceOrientation? orientation) async {
    final c = controller!;
    if (flash != FlashMode.off) await c.setExposureMode(ExposureMode.auto);
    await c.setFlashMode(flash);
    if (orientation != null) await c.lockCaptureOrientation(orientation);
    try {
      return await c.takePicture();
    } finally {
      if (orientation != null) {
        try {
          await c.unlockCaptureOrientation();
        } on CameraException {
          error = '拍摄方向恢复失败，可切换镜头后重试';
        }
      }
    }
  }

  List<CameraDescription> cameras = [];
  int lens = 0, _targetFps = 60;
  int? _configuredFps;
  int get fps => _fpsForFlash(flash);
  int _fpsForFlash(FlashMode mode, {bool? live, bool? retainLive}) {
    // Keep the CameraX rear session in the flash-compatible mode throughout
    // the three-state cycle. Rebinding for 30/60 on each tap clears preview.
    if (usesStableLiveSession && supportsFlashControl) return 30;
    return mode == FlashMode.off &&
            !(live ?? liveRequested) &&
            !(retainLive ?? _keepLiveSession)
        ? _targetFps
        : 30;
  }

  bool flashRequiresRestart(FlashMode mode) =>
      _configuredFps != _fpsForFlash(mode);
  bool get supportsFlashControl =>
      (controller?.description ??
              (cameras.isNotEmpty && lens < cameras.length
                  ? cameras[lens]
                  : null))
          ?.lensDirection ==
      CameraLensDirection.back;
  bool busy = false, active = true, closed = false, enabled = true;
  double minZoom = 1, maxZoom = 1;
  double _nativeMinZoom = 1, _nativeMaxZoom = 1;
  final zoom = ValueNotifier<double>(1);
  final _lensZoom = <String, double>{};
  RearZoomConfiguration? _rearZoom;
  bool _virtualRearUnavailable = false;
  CameraDescription? _lastZoomCamera;
  double? _nextZoom;
  bool _zoomQueued = false;
  bool get canZoom => controller != null && maxZoom > minZoom;

  Future<void> focusAt(Offset point) async {
    final current = controller;
    if (!active ||
        !enabled ||
        busy ||
        closed ||
        current == null ||
        !current.value.isInitialized) {
      return;
    }
    try {
      if (Platform.isIOS) {
        await const MethodChannel(
          'panda_ccd/preview_status',
        ).invokeMethod<void>('focus', {
          'textureId': current.cameraId,
          'x': point.dx,
          'y': point.dy,
        });
      } else if (current.value.focusPointSupported) {
        await current.setFocusPoint(point);
      } else if (current.value.exposurePointSupported) {
        await current.setExposurePoint(point);
      }
    } on CameraException {
      // A new tap or lens change can supersede a pending metering request.
    } on PlatformException {
      // Some lenses do not expose a configurable focus or exposure point.
    }
  }

  bool get hasZoomControls =>
      _zoomDescription != null && (maxZoom > minZoom || zoomStops.length > 1);
  CameraDescription? get _zoomDescription =>
      controller?.description ?? _lastZoomCamera;

  bool _isVirtualRear(CameraDescription camera) =>
      camera.name == _rearZoom?.camera;

  double _nativeZoomScale(CameraDescription camera) =>
      _isVirtualRear(camera) ? _rearZoom!.mainLevel : 1;

  static int _mainRear(List<CameraDescription> devices) {
    final wide = devices.indexWhere(
      (d) =>
          d.lensDirection == CameraLensDirection.back &&
          d.lensType == CameraLensType.wide,
    );
    return wide >= 0
        ? wide
        : devices.indexWhere(
            (d) => d.lensDirection == CameraLensDirection.back,
          );
  }

  CameraZoomStop? get mainZoomStop {
    final current = _zoomDescription;
    if (current == null) return null;
    final rear = _mainRear(cameras);
    final isRear = current.lensDirection == CameraLensDirection.back;
    final main = isRear && rear >= 0 ? cameras[rear] : current;
    return (
      camera: main.name,
      level: 1,
      factor: 1,
      name: isRear ? '主摄' : '原始倍率',
    );
  }

  static String _lensName(CameraLensType type) => switch (type) {
    CameraLensType.ultraWide => '超广角',
    CameraLensType.telephoto => '长焦',
    _ => '主摄',
  };

  List<CameraZoomStop> get zoomStops {
    final main = mainZoomStop;
    if (main == null) return const [];
    final current = _zoomDescription!;
    final rear = current.lensDirection == CameraLensDirection.back;
    final virtual = _isVirtualRear(current);
    final physical = <CameraLensType, CameraZoomStop>{};
    if (rear) {
      for (final d in cameras) {
        if (d.lensDirection != CameraLensDirection.back ||
            d.name == main.camera ||
            (d.lensType != CameraLensType.ultraWide &&
                d.lensType != CameraLensType.telephoto)) {
          continue;
        }
        final factor = _rearZoom?.factors[d.name];
        if (virtual &&
            (factor == null ||
                factor < minZoom - .00001 ||
                factor > maxZoom + .00001)) {
          continue;
        }
        final prior = physical[d.lensType];
        if (prior == null || (prior.factor == null && factor != null)) {
          physical[d.lensType] = (
            camera: virtual ? current.name : d.name,
            level: virtual ? factor! : 1,
            factor: factor,
            name: _lensName(d.lensType),
          );
        }
      }
    }
    return [
      if (physical[CameraLensType.ultraWide] case final ultra?)
        ultra
      else if (current.name == main.camera && minZoom < .995)
        (camera: current.name, level: minZoom, factor: minZoom, name: '拉远'),
      main,
      if (rear &&
          current.name == main.camera &&
          (physical[CameraLensType.telephoto] == null ||
              (virtual && physical[CameraLensType.telephoto]!.level > 2.05)) &&
          maxZoom >= 2)
        (camera: current.name, level: 2, factor: 2, name: '放大'),
      ?physical[CameraLensType.telephoto],
    ];
  }

  bool isAtZoomStop(CameraZoomStop stop, double localZoom) =>
      _zoomDescription?.name == stop.camera &&
      (localZoom - stop.level).abs() < .005;

  static String formatZoom(double factor) {
    final rounded = (factor * 10).round() / 10;
    return '${rounded.toStringAsFixed(rounded == rounded.round() ? 0 : 1)}×';
  }

  double? zoomFactor(double localZoom) {
    final current = _zoomDescription;
    if (current == null || current.name == mainZoomStop?.camera) {
      return localZoom;
    }
    final factor = _rearZoom?.factors[current.name];
    return factor == null ? null : localZoom * factor;
  }

  String zoomLabel(double localZoom) {
    final factor = zoomFactor(localZoom);
    if (factor != null) return formatZoom(factor);
    // A lens without calibration must not show a fake main-relative 1×.
    final name = _lensName(_zoomDescription!.lensType);
    return (localZoom - 1).abs() < .005
        ? name
        : '$name ${formatZoom(localZoom)}';
  }

  bool permissionDenied = false;
  String? error;
  FlashMode flash = FlashMode.off;
  final Map<String, FlashMode> _lensFlash = {};
  final Future<List<CameraDescription>> Function() _discover;
  final Future<RearZoomConfiguration> Function() _readRearZoom;
  final CameraController Function(CameraDescription, int, ResolutionPreset)?
  _create;
  Future<void> _queue = Future.value();
  CameraSession({
    Future<List<CameraDescription>> Function()? discover,
    Future<RearZoomConfiguration> Function()? readRearZoom,
    CameraController Function(CameraDescription, int, ResolutionPreset)? create,
  }) : _discover = discover ?? availableCameras,
       _readRearZoom = readRearZoom ?? _systemRearZoom,
       _create = create {
    WidgetsBinding.instance.addObserver(this);
  }
  static const RearZoomConfiguration _noRearZoom = (
    camera: null,
    mainLevel: 1,
    factors: {},
  );

  static Future<RearZoomConfiguration> _systemRearZoom() async {
    if (!Platform.isIOS) return _noRearZoom;
    final raw = await PandaMedia.call<Map>('rearZoomConfiguration');
    final factors = raw?['factors'];
    final camera = raw?['camera'];
    final mainLevel = raw?['mainLevel'];
    if (factors is! Map || camera is! String || mainLevel is! num) {
      return _noRearZoom;
    }
    return (
      camera: camera,
      mainLevel: mainLevel.toDouble(),
      factors: {
        for (final entry in factors.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toDouble(),
      },
    );
  }

  Future<void> _loadRearZoom() async {
    if (_rearZoom != null) return;
    try {
      final configuration = await _readRearZoom().timeout(
        const Duration(milliseconds: 500),
      );
      _rearZoom = (
        camera: configuration.mainLevel.isFinite && configuration.mainLevel >= 1
            ? configuration.camera
            : null,
        mainLevel: configuration.mainLevel,
        factors: {
          for (final entry in configuration.factors.entries)
            if (entry.value.isFinite && entry.value > 0) entry.key: entry.value,
        },
      );
    } catch (_) {
      // Optional metadata: named physical stops remain available.
      _rearZoom = _noRearZoom;
    }
  }

  Future<void> start() {
    if (!liveRequested && controller == null) _keepLiveSession = false;
    enabled = true;
    permissionDenied = false;
    audioDenied = false;
    return _serialize(_ensureStarted);
  }

  Future<void> _ensureStarted() async {
    if (active &&
        enabled &&
        !closed &&
        controller?.value.isInitialized == true) {
      if (finishLiveOnFocusLoss &&
          liveRequested &&
          liveError == null &&
          controller?.value.isRecordingVideo == false) {
        await _configureStreams();
      }
      return;
    }
    await _start();
  }

  Future<void> _serialize(Future<void> Function() action) {
    _queue = _queue.then((_) => action()).catchError((Object e) {
      error = '相机暂时不可用：$e';
      _notify();
    });
    return _queue;
  }

  void _notify() {
    if (!closed) notifyListeners();
  }

  Future<void> _release() async {
    try {
      await _stopMotion();
    } catch (_) {
      _recordingStart = null;
    }
    await _discardSegments();
    final old = controller;
    controller = null;
    _liveVideoBound = false;
    _nextZoom = null;
    _notify();
    await old?.dispose();
    if (!liveRequested) _keepLiveSession = false;
  }

  Future<void> _start({bool reuseCameraList = false}) async {
    if (liveRequested && usesStableLiveSession) _keepLiveSession = true;
    if (const bool.fromEnvironment('PANDA_TRACE_ROTATION')) {
      debugPrint('CCD_SESSION_START active=$active enabled=$enabled');
    }
    if (!active || closed || !enabled || permissionDenied) return;
    error = null;
    busy = true;
    _notify();
    CameraController? next;
    try {
      await _release();
      if (!active || closed || !enabled) return;
      final preferred = cameras.isNotEmpty ? cameras[lens].name : null;
      if (!reuseCameraList || cameras.isEmpty) {
        cameras = await _discover();
        if (cameras.isEmpty) {
          error = '没有找到摄像头，可导入照片体验 CCD 编辑。';
          return;
        }
        await _loadRearZoom();
        if (!active || closed || !enabled) return;
        final virtualRear = _rearZoom?.camera;
        final physicalMain = _mainRear(cameras);
        if (!_virtualRearUnavailable &&
            virtualRear != null &&
            physicalMain >= 0) {
          final main = cameras[physicalMain];
          cameras = [
            CameraDescription(
              name: virtualRear,
              lensDirection: CameraLensDirection.back,
              sensorOrientation: main.sensorOrientation,
              lensType: CameraLensType.wide,
            ),
            ...cameras,
          ];
        }
      }
      final matched = cameras.indexWhere((item) => item.name == preferred);
      final main = _mainRear(cameras);
      lens = matched >= 0 ? matched : (main >= 0 ? main : 0);
      final camera = cameras[lens];
      flash =
          _lensFlash[camera.name] ??
          (camera.lensDirection == CameraLensDirection.back
              ? FlashMode.always
              : FlashMode.off);
      _configuredFps = fps;
      final resolution = _targetFps == 60
          ? ResolutionPreset.high
          : ResolutionPreset.medium;
      _audioConfigured = liveRequested && liveSoundRequested && !audioDenied;
      next =
          _create?.call(cameras[lens], fps, resolution) ??
          CameraController(
            cameras[lens],
            resolution,
            enableAudio: _audioConfigured,
            fps: fps,
            imageFormatGroup: Platform.isAndroid
                ? ImageFormatGroup.nv21
                : ImageFormatGroup.bgra8888,
          );
      await next.initialize();
      if (!active || closed || !enabled) {
        await next.dispose();
        return;
      }
      controller = next;
      await _configureZoom(next);
      _analysisStreamUnavailable = false;
      await _configureStreams();
      if (liveRequested && _recordingStart == null && _targetFps == 60) {
        _targetFps = 30;
        await _start();
        return;
      }
      try {
        await next.setFlashMode(flash);
      } on CameraException {
        flash = FlashMode.off;
        error = '当前镜头不支持所选闪光模式';
      }
    } on CameraException catch (e) {
      if (identical(controller, next)) controller = null;
      await next?.dispose();
      if (e.code.startsWith('AudioAccess') && !audioDenied) {
        audioDenied = true;
        await _start();
        liveError = '未允许麦克风，当前拍摄无声Live';
        return;
      }
      // Some cameras reject a 60fps capture session instead of negotiating down.
      if (fps == 60 &&
          !e.code.contains('Access') &&
          active &&
          enabled &&
          !closed) {
        _targetFps = 30;
        await _start();
        return;
      }
      if (next != null &&
          _isVirtualRear(next.description) &&
          !e.code.contains('Access') &&
          active &&
          enabled &&
          !closed) {
        _virtualRearUnavailable = true;
        await _start();
        return;
      }
      permissionDenied = e.code.contains('Access');
      error = switch (e.code) {
        'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
          '相机权限未开启。请在系统设置中允许PandaCCD使用相机，再点击重试。',
        'CameraAccessRestricted' => '系统限制了相机访问，请检查设备设置。',
        _ => '相机启动失败（${e.code}），可重试或导入照片。',
      };
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _configureZoom(CameraController c) async {
    _lastZoomCamera = c.description;
    final scale = _nativeZoomScale(c.description);
    minZoom = maxZoom = 1;
    _nativeMinZoom = _nativeMaxZoom = 1;
    var value = 1.0;
    try {
      final min = await c.getMinZoomLevel();
      final max = await c.getMaxZoomLevel();
      if (min.isFinite && max.isFinite && min > 0 && max >= min) {
        final raw = ((_lensZoom[c.description.name] ?? 1) * scale).clamp(
          min,
          max,
        );
        if (raw != 1) await c.setZoomLevel(raw);
        value = raw / scale;
        minZoom = min / scale;
        maxZoom = max / scale;
        _nativeMinZoom = min;
        _nativeMaxZoom = max;
      }
    } catch (_) {
      if (_isVirtualRear(c.description)) {
        throw CameraException('ZoomConfiguration', 'Multi-camera zoom failed');
      }
      // Zoom is optional; an unsupported query must not prevent capture.
      value = 1;
    }
    if (!closed) zoom.value = value;
  }

  Future<void> setZoom(double value) {
    if (!value.isFinite || !canZoom || !active || !enabled || closed || busy) {
      return Future.value();
    }
    final c = controller!;
    final target = value.clamp(minZoom, maxZoom);
    if ((zoom.value - target).abs() < .005) return _queue;
    _nextZoom = target;
    zoom.value = target;
    if (_zoomQueued) return _queue;
    _zoomQueued = true;
    return _serialize(() async {
      final previous = _lensZoom[c.description.name] ?? 1.0;
      try {
        while (_nextZoom != null &&
            identical(controller, c) &&
            active &&
            enabled &&
            !closed) {
          final next = _nextZoom!;
          _nextZoom = null;
          final raw = (next * _nativeZoomScale(c.description)).clamp(
            _nativeMinZoom,
            _nativeMaxZoom,
          );
          final applied = c
              .setZoomLevel(raw)
              .then((_) => true, onError: (Object _) => false);
          if (usesStableLiveSession) {
            // CameraX resolves only after the capture request applies. Send
            // at most one target per preview frame, letting a new target
            // supersede the previous in-flight request during a gesture.
            await Future<void>.delayed(const Duration(milliseconds: 32));
            if (_nextZoom != null) continue;
          }
          if (await applied) {
            _lensZoom[c.description.name] = next;
          } else if (_nextZoom == null && !closed && identical(controller, c)) {
            zoom.value = _lensZoom[c.description.name] ?? previous;
          }
        }
      } finally {
        _nextZoom = null;
        _zoomQueued = false;
      }
    });
  }

  Future<void> switchLens() => _serialize(() async {
    if (cameras.isEmpty) return;
    final index = cameras[lens].lensDirection == CameraLensDirection.front
        ? _mainRear(cameras)
        : cameras.indexWhere(
            (d) => d.lensDirection == CameraLensDirection.front,
          );
    if (index < 0 || index == lens) return;
    lens = index;
    await _start();
  });

  Future<void> selectZoomStop(CameraZoomStop stop) {
    if (controller?.description.name == stop.camera) return setZoom(stop.level);
    return _serialize(() async {
      if (closed || !active || !enabled || busy || controller == null) return;
      final index = cameras.indexWhere((d) => d.name == stop.camera);
      if (index < 0 || index == lens) return;
      _lensZoom[stop.camera] = stop.level;
      lens = index;
      await _start();
    });
  }

  Future<void> setFlash(FlashMode value) => _serialize(() async {
    if (controller == null || !controller!.value.isInitialized) {
      error = '请等待相机就绪后设置闪光灯';
      _notify();
      return;
    }
    if (!supportsFlashControl && value != FlashMode.off) {
      error = '前置镜头不提供硬件闪光';
      _notify();
      return;
    }
    try {
      await controller!.setFlashMode(value);
      flash = value;
      _lensFlash[controller!.description.name] = value;
      error = null;
      // Flash AE/precapture uses a conventional 30fps session instead of a
      // fixed 60fps preview. This is a compatibility measure, not proof of
      // a particular device's missed-flash cause.
      if (_configuredFps != fps) await _start();
    } on CameraException {
      error = '当前镜头不支持此闪光灯模式';
    }
    _notify();
  });
  Future<void> downgrade() => _serialize(() async {
    if (fps == 30 || !active || closed) return;
    _targetFps = 30;
    await _start();
  });
  Future<void> refreshGeometry() => _serialize(() async {
    if (active && enabled && !closed && !permissionDenied) await _start();
  });

  Future<XFile> capture({DeviceOrientation? orientation}) {
    final result = Completer<XFile>();
    unawaited(
      _serialize(() async {
        try {
          if (busy || controller == null || !controller!.value.isInitialized) {
            throw StateError('相机还未就绪');
          }
          busy = true;
          _notify();
          final photo = await _takeStill(orientation);
          result.complete(photo);
        } catch (e, stack) {
          result.completeError(e, stack);
        } finally {
          busy = false;
          _notify();
        }
      }),
    );
    return result.future;
  }

  Future<void> pause() {
    enabled = false;
    return _serialize(_release);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (const bool.fromEnvironment('PANDA_TRACE_ROTATION')) {
      debugPrint('CCD_LIFECYCLE $state');
    }
    active = state == AppLifecycleState.resumed;
    if (!active && finishLiveOnFocusLoss) _finishLiveTail();
    if (active) {
      unawaited(_serialize(_ensureStarted));
    } else if (state == AppLifecycleState.inactive) {
      // Still visible, temporarily without focus: rotation, multi-window,
      // notification shade, and transitions are not a camera shutdown signal.
      // Explicit route/photo-picker pause still releases immediately; hidden,
      // paused, and detached below release as soon as the app is not visible.
    } else {
      unawaited(_serialize(_release));
    }
  }

  @override
  void dispose() {
    closed = true;
    active = false;
    if (finishLiveOnFocusLoss) _finishLiveTail();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_serialize(_release));
    zoom.dispose();
    super.dispose();
  }
}
