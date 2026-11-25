import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:panda_ccd/services/filter_engine.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/ui/camera_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Measure the same photo across camera styles without reducing resolution',
    (tester) async {
      final engine = FilterEngine();
      await engine.init();
      final source = await engine.decodePhoto(await makeDemo());
      final stamp = Watermark();
      // Warm the shared shader and PNG encoder before collecting paired runs.
      await engine.render(
        source,
        presets.first.parameters,
        engine.lut(presets.first.id),
        stamp,
        DateTime(2026, 10, 27),
        presets.first.stampLabel,
      );
      for (var run = 0; run < 3; run++) {
        for (final preset in presets) {
          final clock = Stopwatch()..start();
          final bytes = await engine.render(
            source,
            preset.parameters,
            engine.lut(preset.id),
            stamp,
            DateTime(2026, 10, 27),
            preset.stampLabel,
          );
          clock.stop();
          final phases = engine.lastRenderTimings!;
          debugPrint(
            'CCD_STAGE ${preset.id} $run ${phases.raster.inMicroseconds} ${phases.readbackAndEncode.inMicroseconds}',
          );
          var hash = 2166136261;
          for (final byte in bytes) {
            hash = ((hash ^ byte) * 16777619) & 0xffffffff;
          }
          debugPrint('CCD_IMAGE_HASH ${preset.id} $hash');
          debugPrint(
            'CCD_BENCH ${preset.id} $run ${clock.elapsedMicroseconds} ${bytes.length}',
          );
        }
      }
      source.dispose();
      engine.dispose();
    },
  );
}
