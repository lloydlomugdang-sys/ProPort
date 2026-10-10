import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:proport_app/services/scanner/classical_cv_engine.dart';

import 'helpers/scanner_fixture.dart';

void main() {
  void expectDetected(img.Image image, List<Offset> expected) {
    final bytes = scannerBytes(image);
    final result = ClassicalCvEngine.detectDocument(bytes);
    expect(
      result.isConfident,
      isTrue,
      reason:
          'score=${result.confidence}, edges=${result.edgeSupport}, weakest=${result.weakestSideSupport}, ambiguous=${result.ambiguous}',
    );
    expect(result.confidence, inInclusiveRange(.78, 1));
    final ordered = ClassicalCvEngine.orderCorners(expected);
    for (var i = 0; i < 4; i++) {
      expect(
        (result.corners.toList()[i] - ordered[i]).distance,
        lessThan(.035),
      );
    }
    final corrected = img.decodeJpg(
      ClassicalCvEngine.warpAndEnhance(
        imageBytes: bytes,
        corners: result.corners,
        mode: ScanEnhancementMode.original,
      ),
    )!;
    expect(corrected.width, greaterThan(20));
    expect(corrected.height, greaterThan(20));
    expect(
      corrected.getPixel(corrected.width ~/ 10, corrected.height ~/ 10).r,
      greaterThan(140),
    );
  }

  const rectangle = [
    Offset(.15, .12),
    Offset(.85, .12),
    Offset(.85, .88),
    Offset(.15, .88),
  ];
  for (final size in [(400, 560), (560, 400)]) {
    test('confident contrasting document ${size.$1}x${size.$2}', () {
      expectDetected(scannerPhoto(width: size.$1, height: size.$2), rectangle);
    });
  }
  test(
    'rotated page and symmetric diamond have distinct clockwise corners',
    () {
      const rotated = [
        Offset(.30, .08),
        Offset(.88, .30),
        Offset(.67, .92),
        Offset(.09, .70),
      ];
      expectDetected(scannerPhoto(corners: rotated), rotated);
      const diamond = [
        Offset(.5, .06),
        Offset(.94, .5),
        Offset(.5, .94),
        Offset(.06, .5),
      ];
      final ordered = ClassicalCvEngine.orderCorners(diamond.reversed.toList());
      expect(ordered, diamond);
      expectDetected(
        scannerPhoto(width: 400, height: 400, corners: diamond),
        diamond,
      );
    },
  );
  test('perspective page produces a flat non-mirrored result', () {
    const angled = [
      Offset(.24, .10),
      Offset(.76, .18),
      Offset(.92, .89),
      Offset(.08, .82),
    ];
    final photo = scannerPhoto(corners: angled);
    expectDetected(photo, angled);
    // Distinct colors in the four source quadrants expose rotations/mirroring.
    for (var y = 0; y < photo.height; y++) {
      for (var x = 0; x < photo.width; x++) {
        if (photo.getPixel(x, y).r < 200) continue;
        photo.setPixelRgb(
          x,
          y,
          x < photo.width / 2 ? 230 : 20,
          y < photo.height / 2 ? 230 : 20,
          20,
        );
      }
    }
    final output = img.decodeJpg(
      ClassicalCvEngine.warpAndEnhance(
        imageBytes: scannerBytes(photo),
        corners: DocumentCorners.fromList(angled),
        mode: ScanEnhancementMode.original,
      ),
    )!;
    final tl = output.getPixel(output.width ~/ 5, output.height ~/ 5);
    final tr = output.getPixel(output.width * 4 ~/ 5, output.height ~/ 5);
    final br = output.getPixel(output.width * 4 ~/ 5, output.height * 4 ~/ 5);
    final bl = output.getPixel(output.width ~/ 5, output.height * 4 ~/ 5);
    expect(tl.r, greaterThan(200));
    expect(tl.g, greaterThan(200));
    expect(tr.r, lessThan(50));
    expect(tr.g, greaterThan(200));
    expect(br.r, lessThan(50));
    expect(br.g, lessThan(50));
    expect(bl.r, greaterThan(200));
    expect(bl.g, lessThan(50));
  });
  test('nearly full-frame contour longer than 2000 pixels is retained', () {
    const close = [
      Offset(.008, .01),
      Offset(.99, .01),
      Offset(.99, .99),
      Offset(.008, .99),
    ];
    expectDetected(
      scannerPhoto(width: 1000, height: 900, corners: close),
      close,
    );
  });
  test('one frame-touching side can use three strong document boundaries', () {
    const close = [
      Offset(0, .12),
      Offset(.85, .12),
      Offset(.85, .88),
      Offset(0, .88),
    ];
    expectDetected(scannerPhoto(corners: close), close);
  });
  test('paper beats smaller rectangles, text boxes and desk clutter', () {
    final photo = scannerPhoto(width: 600, height: 500);
    img.fillRect(
      photo,
      x1: 12,
      y1: 25,
      x2: 60,
      y2: 80,
      color: img.ColorRgb8(250, 250, 250),
    );
    img.fillRect(
      photo,
      x1: 210,
      y1: 180,
      x2: 340,
      y2: 260,
      color: img.ColorRgb8(40, 40, 40),
    );
    for (var y = 90; y < 150; y += 12) {
      img.drawLine(
        photo,
        x1: 140,
        y1: y,
        x2: 430,
        y2: y,
        color: img.ColorRgb8(60, 60, 60),
      );
    }
    expectDetected(photo, rectangle);
  });
  test('moderate blur, illumination gradient and noise retain the page', () {
    final photo = scannerPhoto(noise: 14, shadow: true);
    expectDetected(img.gaussianBlur(photo, radius: 2), rectangle);
  });
  test(
    'blank, very low contrast, tiny and thin objects keep the full image',
    () {
      final cases = [
        scannerPhoto(paper: 180, background: 180),
        scannerPhoto(paper: 184, background: 180, noise: 2),
        scannerPhoto(
          corners: const [
            Offset(.4, .4),
            Offset(.6, .4),
            Offset(.6, .6),
            Offset(.4, .6),
          ],
        ),
        scannerPhoto(
          corners: const [
            Offset(.1, .45),
            Offset(.9, .45),
            Offset(.9, .50),
            Offset(.1, .50),
          ],
        ),
      ];
      for (final photo in cases) {
        final bytes = scannerBytes(photo);
        final result = ClassicalCvEngine.detectDocument(bytes);
        expect(result.isConfident, isFalse);
        expect(result.corners, DocumentCorners.fullImage());
        final output = img.decodeJpg(
          ClassicalCvEngine.warpAndEnhance(
            imageBytes: bytes,
            corners: result.corners,
            mode: ScanEnhancementMode.original,
          ),
        )!;
        expect(output.width, photo.width);
        expect(output.height, photo.height);
      }
    },
  );
  test(
    'two similarly plausible documents request review instead of guessing',
    () {
      final photo = scannerPhoto(width: 600, height: 400, paper: 45);
      for (final x in [30, 330]) {
        img.fillRect(
          photo,
          x1: x,
          y1: 40,
          x2: x + 240,
          y2: 360,
          color: img.ColorRgb8(230, 230, 230),
        );
      }
      final result = ClassicalCvEngine.detectDocument(scannerBytes(photo));
      expect(result.ambiguous, isTrue);
      expect(result.isConfident, isFalse);
      expect(result.corners, DocumentCorners.fullImage());
    },
  );
  for (final orientation in [3, 6, 8]) {
    test(
      'EXIF orientation $orientation is shared by detection and correction',
      () {
        final photo = scannerPhoto(width: 500, height: 300);
        photo.exif.imageIfd.orientation = orientation;
        final bytes = scannerBytes(photo);
        final result = ClassicalCvEngine.detectDocument(bytes);
        expect(result.isConfident, isTrue);
        final output = img.decodeJpg(
          ClassicalCvEngine.warpAndEnhance(
            imageBytes: bytes,
            corners: result.corners,
            mode: ScanEnhancementMode.original,
          ),
        )!;
        expect(output.width > output.height, orientation == 3);
        expect(output.exif.imageIfd.orientation, anyOf(isNull, 1));
      },
    );
  }
  test('large-resolution detection maps back to OCR-quality source pixels', () {
    final photo = scannerPhoto(width: 2400, height: 1800);
    final bytes = scannerBytes(photo);
    final result = ClassicalCvEngine.detectDocument(bytes);
    expect(result.isConfident, isTrue);
    expect((result.corners.topLeft - rectangle.first).distance, lessThan(.02));
    final output = img.decodeJpg(
      ClassicalCvEngine.warpAndEnhance(
        imageBytes: bytes,
        corners: result.corners,
        mode: ScanEnhancementMode.original,
      ),
    )!;
    expect(output.width, greaterThan(1500));
    expect(output.height, greaterThan(1200));
  });
  test('output limits scale both dimensions together without squashing', () {
    final photo = scannerPhoto(
      width: 4400,
      height: 220,
      paper: 200,
      background: 200,
    );
    final output = img.decodeJpg(
      ClassicalCvEngine.warpAndEnhance(
        imageBytes: scannerBytes(photo),
        corners: DocumentCorners.fullImage(),
        mode: ScanEnhancementMode.original,
      ),
    )!;
    expect(output.width, 4096);
    expect(output.width / output.height, closeTo(20, .06));
  });
  test('invalid and mirrored corner geometry is rejected safely', () {
    final bytes = scannerBytes(scannerPhoto());
    for (final points in [
      [Offset.zero, Offset.zero, const Offset(1, 1), const Offset(0, 1)],
      [Offset.zero, const Offset(1, 1), const Offset(1, 0), const Offset(0, 1)],
      [
        Offset.zero,
        const Offset(.5, 0),
        const Offset(1, 0),
        const Offset(0, 1),
      ],
      [Offset.zero, const Offset(0, 1), const Offset(1, 1), const Offset(1, 0)],
      [
        const Offset(double.nan, 0),
        const Offset(1, 0),
        const Offset(1, 1),
        const Offset(0, 1),
      ],
      [
        const Offset(-.1, 0),
        const Offset(1, 0),
        const Offset(1, 1),
        const Offset(0, 1),
      ],
    ]) {
      expect(
        () => ClassicalCvEngine.warpAndEnhance(
          imageBytes: bytes,
          corners: DocumentCorners.fromList(points),
        ),
        throwsArgumentError,
      );
    }
  });
  test('enhancement preserves nearly uniform paper and faint details', () {
    final photo = scannerPhoto(
      width: 160,
      height: 120,
      paper: 230,
      background: 230,
    );
    img.drawLine(
      photo,
      x1: 10,
      y1: 60,
      x2: 150,
      y2: 60,
      color: img.ColorRgb8(205, 210, 215),
    );
    final output = img.decodeJpg(
      ClassicalCvEngine.warpAndEnhance(
        imageBytes: scannerBytes(photo),
        corners: DocumentCorners.fullImage(),
      ),
    )!;
    expect(output.getPixel(40, 30).r, greaterThan(220));
    expect(output.getPixel(40, 60).r, lessThan(output.getPixel(40, 30).r));
    expect(math.min(output.width, output.height), greaterThan(0));
  });
}
