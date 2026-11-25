import 'design_system.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/library.dart';

Future<void> sharePhoto(BuildContext context, PhotoEntry photo) async {
  String? path = photo.path;
  if (photo.live) {
    final movie = File('${photo.liveDirectory}/movie.mp4');
    final motion = File('${photo.liveDirectory}/export.MP.jpg');
    final hasMovie = await movie.exists(), hasMotion = await motion.exists();
    if (!context.mounted) return;
    final choice = await PandaDesign.sheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasMotion)
            ListTile(
              leading: const Icon(Icons.motion_photos_on),
              title: const Text('分享动态照片'),
              subtitle: const Text('接收应用需支持此格式'),
              onTap: () => Navigator.pop(context, 'motion'),
            ),
          if (Platform.isIOS)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('要保留 Live 效果，请从系统相册分享。'),
            ),
          if (hasMovie)
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('分享动态视频'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('分享静态照片'),
            onTap: () => Navigator.pop(context, 'image'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    path = choice == 'motion'
        ? motion.path
        : choice == 'video'
        ? movie.path
        : photo.path;
  }
  if (!context.mounted) return;
  final render = context.findRenderObject() as RenderBox;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path)],
      sharePositionOrigin: render.localToGlobal(Offset.zero) & render.size,
    ),
  );
}
