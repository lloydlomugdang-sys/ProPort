import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/services/scanner/classical_cv_engine.dart';
import 'package:proport_app/services/scanner/live_scan_controller.dart';
import 'package:proport_app/services/scanner/live_scan_geometry.dart';

DocumentDetection detection({
  double shift = 0,
  bool confident = true,
  bool ambiguous = false,
}) => DocumentDetection(
  corners: confident
      ? DocumentCorners.fromList([
          Offset(.15 + shift, .15),
          Offset(.75 + shift, .15),
          Offset(.75 + shift, .85),
          Offset(.15 + shift, .85),
        ])
      : DocumentCorners.fullImage(),
  confidence: confident ? .9 : .1,
  edgeSupport: .9,
  weakestSideSupport: .9,
  areaFraction: .5,
  ambiguous: ambiguous,
);

void main() {
  final frame = GrayscaleFrame(Uint8List(10000), 100, 100);
  const geometry = ScanPreviewGeometry(frameSize: Size(100, 100));
  testWidgets(
    'similar quads stabilize, smooth jitter and reject an isolated jump',
    (tester) async {
      var now = 0;
      var result = detection();
      final controller = LiveScanController(
        clock: () => now,
        detector: (_) async => result,
      );
      for (var i = 0; i < 3; i++) {
        await controller.process(frame, geometry);
        now += 350;
      }
      expect(controller.stable, isTrue);
      final old = controller.corners!;
      result = detection(shift: .01);
      await controller.process(frame, geometry);
      expect(
        controller.corners!.topLeft.dx,
        closeTo(old.topLeft.dx + .0065, .0001),
      );
      now += 350;
      final smooth = controller.corners;
      result = detection(shift: .2);
      await controller.process(frame, geometry);
      expect(controller.corners, smooth);
      expect(controller.stable, isFalse);
      now += 350;
      await controller.process(frame, geometry);
      expect(controller.corners!.topLeft.dx, closeTo(.35, .0001));
      expect(controller.stable, isFalse);
      controller.dispose();
    },
  );
  testWidgets('disappearance expires outline; ambiguity is never ready', (
    tester,
  ) async {
    var now = 0;
    var result = detection();
    final controller = LiveScanController(
      clock: () => now,
      detector: (_) async => result,
    );
    addTearDown(controller.dispose);
    await controller.process(frame, geometry);
    now += 350;
    result = detection(confident: false);
    await controller.process(frame, geometry);
    expect(controller.stable, isFalse);
    await tester.pump(const Duration(milliseconds: 1001));
    expect(controller.corners, isNull);
    now += 1001;
    result = detection(ambiguous: true);
    await controller.process(frame, geometry);
    expect(controller.corners, isNull);
    expect(controller.stable, isFalse);
  });
  test(
    'single flight, throttling, reset and disposal ignore late work',
    () async {
      var now = 0;
      var calls = 0;
      var pending = Completer<DocumentDetection>();
      final controller = LiveScanController(
        clock: () => now,
        detector: (_) {
          calls++;
          return pending.future;
        },
      );
      var notifications = 0;
      controller.addListener(() {
        notifications++;
      });
      final running = controller.process(frame, geometry);
      now = 500;
      await controller.process(frame, geometry);
      expect(calls, 1);
      controller.reset();
      await controller.process(frame, geometry);
      expect(calls, 1); // Reset does not allow overlapping isolate work.
      pending.complete(detection());
      await running;
      expect(controller.corners, isNull);
      pending = Completer<DocumentDetection>();
      final second = controller.process(frame, geometry);
      expect(calls, 2);
      controller.dispose();
      final before = notifications;
      pending.complete(detection());
      await second;
      await controller.process(frame, geometry);
      expect(notifications, before);
      expect(calls, 2);
    },
  );
  test('elapsed-time scheduling and slow results stay conservative', () async {
    var now = 0;
    var calls = 0;
    final controller = LiveScanController(
      clock: () => now,
      detector: (_) async {
        calls++;
        now += 1500;
        return detection();
      },
    );
    addTearDown(controller.dispose);
    await controller.process(frame, geometry);
    expect(controller.corners, isNull);
    expect(controller.lastProcessingMilliseconds, 1500);
    await controller.process(frame, geometry);
    expect(calls, 1);
    now += 80;
    await controller.process(frame, geometry);
    expect(calls, 2);
  });
  test('orientation change resets old temporal evidence', () async {
    var now = 0;
    final controller = LiveScanController(
      clock: () => now,
      detector: (_) async => detection(),
    );
    addTearDown(controller.dispose);
    for (var i = 0; i < 3; i++) {
      await controller.process(frame, geometry);
      now += 350;
    }
    expect(controller.stable, isTrue);
    await controller.process(
      frame,
      const ScanPreviewGeometry(
        frameSize: Size(100, 100),
        clockwiseQuarterTurns: 1,
      ),
    );
    expect(controller.stable, isFalse);
  });
  test(
    'exceptionally strong candidate (confidence >= 0.95) becomes stable in 2 frames',
    () async {
      var now = 0;
      final controller = LiveScanController(
        clock: () => now,
        detector: (_) async => DocumentDetection(
          corners: DocumentCorners.fromList(const [
            Offset(.15, .15),
            Offset(.75, .15),
            Offset(.75, .85),
            Offset(.15, .85),
          ]),
          confidence: 0.96,
          edgeSupport: 0.95,
          weakestSideSupport: 0.92,
          areaFraction: 0.5,
          ambiguous: false,
        ),
      );
      addTearDown(controller.dispose);
      // 1st frame: first observation, _consistent = 1
      await controller.process(frame, geometry);
      now += 200;
      expect(controller.stable, isFalse);
      // 2nd frame: tight quad, _consistent = 2 → stable (strong detection)
      await controller.process(frame, geometry);
      expect(controller.stable, isTrue);
    },
  );
  test(
    'weak candidate (confidence < 0.88) still requires 3 consistent frames',
    () async {
      var now = 0;
      final controller = LiveScanController(
        clock: () => now,
        detector: (_) async => DocumentDetection(
          corners: DocumentCorners.fromList(const [
            Offset(.15, .15),
            Offset(.75, .15),
            Offset(.75, .85),
            Offset(.15, .85),
          ]),
          confidence: 0.80,
          edgeSupport: 0.78,
          weakestSideSupport: 0.72,
          areaFraction: 0.45,
          ambiguous: false,
        ),
      );
      addTearDown(controller.dispose);
      await controller.process(frame, geometry);
      now += 200;
      expect(controller.stable, isFalse);
      await controller.process(frame, geometry);
      now += 200;
      expect(controller.stable, isFalse); // Only 2 frames — still not ready
      await controller.process(frame, geometry);
      expect(controller.stable, isTrue); // 3rd frame → ready
    },
  );
  test(
    'loose-but-not-large jitter frame resets _consistent to 1 not 0',
    () async {
      var now = 0;
      var shift = 0.0;
      final controller = LiveScanController(
        clock: () => now,
        detector: (_) async => DocumentDetection(
          corners: DocumentCorners.fromList([
            Offset(.15 + shift, .15),
            Offset(.75 + shift, .15),
            Offset(.75 + shift, .85),
            Offset(.15 + shift, .85),
          ]),
          confidence: 0.91,
          edgeSupport: 0.90,
          weakestSideSupport: 0.85,
          areaFraction: 0.5,
          ambiguous: false,
        ),
      );
      addTearDown(controller.dispose);
      // Build up 2 consistent frames
      await controller.process(frame, geometry);
      now += 200;
      await controller.process(frame, geometry);
      now += 200;
      expect(controller.debugStabilizationCount, 2);
      // Now inject a slightly loose jitter (distance > 0.035 but < 0.12)
      shift = 0.06;
      await controller.process(frame, geometry);
      now += 200;
      // _consistent should be 1 (not 0) — jitter frame is "1 confirmed observation"
      expect(controller.debugStabilizationCount, 1);
      expect(controller.stable, isFalse);
    },
  );
  test('adaptive interval is 120 ms minimum instead of 350 ms', () {
    final controller = LiveScanController(
      clock: () => 0,
      detector: (_) async => detection(),
    );
    addTearDown(controller.dispose);
    // When last processing was fast, floor is 120 ms
    expect(controller.intervalMilliseconds, 120);
    // When processing was slow (300 ms), interval = 300 + 50 = 350 ms
    controller.lastProcessingMilliseconds = 300;
    expect(controller.intervalMilliseconds, 350);
    // When processing was very slow (1500 ms), interval = 1500 + 50 = 1550 ms
    controller.lastProcessingMilliseconds = 1500;
    expect(controller.intervalMilliseconds, 1550);
  });
  test(
    'one noisy frame does not reset stable tracking; real movement causes reacquisition and oriented hint maps rotation',
    () async {
      var now = 0;
      var shift = 0.0;
      final controller = LiveScanController(
        clock: () => now,
        detector: (_) async => DocumentDetection(
          corners: DocumentCorners.fromList([
            Offset(.15 + shift, .15),
            Offset(.75 + shift, .15),
            Offset(.75 + shift, .85),
            Offset(.15 + shift, .85),
          ]),
          confidence: 0.91,
          edgeSupport: 0.90,
          weakestSideSupport: 0.85,
          areaFraction: 0.5,
          ambiguous: false,
        ),
      );
      addTearDown(controller.dispose);
      const rotatedGeometry = ScanPreviewGeometry(
        frameSize: Size(100, 100),
        clockwiseQuarterTurns: 1,
      );

      // Reach stable state (3 consistent frames)
      for (var i = 0; i < 3; i++) {
        await controller.process(frame, rotatedGeometry);
        now += 200;
      }
      expect(controller.stable, isTrue);
      expect(controller.stableOrientedCorners, isNotNull);
      expect(controller.stableOrientedCorners!.isAutoDetected, isTrue);

      // Single moderate noisy frame (distance 0.05 <= 0.08): hysteresis keeps stable = true
      shift = 0.05;
      await controller.process(frame, rotatedGeometry);
      now += 200;
      expect(controller.stable, isTrue);

      // Real document movement (distance > 0.12) requires reacquisition
      shift = 0.22;
      await controller.process(frame, rotatedGeometry);
      now += 200;
      expect(
        controller.stable,
        isFalse,
      ); // 1st frame at new position: isolated jump ignored
      await controller.process(frame, rotatedGeometry);
      now += 200;
      expect(
        controller.stable,
        isFalse,
      ); // 2nd frame confirms new position (_consistent = 1)
      expect(controller.debugStabilizationCount, 1);
      await controller.process(frame, rotatedGeometry);
      now += 200;
      expect(controller.stable, isFalse); // _consistent = 2
      await controller.process(frame, rotatedGeometry);
      now += 200;
      expect(controller.stable, isTrue); // _consistent = 3 -> reacquired!
    },
  );
}
