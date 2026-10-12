// LOCATION: lib/services/scanner/classical_cv_engine.dart
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Represents the four ordered corners of a detected or adjusted document quadrilateral.
///
/// All coordinates are normalized in the range `[0.0, 1.0]` relative to image width and height.
@immutable
class DocumentCorners {
  const DocumentCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
    this.isAutoDetected = true,
  });

  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  /// True if automatically detected by the classical CV pipeline;
  /// false if fallback default positions were used or manually adjusted.
  final bool isAutoDetected;

  /// Safe detection fallback: no part of the capture is discarded.
  factory DocumentCorners.fullImage() => const DocumentCorners(
    topLeft: Offset.zero,
    topRight: Offset(1, 0),
    bottomRight: Offset(1, 1),
    bottomLeft: Offset(0, 1),
    isAutoDetected: false,
  );

  /// Optional manual inset. Detection failures use [DocumentCorners.fullImage].
  factory DocumentCorners.defaultInset({double insetFraction = 0.06}) {
    final min = insetFraction.clamp(0.01, 0.25);
    final max = 1.0 - min;
    return DocumentCorners(
      topLeft: Offset(min, min),
      topRight: Offset(max, min),
      bottomRight: Offset(max, max),
      bottomLeft: Offset(min, max),
      isAutoDetected: false,
    );
  }

  /// Constructs from an ordered list of 4 points: [TL, TR, BR, BL].
  factory DocumentCorners.fromList(
    List<Offset> points, {
    bool isAutoDetected = true,
  }) {
    if (points.length != 4) {
      throw ArgumentError('DocumentCorners requires exactly 4 points.');
    }
    return DocumentCorners(
      topLeft: points[0],
      topRight: points[1],
      bottomRight: points[2],
      bottomLeft: points[3],
      isAutoDetected: isAutoDetected,
    );
  }

  /// Constructs from 4 arbitrary quadrilateral points, ordering them into [TL, TR, BR, BL].
  factory DocumentCorners.ordered(
    List<Offset> points, {
    bool isAutoDetected = true,
  }) {
    return DocumentCorners.fromList(
      ClassicalCvEngine.orderCorners(points),
      isAutoDetected: isAutoDetected,
    );
  }

  List<Offset> toList() => [topLeft, topRight, bottomRight, bottomLeft];

  /// Scales normalized corners to absolute pixel coordinates for an image of given dimensions.
  DocumentCorners toAbsolute(double width, double height) {
    return DocumentCorners(
      topLeft: Offset(topLeft.dx * width, topLeft.dy * height),
      topRight: Offset(topRight.dx * width, topRight.dy * height),
      bottomRight: Offset(bottomRight.dx * width, bottomRight.dy * height),
      bottomLeft: Offset(bottomLeft.dx * width, bottomLeft.dy * height),
      isAutoDetected: isAutoDetected,
    );
  }

  /// Normalizes absolute pixel coordinates to `[0.0, 1.0]` for an image of given dimensions.
  DocumentCorners toNormalized(double width, double height) {
    if (width <= 0 || height <= 0) return this;
    return DocumentCorners(
      topLeft: Offset(
        (topLeft.dx / width).clamp(0.0, 1.0),
        (topLeft.dy / height).clamp(0.0, 1.0),
      ),
      topRight: Offset(
        (topRight.dx / width).clamp(0.0, 1.0),
        (topRight.dy / height).clamp(0.0, 1.0),
      ),
      bottomRight: Offset(
        (bottomRight.dx / width).clamp(0.0, 1.0),
        (bottomRight.dy / height).clamp(0.0, 1.0),
      ),
      bottomLeft: Offset(
        (bottomLeft.dx / width).clamp(0.0, 1.0),
        (bottomLeft.dy / height).clamp(0.0, 1.0),
      ),
      isAutoDetected: isAutoDetected,
    );
  }

  DocumentCorners copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
    bool? isAutoDetected,
  }) {
    return DocumentCorners(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
      isAutoDetected: isAutoDetected ?? this.isAutoDetected,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentCorners &&
          runtimeType == other.runtimeType &&
          topLeft == other.topLeft &&
          topRight == other.topRight &&
          bottomRight == other.bottomRight &&
          bottomLeft == other.bottomLeft &&
          isAutoDetected == other.isAutoDetected;

  @override
  int get hashCode =>
      Object.hash(topLeft, topRight, bottomRight, bottomLeft, isAutoDetected);

  @override
  String toString() =>
      'DocumentCorners(TL: $topLeft, TR: $topRight, BR: $bottomRight, BL: $bottomLeft, auto: $isAutoDetected)';
}

/// Deterministic image enhancement modes.
enum ScanEnhancementMode {
  /// Unmodified cropped RGB document.
  original,

  /// Contrast stretched with conservative unsharp mask for crisp text glyphs.
  enhanced,

  /// Deterministic luminance conversion.
  grayscale,

  /// Adaptive local thresholding binarization.
  blackAndWhite,
}

/// Parameters passed to the background Isolate for perspective warping and enhancement.
class WarpParams {
  const WarpParams({
    required this.imageBytes,
    required this.corners,
    this.mode = ScanEnhancementMode.enhanced,
    this.jpegQuality = 90,
  });

  final Uint8List imageBytes;
  final DocumentCorners corners;
  final ScanEnhancementMode mode;
  final int jpegQuality;
}

/// Boundary decision with inspectable, deterministic geometric evidence.
@immutable
class DocumentDetection {
  const DocumentDetection({
    required this.corners,
    required this.confidence,
    required this.edgeSupport,
    required this.weakestSideSupport,
    required this.areaFraction,
    required this.ambiguous,
  });

  final DocumentCorners corners;

  /// Geometric/evidence score, not a calibrated probability or OCR confidence.
  final double confidence;
  final double edgeSupport;
  final double weakestSideSupport;
  final double areaFraction;
  final bool ambiguous;
  bool get isConfident => corners.isAutoDetected;
}

/// Owned, tightly packed luminance pixels. Live frames are sampled before they
/// cross the isolate boundary; neither full camera buffers nor JPEGs are queued.
class GrayscaleFrame {
  const GrayscaleFrame(this.pixels, this.width, this.height);
  final Uint8List pixels;
  final int width;
  final int height;
}

/// Classical edge/region detection, polygon approximation, homography and
/// enhancement. No trained models or neural document detection.
class ClassicalCvEngine {
  const ClassicalCvEngine._();

  /// Detects the 4 corners of a document within the provided image bytes using classical CV.
  ///
  /// Safe to call synchronously or in a background Isolate.
  static DocumentCorners detectCorners(Uint8List imageBytes) {
    return detectDocument(imageBytes).corners;
  }

  static DocumentDetection detectDocument(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null || decoded.width < 50 || decoded.height < 50) {
      return _detectionResult(null, false, 1, 1);
    }

    final original = _normalizeOrientation(decoded);
    final origW = original.width;
    final origH = original.height;

    // Downscale for analysis (max dimension 800) for real-time edge processing.
    const maxDimension = 800;
    final scale = math.min(1.0, maxDimension / math.max(origW, origH));
    final analysisW = math.max(1, (origW * scale).round());
    final analysisH = math.max(1, (origH * scale).round());

    final analysisImage = (scale < 1.0)
        ? img.copyResize(
            original,
            width: analysisW,
            height: analysisH,
            interpolation: img.Interpolation.linear,
          )
        : original;

    // 1. Grayscale conversion (CCIR 601 luminance: 0.299R + 0.587G + 0.114B)
    final gray = Uint8List(analysisW * analysisH);
    for (var y = 0; y < analysisH; y++) {
      final rowOffset = y * analysisW;
      for (var x = 0; x < analysisW; x++) {
        final p = analysisImage.getPixel(x, y);
        gray[rowOffset + x] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b)
            .round()
            .clamp(0, 255);
      }
    }

    return detectGrayscale(GrayscaleFrame(gray, analysisW, analysisH));
  }

  /// Shared still/live detector: exactly the same candidates, scoring and
  /// conservative confidence gates. Callers must supply a bounded image.
  static DocumentDetection detectGrayscale(GrayscaleFrame frame) {
    final analysisW = frame.width;
    final analysisH = frame.height;
    if (analysisW < 50 ||
        analysisH < 50 ||
        analysisW > 800 ||
        analysisH > 800 ||
        frame.pixels.length != analysisW * analysisH) {
      return _detectionResult(null, false, 1, 1);
    }
    final gray = frame.pixels;
    // 2. Gaussian Noise Reduction (5x5 separable kernel [1, 4, 6, 4, 1] / 16)
    final blurred = _applyGaussian5x5(gray, analysisW, analysisH);

    // 3. Sobel Gradient Magnitude & Direction
    final gradients = _computeSobelGradients(blurred, analysisW, analysisH);

    // 4. Canny Non-Maximum Suppression (NMS)
    final nms = _applyNonMaxSuppression(gradients, analysisW, analysisH);

    // 5. Dual-Threshold Hysteresis Edge Extraction
    final edges = _applyHysteresis(nms, analysisW, analysisH);

    // Connected edge hulls plus luminance-region hulls recover fragmented edges
    // and documents close to the frame. Region candidates still need real edges.
    final contours = _findContours(edges, analysisW, analysisH);
    final threshold = _otsuThreshold(blurred);
    for (final bright in [true, false]) {
      final mask = Uint8List(blurred.length);
      for (var i = 0; i < mask.length; i++) {
        if ((blurred[i] > threshold) == bright) mask[i] = 255;
      }
      contours.addAll(_findContours(mask, analysisW, analysisH));
    }
    final candidates = _rankQuadrilaterals(
      contours,
      edges,
      blurred,
      analysisW,
      analysisH,
    );
    final best = candidates.firstOrNull;
    // Comparable, spatially distinct candidates need a human decision.
    final ambiguous =
        best != null &&
        candidates
            .skip(1)
            .any(
              (other) =>
                  best.score - other.score < 0.045 &&
                  _cornerDistance(best.points, other.points) >
                      math.min(analysisW, analysisH) * 0.12,
            );
    return _detectionResult(best, ambiguous, analysisW, analysisH);
  }

  static DocumentDetection _detectionResult(
    _QuadCandidate? best,
    bool ambiguous,
    int w,
    int h,
  ) {
    final confident =
        best != null &&
        !ambiguous &&
        best.score >= 0.78 &&
        best.edgeSupport >= 0.72 &&
        best.weakestSide >= 0.48 &&
        best.contrast >= 0.20;
    return DocumentDetection(
      corners: confident
          ? DocumentCorners.fromList(
              best.points
                  .map(
                    (p) => Offset(
                      (p.dx / (w - 1)).clamp(0.0, 1.0),
                      (p.dy / (h - 1)).clamp(0.0, 1.0),
                    ),
                  )
                  .toList(),
            )
          : DocumentCorners.fullImage(),
      confidence: best?.score ?? 0,
      edgeSupport: best?.edgeSupport ?? 0,
      weakestSideSupport: best?.weakestSide ?? 0,
      areaFraction: best?.areaFraction ?? 0,
      ambiguous: ambiguous,
    );
  }

  /// Runs corner detection in a background Isolate.
  static Future<DocumentCorners> detectCornersAsync(Uint8List imageBytes) {
    return compute(detectCorners, imageBytes);
  }

  /// Warps the perspective of the document using projective homography and applies deterministic enhancement.
  ///
  /// Processes the full-resolution source image using the 4 normalized corners.
  static Uint8List warpAndEnhance({
    required Uint8List imageBytes,
    required DocumentCorners corners,
    ScanEnhancementMode mode = ScanEnhancementMode.enhanced,
    int jpegQuality = 90,
  }) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw const FormatException(
        'Unable to decode source image for document warping.',
      );
    }

    final image = _normalizeOrientation(decoded);
    final srcW = image.width;
    final srcH = image.height;

    // Convert normalized corners to full-res pixel space
    if (corners.toList().any(
      (p) =>
          !p.dx.isFinite ||
          !p.dy.isFinite ||
          p.dx < 0 ||
          p.dx > 1 ||
          p.dy < 0 ||
          p.dy > 1,
    )) {
      throw ArgumentError(
        'Corners must be finite normalized image coordinates.',
      );
    }
    final absolute = corners.toAbsolute(
      (srcW - 1).toDouble(),
      (srcH - 1).toDouble(),
    );
    final absTL = absolute.topLeft;
    final absTR = absolute.topRight;
    final absBR = absolute.bottomRight;
    final absBL = absolute.bottomLeft;

    // Validate geometry against degenerate quadrilateral
    if (!_isConvexQuad(absTL, absTR, absBR, absBL) ||
        _cross(absTL, absTR, absBR) <= 0) {
      throw ArgumentError(
        'The selected corners form a self-intersecting or concave polygon.',
      );
    }

    // Compute target rectangle dimensions
    final widthTop = (absTR - absTL).distance;
    final widthBottom = (absBR - absBL).distance;
    final heightLeft = (absBL - absTL).distance;
    final heightRight = (absBR - absTR).distance;

    final nativeW = math.max(widthTop, widthBottom) + 1;
    final nativeH = math.max(heightLeft, heightRight) + 1;
    // Uniform scaling preserves geometry; bound the output to 8 MP / 4096 px.
    final outputScale = math.min(
      1.0,
      math.min(
        4096 / math.max(nativeW, nativeH),
        math.sqrt(8000000 / (nativeW * nativeH)),
      ),
    );
    final targetW = math.max(2, (nativeW * outputScale).round());
    final targetH = math.max(2, (nativeH * outputScale).round());

    // Solve Closed-Form Projective Homography: Destination (0..1) -> Source (x, y)
    // Mapping from unit rectangle to quadrilateral (Heckbert, 1989)
    final x0 = absTL.dx;
    final y0 = absTL.dy;
    final x1 = absTR.dx;
    final y1 = absTR.dy;
    final x2 = absBR.dx;
    final y2 = absBR.dy;
    final x3 = absBL.dx;
    final y3 = absBL.dy;

    final dx1 = x1 - x2;
    final dx2 = x3 - x2;
    final dx3 = x0 - x1 + x2 - x3;
    final dy1 = y1 - y2;
    final dy2 = y3 - y2;
    final dy3 = y0 - y1 + y2 - y3;

    final double a11, a12, a13, a21, a22, a23, a31, a32;

    if (dx3.abs() < 1e-6 && dy3.abs() < 1e-6) {
      // Affine mapping
      a11 = x1 - x0;
      a12 = x3 - x0;
      a13 = x0;
      a21 = y1 - y0;
      a22 = y3 - y0;
      a23 = y0;
      a31 = 0.0;
      a32 = 0.0;
    } else {
      final det = dx1 * dy2 - dx2 * dy1;
      if (det.abs() < 1e-9) {
        throw ArgumentError(
          'Singular corner geometry; unable to compute perspective warp.',
        );
      }
      a31 = (dx3 * dy2 - dx2 * dy3) / det;
      a32 = (dx1 * dy3 - dx3 * dy1) / det;
      a11 = x1 - x0 + a31 * x1;
      a12 = x3 - x0 + a32 * x3;
      a13 = x0;
      a21 = y1 - y0 + a31 * y1;
      a22 = y3 - y0 + a32 * y3;
      a23 = y0;
    }

    final warped = img.Image(width: targetW, height: targetH);
    final denomW = targetW > 1 ? targetW - 1 : 1;
    final denomH = targetH > 1 ? targetH - 1 : 1;

    // Inverse mapping with bilinear interpolation
    for (var v = 0; v < targetH; v++) {
      final vNorm = v / denomH;
      for (var u = 0; u < targetW; u++) {
        final uNorm = u / denomW;
        final denom = a31 * uNorm + a32 * vNorm + 1.0;
        final srcX = (a11 * uNorm + a12 * vNorm + a13) / denom;
        final srcY = (a21 * uNorm + a22 * vNorm + a23) / denom;

        final color = _sampleBilinear(image, srcX, srcY, srcW, srcH);
        warped.setPixelRgb(u, v, color[0], color[1], color[2]);
      }
    }

    // Apply deterministic enhancement
    final enhanced = _applyEnhancement(warped, mode);

    return Uint8List.fromList(img.encodeJpg(enhanced, quality: jpegQuality));
  }

  /// Runs perspective warping and enhancement in a background Isolate.
  static Future<Uint8List> warpAndEnhanceAsync(WarpParams params) {
    return compute(_warpAndEnhanceEntry, params);
  }

  static Uint8List _warpAndEnhanceEntry(WarpParams params) {
    return warpAndEnhance(
      imageBytes: params.imageBytes,
      corners: params.corners,
      mode: params.mode,
      jpegQuality: params.jpegQuality,
    );
  }

  // =========================================================================
  // Internal Classical Computer Vision Algorithms
  // =========================================================================

  static img.Image _normalizeOrientation(img.Image image) {
    final orientation = image.exif.imageIfd.orientation;
    // bakeOrientation makes a full image copy even if there is nothing to do.
    return orientation == null || orientation == 1
        ? image
        : img.bakeOrientation(image);
  }

  /// Bilinear sampling of pixel at sub-pixel coordinate (srcX, srcY).
  static List<int> _sampleBilinear(
    img.Image image,
    double srcX,
    double srcY,
    int srcW,
    int srcH,
  ) {
    if (srcX < 0 || srcX >= srcW - 1 || srcY < 0 || srcY >= srcH - 1) {
      final cx = srcX.round().clamp(0, srcW - 1);
      final cy = srcY.round().clamp(0, srcH - 1);
      final p = image.getPixel(cx, cy);
      return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
    }

    final x0 = srcX.floor();
    final y0 = srcY.floor();
    final x1 = x0 + 1;
    final y1 = y0 + 1;

    final dx = srcX - x0;
    final dy = srcY - y0;
    final w00 = (1.0 - dx) * (1.0 - dy);
    final w10 = dx * (1.0 - dy);
    final w01 = (1.0 - dx) * dy;
    final w11 = dx * dy;

    final p00 = image.getPixel(x0, y0);
    final p10 = image.getPixel(x1, y0);
    final p01 = image.getPixel(x0, y1);
    final p11 = image.getPixel(x1, y1);

    final r = (p00.r * w00 + p10.r * w10 + p01.r * w01 + p11.r * w11)
        .round()
        .clamp(0, 255);
    final g = (p00.g * w00 + p10.g * w10 + p01.g * w01 + p11.g * w11)
        .round()
        .clamp(0, 255);
    final b = (p00.b * w00 + p10.b * w10 + p01.b * w01 + p11.b * w11)
        .round()
        .clamp(0, 255);

    return [r, g, b];
  }

  /// Separable 5x5 Gaussian blur with kernel [1, 4, 6, 4, 1] / 16.
  static Uint8List _applyGaussian5x5(Uint8List src, int w, int h) {
    final temp = Uint8List(w * h);
    final out = Uint8List(w * h);

    // Horizontal pass
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final xm2 = math.max(0, x - 2);
        final xm1 = math.max(0, x - 1);
        final xp1 = math.min(w - 1, x + 1);
        final xp2 = math.min(w - 1, x + 2);

        final sum =
            src[row + xm2] * 1 +
            src[row + xm1] * 4 +
            src[row + x] * 6 +
            src[row + xp1] * 4 +
            src[row + xp2] * 1;
        temp[row + x] = (sum >> 4).clamp(0, 255);
      }
    }

    // Vertical pass
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        final ym2 = math.max(0, y - 2);
        final ym1 = math.max(0, y - 1);
        final yp1 = math.min(h - 1, y + 1);
        final yp2 = math.min(h - 1, y + 2);

        final sum =
            temp[ym2 * w + x] * 1 +
            temp[ym1 * w + x] * 4 +
            temp[y * w + x] * 6 +
            temp[yp1 * w + x] * 4 +
            temp[yp2 * w + x] * 1;
        out[y * w + x] = (sum >> 4).clamp(0, 255);
      }
    }

    return out;
  }

  /// Computes Sobel gradient magnitude and orientation angle in degrees [0, 180).
  static _SobelResult _computeSobelGradients(Uint8List gray, int w, int h) {
    final mag = Float32List(w * h);
    final angle = Uint8List(w * h);
    var maxMag = 0;

    for (var y = 1; y < h - 1; y++) {
      final ym1 = (y - 1) * w;
      final y0 = y * w;
      final yp1 = (y + 1) * w;

      for (var x = 1; x < w - 1; x++) {
        final xm1 = x - 1;
        final xp1 = x + 1;

        final gx =
            (gray[ym1 + xp1] + (gray[y0 + xp1] << 1) + gray[yp1 + xp1]) -
            (gray[ym1 + xm1] + (gray[y0 + xm1] << 1) + gray[yp1 + xm1]);

        final gy =
            (gray[yp1 + xm1] + (gray[yp1 + x] << 1) + gray[yp1 + xp1]) -
            (gray[ym1 + xm1] + (gray[ym1 + x] << 1) + gray[ym1 + xp1]);

        final m = math.sqrt((gx * gx + gy * gy).toDouble()).round();
        mag[y0 + x] = m.toDouble();
        if (m > maxMag) maxMag = m;

        var deg =
            (math.atan2(gy.toDouble(), gx.toDouble()) * 180.0 / math.pi) %
            180.0;
        if (deg < 0) deg += 180.0;
        angle[y0 + x] = deg.round().clamp(0, 179);
      }
    }

    return _SobelResult(mag: mag, angle: angle, maxMag: maxMag);
  }

  /// Canny non-maximum suppression along gradient normals.
  static Float32List _applyNonMaxSuppression(_SobelResult sobel, int w, int h) {
    final mag = sobel.mag;
    final angle = sobel.angle;
    final nms = Float32List(w * h);

    for (var y = 1; y < h - 1; y++) {
      final y0 = y * w;
      final ym1 = (y - 1) * w;
      final yp1 = (y + 1) * w;

      for (var x = 1; x < w - 1; x++) {
        final c = mag[y0 + x];
        if (c == 0) continue;

        final a = angle[y0 + x];
        double n1 = 0, n2 = 0;

        if ((a >= 0 && a < 22.5) || (a >= 157.5 && a <= 180)) {
          // Horizontal gradient: compare with left and right
          n1 = mag[y0 + (x - 1)];
          n2 = mag[y0 + (x + 1)];
        } else if (a >= 22.5 && a < 67.5) {
          // Image y increases downwards: a 45-degree normal runs NW to SE.
          n1 = mag[ym1 + (x - 1)];
          n2 = mag[yp1 + (x + 1)];
        } else if (a >= 67.5 && a < 112.5) {
          // Vertical 90°: compare with top and bottom
          n1 = mag[ym1 + x];
          n2 = mag[yp1 + x];
        } else {
          n1 = mag[ym1 + (x + 1)];
          n2 = mag[yp1 + (x - 1)];
        }

        if (c >= n1 && c >= n2) {
          nms[y0 + x] = c;
        }
      }
    }

    return nms;
  }

  /// Dual-threshold hysteresis edge extraction.
  static Uint8List _applyHysteresis(Float32List nms, int w, int h) {
    final edges = Uint8List(w * h);
    var maxVal = 0.0;
    for (var i = 0; i < nms.length; i++) {
      if (nms[i] > maxVal) maxVal = nms[i];
    }

    final tHigh = math.max(25, (maxVal * 0.20).round());
    final tLow = math.max(10, (tHigh * 0.40).round());

    final queue = <int>[];

    for (var y = 1; y < h - 1; y++) {
      final y0 = y * w;
      for (var x = 1; x < w - 1; x++) {
        final idx = y0 + x;
        final v = nms[idx];
        if (v >= tHigh) {
          edges[idx] = 255;
          queue.add(idx);
        } else if (v >= tLow) {
          edges[idx] = 100; // Weak edge candidate
        }
      }
    }

    // 8-connected flood fill to link weak edges to strong edges
    while (queue.isNotEmpty) {
      final curr = queue.removeLast();
      final cx = curr % w;
      final cy = curr ~/ w;

      for (var dy = -1; dy <= 1; dy++) {
        final ny = cy + dy;
        if (ny < 1 || ny >= h - 1) continue;
        final row = ny * w;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = cx + dx;
          if (nx < 1 || nx >= w - 1) continue;
          final nIdx = row + nx;
          if (edges[nIdx] == 100) {
            edges[nIdx] = 255;
            queue.add(nIdx);
          }
        }
      }
    }

    // Suppress remaining disconnected weak edges
    for (var i = 0; i < edges.length; i++) {
      if (edges[i] != 255) edges[i] = 0;
    }

    return edges;
  }

  /// Eight-connected component envelopes, visiting every pixel once. Row/column
  /// extrema preserve the convex hull without retaining every interior pixel.
  static List<List<Offset>> _findContours(Uint8List edges, int w, int h) {
    final visited = Uint8List(w * h);
    final contours = <List<Offset>>[];
    final queue = Int32List(w * h);
    for (var start = 0; start < edges.length; start++) {
      if (edges[start] == 0 || visited[start] != 0) continue;
      var head = 0;
      var tail = 1;
      queue[0] = start;
      visited[start] = 1;
      var minX = w, maxX = 0, minY = h, maxY = 0;
      while (head < tail) {
        final p = queue[head++];
        final x = p % w, y = p ~/ w;
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= w) continue;
            final next = ny * w + nx;
            if (edges[next] != 0 && visited[next] == 0) {
              visited[next] = 1;
              queue[tail++] = next;
            }
          }
        }
      }
      if (tail < 20 || (maxX - minX) * (maxY - minY) < w * h * 0.08) continue;
      final left = List<int>.filled(h, w), right = List<int>.filled(h, -1);
      final top = List<int>.filled(w, h), bottom = List<int>.filled(w, -1);
      for (var i = 0; i < tail; i++) {
        final x = queue[i] % w, y = queue[i] ~/ w;
        left[y] = math.min(left[y], x);
        right[y] = math.max(right[y], x);
        top[x] = math.min(top[x], y);
        bottom[x] = math.max(bottom[x], y);
      }
      final points = <Offset>[];
      for (var y = minY; y <= maxY; y++) {
        if (right[y] < 0) continue;
        points.add(Offset(left[y].toDouble(), y.toDouble()));
        points.add(Offset(right[y].toDouble(), y.toDouble()));
      }
      for (var x = minX; x <= maxX; x++) {
        if (bottom[x] < 0) continue;
        points.add(Offset(x.toDouble(), top[x].toDouble()));
        points.add(Offset(x.toDouble(), bottom[x].toDouble()));
      }
      final hull = _convexHull(points);
      if (_computePolygonArea(hull) < w * h * 0.08) continue;
      contours.add(hull);
      contours.sort(
        (a, b) => _computePolygonArea(b).compareTo(_computePolygonArea(a)),
      );
      if (contours.length > 24) contours.removeLast();
    }
    return contours;
  }

  static double _cross(Offset a, Offset b, Offset c) =>
      (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);

  static List<Offset> _convexHull(List<Offset> points) {
    points.sort(
      (a, b) => a.dx == b.dx ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx),
    );
    final unique = <Offset>[];
    for (final p in points) {
      if (unique.isEmpty || unique.last != p) unique.add(p);
    }
    final lower = <Offset>[], upper = <Offset>[];
    for (final p in unique) {
      while (lower.length >= 2 &&
          _cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    for (final p in unique.reversed) {
      while (upper.length >= 2 &&
          _cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    return [
      ...lower.take(math.max(0, lower.length - 1)),
      ...upper.take(math.max(0, upper.length - 1)),
    ];
  }

  static int _otsuThreshold(Uint8List gray) {
    final histogram = List<int>.filled(256, 0);
    var sum = 0.0;
    for (final value in gray) {
      histogram[value]++;
      sum += value;
    }
    var count = 0, threshold = 0;
    var partial = 0.0, bestVariance = 0.0;
    for (var t = 0; t < 255; t++) {
      count += histogram[t];
      partial += t * histogram[t];
      final remaining = gray.length - count;
      if (count == 0 || remaining == 0) continue;
      final difference = partial / count - (sum - partial) / remaining;
      final variance = count * remaining * difference * difference;
      if (variance > bestVariance) {
        bestVariance = variance;
        threshold = t;
      }
    }
    return threshold;
  }

  static double _cornerDistance(List<Offset> a, List<Offset> b) {
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      sum += (a[i] - b[i]).distance;
    }
    return sum / 4;
  }

  static List<_QuadCandidate> _rankQuadrilaterals(
    List<List<Offset>> contours,
    Uint8List edges,
    Uint8List gray,
    int w,
    int h,
  ) {
    final candidates = <_QuadCandidate>[];
    for (final hull in contours) {
      if (hull.length < 4) continue;
      // Closed RDP uses two open arcs so the arbitrary start vertex is not
      // mistaken for an additional corner or connected to an almost equal end.
      var opposite = 1;
      for (var i = 2; i < hull.length; i++) {
        if ((hull[i] - hull.first).distanceSquared >
            (hull[opposite] - hull.first).distanceSquared) {
          opposite = i;
        }
      }
      final perimeter = _computePerimeter(hull);
      for (final factor in [0.008, 0.015, 0.025, 0.04, 0.06]) {
        final a = _ramerDouglasPeucker(
          hull.sublist(0, opposite + 1),
          perimeter * factor,
        );
        final b = _ramerDouglasPeucker([
          ...hull.sublist(opposite),
          hull.first,
        ], perimeter * factor);
        final quad = [...a.take(a.length - 1), ...b.take(b.length - 1)];
        if (!_isValidDocumentQuad(quad, w, h)) continue;
        final ordered = _orderCorners(quad);
        final candidate = _scoreQuad(
          ordered,
          _computePolygonArea(hull),
          edges,
          gray,
          w,
          h,
        );
        if (candidate == null) continue;
        final same = candidates.indexWhere(
          (c) => _cornerDistance(c.points, ordered) < math.min(w, h) * 0.035,
        );
        if (same < 0) {
          candidates.add(candidate);
        } else if (candidate.score > candidates[same].score) {
          candidates[same] = candidate;
        }
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  static _QuadCandidate? _scoreQuad(
    List<Offset> quad,
    double hullArea,
    Uint8List edges,
    Uint8List gray,
    int w,
    int h,
  ) {
    final area = _computePolygonArea(quad) / (w * h);
    final fit = _computePolygonArea(quad) / hullArea;
    if (area < 0.08 || fit < 0.82) return null;
    final supports = <double>[];
    var contrastSum = 0.0, contrastCount = 0;
    var geometry = 0.0;
    final frameSides = <int>[];
    for (var side = 0; side < 4; side++) {
      final a = quad[side], b = quad[(side + 1) % 4];
      final delta = b - a;
      final normal = Offset(-delta.dy, delta.dx) / delta.distance;
      var hits = 0, frameSamples = 0;
      const samples = 48;
      for (var i = 0; i < samples; i++) {
        final p = a + delta * (0.05 + 0.90 * i / (samples - 1));
        var hit = false;
        for (var dy = -3; dy <= 3 && !hit; dy++) {
          for (var dx = -3; dx <= 3; dx++) {
            final x = p.dx.round() + dx, y = p.dy.round() + dy;
            if (x >= 0 && x < w && y >= 0 && y < h && edges[y * w + x] != 0) {
              hit = true;
              break;
            }
          }
        }
        if (hit) hits++;
        final inside = p + normal * 5, outside = p - normal * 5;
        bool inImage(Offset v) =>
            v.dx >= 0 && v.dx < w && v.dy >= 0 && v.dy < h;
        if (!inImage(outside)) frameSamples++;
        if (inImage(inside) && inImage(outside)) {
          contrastSum +=
              (gray[inside.dy.floor() * w + inside.dx.floor()] -
                      gray[outside.dy.floor() * w + outside.dx.floor()])
                  .abs();
          contrastCount++;
        }
      }
      supports.add(hits / samples);
      if (frameSamples > samples * 0.7) frameSides.add(side);
      final previous = quad[(side + 3) % 4] - a;
      final cosine =
          (previous.dx * delta.dx + previous.dy * delta.dy) /
          (previous.distance * delta.distance);
      geometry += 1 - cosine.abs();
    }
    // One clipped side may be inferred only from three well-supported sides.
    // Never infer an entire camera frame from absent boundary evidence.
    var inferredSide = false;
    if (frameSides.length == 1 &&
        supports[frameSides.single] < 0.55 &&
        List.generate(4, (i) => i)
            .where((i) => i != frameSides.single)
            .every((i) => supports[i] >= 0.85)) {
      supports[frameSides.single] = 0.55;
      inferredSide = true;
    }
    final average = supports.reduce((a, b) => a + b) / 4;
    final weakest = supports.reduce(math.min);
    final contrast = contrastCount == 0
        ? 0.0
        : (contrastSum / contrastCount / 40).clamp(0.0, 1.0);
    final score =
        (0.38 * average +
                0.14 * weakest +
                0.16 * math.sqrt((area / 0.60).clamp(0.0, 1.0)) +
                0.12 * geometry / 4 +
                0.12 * contrast +
                0.08 * fit -
                (inferredSide ? 0.04 : 0))
            .clamp(0.0, 1.0);
    return _QuadCandidate(quad, score, average, weakest, contrast, area);
  }

  /// Ramer-Douglas-Peucker (RDP) polygon simplification algorithm.
  static List<Offset> _ramerDouglasPeucker(
    List<Offset> points,
    double epsilon,
  ) {
    if (points.length < 3) return points;

    var maxDist = 0.0;
    var index = 0;
    final first = points.first;
    final last = points.last;

    for (var i = 1; i < points.length - 1; i++) {
      final d = _perpendicularDistance(points[i], first, last);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _ramerDouglasPeucker(points.sublist(0, index + 1), epsilon);
      final right = _ramerDouglasPeucker(points.sublist(index), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [first, last];
    }
  }

  static double _perpendicularDistance(
    Offset pt,
    Offset lineStart,
    Offset lineEnd,
  ) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return (pt - lineStart).distance;

    final num = ((pt.dx - lineStart.dx) * dy - (pt.dy - lineStart.dy) * dx)
        .abs();
    return num / math.sqrt(lenSq);
  }

  /// Computes polygon area using Shoelace formula (Green's theorem).
  static double _computePolygonArea(List<Offset> pts) {
    if (pts.length < 3) return 0.0;
    var sum = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      sum += pts[i].dx * pts[j].dy - pts[j].dx * pts[i].dy;
    }
    return (sum * 0.5).abs();
  }

  static double _computePerimeter(List<Offset> pts) {
    if (pts.length < 2) return 0.0;
    var sum = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      sum += (pts[j] - pts[i]).distance;
    }
    return sum;
  }

  /// Verifies convexity and interior angles of a 4-vertex candidate.
  static bool _isValidDocumentQuad(List<Offset> quad, int w, int h) {
    if (quad.length != 4) return false;
    final tl = quad[0];
    final tr = quad[1];
    final br = quad[2];
    final bl = quad[3];

    // Must be convex
    if (!_isConvexQuad(tl, tr, br, bl)) return false;

    if (quad.any((p) => !p.dx.isFinite || !p.dy.isFinite)) return false;
    final lengths = List.generate(
      4,
      (i) => (quad[(i + 1) % 4] - quad[i]).distance,
    );
    final ratio = (lengths[0] + lengths[2]) / (lengths[1] + lengths[3]);
    if (ratio < 0.20 ||
        ratio > 5.0 ||
        lengths.reduce(math.max) / lengths.reduce(math.min) > 6) {
      return false;
    }
    final minEdge = math.min(w, h) * 0.10;
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      if ((quad[j] - quad[i]).distance < minEdge) return false;
    }

    // Admit perspective-distorted corners, but reject extreme acute angles.
    for (var i = 0; i < 4; i++) {
      final prev = quad[(i + 3) % 4];
      final curr = quad[i];
      final next = quad[(i + 1) % 4];

      final v1 = prev - curr;
      final v2 = next - curr;
      final d1 = v1.distance;
      final d2 = v2.distance;
      if (d1 < 1e-6 || d2 < 1e-6) return false;

      final cosTheta = (v1.dx * v2.dx + v1.dy * v2.dy) / (d1 * d2);
      if (cosTheta.abs() > 0.866) {
        // 30..150 degrees admits perspective while excluding needle-like quads.
        return false;
      }
    }

    return true;
  }

  /// Checks if a quadrilateral is convex using 2D cross product sign consistency.
  static bool _isConvexQuad(Offset p0, Offset p1, Offset p2, Offset p3) {
    final pts = [p0, p1, p2, p3];
    var sign = 0;

    for (var i = 0; i < 4; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % 4];
      final c = pts[(i + 2) % 4];

      final cross =
          (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (!cross.isFinite || cross.abs() < 1e-6) return false;

      final currentSign = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = currentSign;
      } else if (sign != currentSign) {
        return false; // Concave or self-intersecting
      }
    }

    return sign != 0;
  }

  /// Cyclic ordering prevents duplicate corners in rotated/symmetric captures.
  static List<Offset> orderCorners(List<Offset> pts) => _orderCorners(pts);

  static List<Offset> _orderCorners(List<Offset> pts) {
    if (pts.length != 4 ||
        pts.toSet().length != 4 ||
        pts.any((p) => !p.dx.isFinite || !p.dy.isFinite)) {
      throw ArgumentError('Four distinct finite corners are required.');
    }
    final center = pts.reduce((a, b) => a + b) / 4;
    final ordered = [...pts]
      ..sort(
        (a, b) => math
            .atan2(a.dy - center.dy, a.dx - center.dx)
            .compareTo(math.atan2(b.dy - center.dy, b.dx - center.dx)),
      );
    // A diagonal page has two equally plausible top-left extrema. Allow pixel
    // quantization tolerance and choose the upper one consistently.
    final tieTolerance =
        pts.map((p) => (p - center).distance).reduce(math.max) * 0.02;
    var start = 0;
    for (var i = 1; i < 4; i++) {
      final difference =
          ordered[i].dx + ordered[i].dy - ordered[start].dx - ordered[start].dy;
      if (difference < -tieTolerance ||
          (difference.abs() <= tieTolerance &&
              ordered[i].dy < ordered[start].dy)) {
        start = i;
      }
    }
    return List.generate(4, (i) => ordered[(start + i) % 4]);
  }

  /// Applies deterministic image enhancement.
  static img.Image _applyEnhancement(
    img.Image warped,
    ScanEnhancementMode mode,
  ) {
    switch (mode) {
      case ScanEnhancementMode.original:
        return warped;

      case ScanEnhancementMode.enhanced:
        return _contrastStretchAndSharpen(warped);

      case ScanEnhancementMode.grayscale:
        return _convertToGrayscale(warped);

      case ScanEnhancementMode.blackAndWhite:
        return _adaptiveThreshold(warped);
    }
  }

  /// Contrast stretch (1st and 99th percentile dynamic range mapping) + conservative unsharp mask.
  static img.Image _contrastStretchAndSharpen(img.Image src) {
    final w = src.width;
    final h = src.height;
    final total = w * h;

    // 1. Build luminance histogram
    final hist = Int32List(256);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final yVal = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(
          0,
          255,
        );
        hist[yVal]++;
      }
    }

    // Find 1st percentile and 99th percentile
    final count1 = (total * 0.01).round();
    final count99 = (total * 0.99).round();

    var acc = 0;
    var yMin = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= count1) {
        yMin = i;
        break;
      }
    }

    acc = 0;
    var yMax = 255;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= count99) {
        yMax = i;
        break;
      }
    }

    // Near-uniform paper must not turn black or amplify sensor noise.
    if (yMax - yMin < 24) return src;
    final range = math.max(1, yMax - yMin);
    final scale = 255.0 / range;

    final out = img.Image(width: w, height: h);

    // Apply linear contrast stretch
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final r = ((p.r - yMin) * scale).round().clamp(0, 255);
        final g = ((p.g - yMin) * scale).round().clamp(0, 255);
        final b = ((p.b - yMin) * scale).round().clamp(0, 255);
        out.setPixelRgb(x, y, r, g, b);
      }
    }

    // 2. Conservative unsharp mask (sharpening kernel: center 5, cross -1)
    final sharpened = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      final ym1 = math.max(0, y - 1);
      final yp1 = math.min(h - 1, y + 1);

      for (var x = 0; x < w; x++) {
        final xm1 = math.max(0, x - 1);
        final xp1 = math.min(w - 1, x + 1);

        final p = out.getPixel(x, y);
        final top = out.getPixel(x, ym1);
        final bot = out.getPixel(x, yp1);
        final left = out.getPixel(xm1, y);
        final right = out.getPixel(xp1, y);

        // Subtle boost: original + 0.3 * (original - blur)
        final blurR = (top.r + bot.r + left.r + right.r) * 0.25;
        final blurG = (top.g + bot.g + left.g + right.g) * 0.25;
        final blurB = (top.b + bot.b + left.b + right.b) * 0.25;

        final r = (p.r + 0.35 * (p.r - blurR)).round().clamp(0, 255);
        final g = (p.g + 0.35 * (p.g - blurG)).round().clamp(0, 255);
        final b = (p.b + 0.35 * (p.b - blurB)).round().clamp(0, 255);

        sharpened.setPixelRgb(x, y, r, g, b);
      }
    }

    return sharpened;
  }

  /// Converts RGB image to clean grayscale.
  static img.Image _convertToGrayscale(img.Image src) {
    final w = src.width;
    final h = src.height;
    final out = img.Image(width: w, height: h);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final yVal = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(
          0,
          255,
        );
        out.setPixelRgb(x, y, yVal, yVal, yVal);
      }
    }

    return out;
  }

  /// Adaptive local thresholding (Bradley-Roth local mean thresholding).
  static img.Image _adaptiveThreshold(img.Image src) {
    final w = src.width;
    final h = src.height;

    // 1. Grayscale luminance
    final gray = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        gray[row + x] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(
          0,
          255,
        );
      }
    }

    // 2. Integral image
    final integral = Int64List(w * h);
    for (var y = 0; y < h; y++) {
      var sum = 0;
      final row = y * w;
      final prevRow = (y - 1) * w;
      for (var x = 0; x < w; x++) {
        sum += gray[row + x];
        integral[row + x] = sum + (y > 0 ? integral[prevRow + x] : 0);
      }
    }

    final out = img.Image(width: w, height: h);
    final s = math.max(4, (w / 16).round()); // Window radius
    const t = 12; // 12% lower than local mean threshold

    for (var y = 0; y < h; y++) {
      final y1 = math.max(0, y - s);
      final y2 = math.min(h - 1, y + s);
      final row = y * w;

      for (var x = 0; x < w; x++) {
        final x1 = math.max(0, x - s);
        final x2 = math.min(w - 1, x + s);
        final count = (x2 - x1 + 1) * (y2 - y1 + 1);

        // Sum over rectangle [x1, y1] to [x2, y2] using integral image
        final sum =
            integral[y2 * w + x2] -
            (y1 > 0 ? integral[(y1 - 1) * w + x2] : 0) -
            (x1 > 0 ? integral[y2 * w + (x1 - 1)] : 0) +
            (x1 > 0 && y1 > 0 ? integral[(y1 - 1) * w + (x1 - 1)] : 0);

        final val = gray[row + x];
        final isText = (val * count) < (sum * (100 - t) ~/ 100);
        final outVal = isText ? 0 : 255;

        out.setPixelRgb(x, y, outVal, outVal, outVal);
      }
    }

    return out;
  }
}

class _SobelResult {
  const _SobelResult({
    required this.mag,
    required this.angle,
    required this.maxMag,
  });
  final Float32List mag;
  final Uint8List angle;
  final int maxMag;
}

class _QuadCandidate {
  const _QuadCandidate(
    this.points,
    this.score,
    this.edgeSupport,
    this.weakestSide,
    this.contrast,
    this.areaFraction,
  );
  final List<Offset> points;
  final double score, edgeSupport, weakestSide, contrast, areaFraction;
}
