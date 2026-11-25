import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/hardware_shutter.dart';
import 'package:vol_spotter/vol_spotter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Both volume keys capture once per press; repeats/busy/background do not capture',
    () {
      var enabled = true, ready = true, photos = 0;
      final keys = HardwareShutter(
        enabled: () => enabled,
        canCapture: () => ready,
        capture: () => photos++,
      );
      for (final key in [
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.audioVolumeDown,
      ]) {
        final physical = key == LogicalKeyboardKey.audioVolumeUp
            ? PhysicalKeyboardKey.audioVolumeUp
            : PhysicalKeyboardKey.audioVolumeDown;
        expect(
          keys.handle(
            KeyDownEvent(
              physicalKey: physical,
              logicalKey: key,
              timeStamp: Duration.zero,
            ),
          ),
          isTrue,
        );
        keys.handle(
          KeyRepeatEvent(
            physicalKey: physical,
            logicalKey: key,
            timeStamp: const Duration(milliseconds: 10),
          ),
        );
        keys.handle(
          KeyDownEvent(
            physicalKey: physical,
            logicalKey: key,
            timeStamp: const Duration(milliseconds: 20),
          ),
        );
        keys.handle(
          KeyUpEvent(
            physicalKey: physical,
            logicalKey: key,
            timeStamp: const Duration(milliseconds: 30),
          ),
        );
      }
      expect(photos, 2);
      ready = false;
      keys.handle(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.audioVolumeUp,
          logicalKey: LogicalKeyboardKey.audioVolumeUp,
          timeStamp: Duration.zero,
        ),
      );
      ready = true;
      keys.handle(
        const KeyRepeatEvent(
          physicalKey: PhysicalKeyboardKey.audioVolumeUp,
          logicalKey: LogicalKeyboardKey.audioVolumeUp,
          timeStamp: Duration.zero,
        ),
      );
      expect(photos, 2);
      keys.handle(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.audioVolumeUp,
          logicalKey: LogicalKeyboardKey.audioVolumeUp,
          timeStamp: Duration.zero,
        ),
      );
      enabled = false;
      expect(
        keys.handle(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.audioVolumeUp,
            logicalKey: LogicalKeyboardKey.audioVolumeUp,
            timeStamp: Duration.zero,
          ),
        ),
        isFalse,
      );
      expect(photos, 2);
      keys.dispose();
    },
  );
  testWidgets(
    'Native volume events suppress holds and ignore inactive routes',
    (tester) async {
      var active = true, ready = true, count = 0;
      final keys = HardwareShutter(
        enabled: () => active,
        canCapture: () => ready,
        capture: () => count++,
      );
      keys.setActive(true);
      const press = ButtonEvent(
        button: VolumeUpButton(),
        action: ButtonPressed(),
      );
      const release = ButtonEvent(
        button: VolumeUpButton(),
        action: ButtonReleased(),
      );
      keys.handleNative(press);
      for (var repeat = 0; repeat < 5; repeat++) {
        await tester.pump(const Duration(milliseconds: 200));
        keys.handleNative(press);
      }
      expect(count, 1);
      keys.handleNative(release);
      keys.handleNative(press);
      expect(count, 2);
      keys.handleNative(release);
      ready = false;
      keys.handleNative(press);
      ready = true;
      keys.handleNative(press);
      expect(count, 2);
      keys.handleNative(release);
      active = false;
      keys.handleNative(press);
      expect(count, 2);
      active = true;
      keys.setActive(false);
      keys.handleNative(press);
      expect(count, 2);
      await keys.dispose();
    },
  );
}
