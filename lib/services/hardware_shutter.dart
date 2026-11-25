import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vol_spotter/vol_spotter.dart';

/// Physical events are supplied by a cross-platform plugin. Flutter keyboard
/// events remain a fallback for devices/external keyboards which forward them.
class HardwareShutter with WidgetsBindingObserver {
  final bool Function() enabled;
  final bool Function() canCapture;
  final VoidCallback capture;
  final bool useNative;
  final Set<LogicalKeyboardKey> _held = {};
  final _plugin = const VolSpotter();
  StreamSubscription<ButtonEvent>? _subscription;
  Future<void> _nativeQueue = Future.value();
  final Map<LogicalKeyboardKey, Timer> _quietTimers = {};
  bool _started = false, _closed = false, _wanted = false, _listening = false;
  HardwareShutter({
    required this.enabled,
    required this.canCapture,
    required this.capture,
    this.useNative = false,
  });
  void start() {
    if (_started) return;
    _started = true;
    HardwareKeyboard.instance.addHandler(handle);
    WidgetsBinding.instance.addObserver(this);
  }

  void setActive(bool active) {
    if (active == _wanted) return;
    _wanted = active;
    if (!useNative) return;
    _nativeQueue = _nativeQueue
        .then((_) async {
          if (_wanted && !_closed && !_listening) {
            _subscription ??= _plugin.buttonEvents.listen(
              handleNative,
              onError: (Object _) {},
            );
            await _plugin.startListening(
              config: const VolSpotterConfig(interceptVolumeEvents: true),
            );
            _listening = true;
          } else if (!_wanted && _listening) {
            await _plugin.stopListening();
            _listening = false;
          }
        })
        .catchError((Object _) {});
  }

  void handleNative(ButtonEvent event) {
    if (_closed || !_wanted) return;
    final key = switch (event.button) {
      VolumeUpButton() => LogicalKeyboardKey.audioVolumeUp,
      VolumeDownButton() => LogicalKeyboardKey.audioVolumeDown,
      _ => null,
    };
    if (key == null) return;
    if (event.action is ButtonReleased) {
      _quietTimers.remove(key)?.cancel();
      _held.remove(key);
      return;
    }
    if (!enabled()) return;
    _quietTimers.remove(key)?.cancel();
    // Platforms without release events need an inactivity debounce. Android
    // releases clear immediately; native repeat presses keep this timer alive.
    _quietTimers[key] = Timer(
      const Duration(milliseconds: 700),
      () => _held.remove(key),
    );
    if (_held.add(key) && canCapture()) capture();
  }

  bool handle(KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.audioVolumeUp &&
        key != LogicalKeyboardKey.audioVolumeDown) {
      return false;
    }
    if (event is KeyUpEvent) {
      _held.remove(key);
      return !_closed && enabled();
    }
    if (_closed || !enabled()) {
      _held.remove(key);
      return false;
    }
    if (event is KeyDownEvent &&
        !event.synthesized &&
        _held.add(key) &&
        canCapture()) {
      capture();
    }
    return true;
  }

  void _clearHeld() {
    for (final timer in _quietTimers.values) {
      timer.cancel();
    }
    _quietTimers.clear();
    _held.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clearHeld();
    setActive(state == AppLifecycleState.resumed && enabled());
  }

  Future<void> dispose() async {
    if (_started) {
      HardwareKeyboard.instance.removeHandler(handle);
      WidgetsBinding.instance.removeObserver(this);
    }
    _started = false;
    _closed = true;
    _clearHeld();
    setActive(false);
    await _nativeQueue;
    await _subscription?.cancel();
  }
}
