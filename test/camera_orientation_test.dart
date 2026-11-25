import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ccd/services/camera_orientation.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  testWidgets(
    'Expanded display releases portrait lock and returns safely to compact policy',
    (tester) async {
      final samples = StreamController<AccelerometerEvent>(sync: true);
      final requests = <List<DeviceOrientation>>[];
      final service = CameraOrientation(
        samples: () => samples.stream,
        request: (value) async {
          requests.add(value);
        },
      );
      service.start();
      samples.add(AccelerometerEvent(9.81, 0, 0, DateTime.now()));
      await tester.pump(const Duration(milliseconds: 100));
      service.setExpanded(true);
      await tester.pump(const Duration(seconds: 1));
      expect(requests.last, isEmpty);
      expect(service.orientation, isNull);
      samples.add(AccelerometerEvent(-9.81, 0, 0, DateTime.now()));
      await tester.pump(const Duration(seconds: 1));
      final releasedRequests = requests.length;
      expect(requests.last, isEmpty);
      service.setExpanded(false);
      samples.add(AccelerometerEvent(0, 9.81, 0, DateTime.now()));
      await tester.pump(const Duration(milliseconds: 400));
      expect(requests.last, [DeviceOrientation.portraitUp]);
      expect(requests.length, releasedRequests + 1);
      service.dispose();
      await tester.pump();
      unawaited(samples.close());
    },
  );
  test(
    'Gravity axes distinguish both landscape grips and reject unstable poses',
    () {
      expect(cameraGrip(9.81, 0, 0), DeviceOrientation.landscapeLeft);
      expect(cameraGrip(-9.81, 0, 0), DeviceOrientation.landscapeRight);
      expect(cameraGrip(0, 9.81, 0), DeviceOrientation.portraitUp);
      expect(cameraGrip(0, 0, 9.81), isNull);
      expect(cameraGrip(7, 7, 0), isNull);
      expect(cameraGrip(18, 0, 0), isNull);
    },
  );

  testWidgets(
    'Only controls turn for a stable grip; disposal restores OS policy',
    (tester) async {
      final samples = StreamController<AccelerometerEvent>(sync: true);
      final requests = <List<DeviceOrientation>>[];
      final service = CameraOrientation(
        samples: () => samples.stream,
        request: (value) async {
          requests.add(value);
        },
      );
      void pose(double x, double y, double z) {
        samples.add(AccelerometerEvent(x, y, z, DateTime.now()));
      }

      service.start();
      pose(9.81, 0, 0);
      await tester.pump(const Duration(milliseconds: 200));
      pose(-9.81, 0, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(requests, [
        [DeviceOrientation.portraitUp],
      ]);
      await tester.pump(const Duration(milliseconds: 151));
      expect(service.orientation, DeviceOrientation.landscapeRight);
      expect(requests.single, [DeviceOrientation.portraitUp]);
      pose(0, 0, 9.81);
      await tester.pump(const Duration(seconds: 1));
      expect(requests.length, 1);
      pose(0, 9.81, 0);
      service.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(requests.last, isEmpty);
      expect(requests.length, 2);
      unawaited(samples.close());
    },
  );
}
