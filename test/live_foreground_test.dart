import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/live_foreground.dart';

void main() {
  testWidgets('Interrupted Live rendering waits for foreground and retries', (
    tester,
  ) async {
    final gate = LiveForeground();
    gate.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final inFlight = Completer<int>();
    var attempts = 0;
    final work = gate.run(() async => ++attempts == 1 ? inFlight.future : 2);
    await tester.pump();
    expect(attempts, 1);
    gate.didChangeAppLifecycleState(AppLifecycleState.paused);
    inFlight.completeError(StateError('GPU interrupted by background'));
    await tester.pump();
    expect(attempts, 1);
    gate.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(await work, 2);
    await expectLater(
      gate.run<int>(() async => throw StateError('invalid input')),
      throwsStateError,
    );
    gate.dispose();
  });
}
