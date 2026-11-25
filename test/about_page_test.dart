import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/app_state.dart';
import 'package:panda_ccd/ui/settings_page.dart';
import 'package:panda_ccd/ui/about_page.dart';
import 'package:panda_ccd/ui/design_system.dart';
import 'package:panda_ccd/domain/app_info.dart';

class _SettingsState extends AppState {
  @override
  Future<void> persist() async {}
}

void main() {
  testWidgets(
    'Saving options remain editable and update the settings summary',
    (tester) async {
      final app = _SettingsState();
      await tester.pumpWidget(
        MaterialApp(
          theme: PandaDesign.theme(),
          home: SettingsPage(state: app),
        ),
      );
      expect(find.text('拍后直接保存'), findsOneWidget);
      await tester.tap(find.text('保存与水印'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('拍照后打开编辑'));
      await tester.pumpAndSettle();
      expect(app.directSave, false);
      expect(find.text('同时保留原图'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('拍后打开编辑'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'Settings opens About with current version, privacy and licenses at large text',
    (tester) async {
      final app = AppState();
      await tester.binding.setSurfaceSize(const Size(375, 650));
      await tester.pumpWidget(
        MaterialApp(
          theme: PandaDesign.theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.6),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: SettingsPage(state: app),
        ),
      );
      await tester.scrollUntilVisible(find.text('关于PandaCCD'), 360);
      await tester.tap(find.text('关于PandaCCD'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);
      expect(
        find.text('${AppInfo.versionLabel} · BUILD ${AppInfo.build}'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('开源许可证'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(AboutPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('开源许可证'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      app.dispose();
    },
  );
}
