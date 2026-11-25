import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Gravity turns camera controls even when system auto-rotate is off.
/// Flat, diagonal and moving positions retain the last stable orientation.
DeviceOrientation? cameraGrip(double x, double y, double z) {
  final energy = x * x + y * y + z * z;
  if (energy < 49 || energy > 169) return null;
  if (x.abs() > 6 && x.abs() > y.abs() * 1.4 && x.abs() > z.abs()) {
    return x > 0
        ? DeviceOrientation.landscapeLeft
        : DeviceOrientation.landscapeRight;
  }
  if (y > 6 && y > x.abs() * 1.4 && y > z.abs()) {
    return DeviceOrientation.portraitUp;
  }
  return null;
}

class CameraOrientation extends ChangeNotifier with WidgetsBindingObserver {
  CameraOrientation({
    Stream<AccelerometerEvent> Function()? samples,
    Future<void> Function(List<DeviceOrientation>)? request,
  }) : _samples =
           samples ??
           (() => accelerometerEventStream(
             samplingPeriod: SensorInterval.uiInterval,
           )),
       _request = request ?? SystemChrome.setPreferredOrientations;

  CameraOrientation.disabled()
    : this(samples: () => const Stream.empty(), request: (_) async {});

  final Stream<AccelerometerEvent> Function() _samples;
  final Future<void> Function(List<DeviceOrientation>) _request;
  StreamSubscription<AccelerometerEvent>? _subscription;
  Timer? _settle;
  DeviceOrientation? orientation, _candidate;
  Future<void> _queue = Future.value();
  bool _closed = false;
  int _generation = 0;
  bool _followGrip = true;
  bool get expanded => !_followGrip;

  /// Expanded displays use the official plugin's canonical UI orientation,
  /// because raw accelerometer axes can describe a landscape-natural display.
  /// Release the compact portrait preference on expanded/letterboxed displays;
  /// The unfolded camera lays out directly in the full OS window.
  void setExpanded(bool expanded) {
    if (_followGrip == !expanded) return;
    _followGrip = !expanded;
    _settle?.cancel();
    orientation = _candidate = null;
    _apply(expanded ? [] : [DeviceOrientation.portraitUp]);
    notifyListeners();
  }

  void start() {
    WidgetsBinding.instance.addObserver(this);
    // Keep the compact camera window stable. Grip changes rotate controls,
    // never the Activity/window or its live texture. Expanded windows remain
    // resizable because Android large displays can ignore orientation locks.
    _apply([DeviceOrientation.portraitUp]);
    _listen();
  }

  void _listen() {
    if (_closed || _subscription != null) return;
    _subscription = _samples().listen(
      (event) {
        if (!_followGrip) return;
        final next = cameraGrip(event.x, event.y, event.z);
        if (const bool.fromEnvironment('PANDA_TRACE_ROTATION') &&
            next != _candidate) {
          debugPrint('CCD_GRIP ${event.x},${event.y},${event.z} -> $next');
        }
        if (next == _candidate) return;
        _settle?.cancel();
        _candidate = next;
        if (next == null || next == orientation) return;
        _settle = Timer(const Duration(milliseconds: 350), () {
          orientation = next;
          notifyListeners();
        });
      },
      onError: (Object _) {
        // Devices without a motion sensor keep normal OS rotation behavior.
        _reset();
      },
    );
  }

  void _apply(List<DeviceOrientation> value) {
    final generation = ++_generation;
    _queue = _queue
        .then((_) async {
          if (generation == _generation) await _request(value);
        })
        .catchError((Object _) {});
  }

  void _reset() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _settle?.cancel();
    orientation = _candidate = null;
    _apply([]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _apply(expanded ? [] : [DeviceOrientation.portraitUp]);
      _listen();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _reset();
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _reset();
    super.dispose();
  }
}
