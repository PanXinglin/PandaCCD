import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/ui/preview_handoff.dart';

void main() {
  PreviewStatus status(int frame, int stable, [int age = 12]) =>
      (frame: frame, stable: stable, ageMs: age);

  test('Live reveal waits for fresh frames and stable exposure', () {
    final gate = PreviewHandoff();
    expect(gate.observe(null), false);
    expect(gate.observe(status(10, 10)), false);
    expect(gate.observe(status(11, 10)), false);
    expect(gate.observe(status(13, 0)), false);
    expect(gate.observe(status(15, 2)), false);
    expect(gate.observe(status(16, 3, 190)), false);
    expect(gate.observe(status(17, 4)), true);
  });

  test('Rear Live stays covered while a new optical configuration settles', () {
    final gate = PreviewHandoff(stableFrames: 10);
    expect(gate.observe(status(12, 2)), false);
    expect(gate.observe(status(20, 9)), false);
    expect(gate.observe(status(21, 0)), false);
    expect(gate.observe(status(30, 9)), false);
    expect(gate.observe(status(31, 10)), true);
  });
}
