import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/services/scanner/classical_cv_engine.dart';
import 'package:proport_app/services/scanner/live_scan_geometry.dart';
import 'package:proport_app/services/scanner/scanner_camera.dart';

import 'helpers/scanner_fixture.dart';

void main() {
  test('portrait sensor rotation maps raw corners to preview bounds', () {
    const geometry = ScanPreviewGeometry(
      frameSize: Size(640, 480),
      clockwiseQuarterTurns: 1,
    );
    expect(geometry.orientedSize, const Size(480, 640));
    expect(
      geometry.map(Offset.zero, const Size(300, 400)),
      const Offset(300, 0),
    );
    expect(
      geometry.map(const Offset(1, 1), const Size(300, 400)),
      const Offset(0, 400),
    );
    for (final corner in DocumentCorners.fullImage().toList()) {
      final mapped = geometry.map(corner, const Size(300, 400));
      expect(mapped.dx, inInclusiveRange(0, 300));
      expect(mapped.dy, inInclusiveRange(0, 400));
    }
  });
  test('landscape and all quarter-turn mappings including mirror', () {
    const expected = [
      Offset(.2, .3),
      Offset(.7, .2),
      Offset(.8, .7),
      Offset(.3, .8),
    ];
    for (var turn = 0; turn < 4; turn++) {
      final g = ScanPreviewGeometry(
        frameSize: const Size(640, 480),
        clockwiseQuarterTurns: turn,
      );
      expect(
        (g.orient(const Offset(.2, .3)) - expected[turn]).distance,
        lessThan(1e-10),
      );
    }
    const landscape = ScanPreviewGeometry(frameSize: Size(640, 480));
    expect(
      landscape.map(const Offset(.25, .5), const Size(800, 600)),
      const Offset(200, 300),
    );
    const mirror = ScanPreviewGeometry(
      frameSize: Size(640, 480),
      clockwiseQuarterTurns: 1,
      mirrored: true,
    );
    expect(
      (mirror.orient(const Offset(.2, .3)) - const Offset(.3, .2)).distance,
      lessThan(1e-10),
    );
  });
  test('cover uses exact center crop, contain uses exact letterbox', () {
    const g = ScanPreviewGeometry(frameSize: Size(400, 300));
    expect(g.map(Offset.zero, const Size(300, 600)), const Offset(-250, 0));
    expect(
      g.map(const Offset(.5, .5), const Size(300, 600)),
      const Offset(150, 300),
    );
    // Visible left/right border, not incorrectly clamped document vertices.
    expect(g.map(const Offset(.3125, 0), const Size(300, 600)), Offset.zero);
    expect(
      g.map(const Offset(.6875, 1), const Size(300, 600)),
      const Offset(300, 600),
    );
    expect(
      g.map(Offset.zero, const Size(300, 600), fit: BoxFit.contain),
      const Offset(0, 187.5),
    );
    expect(
      g.map(const Offset(1, 1), const Size(300, 600), fit: BoxFit.contain),
      const Offset(300, 412.5),
    );
    expect(g.matchesPreview(const Size(1920, 1080)), isFalse);
    expect(g.matchesPreview(const Size(800, 600)), isTrue);
  });
  test('rear sensor and device orientation compensation', () {
    expect(sensorQuarterTurns(90, DeviceOrientation.portraitUp), 1);
    expect(sensorQuarterTurns(90, DeviceOrientation.landscapeLeft), 0);
    expect(sensorQuarterTurns(90, DeviceOrientation.landscapeRight), 2);
    expect(sensorQuarterTurns(90, DeviceOrientation.portraitDown), 3);
    expect(sensorQuarterTurns(270, DeviceOrientation.portraitUp), 3);
  });
  test('Y luma sampling respects padded row and pixel strides', () {
    final frame = sampleCameraLuminance(
      bytes: Uint8List.fromList([10, 0, 20, 0, 0, 0, 30, 0, 40]),
      width: 2,
      height: 2,
      bytesPerRow: 6,
      bytesPerPixel: 2,
    );
    expect(frame.pixels, [10, 20, 30, 40]);
  });
  test('BGRA uses color luminance with row padding', () {
    final frame = sampleCameraLuminance(
      bytes: Uint8List.fromList([0, 0, 255, 255, 9, 9, 255, 255, 255, 255]),
      width: 1,
      height: 2,
      bytesPerRow: 6,
      bytesPerPixel: 4,
      bgra: true,
    );
    expect(frame.pixels, [76, 255]);
    expect(
      () => sampleCameraLuminance(
        bytes: Uint8List(3),
        width: 2,
        height: 2,
        bytesPerRow: 2,
        bytesPerPixel: 1,
      ),
      throwsFormatException,
    );
  });
  test(
    'camera frames are bounded and owned; detector preserves shared scoring',
    () {
      final photo = scannerPhoto(width: 1280, height: 960);
      final luma = Uint8List(1280 * 960);
      for (var y = 0; y < 960; y++) {
        for (var x = 0; x < 1280; x++) {
          luma[y * 1280 + x] = photo.getPixel(x, y).r.toInt();
        }
      }
      final frame = sampleCameraLuminance(
        bytes: luma,
        width: 1280,
        height: 960,
        bytesPerRow: 1280,
        bytesPerPixel: 1,
      );
      expect(frame.width, 640);
      expect(frame.height, 480);
      luma.fillRange(0, luma.length, 0);
      final watch = Stopwatch()..start();
      final detected = ClassicalCvEngine.detectGrayscale(frame);
      watch.stop();
      // Host timing only, not a physical-phone frame-rate claim.
      debugPrint(
        'Live classical CV 640x480 host pass: ${watch.elapsedMilliseconds} ms',
      );
      expect(detected.isConfident, isTrue);
      expect(
        ClassicalCvEngine.detectGrayscale(
          GrayscaleFrame(Uint8List(801 * 50), 801, 50),
        ).isConfident,
        isFalse,
      );
    },
  );
}
