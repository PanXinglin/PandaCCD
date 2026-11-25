import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/domain/preset.dart';
import 'package:panda_ccd/domain/face_region.dart';
import 'package:panda_ccd/services/filter_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Lower-jaw contour stays tapered without a cheek waist; old/absent contours stay unchanged',
    () async {
      final engine = FilterEngine();
      await engine.init();
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawColor(const Color(0xff2080d0), BlendMode.src);
      c.drawOval(
        const Rect.fromLTWH(48, 16, 160, 280),
        Paint()..color = const Color(0xffb88064),
      );
      final picture = rec.endRecording();
      final source = await picture.toImage(256, 320);
      picture.dispose();
      final face = FaceRegion(
        const Rect.fromLTWH(48 / 256, 16 / 320, 160 / 256, 280 / 320),
        const Offset(.2, .6),
        const Offset(.8, .6),
        mouth: const Offset(128 / 256, 220 / 320),
        outline: [
          for (var i = 0; i < 36; i++)
            Offset(
              (128 + 80 * math.cos(i * math.pi / 18)) / 256,
              (156 + 140 * math.sin(i * math.pi / 18)) / 320,
            ),
        ],
      );
      Future<ui.Image> render(double slim, List<FaceRegion> faces) async =>
          engine.decodePhoto(
            await engine.render(
              source,
              {
                ...parameterDefaults,
                'strength': 0,
                'beauty': .55,
                'beautySmooth': 0,
                'beautyWhiten': 0,
                'beautyEven': 0,
                'faceSlim': slim,
              },
              engine.lut('jade'),
              Watermark()
                ..date = false
                ..model = false,
              DateTime(2026),
              '',
              faces: faces,
            ),
          );
      final off = await render(0, [face]),
          middle = await render(.5, [face]),
          on = await render(1, [face]),
          none = await render(1, const []);
      final a = (await off.toByteData())!,
          m = (await middle.toByteData())!,
          b = (await on.toByteData())!,
          n = (await none.toByteData())!;
      int skinWidth(ByteData data, int y) {
        var count = 0;
        for (var x = 0; x < 256; x++) {
          if (data.getUint8((y * 256 + x) * 4) > 120) count++;
        }
        return count;
      }

      expect(skinWidth(m, 252), lessThan(skinWidth(a, 252)));
      expect(skinWidth(b, 252), lessThanOrEqualTo(skinWidth(a, 252) - 9));
      expect(skinWidth(b, 252), lessThan(skinWidth(m, 252)));
      expect(
        skinWidth(b, 180),
        skinWidth(a, 180),
        reason: 'Cheekbones and cheeks above the mouth must not pinch',
      );
      for (var y = 230; y < 286; y += 4) {
        expect(
          skinWidth(b, y + 4),
          lessThanOrEqualTo(skinWidth(b, y) + 1),
          reason: 'The jaw must taper continuously toward the chin',
        );
      }
      // Neither lip/cheek region nor the rounded chin tip may be reshaped.
      for (final range in [(0, 220), (288, 320)]) {
        for (var y = range.$1; y < range.$2; y++) {
          for (var x = 0; x < 256; x++) {
            final index = (y * 256 + x) * 4;
            expect(
              b.getUint32(index),
              a.getUint32(index),
              reason: 'Protected cheek/chin changed at $x,$y',
            );
          }
        }
      }
      // Narrowing must stay bounded, rather than accumulating radial pulls.
      for (var y = 220; y < 296; y++) {
        expect(skinWidth(a, y) - skinWidth(b, y), inInclusiveRange(0, 16));
      }
      expect(n.buffer.asUint8List(), a.buffer.asUint8List());
      for (var y = 0; y < 320; y++) {
        for (var x = 0; x < 32; x++) {
          final index = (y * 256 + x) * 4;
          expect(b.getUint32(index), a.getUint32(index));
        }
      }
      off.dispose();
      middle.dispose();
      on.dispose();
      none.dispose();
      source.dispose();
      engine.dispose();
    },
  );
}
