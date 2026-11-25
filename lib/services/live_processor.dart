import 'dart:ui' as ui;
import '../domain/frame_ratio.dart';
import 'video_pixels.dart';
import 'dart:ui' show ImmutableBuffer, ImageDescriptor;
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:panda_media/panda_media.dart';
import '../domain/live_capture.dart';
import '../domain/photo_edit.dart';
import '../domain/preset.dart';
import '../domain/face_region.dart';
import 'filter_engine.dart';
import 'face_tracker.dart';
import 'motion_photo.dart';

class _Slice {
  final LiveSegment segment;
  final String reader;
  final int from, to, absoluteStart;
  _Slice(this.segment, this.reader, this.from, this.to, this.absoluteStart);
  int get duration => to - from;
}

/// A bounded off-line export: one decoded GPU frame at a time. Preview never
/// runs CPU filters. Sparse preview face analysis may read bounded snapshots.
/// The same GLSL renders still + motion.
class LiveProcessor {
  final FilterEngine engine;
  LiveProcessor(this.engine);
  Future<Directory> prepare(
    LiveSource source,
    PhotoEdit edit,
    LutImage lut,
    Uint8List cover,
    String format, {
    void Function(double)? progress,
    Future<void> Function()? waitForForeground,
  }) async {
    final buffer = await ImmutableBuffer.fromUint8List(cover);
    final descriptor = await ImageDescriptor.encoded(buffer);
    final coverAspect =
        math.max(descriptor.width, descriptor.height) /
        math.min(descriptor.width, descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    final dir = await Directory.systemTemp.createTemp('panda-live-');
    final slices = <_Slice>[];
    String? writer, rawWriter;
    try {
      for (final segment in source.segments) {
        final info = (await PandaMedia.call<Map>('openReader', {
          'path': segment.path,
        }))!;
        final duration = (info['durationUs'] as num).toInt();
        final videoStart = segment.endedUs - duration;
        final from = math.max(0, source.fromUs - videoStart),
            to = math.min(duration, source.toUs - videoStart);
        if (to > from) {
          slices.add(
            _Slice(segment, info['id'] as String, from, to, videoStart),
          );
        } else {
          await PandaMedia.call<void>('closeReader', {'id': info['id']});
        }
      }
      final duration = slices.fold<int>(0, (sum, s) => sum + s.duration);
      if (duration < 300000) throw StateError('动态片段不足，请稍候再拍');
      var keyUs = 0, base = 0;
      for (final slice in slices) {
        if (source.shutterUs >= slice.absoluteStart + slice.from) {
          keyUs =
              base +
              (source.shutterUs - slice.absoluteStart - slice.from).clamp(
                0,
                slice.duration,
              );
        }
        base += slice.duration;
      }
      const fps = 24;
      final count = (duration * fps / 1000000).ceil();
      final moviePath = '${dir.path}/movie.mp4',
          rawPath = '${dir.path}/segment-0.mp4';
      List<FaceRegion> previous = const [];
      var sliceIndex = 0, sliceBase = 0;
      var lastTrackedSlice = -1;
      for (var frame = 0; frame < count; frame++) {
        if (waitForForeground != null) await waitForForeground();
        final outTime = frame * 1000000 ~/ fps;
        while (sliceIndex < slices.length - 1 &&
            outTime >= sliceBase + slices[sliceIndex].duration) {
          sliceBase += slices[sliceIndex++].duration;
        }
        final slice = slices[sliceIndex];
        final local = (slice.from + outTime - sliceBase).clamp(
          slice.from,
          math.max(slice.from, slice.to - 1000),
        );
        var pixels = VideoPixels.fromMap(
          (await PandaMedia.call<Map>('readPixels', {
            'id': slice.reader,
            'timeUs': local,
            'maxEdge': 1280,
          }))!,
        );
        if (source.legacyRedBlueSwap) {
          pixels = VideoPixels(
            pixels.bytes,
            pixels.width,
            pixels.height,
            bgra: !pixels.bgra,
          );
        }
        if (waitForForeground != null) await waitForForeground();
        final image = await pixels.decode();
        ui.Image? rotated;
        try {
          final turns =
              (_turn(source.orientation) -
                  _turn(slice.segment.orientation) +
                  4) %
              4;
          var normalized = pixels;
          if (turns != 0 || slice.segment.mirrored) {
            if (waitForForeground != null) await waitForForeground();
            final data = await engine.render(
              image,
              {...parameterDefaults, 'strength': 0, 'beauty': 0},
              lut,
              Watermark()
                ..date = false
                ..model = false,
              edit.date,
              '',
              turns: turns,
              mirrorSource: slice.segment.mirrored,
              byteFormat: ui.ImageByteFormat.rawRgba,
            );
            normalized = VideoPixels(
              data,
              turns.isOdd ? image.height : image.width,
              turns.isOdd ? image.width : image.height,
            );
            if (waitForForeground != null) await waitForForeground();
            rotated = await normalized.decode();
          }
          final upright = rotated ?? image;
          rawWriter ??= await PandaMedia.call<String>('openWriter', {
            'path': rawPath,
            'width': upright.width ~/ 2 * 2,
            'height': upright.height ~/ 2 * 2,
            'fps': fps,
          });
          await PandaMedia.call<void>('appendPixels', {
            'id': rawWriter,
            ...normalized.arguments,
            'timeUs': outTime,
          });
          // Sample landmarks at 8 Hz. Every frame still uses the GPU shader
          // and the last tracked landmarks, including the frames in between.
          if ((edit.recipe.values['beauty'] ?? 0) > 0 &&
              (frame % 3 == 0 || lastTrackedSlice != sliceIndex)) {
            final found = await FaceTracker.detectPixels(normalized.arguments);
            previous = lastTrackedSlice == sliceIndex
                ? FaceRegion.stabilize(previous, found, .65)
                : found;
            lastTrackedSlice = sliceIndex;
          }
          final aspect = edit.frameAspect ?? coverAspect;
          final crop = croppedFrameSize(
            ui.Size(upright.width.toDouble(), upright.height.toDouble()),
            aspect: aspect,
            square: edit.square,
          );
          final width = (edit.turns.isOdd ? crop.height : crop.width).round(),
              height = (edit.turns.isOdd ? crop.width : crop.height).round();
          if (waitForForeground != null) await waitForForeground();
          final rendered = await engine.render(
            upright,
            edit.recipe.values,
            lut,
            edit.stamp,
            edit.date,
            presets.firstWhere((p) => p.id == edit.recipe.presetId).stampLabel,
            turns: edit.turns,
            square: edit.square,
            frameAspect: aspect,
            faces: previous,
            byteFormat: ui.ImageByteFormat.rawRgba,
            trackFace: true,
          );
          writer ??= await PandaMedia.call<String>('openWriter', {
            'path': moviePath,
            'width': width ~/ 2 * 2,
            'height': height ~/ 2 * 2,
            'fps': fps,
          });
          await PandaMedia.call<void>('appendPixels', {
            'id': writer,
            'bytes': rendered,
            'width': width,
            'height': height,
            'bgra': false,
            'timeUs': outTime,
          });
        } finally {
          rotated?.dispose();
          image.dispose();
        }
        progress?.call((frame + 1) / count);
      }
      await PandaMedia.call<String>('finishWriter', {'id': writer});
      writer = null;
      await PandaMedia.call<String>('finishWriter', {'id': rawWriter});
      rawWriter = null;
      final audioSources = <Map<String, Object>>[];
      var audioOffset = 0;
      for (final slice in slices) {
        audioSources.add({
          'path': slice.segment.path,
          'fromUs': slice.from,
          'toUs': slice.to,
          'offsetUs': audioOffset,
        });
        audioOffset += slice.duration;
      }
      final audio = (await PandaMedia.call<Map>('copyAudio', {
        'path': moviePath,
        'sources': audioSources,
      }))!;
      await PandaMedia.call<Map>('copyAudio', {
        'path': rawPath,
        'sources': audioSources,
      });
      final actualDuration = count * 1000000 ~/ fps;
      final raw = LiveSource(
        [LiveSegment(rawPath, actualDuration, source.orientation)],
        0,
        actualDuration,
        keyUs,
        source.orientation,
      );
      final metadata = <String, Object>{
        ...raw.toJson(),
        'pixelLayoutVersion': 2,
        'rendered': true,
        'keyUs': keyUs,
        'durationUs': actualDuration,
        'muted': audio['hasAudio'] != true,
      };
      await File('${dir.path}/cover.png').writeAsBytes(cover);
      if (Platform.isIOS) {
        final pair = (await PandaMedia.call<Map>('pairLive', {
          'imagePath': '${dir.path}/cover.png',
          'videoPath': moviePath,
          'keyUs': keyUs,
        }))!;
        await File(pair['imagePath'] as String).copy('${dir.path}/pair.jpg');
        await File(pair['videoPath'] as String).copy('${dir.path}/pair.mov');
        // Pair writer creates its own temporary directory, owned by this export.
        await File(pair['imagePath'] as String).parent.delete(recursive: true);
        metadata['format'] = 'apple';
      } else {
        final device = await PandaMedia.call<Map>('device');
        final selected = MotionPhoto.select(
          format,
          '${device?['brand']} ${device?['manufacturer']}',
        );
        final jpeg = (await PandaMedia.call<Uint8List>('jpeg', {
          'bytes': cover,
        }))!;
        await MotionPhoto.write(
          jpeg: jpeg,
          videoPath: moviePath,
          outputPath: '${dir.path}/export.MP.jpg',
          format: selected,
          keyUs: keyUs,
        );
        metadata['format'] = selected;
      }
      await File(
        '${dir.path}/manifest.json',
      ).writeAsString(jsonEncode(metadata), flush: true);
      return dir;
    } catch (_) {
      if (writer != null) {
        try {
          await PandaMedia.call<void>('abortWriter', {'id': writer});
        } catch (_) {}
      }
      if (rawWriter != null) {
        try {
          await PandaMedia.call<void>('abortWriter', {'id': rawWriter});
        } catch (_) {}
      }
      await dir.delete(recursive: true);
      rethrow;
    } finally {
      for (final s in slices) {
        try {
          await PandaMedia.call<void>('closeReader', {'id': s.reader});
        } catch (_) {}
      }
    }
  }

  static int _turn(DeviceOrientation o) => switch (o) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeRight => 1,
    DeviceOrientation.portraitDown => 2,
    DeviceOrientation.landscapeLeft => 3,
  };
  static Future<Directory> retainFailed(
    LiveSource source,
    Object error, {
    String? pendingFormat,
    Directory? destination,
  }) async {
    final dir =
        await (destination?.create() ??
            Directory.systemTemp.createTemp('panda-live-pending-'));
    try {
      for (var i = 0; i < source.segments.length; i++) {
        await File(source.segments[i].path).copy('${dir.path}/segment-$i.mp4');
      }
      await File('${dir.path}/manifest.json').writeAsString(
        jsonEncode({
          ...source.toJson(),
          'rendered': false,
          'error': error.toString(),
          'pendingFormat': ?pendingFormat,
        }),
        flush: true,
      );
      return dir;
    } catch (_) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Preserve the original failure for retry.
      }
      rethrow;
    }
  }
}
