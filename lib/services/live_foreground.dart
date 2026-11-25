import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:panda_media/panda_media.dart';

/// Metal work must wait for the app to be visible on iPhone. If focus was
/// lost during a failed GPU operation, retry from the retained inputs.
class LiveForeground with WidgetsBindingObserver {
  LiveForeground() {
    _visible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  late bool _visible;
  int _interruption = 0;
  Completer<void>? _resume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (_visible && !visible) _interruption++;
    _visible = visible;
    if (visible) {
      _resume?.complete();
      _resume = null;
    }
  }

  Future<void> wait() async {
    while (!_visible) {
      await (_resume ??= Completer<void>()).future;
    }
  }

  Future<T> run<T>(Future<T> Function() operation) async {
    while (true) {
      await wait();
      final interruption = _interruption;
      try {
        return await operation();
      } catch (_) {
        if (_interruption == interruption) rethrow;
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    didChangeAppLifecycleState(AppLifecycleState.resumed);
  }
}

/// A short iOS allowance for finalizing already captured frames. This does not
/// extend camera access or run the filter in the background.
class LiveFinishLease {
  final String id;
  LiveFinishLease._(this.id);

  static Future<LiveFinishLease?> begin() async {
    if (!Platform.isIOS) return null;
    try {
      final id = await PandaMedia.call<String>('beginLiveFinish', {});
      return id == null ? null : LiveFinishLease._(id);
    } catch (_) {
      return null;
    }
  }

  Future<void> end() async {
    try {
      await PandaMedia.call<void>('endLiveFinish', {'id': id});
    } catch (_) {}
  }
}
