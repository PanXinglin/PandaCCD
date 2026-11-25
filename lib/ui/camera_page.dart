import 'design_system.dart';
import '../domain/live_capture.dart';
import '../services/face_tracker.dart';
import '../domain/face_region.dart';
import 'beauty_panel.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, mapEquals;
import 'package:camera/camera.dart';
import '../services/photo_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show DeviceOrientation, SystemUiOverlayStyle, HapticFeedback;
import 'camera_stage.dart';
import 'camera_glass.dart';
import 'camera_turn.dart';
import 'camera_viewport.dart';
import 'camera_preview_boundary.dart';
import 'preview_handoff.dart';
import 'capture_feedback.dart';
import 'frame_ratio_picker.dart';
import '../domain/frame_ratio.dart';
import '../services/hardware_shutter.dart';
import '../services/shutter_sound.dart';
import 'preset_picker.dart';
import '../services/app_state.dart';
import '../services/camera_session.dart';
import '../services/live_foreground.dart';
import '../services/camera_orientation.dart';
import 'components.dart';
import 'editor_page.dart';
import 'gallery_page.dart';
import 'settings_page.dart';

class CameraPage extends StatefulWidget {
  final AppState state;
  final bool ready;
  final CameraOrientation? orientation;
  final CameraSession? session;
  final ShutterSound? sound;
  final Future<XFile?> Function()? choosePhoto;
  const CameraPage({
    super.key,
    required this.state,
    this.ready = true,
    this.orientation,
    this.session,
    this.sound,
    this.choosePhoto,
  });
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  late final CameraSession camera;
  late final CameraOrientation orientation;
  late final HardwareShutter hardwareShutter;
  late final ShutterSound sound;
  final faceTracker = FaceTracker();
  ({bool live, bool analysis, bool sound})? _modes;
  String? _facePose;
  List<FaceRegion>? _shaderFaces;
  double? _shaderAspect;
  bool? _shaderMirror;
  ui.FragmentShader? liveShader;
  Map<String, double>? _shaderValues;
  ui.Image? _shaderLut;
  bool cleanView = false, opening = false, onCamera = true;
  bool _beautyPanelOpen = false;
  bool _zoomOpen = false, _pinching = false;
  int _previewPointers = 0;
  double _pinchBase = 1;
  int _lastLiveNoticeRevision = 0;
  int frames = 0, slow = 0;
  DateTime _performanceAfter = DateTime.now().add(const Duration(seconds: 2));
  Timer? _noticeTimer;
  Timer? _surfaceSettle;
  Timer? _liveFaceTimer;
  final _analysisPreviewKey = GlobalKey();
  final _focusMarker = ValueNotifier<Offset?>(null);
  Timer? _focusTimer;
  Size? _surfaceSize;
  final _rotationStill = ValueNotifier<ui.Image?>(null);
  final saveNotice = ValueNotifier<String?>(null);
  final capturePhase = ValueNotifier(CapturePhase.idle);
  final capturedShots = ValueNotifier(0);
  String? _geometry;
  String? _displayPolicyKey;
  bool _expandedDisplay = false;
  final _previewKey = GlobalKey();
  ui.Image? _frozen;
  bool _softenFrozenPreview = false;
  bool _fadeFrozenPreview = false;
  bool _changingLiveMode = false;
  bool _reconfiguring = false;
  AppState get app => widget.state;
  bool get canUseCamera =>
      widget.ready &&
      (widget.session != null || ui.ImageFilter.isShaderFilterSupported);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    camera = widget.session ?? CameraSession();
    if (!widget.ready) camera.enabled = false;
    orientation = widget.orientation ?? CameraOrientation();
    orientation.addListener(_settlePerformance);
    orientation.start();
    sound = widget.sound ?? ShutterSound();
    hardwareShutter = HardwareShutter(
      useNative: ui.ImageFilter.isShaderFilterSupported,
      enabled: () =>
          mounted &&
          widget.ready &&
          app.volumeShutter &&
          onCamera &&
          camera.active &&
          ModalRoute.of(context)?.isCurrent == true,
      canCapture: () =>
          !opening &&
          !_reconfiguring &&
          !camera.busy &&
          camera.controller?.value.isInitialized == true,
      capture: () => unawaited(openPhoto(capture: true)),
    )..start();
    camera.onFrame = (image) {
      final c = camera.controller;
      if (c == null || !app.beautyEnabled || !onCamera || !mounted) return;
      final size = View.of(context).physicalSize;
      final pose = orientation.expanded
          ? cameraWindowOrientation(size, c.value.deviceOrientation)
          : DeviceOrientation.portraitUp;
      final key = '${c.description.name}/${pose.name}';
      if (key != _facePose) {
        _facePose = key;
        faceTracker.clear();
      }
      unawaited(faceTracker.frame(image, c.description, pose));
    };
    _liveFaceTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => unawaited(_sampleLiveFace()),
    );
    faceTracker.addListener(changed);
    _lastLiveNoticeRevision = app.liveNoticeRevision;
    camera.addListener(changed);
    app.addListener(changed);
    SchedulerBinding.instance.addTimingsCallback(timings);
    if (widget.ready) startCamera();
  }

  @override
  void didUpdateWidget(CameraPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.ready && widget.ready) startCamera();
  }

  void startCamera() {
    _modes = _requestedModes;
    camera.liveRequested = app.liveEnabled;
    camera.analysisRequested = app.beautyEnabled;
    camera.liveSoundRequested = app.liveSound;
    if (app.shutterSound && ui.ImageFilter.isShaderFilterSupported) {
      unawaited(sound.prepare());
    }
    if (canUseCamera) unawaited(camera.start());
  }

  ({bool live, bool analysis, bool sound}) get _requestedModes => (
    live: app.liveEnabled,
    analysis: app.beautyEnabled,
    sound: app.liveSound,
  );

  Future<void> _sampleLiveFace() async {
    if (!mounted ||
        !onCamera ||
        !camera.active ||
        !camera.enabled ||
        camera.busy ||
        !app.beautyEnabled ||
        !camera.usesPreviewFaceSnapshots ||
        !ui.ImageFilter.isShaderFilterSupported) {
      return;
    }
    final c = camera.controller;
    if (c == null || !c.value.isInitialized) return;
    final pose = orientation.expanded
        ? cameraWindowOrientation(
            View.of(context).physicalSize,
            c.value.deviceOrientation,
          )
        : DeviceOrientation.portraitUp;
    final key = '${c.description.name}/${pose.name}';
    if (_facePose != key) {
      _facePose = key;
      faceTracker.clear();
    }
    await faceTracker.previewSnapshot(() async {
      final boundary = _analysisPreviewKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary ||
          boundary.debugNeedsPaint ||
          boundary.size.isEmpty) {
        return null;
      }
      final edge = boundary.size.longestSide;
      return boundary.toImage(pixelRatio: (480 / edge).clamp(.01, 1.0));
    }, mirrored: c.description.lensDirection == CameraLensDirection.front);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkGeometry();
    _syncHardwareShutter();
  }

  void _syncHardwareShutter() => hardwareShutter.setActive(
    onCamera &&
        camera.active &&
        app.volumeShutter &&
        (camera.error == null || camera.controller != null) &&
        ModalRoute.of(context)?.isCurrent == true,
  );

  void _settlePerformance() {
    frames = slow = 0;
    _performanceAfter = DateTime.now().add(const Duration(seconds: 1));
  }

  @override
  void didChangeMetrics() {
    final size = View.of(context).physicalSize;
    if (_surfaceSize != null && size != _surfaceSize) _holdSurfaceFrame();
    _surfaceSize = size;
    _settlePerformance();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkGeometry();
    });
  }

  void _checkGeometry() {
    final view = View.of(context);
    final display = view.display;
    _surfaceSize ??= view.physicalSize;
    final policyKey =
        '${display.id}/${display.size.shortestSide.round()}/'
        '${display.size.longestSide.round()}/${display.devicePixelRatio}';
    if (_displayPolicyKey != policyKey) {
      _displayPolicyKey = policyKey;
      _expandedDisplay =
          display.size.shortestSide / display.devicePixelRatio >= 600;
    }
    // Some foldable OEMs letterbox a portrait-locked app even below 600dp.
    // Once observed, release the lock for this physical display; retain that
    // decision after the window fills it to avoid lock/unlock oscillation.
    final fullArea = display.size.width * display.size.height;
    final windowArea = view.physicalSize.width * view.physicalSize.height;
    if (fullArea > 0 && windowArea / fullArea < .85) _expandedDisplay = true;
    orientation.setExpanded(_expandedDisplay);
    // Window, cutout and fold metadata can change during OS rotation. These
    // events update layout; they must not tear down a working camera session.
    String extent(Size size) =>
        '${size.shortestSide.round()}x${size.longestSide.round()}';
    final next =
        '${display.id}/${extent(display.size)}/'
        '${view.devicePixelRatio}/'
        '${view.displayFeatures.map((feature) => '${feature.type}:${feature.state}').join(',')}';
    if (next == _geometry) return;
    if (const bool.fromEnvironment('PANDA_TRACE_ROTATION')) {
      debugPrint(
        'CCD_GEOMETRY $_geometry -> $next; window=${view.physicalSize}',
      );
    }
    _geometry = next;
    // Metrics describe the presentation, not a camera failure. Reopening here
    // discarded a healthy texture and disabled controls during fold/rotation.
    // CameraViewport and the endorsed plugin update their existing geometry.
  }

  void _holdSurfaceFrame() {
    if (orientation.expanded ||
        !onCamera ||
        camera.controller?.value.isInitialized != true ||
        _reconfiguring ||
        !mounted) {
      return;
    }
    // Snapshot the last painted GPU layer before the new window constraints
    // reach the camera texture. No byte readback or per-frame CPU processing.
    if (_rotationStill.value == null) {
      try {
        final boundary = _previewKey.currentContext?.findRenderObject();
        if (boundary is CameraPreviewRenderBoundary) {
          _rotationStill.value = boundary.lastPaintedFrame();
        }
      } catch (_) {
        // Startup or a destroyed surface may not have a painted layer yet.
      }
    }
    _surfaceSettle?.cancel();
    _surfaceSettle = Timer(const Duration(milliseconds: 350), () {
      final previous = _rotationStill.value;
      _rotationStill.value = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
    });
  }

  Future<void> _reconfigure(
    Future<void> Function() action, {
    bool liveTransition = false,
  }) async {
    if (_reconfiguring || !mounted) return;
    _reconfiguring = true;
    _settlePerformance();
    final soften = liveTransition && !MediaQuery.disableAnimationsOf(context);
    _dropFrozenPreview(_frozen);
    try {
      final boundary = _previewKey.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary &&
          !boundary.debugNeedsPaint &&
          camera.controller != null) {
        final pixelRatio = liveTransition
            ? math.min(1.0, 560 / boundary.size.longestSide)
            : 1.0;
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        if (!mounted) {
          image.dispose();
          return;
        }
        _frozen = image;
        _softenFrozenPreview = soften;
      }
    } catch (_) {
      // A surface can disappear before the snapshot during display handoff.
    }
    if (!mounted) return;
    setState(() {});
    try {
      // Paint the held frame before touching a native session that may clear
      // its texture even when the CameraController itself stays alive.
      if (_frozen != null) await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await action();
      if (_frozen != null) {
        if (liveTransition) {
          await _waitForPreviewHandoff();
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    } finally {
      if (mounted) {
        final old = _frozen;
        setState(() {
          _reconfiguring = false;
          _fadeFrozenPreview = soften && old != null;
        });
        if (!_fadeFrozenPreview) _dropFrozenPreview(old);
        _applyCameraModes();
      }
    }
  }

  Future<void> _waitForPreviewHandoff() async {
    final controller = camera.controller;
    if (controller?.value.isInitialized != true) return;
    final rearIos =
        defaultTargetPlatform == TargetPlatform.iOS &&
        controller!.description.lensDirection == CameraLensDirection.back;
    final handoff = PreviewHandoff(stableFrames: rearIos ? 10 : 3);
    final elapsed = Stopwatch()..start();
    var samples = 0;
    var missing = 0;
    var settled = false;
    PreviewStatus? lastStatus;
    while (mounted &&
        camera.active &&
        onCamera &&
        identical(camera.controller, controller) &&
        elapsed.elapsedMilliseconds < (rearIos ? 1200 : 850)) {
      final status = await PreviewHandoff.read(
        controller!.cameraId,
      ).timeout(const Duration(milliseconds: 100), onTimeout: () => null);
      samples++;
      lastStatus = status;
      missing = status == null ? missing + 1 : 0;
      if (handoff.observe(status)) {
        settled = true;
        break;
      }
      if (missing >= 5) break;
      await Future<void>.delayed(const Duration(milliseconds: 36));
    }
    if (!mounted || !camera.active || !onCamera) return;
    // Give Flutter a composited frame after the native texture reports ready.
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(milliseconds: 60),
      onTimeout: () {},
    );
    if (const bool.fromEnvironment('PANDA_TRACE_PREVIEW_HANDOFF')) {
      debugPrint(
        'CCD_HANDOFF settled=$settled samples=$samples '
        'elapsedMs=${elapsed.elapsedMilliseconds} status=$lastStatus',
      );
    }
  }

  void _dropFrozenPreview(ui.Image? image) {
    if (image == null || !identical(_frozen, image)) return;
    setState(() {
      _frozen = null;
      _fadeFrozenPreview = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  void changed() {
    if (mounted && widget.ready) {
      setState(() {});
      _syncHardwareShutter();
      if (_lastLiveNoticeRevision != app.liveNoticeRevision) {
        _lastLiveNoticeRevision = app.liveNoticeRevision;
        if (onCamera) showSaveIssue(app.liveNotice);
      }
      _applyCameraModes();
    }
  }

  void _applyCameraModes() {
    final previous = _modes;
    final mode = _requestedModes;
    if (_reconfiguring || mode == previous || !canUseCamera) return;
    _modes = mode;
    final changesRecording =
        mode.live != previous?.live ||
        (mode.live && mode.sound != previous?.sound);
    final switchingVisibleLive =
        changesRecording &&
        onCamera &&
        camera.active &&
        camera.controller?.value.isInitialized == true;
    Future<void> apply() async {
      if (switchingVisibleLive) _changingLiveMode = true;
      try {
        if (mode.analysis != previous?.analysis) faceTracker.clear();
        await camera.setModes(
          live: mode.live,
          analysis: mode.analysis,
          sound: mode.sound,
        );
      } finally {
        if (switchingVisibleLive && mounted) {
          setState(() => _changingLiveMode = false);
        }
      }
    }

    if (switchingVisibleLive &&
        camera.liveModeMayInterruptPreview(
          live: mode.live,
          sound: mode.sound,
        )) {
      unawaited(_reconfigure(apply, liveTransition: true));
    } else {
      unawaited(apply());
    }
  }

  void timings(List<ui.FrameTiming> batch) {
    if (!onCamera ||
        !camera.active ||
        opening ||
        camera.busy ||
        _reconfiguring ||
        camera.controller == null ||
        camera.fps == 30 ||
        DateTime.now().isBefore(_performanceAfter)) {
      return;
    }
    for (final timing in batch) {
      frames++;
      if (timing.rasterDuration.inMicroseconds > 16667) slow++;
    }
    if (frames >= 180) {
      if (slow / frames > .25 && !_reconfiguring && !opening) {
        unawaited(_reconfigure(camera.downgrade));
      }
      frames = 0;
      slow = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noticeTimer?.cancel();
    _surfaceSettle?.cancel();
    _liveFaceTimer?.cancel();
    _focusTimer?.cancel();
    _focusMarker.dispose();
    _rotationStill.value?.dispose();
    _rotationStill.dispose();
    saveNotice.dispose();
    capturePhase.dispose();
    capturedShots.dispose();
    _frozen?.dispose();
    SchedulerBinding.instance.removeTimingsCallback(timings);
    app.removeListener(changed);
    camera.removeListener(changed);
    camera.onFrame = null;
    faceTracker.removeListener(changed);
    faceTracker.dispose();
    unawaited(hardwareShutter.dispose());
    unawaited(sound.dispose());
    orientation.removeListener(_settlePerformance);
    orientation.dispose();
    camera.dispose();
    liveShader?.dispose();
    super.dispose();
  }

  Future<void> route(Widget page) async {
    onCamera = false;
    _syncHardwareShutter();
    await camera.pause();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    onCamera = true;
    if (mounted && canUseCamera) {
      await camera.start();
    }
  }

  void showSaveIssue(String? message) {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        message == null ||
        message.isEmpty) {
      return;
    }
    saveNotice.value = message;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) saveNotice.value = null;
    });
  }

  Future<void> saveInBackground(XFile file, LiveSource? source) async {
    try {
      showSaveIssue(await app.saveCaptureFile(file, liveSource: source));
    } catch (_) {
      showSaveIssue('照片未保存，可在相册重试');
    }
  }

  Future<void> openPhoto({bool capture = false, bool demo = false}) async {
    if (opening || _reconfiguring) return;
    setState(() => opening = true);
    if (capture) {
      capturePhase.value = CapturePhase.capturing;
      unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    }
    try {
      Uint8List bytes;
      LiveSource? motion;
      if (demo) {
        bytes = await makeDemo();
      } else if (capture) {
        void exposed() {
          if (!mounted) return;
          capturedShots.value++;
          if (app.shutterSound &&
              (ui.ImageFilter.isShaderFilterSupported ||
                  widget.sound != null)) {
            unawaited(sound.play());
          }
          capturePhase.value = app.directSave
              ? CapturePhase.saving
              : CapturePhase.idle;
        }

        final XFile file;
        if (app.liveEnabled) {
          final lease = await LiveFinishLease.begin();
          final LiveShot shot;
          try {
            shot = await camera.captureLive(
              orientation: orientation.orientation,
              onExposed: exposed,
            );
          } finally {
            if (lease != null) unawaited(lease.end());
          }
          file = shot.photo;
          motion = shot.source;
          if (mounted) showSaveIssue(shot.warning);
        } else {
          file = await camera.capture(orientation: orientation.orientation);
          exposed();
        }
        if (!mounted) {
          await motion?.dispose();
          return;
        }
        // Paint the exposure acknowledgement before starting full-size export.
        if (camera.active &&
            !(app.liveEnabled && camera.finishLiveOnFocusLoss)) {
          await SchedulerBinding.instance.endOfFrame;
        }
        if (!mounted) {
          await motion?.dispose();
          return;
        }
        if (app.directSave) {
          unawaited(saveInBackground(file, motion));
          return;
        }
        bytes = await file.readAsBytes();
      } else {
        onCamera = false;
        _syncHardwareShutter();
        await camera.pause();
        final file =
            await (widget.choosePhoto?.call() ?? chooseImportedPhoto());
        if (file == null) {
          onCamera = true;
          if (canUseCamera) {
            await camera.start();
          }
          return;
        }
        bytes = await file.readAsBytes();
      }
      if (!mounted) return;
      await route(
        EditorPage(
          state: app,
          bytes: bytes,
          isDemo: demo,
          liveSource: motion,
          ownsLiveSource: motion != null,
        ),
      );
    } catch (_) {
      showSaveIssue(capture ? '拍摄失败，请重试' : '无法打开照片');
    } finally {
      if (!onCamera && mounted) {
        onCamera = true;
        if (canUseCamera) {
          await camera.start();
        }
      }
      if (mounted) {
        capturePhase.value = CapturePhase.idle;
        setState(() => opening = false);
      }
    }
  }

  Widget preview() => Stack(
    fit: StackFit.expand,
    children: [
      CameraPreviewBoundary(key: _previewKey, child: livePreview()),
      Positioned.fill(
        child: ValueListenableBuilder<ui.Image?>(
          valueListenable: _rotationStill,
          builder: (context, image, _) => image == null
              ? const SizedBox.shrink()
              : IgnorePointer(
                  child: RawImage(
                    key: const ValueKey('ccd-rotation-still'),
                    image: image,
                    fit: BoxFit.contain,
                  ),
                ),
        ),
      ),
      if (_frozen case final image?) frozenPreview(image),
      Positioned.fill(
        key: const ValueKey('ccd-shutter-feedback-layer'),
        child: ShutterPulse(shots: capturedShots),
      ),
    ],
  );

  Widget frozenPreview(ui.Image image) {
    final still = ColoredBox(
      color: CameraGlass.backdrop,
      child: RawImage(
        key: const ValueKey('ccd-frozen-preview'),
        image: image,
        fit: BoxFit.contain,
      ),
    );
    return Positioned.fill(
      child: IgnorePointer(
        child: !_softenFrozenPreview
            ? still
            : AnimatedOpacity(
                key: ObjectKey(image),
                opacity: _fadeFrozenPreview ? 0 : 1,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                onEnd: () {
                  if (_fadeFrozenPreview) _dropFrozenPreview(image);
                },
                child: ClipRect(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 7),
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeOut,
                    child: still,
                    builder: (_, sigma, child) => ImageFiltered(
                      enabled: sigma > 0,
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: sigma,
                        sigmaY: sigma,
                        tileMode: TileMode.clamp,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  void _tapToFocus(TapUpDetails tap, Size frame, DeviceOrientation window) {
    final controller = camera.controller;
    final texture = _analysisPreviewKey.currentContext?.findRenderObject();
    if (opening ||
        _reconfiguring ||
        camera.busy ||
        !camera.active ||
        controller == null ||
        texture is! RenderBox ||
        !texture.hasSize ||
        texture.size.isEmpty ||
        frame.isEmpty) {
      return;
    }
    final value = controller.value;
    if (!value.focusPointSupported && !value.exposurePointSupported) return;
    final hit = texture.globalToLocal(tap.globalPosition);
    if (!(Offset.zero & texture.size).contains(hit)) return;
    var point = Offset(
      hit.dx / texture.size.width,
      hit.dy / texture.size.height,
    );
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      point = portraitMeteringPoint(
        point,
        window,
        mirrored:
            controller.description.lensDirection == CameraLensDirection.front,
      );
    }
    _focusMarker.value = Offset(
      tap.localPosition.dx / frame.width,
      tap.localPosition.dy / frame.height,
    );
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 850), () {
      _focusMarker.value = null;
    });
    unawaited(camera.focusAt(point));
  }

  Widget livePreview() {
    if (!widget.ready) {
      return const ColoredBox(color: CameraGlass.backdrop);
    }
    final controller = camera.controller;
    if (ui.ImageFilter.isShaderFilterSupported &&
        controller != null &&
        controller.value.isInitialized) {
      final values = app.parameters;
      final lut = app.lut;
      return ValueListenableBuilder<CameraValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          // Match the orientation used by CameraPreview itself. Window orientation
          // can differ from sensor orientation on a foldable or in split screen.
          final window =
              CameraViewportScope.maybeOf(context)?.window ??
              cameraWindowOrientation(
                MediaQuery.sizeOf(context),
                value.deviceOrientation,
              );
          final orientation = cameraWindowOrientation(
            MediaQuery.sizeOf(context),
            value.deviceOrientation,
          );
          final landscape =
              orientation == DeviceOrientation.landscapeLeft ||
              orientation == DeviceOrientation.landscapeRight;
          final sourceAspect = landscape
              ? value.aspectRatio
              : 1 / value.aspectRatio;
          final targetAspect = app.frameAspect == null
              ? sourceAspect
              : (landscape ? app.frameAspect! : 1 / app.frameAspect!);
          final mirror =
              controller.description.lensDirection == CameraLensDirection.front;
          if (liveShader == null ||
              !mapEquals(values, _shaderValues) ||
              _shaderLut != lut.image ||
              !identical(_shaderFaces, faceTracker.faces) ||
              _shaderAspect != targetAspect ||
              _shaderMirror != mirror) {
            final old = liveShader;
            final faces = faceTracker.faces
                .map(
                  (face) => (mirror ? face.mirrored() : face).cropped(
                    sourceAspect,
                    targetAspect,
                  ),
                )
                .toList();
            liveShader = app.engine.shader(
              values,
              lut,
              faces: faces,
              imageFilter: true,
              trackFace: true,
            );
            _shaderValues = Map.of(values);
            _shaderLut = lut.image;
            _shaderFaces = faceTracker.faces;
            _shaderAspect = targetAspect;
            _shaderMirror = mirror;
            WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
          }
          return CameraStage(
            aspectRatio: app.frameAspect == null
                ? (landscape ? value.aspectRatio : 1 / value.aspectRatio)
                : (landscape ? app.frameAspect! : 1 / app.frameAspect!),
            overlay: LayoutBuilder(
              builder: (context, bounds) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (tap) => _tapToFocus(tap, bounds.biggest, window),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    StampOverlay(
                      stamp: app.watermark,
                      date: DateTime.now(),
                      model: app.preset.stampLabel,
                    ),
                    const IgnorePointer(
                      child: CustomPaint(painter: _FramePainter()),
                    ),
                    ValueListenableBuilder<Offset?>(
                      valueListenable: _focusMarker,
                      builder: (_, point, _) => point == null
                          ? const SizedBox.shrink()
                          : CustomPaint(painter: _FocusPainter(point)),
                    ),
                  ],
                ),
              ),
            ),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.shader(liveShader!),
              // CameraPreview has its own asynchronous orientation listener.
              // Give it one bounded axis, so it can choose its intrinsic aspect
              // ratio; a temporary disagreement with the outer frame is fitted,
              // never forced into tight width AND height (which squashes it).
              child: ClipRect(
                child: CameraTextureFit(
                  fit: app.frameAspect == null ? BoxFit.contain : BoxFit.cover,
                  child: RepaintBoundary(
                    key: _analysisPreviewKey,
                    child: StableCameraPreview(
                      controller: controller,
                      window: window,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    if (ui.ImageFilter.isShaderFilterSupported && camera.error == null) {
      return const ColoredBox(
        color: CameraGlass.backdrop,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white38,
            ),
          ),
        ),
      );
    }
    return CameraStage(
      aspectRatio: 3 / 4,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff272d35), Color(0xff171a20)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 80, 28, 150),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    camera.busy
                        ? '正在打开取景器…'
                        : !ui.ImageFilter.isShaderFilterSupported
                        ? '当前渲染器不支持实时 GPU 滤镜'
                        : camera.error ?? '相机暂时不可用',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: CameraGlass.foreground,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                  if (!camera.busy) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => openPhoto(),
                      child: const Text('从相册导入'),
                    ),
                    if (ui.ImageFilter.isShaderFilterSupported)
                      TextButton(
                        onPressed: () => camera.start(),
                        child: const Text('重试相机'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> showParameters() async {
    await PandaDesign.sheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => SizedBox(
        key: const ValueKey('ccd-parameter-sheet'),
        height: MediaQuery.sizeOf(context).height * .65,
        child: AnimatedBuilder(
          animation: app,
          builder: (context, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '调一调 · ${app.preset.name}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(onPressed: app.reset, child: const Text('重置')),
                    IconButton(
                      tooltip: '关闭参数',
                      onPressed: () => Navigator.pop(context),
                      icon: turn(const Icon(Icons.close)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: ParameterPanel(
                    values: app.parameters,
                    onChanged: app.update,
                  ),
                ),
              ),
              const SafeArea(top: false, child: SizedBox(height: 12)),
            ],
          ),
        ),
      ),
    );
    if (mounted) await guarded(context, app.persist);
  }

  Widget turn(Widget child) => CameraTurn(
    orientation: orientation,
    controller: camera.controller,
    child: child,
  );

  Widget shutter() => Semantics(
    label: '拍照',
    button: true,
    child: GestureDetector(
      key: const ValueKey('ccd-shutter'),
      onTap:
          opening ||
              _reconfiguring ||
              camera.busy ||
              camera.controller?.value.isInitialized != true
          ? null
          : () => openPhoto(capture: true),
      child: Container(
        width: 76,
        height: 76,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: CameraGlass.foreground, width: 2),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CameraGlass.foreground.withValues(
              alpha: camera.controller == null && !_changingLiveMode ? .4 : .96,
            ),
          ),
          child: CaptureButtonFace(
            phase: capturePhase,
            color: CameraGlass.backdrop,
          ),
        ),
      ),
    ),
  );

  Future<void> showPresetPicker() => PandaDesign.sheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: PresetPicker(
        selected: app.selected,
        onSelect: (index) {
          app.select(index);
          Navigator.pop(context);
        },
      ),
    ),
  );

  Widget brandSelector() => Tooltip(
    message: '选择机型',
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: showPresetPicker,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              const PandaMark(size: 28),
              const SizedBox(width: 3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'PandaCCD',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CameraGlass.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      app.preset.compactName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CameraGlass.secondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.expand_more,
                size: 13,
                color: CameraGlass.foreground,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget toolbarButton({
    Key? key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool active = false,
  }) => SizedBox.square(
    key: key,
    dimension: 44,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        foregroundColor: active
            ? const Color(0xfff8dca2)
            : CameraGlass.foreground,
        disabledForegroundColor: CameraGlass.secondary,
      ),
      icon: turn(
        Icon(
          icon,
          size: 22,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 5)],
        ),
      ),
    ),
  );

  Widget toolbar() => Row(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 126),
            child: CameraGlass(radius: 18, child: brandSelector()),
          ),
        ),
      ),
      toolbarButton(
        key: const ValueKey('ccd-live-toggle'),
        label: app.liveEnabled ? '关闭动态照片' : '开启动态照片',
        icon: app.liveEnabled
            ? Icons.motion_photos_on
            : Icons.motion_photos_off,
        active: app.liveEnabled,
        onPressed: opening || camera.busy || _reconfiguring
            ? null
            : () => app.setLiveEnabled(!app.liveEnabled),
      ),
      if (camera.supportsFlashControl)
        Semantics(
          value: switch (camera.flash) {
            FlashMode.auto => '自动',
            FlashMode.off => '关闭',
            _ => '开启',
          },
          child: toolbarButton(
            key: const ValueKey('ccd-flash-cycle'),
            label: '闪光灯',
            icon: switch (camera.flash) {
              FlashMode.auto => Icons.flash_auto,
              FlashMode.off => Icons.flash_off,
              _ => Icons.flash_on,
            },
            active: camera.flash == FlashMode.always,
            onPressed: camera.busy || _reconfiguring || opening
                ? null
                : () async {
                    final next = switch (camera.flash) {
                      FlashMode.off => FlashMode.auto,
                      FlashMode.auto => FlashMode.always,
                      _ => FlashMode.off,
                    };
                    if (camera.flashRequiresRestart(next)) {
                      await _reconfigure(() => camera.setFlash(next));
                    } else {
                      await camera.setFlash(next);
                    }
                    if (mounted && camera.error != null) {
                      toast(context, camera.error!);
                    }
                  },
          ),
        ),
      toolbarButton(
        label: cleanView ? '显示机型栏' : '纯净取景',
        icon: cleanView ? Icons.fullscreen_exit : Icons.fullscreen,
        onPressed: () {
          final saveBeauty = _beautyPanelOpen;
          setState(() {
            cleanView = !cleanView;
            _beautyPanelOpen = false;
          });
          if (saveBeauty) unawaited(app.persist());
        },
      ),
      toolbarButton(
        label: '导入照片',
        icon: Icons.add_photo_alternate_outlined,
        onPressed: () => openPhoto(),
      ),
      toolbarButton(
        label: '设置',
        icon: Icons.settings_outlined,
        onPressed: () => route(SettingsPage(state: app)),
      ),
    ],
  );

  Future<void> showBeauty() async {
    setState(() {
      _beautyPanelOpen = !_beautyPanelOpen;
      cleanView = false;
    });
    if (!_beautyPanelOpen) await app.persist();
  }

  Widget beautyDock() => BeautyPanel(
    values: app.parameters,
    status:
        faceTracker.error ??
        (faceTracker.faces.any((face) => face.lowerJaw.isNotEmpty)
            ? '已识别下颌 · 实时预览'
            : '请正对镜头，让下颌完整入镜'),
    onEnabled: (enabled) {
      if (enabled != app.beautyEnabled) app.toggleBeauty();
    },
    onChanged: (key, value) {
      if (key != 'beauty' && !app.beautyEnabled) app.toggleBeauty();
      app.update(key, value);
    },
    onClose: showBeauty,
    onReset: () {
      for (final e in {
        'beautySmooth': .7,
        'beautyEven': .45,
        'beautyWhiten': .3,
        'faceSlim': .25,
        'beauty': .55,
      }.entries) {
        app.update(e.key, e.value);
      }
    },
  );

  Widget beautyButton() => CameraGlass(
    key: const ValueKey('ccd-beauty-toggle'),
    child: SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: '美颜',
        onPressed: showBeauty,
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: app.beautyEnabled || _beautyPanelOpen
              ? CameraGlass.selection
              : Colors.transparent,
          foregroundColor: CameraGlass.foreground,
        ),
        icon: turn(
          Icon(
            app.beautyEnabled
                ? Icons.face_retouching_natural
                : Icons.face_retouching_off,
            size: 20,
          ),
        ),
      ),
    ),
  );

  Widget frameRatioButton() => CameraGlass(
    key: const ValueKey('ccd-frame-ratio-chip'),
    child: SizedBox(
      width: 44,
      height: 44,
      child: TextButton(
        onPressed: opening || _reconfiguring
            ? null
            : () => showFrameRatioPicker(
                context,
                app.frameAspect,
                app.setFrameAspect,
              ),
        style: TextButton.styleFrom(
          foregroundColor: CameraGlass.foreground,
          disabledForegroundColor: CameraGlass.secondary,
          padding: const EdgeInsets.symmetric(horizontal: 5),
        ),
        child: Tooltip(
          message: '画幅比例',
          child: turn(
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                frameRatioLabel(app.frameAspect),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget quickControls() => Row(
    key: const ValueKey('ccd-quick-controls'),
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!cleanView) frameRatioButton(),
      if (camera.hasZoomControls) ...[
        if (!cleanView) const SizedBox(width: 6),
        Flexible(child: zoomControl()),
      ],
      if (!cleanView) ...[const SizedBox(width: 6), beautyButton()],
    ],
  );

  Widget cameraControls({required bool rail, required double bottomInset}) {
    final controls = Padding(
      padding: EdgeInsets.fromLTRB(4, rail ? 8 : 18, 4, 2 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _beautyPanelOpen ? 136 : 0,
            child: Offstage(offstage: !_beautyPanelOpen, child: beautyDock()),
          ),
          Offstage(
            offstage: !rail || _beautyPanelOpen,
            child: SizedBox(
              key: rail ? const ValueKey('ccd-control-rail') : null,
              height: 48,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text(
                    '机型',
                    style: TextStyle(
                      color: CameraGlass.foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            fit: rail && _beautyPanelOpen ? FlexFit.tight : FlexFit.loose,
            child: Offstage(
              offstage: _beautyPanelOpen,
              child: Row(
                children: [
                  Expanded(
                    child: RepaintBoundary(
                      key: const ValueKey('ccd-preset-strip-layer'),
                      child: CompactPresetStrip(
                        selected: app.selected,
                        onSelect: app.select,
                        vertical: rail,
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: rail,
                    child: IconButton(
                      tooltip: '调一调',
                      color: CameraGlass.foreground,
                      onPressed: showParameters,
                      icon: turn(const Icon(Icons.tune, size: 22)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Offstage(
            offstage: !rail || _beautyPanelOpen,
            child: Tooltip(
              message: '调一调',
              child: TextButton.icon(
                onPressed: showParameters,
                style: TextButton.styleFrom(
                  foregroundColor: CameraGlass.foreground,
                ),
                icon: turn(const Icon(Icons.tune, size: 18)),
                label: const Text('调一调'),
              ),
            ),
          ),
          controlActions(rail: rail),
        ],
      ),
    );
    return CameraGlass(
      key: const ValueKey('ccd-floating-dock'),
      radius: 0,
      panel: true,
      border: false,
      edgeFade: !rail,
      child: controls,
    );
  }

  Widget controlActions({required bool rail}) => LayoutBuilder(
    builder: (context, bounds) {
      final actionStyle =
          IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: CameraGlass.foreground,
            disabledForegroundColor: CameraGlass.secondary,
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.pressed) ||
                      states.contains(WidgetState.focused)
                  ? Colors.white24
                  : Colors.transparent,
            ),
          );
      return SizedBox(
        height: rail ? 132 : 88,
        child: Stack(
          children: [
            Positioned(
              left: rail ? 8 : 16,
              bottom: rail ? 0 : 20,
              child: IconButton(
                tooltip: '相册',
                style: actionStyle,
                onPressed: () => route(GalleryPage(state: app)),
                icon: turn(const Icon(Icons.photo_library_outlined, size: 25)),
              ),
            ),
            Positioned(
              left: (bounds.maxWidth - 76) / 2,
              top: rail ? 0 : 6,
              child: shutter(),
            ),
            Positioned(
              right: rail ? 8 : 16,
              bottom: rail ? 0 : 20,
              child: IconButton(
                tooltip: '切换前后镜头',
                style: actionStyle,
                onPressed:
                    _reconfiguring || camera.busy || camera.cameras.length < 2
                    ? null
                    : () => _reconfigure(camera.switchLens),
                icon: turn(const Icon(Icons.sync_rounded, size: 25)),
              ),
            ),
          ],
        ),
      );
    },
  );

  void _selectZoomStop(CameraZoomStop stop) {
    if (camera.controller?.description.name == stop.camera) {
      unawaited(camera.selectZoomStop(stop));
    } else {
      unawaited(_reconfigure(() => camera.selectZoomStop(stop)));
    }
  }

  Widget zoomControl() => ValueListenableBuilder<double>(
    valueListenable: camera.zoom,
    builder: (context, zoom, _) {
      final enabled =
          camera.controller != null &&
          !opening &&
          !_reconfiguring &&
          !camera.busy;
      final label = camera.zoomLabel(zoom);
      final stops = camera.zoomStops;
      if (stops.isEmpty) return const SizedBox.shrink();
      final main = camera.mainZoomStop;
      final precise = _zoomOpen && camera.canZoom;
      final factor = camera.zoomFactor(zoom);
      final selectedStop =
          stops.where((stop) {
            if (factor == null) {
              return stop.camera == camera.controller?.description.name;
            }
            return stop.factor != null && stop.factor! <= factor + .000001;
          }).lastOrNull ??
          stops.firstOrNull;
      final highlightDuration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 140);
      void toggleSlider() => setState(() => _zoomOpen = !_zoomOpen);
      void openSlider() => setState(() => _zoomOpen = true);
      double level(double value) =>
          math.exp(value).clamp(camera.minZoom, camera.maxZoom);

      Widget chip(
        String text, {
        Key? key,
        required String description,
        bool selected = false,
        bool drawSelection = true,
        VoidCallback? onTap,
        VoidCallback? onHold,
      }) => Tooltip(
        message: description,
        // Long-press on an unselected step is reserved for precise zoom.
        triggerMode: TooltipTriggerMode.manual,
        child: Semantics(
          selected: selected,
          child: AnimatedContainer(
            duration: highlightDuration,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected && drawSelection
                  ? CameraGlass.selection
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextButton(
              key: key,
              onPressed: enabled ? onTap : null,
              onLongPress: enabled ? onHold : null,
              style: TextButton.styleFrom(
                foregroundColor: CameraGlass.foreground,
                disabledForegroundColor: CameraGlass.foreground,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: turn(
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    text,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Widget stepChip(CameraZoomStop stop, double width) {
        final selected = stop == selectedStop;
        final atStop = selected && camera.isAtZoomStop(stop, zoom);
        final fixedLabel = stop.factor == null
            ? stop.name
            : CameraSession.formatZoom(stop.factor!);
        return SizedBox(
          key: ValueKey((stop.camera, stop.level)),
          width: width,
          child: chip(
            selected ? label : fixedLabel,
            key: atStop
                ? const ValueKey('ccd-zoom-toggle')
                : stop == main
                ? const ValueKey('ccd-zoom-main')
                : null,
            description: atStop
                ? '${stop.name}，点按微调倍率'
                : '${stop.name}，回到 $fixedLabel',
            selected: selected,
            drawSelection: false,
            onTap: atStop && camera.canZoom
                ? toggleSlider
                : () => _selectZoomStop(stop),
            onHold: camera.canZoom ? openSlider : null,
          ),
        );
      }

      return MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: CameraGlass(
          key: const ValueKey('ccd-zoom-bar'),
          child: SizedBox(
            height: 44,
            child: precise
                ? SizedBox(
                    width: 216,
                    child: Row(
                      children: [
                        chip(
                          label,
                          key: const ValueKey('ccd-zoom-toggle'),
                          description: '收起缩放滑杆',
                          selected: true,
                          onTap: toggleSlider,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: const SliderThemeData(
                              activeTrackColor: CameraGlass.foreground,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: CameraGlass.foreground,
                            ),
                            child: Slider(
                              key: const ValueKey('ccd-zoom-slider'),
                              min: math.log(camera.minZoom),
                              max: math.log(camera.maxZoom),
                              value: math.log(
                                zoom.clamp(camera.minZoom, camera.maxZoom),
                              ),
                              semanticFormatterCallback: (value) =>
                                  camera.zoomLabel(level(value)),
                              onChanged: enabled
                                  ? (value) =>
                                        unawaited(camera.setZoom(level(value)))
                                  : null,
                            ),
                          ),
                        ),
                        if (main != null)
                          chip(
                            '1×',
                            key: const ValueKey('ccd-zoom-main'),
                            description: '回到 1× ${main.name}',
                            onTap: () {
                              setState(() => _zoomOpen = false);
                              _selectZoomStop(main);
                            },
                          ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, bounds) {
                      final width = math.min(
                        44.0,
                        bounds.maxWidth / stops.length,
                      );
                      final selectedIndex = stops.indexOf(
                        selectedStop ?? stops.first,
                      );
                      return SizedBox(
                        width: width * stops.length,
                        child: Stack(
                          children: [
                            PositionedDirectional(
                              start: 0,
                              top: 0,
                              bottom: 0,
                              width: width,
                              child: AnimatedSlide(
                                key: const ValueKey('ccd-zoom-selection'),
                                duration: highlightDuration,
                                curve: Curves.easeOutCubic,
                                offset: Offset(
                                  Directionality.of(context) ==
                                          TextDirection.rtl
                                      ? -selectedIndex.toDouble()
                                      : selectedIndex.toDouble(),
                                  0,
                                ),
                                child: const IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: CameraGlass.selection,
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(24),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final stop in stops) stepChip(stop, width),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      );
    },
  );

  Widget canvas({required bool dock, required double bottomInset}) => Stack(
    fit: StackFit.expand,
    children: [
      Listener(
        onPointerDown: (_) => _pinching = ++_previewPointers > 1,
        onPointerUp: (_) => _previewPointers--,
        onPointerCancel: (_) => _previewPointers--,
        child: GestureDetector(
          onScaleStart: (_) => _pinchBase = camera.zoom.value,
          onScaleUpdate: (details) {
            if (details.pointerCount < 2) return;
            _pinching = true;
            if (!opening && !_reconfiguring) {
              unawaited(camera.setZoom(_pinchBase * details.scale));
            }
          },
          onScaleEnd: (details) {
            final velocity = details.velocity.pixelsPerSecond;
            if (!_pinching &&
                velocity.dx.abs() > 80 &&
                velocity.dx.abs() > velocity.dy.abs()) {
              app.select(app.selected + (velocity.dx < 0 ? 1 : -1));
            }
          },
          child: preview(),
        ),
      ),
      const Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 100,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        key: const ValueKey('ccd-camera-toolbar'),
        top: 8,
        left: 8,
        right: 8,
        child: toolbar(),
      ),
      // Keep a permanent, fixed-size notification layer. Updating or clearing
      // a message must not relayout/repaint the model strip below it.
      Positioned(
        key: const ValueKey('ccd-save-notice'),
        top: 100,
        left: 16,
        right: 16,
        height: 72,
        child: RepaintBoundary(
          child: IgnorePointer(
            child: ValueListenableBuilder<String?>(
              valueListenable: saveNotice,
              builder: (context, message, _) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: Semantics(
                    liveRegion: message != null,
                    child: Text(
                      message ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CameraGlass.foreground,
                        backgroundColor: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      if (app.liveEnabled && camera.liveError != null)
        Positioned(
          top: 124,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Text(
              camera.liveError!,
              style: const TextStyle(
                color: CameraGlass.foreground,
                backgroundColor: Colors.black54,
                fontSize: 11,
              ),
            ),
          ),
        ),
      if (camera.controller != null && camera.error != null)
        Positioned(
          key: const ValueKey('ccd-camera-error'),
          top: 72,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black54,
              child: Text(
                camera.error!,
                style: const TextStyle(
                  color: CameraGlass.foreground,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      if (!dock || _beautyPanelOpen)
        Positioned(
          left: 10,
          right: 10,
          bottom: 8 + bottomInset,
          child: Center(child: quickControls()),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: PopScope(
      canPop: !_beautyPanelOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _beautyPanelOpen) unawaited(showBeauty());
      },
      child: Scaffold(
        backgroundColor: CameraGlass.backdrop,
        body: IgnorePointer(
          ignoring: !widget.ready,
          child: CameraViewport(
            orientation: orientation,
            controller: camera.controller,
            child: SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final logicalWindow = MediaQuery.sizeOf(context);
                  final rail = usesCameraRail(logicalWindow) && !cleanView;
                  final bottomInset = MediaQuery.paddingOf(context).bottom;
                  final railWidth = bounds.maxHeight < 500 ? 172.0 : 220.0;
                  return BackdropGroup(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned(
                          key: const ValueKey('ccd-camera-canvas'),
                          top: 0,
                          bottom: _beautyPanelOpen && !rail
                              ? 252 + bottomInset
                              : 0,
                          left: 0,
                          right: rail ? railWidth + 24 : 0,
                          child: canvas(
                            dock: !rail,
                            bottomInset: rail ? bottomInset : 0,
                          ),
                        ),
                        Positioned(
                          key: const ValueKey('ccd-camera-dock'),
                          top: rail ? 8 : null,
                          bottom: rail || cleanView ? bottomInset : 0,
                          left: rail ? bounds.maxWidth - railWidth - 8 : 0,
                          right: 0,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!rail &&
                                  !_beautyPanelOpen &&
                                  (!cleanView || camera.hasZoomControls))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: quickControls(),
                                ),
                              Flexible(
                                child: cleanView
                                    ? controlActions(rail: false)
                                    : cameraControls(
                                        rail: rail,
                                        bottomInset: rail ? 0 : bottomInset,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _FocusPainter extends CustomPainter {
  const _FocusPainter(this.point);
  final Offset point;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(point.dx * size.width, point.dy * size.height),
      width: 52,
      height: 52,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..color = const Color(0xffffd083),
    );
  }

  @override
  bool shouldRepaint(_FocusPainter oldDelegate) => point != oldDelegate.point;
}

class _FramePainter extends CustomPainter {
  const _FramePainter();
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = Colors.white38
      ..strokeWidth = .5;
    for (final f in [1 / 3, 2 / 3]) {
      c.drawLine(Offset(s.width * f, 0), Offset(s.width * f, s.height), p);
      c.drawLine(Offset(0, s.height * f), Offset(s.width, s.height * f), p);
    }
    p
      ..strokeWidth = 1.5
      ..color = Colors.white70;
    final r = Rect.fromCenter(
      center: Offset(s.width / 2, s.height / 2),
      width: 46,
      height: 46,
    );
    for (final o in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      c.drawLine(o, o + Offset(o.dx < s.width / 2 ? 10 : -10, 0), p);
      c.drawLine(o, o + Offset(0, o.dy < s.height / 2 ? 10 : -10), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<Uint8List> makeDemo() async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  const size = Size(900, 1200);
  c.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 1200), [
        const Color(0xff96c4d5),
        const Color(0xfff9e7ba),
      ]),
  );
  c.drawCircle(
    const Offset(680, 290),
    95,
    Paint()..color = const Color(0xffffe8ad),
  );
  for (var i = 0; i < 4; i++) {
    final path = Path()
      ..moveTo(-80, 750 + i * 90.0)
      ..quadraticBezierTo(260, 250 + i * 170.0, 980, 660 + i * 100.0)
      ..lineTo(980, 1200)
      ..lineTo(-80, 1200)
      ..close();
    c.drawPath(
      path,
      Paint()
        ..color = [
          const Color(0xff8ba89a),
          const Color(0xff6c9187),
          const Color(0xff497365),
          const Color(0xff315447),
        ][i],
    );
  }
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(150, 660, 225, 220),
      const Radius.circular(4),
    ),
    Paint()..color = const Color(0xfff4dfb8),
  );
  c.drawPath(
    Path()
      ..moveTo(125, 670)
      ..lineTo(260, 555)
      ..lineTo(400, 670)
      ..close(),
    Paint()..color = const Color(0xffb36c54),
  );
  c.drawRect(const Rect.fromLTWH(235, 750, 50, 130), Paint()..color = ink);
  c.drawRect(
    const Rect.fromLTWH(170, 710, 38, 46),
    Paint()..color = const Color(0xff91aeb0),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(900, 1200);
  picture.dispose();
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
