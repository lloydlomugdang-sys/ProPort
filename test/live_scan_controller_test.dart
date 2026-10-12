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
}
