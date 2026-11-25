import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/motion_photo.dart';

void main() {
  test(
    'Vendor output preserves video bytes, Google EOF offset and Samsung native footer',
    () async {
      final dir = await Directory.systemTemp.createTemp('motion-test-');
      try {
        final video = Uint8List.fromList([
          0,
          0,
          0,
          24,
          ...ascii.encode('ftypisom'),
          ...List.generate(36, (i) => i),
        ]);
        final path = '${dir.path}/video.mp4';
        await File(path).writeAsBytes(video);
        for (final format in ['google', 'xiaomi', 'oppo', 'samsung']) {
          final output = '${dir.path}/$format.MP.jpg';
          await MotionPhoto.write(
            jpeg: Uint8List.fromList([255, 216, 255, 217]),
            videoPath: path,
            outputPath: output,
            format: format,
            keyUs: 1200000,
          );
          final bytes = await File(output).readAsBytes();
          final text = latin1.decode(bytes);
          final offset = int.parse(
            RegExp(
              r'GCamera:MicroVideoOffset="([0-9]+)"',
            ).firstMatch(text)!.group(1)!,
          );
          final start = bytes.length - offset;
          expect(bytes.sublist(start, start + video.length), video);
          expect(
            text,
            contains('GCamera:MotionPhotoPresentationTimestampUs="1200000"'),
          );
          if (format == 'samsung') {
            final expected = await File(
              'test/fixtures/samsung-motion-trailer.bin',
            ).readAsBytes();
            expect(bytes.sublist(start - 24), expected);
          }
          if (format == 'oppo') {
            expect(text, contains('Oplus_8388608'));
            expect(text, contains('OpCamera:MotionPhotoOwner="oplus"'));
            expect(text, contains('MPF\u0000'));
          }
        }
        expect(
          MotionPhoto.mpf(1234),
          await File('test/fixtures/oppo-mpf-1234.bin').readAsBytes(),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('Automatic format and invalid source handling are explicit', () async {
    expect(MotionPhoto.select('auto', 'Xiaomi Redmi'), 'xiaomi');
    expect(MotionPhoto.select('auto', 'Samsung'), 'samsung');
    expect(MotionPhoto.select('auto', 'OnePlus'), 'oppo');
    expect(MotionPhoto.select('auto', 'vivo'), 'google');
    expect(MotionPhoto.select('google', 'Xiaomi'), 'google');
    await expectLater(
      MotionPhoto.write(
        jpeg: Uint8List(4),
        videoPath: 'missing',
        outputPath: 'unused',
        format: 'google',
        keyUs: 0,
      ),
      throwsFormatException,
    );
  });
}
