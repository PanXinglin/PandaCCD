import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/ui/capture_feedback.dart';

void main() {
  testWidgets(
    'Successful capture gives an immediate short pulse without taking touch input',
    (tester) async {
      final shots = ValueNotifier(0);
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: () => tapped++,
                child: const ColoredBox(color: Colors.white),
              ),
              ShutterPulse(shots: shots),
            ],
          ),
        ),
      );
      double opacity() => tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(ShutterPulse),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;
      expect(opacity(), 0);
      shots.value++;
      await tester.pump();
      expect(opacity(), greaterThan(.3));
      await tester.tapAt(const Offset(100, 100));
      expect(tapped, 1);
      await tester.pump(const Duration(milliseconds: 170));
      expect(opacity(), 0);
      await tester.pumpWidget(const SizedBox());
      shots.dispose();
    },
  );
  testWidgets('Reduced-motion setting suppresses the screen pulse', (
    tester,
  ) async {
    final shots = ValueNotifier(0);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ShutterPulse(shots: shots),
        ),
      ),
    );
    shots.value++;
    await tester.pump(const Duration(milliseconds: 32));
    expect(
      tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value,
      0,
    );
    await tester.pumpWidget(const SizedBox());
    shots.dispose();
  });
  testWidgets(
    'Keep the shutter plain and show a ring only for slower captures',
    (tester) async {
      final phase = ValueNotifier(CapturePhase.idle);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 76,
              height: 76,
              child: CaptureButtonFace(phase: phase, color: Colors.green),
            ),
          ),
        ),
      );
      phase.value = CapturePhase.capturing;
      await tester.pump(const Duration(milliseconds: 249));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      phase.value = CapturePhase.saving;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      phase.value = CapturePhase.idle;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      phase.value = CapturePhase.capturing;
      await tester.pump(const Duration(milliseconds: 40));
      phase.value = CapturePhase.idle;
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      phase.dispose();
    },
  );
}
