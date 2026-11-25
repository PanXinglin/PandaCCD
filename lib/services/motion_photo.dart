import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Only freshly encoded JPEGs are accepted; raw originals remain untouched.
/// Google XMP follows Android Motion Photo 1.0. OPPO MPF layout adapted from
/// Young-Spark/oppo-live-photo-maker (MIT; see assets/licenses).
abstract final class MotionPhoto {
  static const formats = ['auto', 'google', 'xiaomi', 'oppo', 'samsung'];
  static const labels = {
    'auto': '自动选择',
    'google': '通用 / Google 相册',
    'xiaomi': '小米 / Redmi',
    'oppo': 'OPPO / 一加 / realme',
    'samsung': '三星',
  };
  static String select(String setting, String brand) {
    if (formats.contains(setting) && setting != 'auto') return setting;
    final b = brand.toLowerCase();
    if (['xiaomi', 'redmi', 'poco'].any(b.contains)) return 'xiaomi';
    if (['oppo', 'oneplus', 'realme', 'oplus'].any(b.contains)) return 'oppo';
    if (b.contains('samsung')) return 'samsung';
    return 'google';
  }

  static Uint8List app(int marker, List<int> data) {
    if (data.length > 65533) {
      throw const FormatException('JPEG metadata too large');
    }
    return Uint8List.fromList([
      255,
      marker,
      (data.length + 2) >> 8,
      (data.length + 2) & 255,
      ...data,
    ]);
  }

  static Uint8List _u32(int value, {Endian endian = Endian.big}) =>
      (ByteData(4)..setUint32(0, value, endian)).buffer.asUint8List();
  static Uint8List _u16(int value, {Endian endian = Endian.big}) =>
      (ByteData(2)..setUint16(0, value, endian)).buffer.asUint8List();
  static Uint8List mpf(int jpegSize) => app(0xe2, [
    ...ascii.encode('MPF\u0000'),
    77,
    77,
    0,
    42,
    0,
    0,
    0,
    8,
    0,
    3,
    ..._u16(0xb000),
    0,
    7,
    ..._u32(4),
    48,
    49,
    48,
    48,
    ..._u16(0xb001),
    0,
    4,
    ..._u32(1),
    ..._u32(1),
    ..._u16(0xb002),
    0,
    7,
    ..._u32(16),
    ..._u32(50),
    ..._u32(0),
    ..._u32(0x00030000),
    ..._u32(jpegSize),
    ..._u32(0),
    0,
    0,
    0,
    0,
  ]);
  static Uint8List _oppoExif() {
    final comment = [
      ...ascii.encode('ASCII'),
      0,
      0,
      0,
      ...ascii.encode('Oplus_8388608'),
    ];
    return app(0xe1, [
      ...ascii.encode('Exif\u0000\u0000'),
      77,
      77,
      0,
      42,
      0,
      0,
      0,
      8,
      0,
      1,
      ..._u16(0x8769),
      0,
      4,
      ..._u32(1),
      ..._u32(26),
      ..._u32(0),
      0,
      1,
      ..._u16(0x9286),
      0,
      7,
      ..._u32(comment.length),
      ..._u32(44),
      ..._u32(0),
      ...comment,
    ]);
  }

  static Future<void> write({
    required Uint8List jpeg,
    required String videoPath,
    required String outputPath,
    required String format,
    required int keyUs,
  }) async {
    if (jpeg.length < 4 ||
        jpeg[0] != 255 ||
        jpeg[1] != 216 ||
        jpeg[jpeg.length - 2] != 255 ||
        jpeg.last != 217) {
      throw const FormatException('Expected fresh JPEG');
    }
    final video = File(videoPath);
    final length = await video.length();
    if (length < 12) throw const FormatException('Empty Live video');
    final first = await video.open();
    try {
      final header = await first.read(12);
      if (ascii.decode(header.sublist(4, 8), allowInvalid: true) != 'ftyp') {
        throw const FormatException('Expected MP4');
      }
    } finally {
      await first.close();
    }
    final prefix = <int>[];
    final suffix = <int>[];
    if (format == 'samsung') {
      prefix.addAll(_sefBlock(0x0a30, 'MotionPhoto_Data', const []));
      final version = _sefBlock(
        0x0a31,
        'MotionPhoto_Version',
        ascii.encode('mpv3'),
      );
      suffix.addAll(version);
      final dataSize = prefix.length + length;
      final index = [
        ...ascii.encode('SEFH'),
        ..._u32(107, endian: Endian.little),
        ..._u32(2, endian: Endian.little),
        0,
        0,
        ..._u16(0x0a30, endian: Endian.little),
        ..._u32(dataSize + version.length, endian: Endian.little),
        ..._u32(dataSize, endian: Endian.little),
        0,
        0,
        ..._u16(0x0a31, endian: Endian.little),
        ..._u32(version.length, endian: Endian.little),
        ..._u32(version.length, endian: Endian.little),
      ];
      suffix.addAll([
        ...index,
        ..._u32(index.length, endian: Endian.little),
        ...ascii.encode('SEFT'),
      ]);
    }
    final offset = length + suffix.length;
    final vendor = format == 'oppo'
        ? 'xmlns:OpCamera="http://ns.oplus.com/photos/1.0/camera/" OpCamera:MotionPhotoPrimaryPresentationTimestampUs="$keyUs" OpCamera:MotionPhotoOwner="oplus" OpCamera:MotionPhotoFeatureFlag="1" OpCamera:OLivePhotoVersion="2" OpCamera:VideoLength="$length"'
        : '';
    final xmp =
        '''<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" xmlns:Container="http://ns.google.com/photos/1.0/container/" xmlns:Item="http://ns.google.com/photos/1.0/container/item/" $vendor GCamera:MotionPhoto="1" GCamera:MotionPhotoVersion="1" GCamera:MotionPhotoPresentationTimestampUs="$keyUs" GCamera:MicroVideo="1" GCamera:MicroVideoVersion="1" GCamera:MicroVideoOffset="$offset" GCamera:MicroVideoPresentationTimestampUs="$keyUs"><Container:Directory><rdf:Seq><rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary" Item:Padding="${prefix.length}"/></rdf:li><rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="$offset"/></rdf:li></rdf:Seq></Container:Directory></rdf:Description></rdf:RDF></x:xmpmeta>''';
    final metadata = app(0xe1, [
      ...ascii.encode('http://ns.adobe.com/xap/1.0/\u0000'),
      ...utf8.encode(xmp),
    ]);
    final exif = format == 'oppo' ? _oppoExif() : Uint8List(0);
    final mpfSize = format == 'oppo' ? mpf(0).length : 0;
    final jpegSize = jpeg.length + metadata.length + exif.length + mpfSize;
    final sink = File(outputPath).openWrite();
    try {
      sink.add(jpeg.sublist(0, 2));
      sink.add(metadata);
      sink.add(exif);
      if (format == 'oppo') sink.add(mpf(jpegSize));
      sink.add(jpeg.sublist(2));
      sink.add(prefix);
      await sink.addStream(video.openRead());
      sink.add(suffix);
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  static Uint8List _sefBlock(int type, String name, List<int> payload) =>
      Uint8List.fromList([
        0,
        0,
        ..._u16(type, endian: Endian.little),
        ..._u32(name.length, endian: Endian.little),
        ...ascii.encode(name),
        ...payload,
      ]);
}
