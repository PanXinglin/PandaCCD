import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'services/app_state.dart';
import 'ui/camera_page.dart';
import 'ui/camera_viewport.dart';
import 'ui/components.dart';
import 'ui/design_system.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in {
      'OPPO Motion Photo MPF reference — Young':
          'oppo-live-photo-maker-MIT.txt',
      'Samsung SEF reference — Petr Vyskocil': 'MotionPhoto2-MIT.txt',
      'PandaCCD system media bridge': 'panda_media-BSD.txt',
      'GPUPixel — PixPark': 'GPUPixel-Apache-2.0.txt',
      'GPUPixel adaptations': 'GPUPixel-NOTICE.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('assets/licenses/${entry.value}'));
    }

    yield LicenseEntryWithLineBreaks([
      'Shutter recording — ristooooo1',
    ], await rootBundle.loadString('assets/licenses/shutter.txt'));
  });
  runApp(const PandaApp());
}

Widget pandaAppFrame(BuildContext context, Widget? child) =>
    AnnotatedRegion<SystemUiOverlayStyle>(
      value: PandaDesign.lightSystemBars,
      child: CameraDisplayArea(child: child ?? const SizedBox.shrink()),
    );

class PandaApp extends StatefulWidget {
  const PandaApp({super.key});
  @override
  State<PandaApp> createState() => _PandaAppState();
}

class _PandaAppState extends State<PandaApp> {
  final state = AppState();
  late Future<void> ready;
  @override
  void initState() {
    super.initState();
    ready = prepareCamera();
  }

  Future<void> prepareCamera() {
    final cameraReady = Completer<void>();
    unawaited(
      state.init(onCameraReady: cameraReady.complete).catchError((
        Object error,
        StackTrace stack,
      ) {
        if (!cameraReady.isCompleted) {
          cameraReady.completeError(error, stack);
        } else {
          debugPrint('相册恢复失败：$error');
        }
      }),
    );
    return cameraReady.future;
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: pandaAppFrame,
    title: 'PandaCCD',
    debugShowCheckedModeBanner: false,
    theme: PandaDesign.theme(),
    home: FutureBuilder(
      future: ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PandaMark(size: 70),
                    const SizedBox(height: 20),
                    Text('初始化失败：${snapshot.error}'),
                    TextButton(
                      onPressed: () => setState(() => ready = prepareCamera()),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Theme(
          data: PandaDesign.cameraTheme,
          child: CameraPage(
            state: state,
            ready: snapshot.connectionState == ConnectionState.done,
          ),
        );
      },
    ),
  );
}
