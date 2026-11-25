import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'camera_glass.dart';
import 'components.dart';

abstract final class PandaDesign {
  static const background = Color(0xfff5f6f8);
  static const paper = Color(0xffffffff);
  static const raised = Color(0xfff8f9fb);
  static const line = Color(0xffe0e4ea);
  static const muted = Color(0xff535d6c);
  static const danger = Color(0xffae404a);
  static final lightSystemBars = SystemUiOverlayStyle.dark.copyWith(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static final cameraTheme = theme(camera: true);

  static ThemeData theme({bool camera = false}) {
    final canvas = camera ? CameraGlass.backdrop : background;
    final foreground = camera ? CameraGlass.foreground : ink;
    final detail = camera ? CameraGlass.secondary : muted;
    final separator = camera ? const Color(0xff3c4149) : line;
    final elevated = camera ? const Color(0xff282c32) : raised;
    final scheme =
        (camera ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
              primary: foreground,
              onPrimary: canvas,
              secondary: detail,
              onSecondary: canvas,
              secondaryContainer: camera
                  ? const Color(0xff3c434d)
                  : const Color(0xffe6eaf0),
              onSecondaryContainer: foreground,
              surface: canvas,
              onSurface: foreground,
              onSurfaceVariant: detail,
              surfaceContainer: camera ? const Color(0xff1c1f23) : paper,
              surfaceContainerHigh: elevated,
              outline: detail,
              outlineVariant: separator,
              error: camera ? const Color(0xffffadb4) : danger,
            );
    final base = camera ? ThemeData.dark() : ThemeData.light();
    final text = base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    );
    final popupShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: separator),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      textTheme: text.copyWith(
        titleLarge: text.titleLarge!.copyWith(
          fontSize: 21,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
        bodyMedium: text.bodyMedium!.copyWith(
          fontSize: 14,
          height: 1.5,
          color: foreground,
        ),
        bodySmall: text.bodySmall!.copyWith(
          fontSize: 12,
          height: 1.5,
          color: detail,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: foreground,
        systemOverlayStyle: camera
            ? SystemUiOverlayStyle.light
            : lightSystemBars,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: text.bodyLarge!.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        subtitleTextStyle: text.bodyMedium!.copyWith(
          fontSize: 12,
          height: 1.5,
          color: detail,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      switchTheme: const SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        surfaceTintColor: Colors.transparent,
        shape: popupShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        shape: popupShape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(color: detail),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: separator),
        ),
      ),
      dividerTheme: DividerThemeData(color: separator, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevated,
        contentTextStyle: TextStyle(color: foreground),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
    );
  }

  static Future<T?> sheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool useSafeArea = true,
    bool showDragHandle = false,
    BoxConstraints? constraints,
  }) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    constraints: constraints,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black45,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (context) {
      final light = Theme.of(context).brightness == Brightness.light;
      final contents = SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDragHandle)
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: light ? line : CameraGlass.secondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Flexible(child: builder(context)),
          ],
        ),
      );
      return light
          ? Material(color: paper, child: contents)
          : BackdropGroup(
              child: CameraGlass(
                panel: true,
                radius: 0,
                border: false,
                child: contents,
              ),
            );
    },
  );
}

class SettingsSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const SettingsSection({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title case final label?)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: PandaDesign.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Material(
          clipBehavior: Clip.antiAlias,
          color: PandaDesign.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: PandaDesign.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class BrandHeading extends StatelessWidget {
  final String subtitle;
  const BrandHeading({super.key, required this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Row(
      children: [
        const PandaMark(size: 68),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PandaCCD',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: PandaDesign.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
