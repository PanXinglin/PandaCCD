import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/app_state.dart';
import '../services/library.dart';

class LivePhotoView extends StatefulWidget {
  final AppState app;
  final PhotoEntry photo;
  final Widget cover;
  const LivePhotoView({
    super.key,
    required this.app,
    required this.photo,
    required this.cover,
  });
  @override
  State<LivePhotoView> createState() => _LivePhotoViewState();
}

class _LivePhotoViewState extends State<LivePhotoView> {
  VideoPlayerController? controller;
  bool playing = false, loading = false;
  int _playRequest = 0;
  @override
  void initState() {
    super.initState();
    widget.app.addListener(refresh);
    refresh();
  }

  void refresh() {
    if (mounted) setState(() {});
    if (controller == null && !loading) load();
  }

  Future<void> load() async {
    loading = true;
    try {
      final info = await widget.app.library.liveInfo(widget.photo);
      if (info?['rendered'] != true) return;
      final file = File('${widget.photo.liveDirectory}/movie.mp4');
      if (!await file.exists()) return;
      final c = VideoPlayerController.file(file);
      try {
        await c.initialize();
        await c.setVolume(info?['muted'] == true ? 0 : 1);
        await c.setLooping(true);
      } catch (_) {
        await c.dispose();
        return;
      }
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => controller = c);
    } finally {
      loading = false;
    }
  }

  Future<void> play(bool value) async {
    final c = controller;
    if (c == null) return;
    final request = ++_playRequest;
    if (value) {
      await c.seekTo(Duration.zero);
      if (!mounted || request != _playRequest) return;
      await c.play();
    } else {
      await c.pause();
    }
    if (mounted && request == _playRequest) setState(() => playing = value);
  }

  @override
  void dispose() {
    widget.app.removeListener(refresh);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPressStart: controller == null ? null : (_) => play(true),
    onLongPressEnd: controller == null ? null : (_) => play(false),
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.cover,
        if (playing && controller != null)
          Center(
            child: AspectRatio(
              aspectRatio: controller!.value.aspectRatio,
              child: VideoPlayer(controller!),
            ),
          ),
        Positioned(
          top: 12,
          left: 16,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              disabledBackgroundColor: Colors.black54,
            ),
            onPressed: controller == null ? null : () => play(!playing),
            icon: const Icon(Icons.motion_photos_on, size: 18),
            label: Text(
              controller != null
                  ? (playing ? '停止播放' : '播放 Live')
                  : widget.app.liveProgress.containsKey(widget.photo.path)
                  ? 'Live 生成中'
                  : 'Live 未生成',
            ),
          ),
        ),
      ],
    ),
  );
}

/// Single-finger drags turn pages at 1x. Zoomed images keep their own pan.
class GalleryPhotoZoom extends StatefulWidget {
  final String path;
  final ValueChanged<bool> onZoomChanged;
  const GalleryPhotoZoom({
    super.key,
    required this.path,
    required this.onZoomChanged,
  });

  @override
  State<GalleryPhotoZoom> createState() => _GalleryPhotoZoomState();
}

class _GalleryPhotoZoomState extends State<GalleryPhotoZoom> {
  final transform = TransformationController();
  bool zoomed = false;

  void updateZoom() {
    final next = transform.value.getMaxScaleOnAxis() > 1.01;
    if (next == zoomed) return;
    setState(() => zoomed = next);
    widget.onZoomChanged(next);
  }

  @override
  void initState() {
    super.initState();
    transform.addListener(updateZoom);
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    transformationController: transform,
    panEnabled: zoomed,
    maxScale: 5,
    child: Center(
      child: Image.file(
        File(widget.path),
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      ),
    ),
  );
}
