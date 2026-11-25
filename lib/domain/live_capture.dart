import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

class LiveSegment {
  final String path;
  final int endedUs;
  final DeviceOrientation orientation;
  final bool mirrored;
  const LiveSegment(
    this.path,
    this.endedUs,
    this.orientation, {
    this.mirrored = false,
  });
  Map<String, Object> toJson(String file) => {
    'file': file,
    'endedUs': endedUs,
    'orientation': orientation.name,
    if (mirrored) 'mirrored': true,
  };
}

class LiveSource {
  final List<LiveSegment> segments;
  final int fromUs, toUs, shutterUs;
  final DeviceOrientation orientation;
  final bool legacyRedBlueSwap;
  const LiveSource(
    this.segments,
    this.fromUs,
    this.toUs,
    this.shutterUs,
    this.orientation, {
    this.legacyRedBlueSwap = false,
  });
  Future<void> dispose() async {
    for (final s in segments) {
      final f = File(s.path);
      if (await f.exists()) await f.delete();
    }
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'fromUs': fromUs,
    'toUs': toUs,
    'shutterUs': shutterUs,
    'orientation': orientation.name,
    if (legacyRedBlueSwap) 'legacyRedBlueSwap': true,
    'segments': [
      for (var i = 0; i < segments.length; i++)
        segments[i].toJson('segment-$i.mp4'),
    ],
  };
  static LiveSource decode(Map raw, String directory) {
    if (raw['version'] != 1) {
      throw const FormatException('Unsupported Live source');
    }
    final segments = <LiveSegment>[];
    for (final item in raw['segments'] as List) {
      final file = item['file'] as String;
      if (!RegExp(r'^segment-[0-9]+\.mp4$').hasMatch(file)) {
        throw const FormatException('Invalid Live source path');
      }
      segments.add(
        LiveSegment(
          '$directory/$file',
          item['endedUs'] as int,
          DeviceOrientation.values.byName(item['orientation'] as String),
          mirrored: item['mirrored'] == true,
        ),
      );
    }
    return LiveSource(
      segments,
      raw['fromUs'] as int,
      raw['toUs'] as int,
      raw['shutterUs'] as int,
      DeviceOrientation.values.byName(raw['orientation'] as String),
      legacyRedBlueSwap: raw['legacyRedBlueSwap'] == true,
    );
  }
}

class LiveShot {
  final XFile photo;
  final LiveSource? source;
  final String? warning;
  const LiveShot(this.photo, this.source, {this.warning});
}
