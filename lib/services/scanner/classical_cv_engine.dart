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

  /// Default 6% inset quadrilateral used when boundary detection does not confidently find a quad.
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
  factory DocumentCorners.fromList(List<Offset> points, {bool isAutoDetected = true}) {
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
  factory DocumentCorners.ordered(List<Offset> points, {bool isAutoDetected = true}) {
    return DocumentCorners.fromList(ClassicalCvEngine.orderCorners(points), isAutoDetected: isAutoDetected);
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
      topLeft: Offset((topLeft.dx / width).clamp(0.0, 1.0), (topLeft.dy / height).clamp(0.0, 1.0)),
      topRight: Offset((topRight.dx / width).clamp(0.0, 1.0), (topRight.dy / height).clamp(0.0, 1.0)),
      bottomRight: Offset((bottomRight.dx / width).clamp(0.0, 1.0), (bottomRight.dy / height).clamp(0.0, 1.0)),
      bottomLeft: Offset((bottomLeft.dx / width).clamp(0.0, 1.0), (bottomLeft.dy / height).clamp(0.0, 1.0)),
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
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft, isAutoDetected);

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

/// Pure Dart Classical Computer Vision Engine.
///
/// Implements deterministic edge detection, polygon approximation, projective homography warping,
/// and image enhancement without machine learning or neural networks.
class ClassicalCvEngine {
  const ClassicalCvEngine._();

  /// Detects the 4 corners of a document within the provided image bytes using classical CV.
  ///
  /// Safe to call synchronously or in a background Isolate.
  static DocumentCorners detectCorners(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null || decoded.width < 50 || decoded.height < 50) {
      return DocumentCorners.defaultInset();
    }

    final original = img.bakeOrientation(decoded);
    final origW = original.width;
    final origH = original.height;

    // Downscale for analysis (max dimension 800) for real-time edge processing.
    const maxDimension = 800;
    final scale = math.min(1.0, maxDimension / math.max(origW, origH));
    final analysisW = math.max(50, (origW * scale).round());
    final analysisH = math.max(50, (origH * scale).round());

    final analysisImage = (scale < 1.0)
        ? img.copyResize(original, width: analysisW, height: analysisH, interpolation: img.Interpolation.linear)
        : original;

    // 1. Grayscale conversion (CCIR 601 luminance: 0.299R + 0.587G + 0.114B)
    final gray = Uint8List(analysisW * analysisH);
    for (var y = 0; y < analysisH; y++) {
      final rowOffset = y * analysisW;
      for (var x = 0; x < analysisW; x++) {
        final p = analysisImage.getPixel(x, y);
        gray[rowOffset + x] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      }
    }

    // 2. Gaussian Noise Reduction (5x5 separable kernel [1, 4, 6, 4, 1] / 16)
    final blurred = _applyGaussian5x5(gray, analysisW, analysisH);

    // 3. Sobel Gradient Magnitude & Direction
    final gradients = _computeSobelGradients(blurred, analysisW, analysisH);

    // 4. Canny Non-Maximum Suppression (NMS)
    final nms = _applyNonMaxSuppression(gradients, analysisW, analysisH);

    // 5. Dual-Threshold Hysteresis Edge Extraction
    final edges = _applyHysteresis(nms, analysisW, analysisH);

    // 6. Contour / Boundary Tracing
    final contours = _findContours(edges, analysisW, analysisH);

    // 7. Find Largest Valid Convex Quadrilateral
    final bestQuad = _findBestQuadrilateral(contours, analysisW, analysisH);

    if (bestQuad == null) {
      return DocumentCorners.defaultInset();
    }

    // Order corners into TL, TR, BR, BL
    final ordered = _orderCorners(bestQuad);

    // Normalize coordinates to [0.0, 1.0]
    return DocumentCorners(
      topLeft: Offset(ordered[0].dx / analysisW, ordered[0].dy / analysisH),
      topRight: Offset(ordered[1].dx / analysisW, ordered[1].dy / analysisH),
      bottomRight: Offset(ordered[2].dx / analysisW, ordered[2].dy / analysisH),
      bottomLeft: Offset(ordered[3].dx / analysisW, ordered[3].dy / analysisH),
      isAutoDetected: true,
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
      throw const FormatException('Unable to decode source image for document warping.');
    }

    final image = img.bakeOrientation(decoded);
    final srcW = image.width;
    final srcH = image.height;

    // Convert normalized corners to full-res pixel space
    final absTL = Offset(corners.topLeft.dx * srcW, corners.topLeft.dy * srcH);
    final absTR = Offset(corners.topRight.dx * srcW, corners.topRight.dy * srcH);
    final absBR = Offset(corners.bottomRight.dx * srcW, corners.bottomRight.dy * srcH);
    final absBL = Offset(corners.bottomLeft.dx * srcW, corners.bottomLeft.dy * srcH);

    // Validate geometry against degenerate quadrilateral
    if (!_isConvexQuad(absTL, absTR, absBR, absBL)) {
      throw ArgumentError('The selected corners form a self-intersecting or concave polygon.');
    }

    // Compute target rectangle dimensions
    final widthTop = (absTR - absTL).distance;
    final widthBottom = (absBR - absBL).distance;
    final heightLeft = (absBL - absTL).distance;
    final heightRight = (absBR - absTR).distance;

    final targetW = math.max(100, math.min(4096, math.max(widthTop, widthBottom).round()));
    final targetH = math.max(100, math.min(4096, math.max(heightLeft, heightRight).round()));

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
        throw ArgumentError('Singular corner geometry; unable to compute perspective warp.');
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

  /// Bilinear sampling of pixel at sub-pixel coordinate (srcX, srcY).
  static List<int> _sampleBilinear(img.Image image, double srcX, double srcY, int srcW, int srcH) {
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

    final r = (p00.r * w00 + p10.r * w10 + p01.r * w01 + p11.r * w11).round().clamp(0, 255);
    final g = (p00.g * w00 + p10.g * w10 + p01.g * w01 + p11.g * w11).round().clamp(0, 255);
    final b = (p00.b * w00 + p10.b * w10 + p01.b * w01 + p11.b * w11).round().clamp(0, 255);

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

        final sum = src[row + xm2] * 1 +
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

        final sum = temp[ym2 * w + x] * 1 +
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
    final mag = Uint8List(w * h);
    final angle = Uint8List(w * h);
    var maxMag = 0;

    for (var y = 1; y < h - 1; y++) {
      final ym1 = (y - 1) * w;
      final y0 = y * w;
      final yp1 = (y + 1) * w;

      for (var x = 1; x < w - 1; x++) {
        final xm1 = x - 1;
        final xp1 = x + 1;

        final gx = (gray[ym1 + xp1] + (gray[y0 + xp1] << 1) + gray[yp1 + xp1]) -
            (gray[ym1 + xm1] + (gray[y0 + xm1] << 1) + gray[yp1 + xm1]);

        final gy = (gray[yp1 + xm1] + (gray[yp1 + x] << 1) + gray[yp1 + xp1]) -
            (gray[ym1 + xm1] + (gray[ym1 + x] << 1) + gray[ym1 + xp1]);

        final m = (math.sqrt((gx * gx + gy * gy).toDouble())).round().clamp(0, 255);
        mag[y0 + x] = m;
        if (m > maxMag) maxMag = m;

        var deg = (math.atan2(gy.toDouble(), gx.toDouble()) * 180.0 / math.pi) % 180.0;
        if (deg < 0) deg += 180.0;
        angle[y0 + x] = deg.round().clamp(0, 179);
      }
    }

    return _SobelResult(mag: mag, angle: angle, maxMag: maxMag);
  }

  /// Canny non-maximum suppression along gradient normals.
  static Uint8List _applyNonMaxSuppression(_SobelResult sobel, int w, int h) {
    final mag = sobel.mag;
    final angle = sobel.angle;
    final nms = Uint8List(w * h);

    for (var y = 1; y < h - 1; y++) {
      final y0 = y * w;
      final ym1 = (y - 1) * w;
      final yp1 = (y + 1) * w;

      for (var x = 1; x < w - 1; x++) {
        final c = mag[y0 + x];
        if (c == 0) continue;

        final a = angle[y0 + x];
        int n1 = 0, n2 = 0;

        if ((a >= 0 && a < 22.5) || (a >= 157.5 && a <= 180)) {
          // Horizontal gradient: compare with left and right
          n1 = mag[y0 + (x - 1)];
          n2 = mag[y0 + (x + 1)];
        } else if (a >= 22.5 && a < 67.5) {
          // Diagonal 45°: compare with top-right and bottom-left
          n1 = mag[ym1 + (x + 1)];
          n2 = mag[yp1 + (x - 1)];
        } else if (a >= 67.5 && a < 112.5) {
          // Vertical 90°: compare with top and bottom
          n1 = mag[ym1 + x];
          n2 = mag[yp1 + x];
        } else {
          // Anti-diagonal 135°: compare with top-left and bottom-right
          n1 = mag[ym1 + (x - 1)];
          n2 = mag[yp1 + (x + 1)];
        }

        if (c >= n1 && c >= n2) {
          nms[y0 + x] = c;
        }
      }
    }

    return nms;
  }

  /// Dual-threshold hysteresis edge extraction.
  static Uint8List _applyHysteresis(Uint8List nms, int w, int h) {
    final edges = Uint8List(w * h);
    var maxVal = 0;
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

  /// Traces external boundaries of connected edge components.
  static List<List<Offset>> _findContours(Uint8List edges, int w, int h) {
    final visited = Uint8List(w * h);
    final contours = <List<Offset>>[];

    final dxDirs = [1, 1, 0, -1, -1, -1, 0, 1];
    final dyDirs = [0, 1, 1, 1, 0, -1, -1, -1];

    for (var y = 2; y < h - 2; y += 2) {
      final row = y * w;
      for (var x = 2; x < w - 2; x += 2) {
        final idx = row + x;
        if (edges[idx] != 255 || visited[idx] == 1) continue;

        // Trace contour starting from (x, y)
        final points = <Offset>[];
        var currX = x;
        var currY = y;
        var dir = 0;
        final startX = x;
        final startY = y;

        for (var steps = 0; steps < 2000; steps++) {
          points.add(Offset(currX.toDouble(), currY.toDouble()));
          visited[currY * w + currX] = 1;

          var foundNext = false;
          final searchStartDir = (dir + 5) % 8;

          for (var i = 0; i < 8; i++) {
            final testDir = (searchStartDir + i) % 8;
            final nx = currX + dxDirs[testDir];
            final ny = currY + dyDirs[testDir];

            if (nx >= 0 && nx < w && ny >= 0 && ny < h && edges[ny * w + nx] == 255) {
              currX = nx;
              currY = ny;
              dir = testDir;
              foundNext = true;
              break;
            }
          }

          if (!foundNext) break;
          if (currX == startX && currY == startY && points.length > 10) break;
        }

        if (points.length >= 20) {
          contours.add(points);
        }
      }
    }

    return contours;
  }

  /// Evaluates contours to find the largest plausible document quadrilateral.
  static List<Offset>? _findBestQuadrilateral(List<List<Offset>> contours, int w, int h) {
    final imageArea = (w * h).toDouble();
    const minAreaFraction = 0.10; // At least 10% of image frame
    final minArea = imageArea * minAreaFraction;

    List<Offset>? bestQuad;
    var maxArea = 0.0;

    for (final contour in contours) {
      final area = _computePolygonArea(contour);
      if (area < minArea) continue;

      final perimeter = _computePerimeter(contour);
      if (perimeter < 100) continue;

      // Adaptively search epsilon multipliers from 0.015 to 0.065 to find a 4-vertex polygon
      for (var factor = 0.015; factor <= 0.065; factor += 0.005) {
        final epsilon = perimeter * factor;
        final simplified = _ramerDouglasPeucker(contour, epsilon);

        // A closed 4-sided contour has either 4 vertices, or 5 vertices where the last point closes back to the first.
        List<Offset>? candidateQuad;
        if (simplified.length == 4) {
          candidateQuad = simplified;
        } else if (simplified.length == 5 && (simplified.first - simplified.last).distance < 20.0) {
          candidateQuad = simplified.sublist(0, 4);
        }

        if (candidateQuad != null) {
          if (_isValidDocumentQuad(candidateQuad, w, h)) {
            final quadArea = _computePolygonArea(candidateQuad);
            if (quadArea > maxArea) {
              maxArea = quadArea;
              bestQuad = candidateQuad;
            }
          }
          break; // Found 4-vertex approximation for this contour
        }
      }
    }

    return bestQuad;
  }

  /// Ramer-Douglas-Peucker (RDP) polygon simplification algorithm.
  static List<Offset> _ramerDouglasPeucker(List<Offset> points, double epsilon) {
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

  static double _perpendicularDistance(Offset pt, Offset lineStart, Offset lineEnd) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return (pt - lineStart).distance;

    final num = ((pt.dx - lineStart.dx) * dy - (pt.dy - lineStart.dy) * dx).abs();
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

    // Minimum edge length sanity check (at least 15% of dimension)
    final minEdge = math.min(w, h) * 0.15;
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      if ((quad[j] - quad[i]).distance < minEdge) return false;
    }

    // Check interior angles: dot product between adjacent unit edge vectors must be between -0.707 and 0.707 (45°..135°)
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
      if (cosTheta.abs() > 0.766) {
        // Exceeds roughly 40°..140° bounds, reject extreme distorted quadrilateral
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

      final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross.abs() < 1e-6) continue;

      final currentSign = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = currentSign;
      } else if (sign != currentSign) {
        return false; // Concave or self-intersecting
      }
    }

    return sign != 0;
  }

  /// Orders 4 quadrilateral vertices into [TL, TR, BR, BL] based on coordinate sums and differences.
  static List<Offset> orderCorners(List<Offset> pts) => _orderCorners(pts);

  static List<Offset> _orderCorners(List<Offset> pts) {
    if (pts.length != 4) return pts;

    // TL has minimum (x + y), BR has maximum (x + y)
    var tl = pts[0];
    var br = pts[0];
    var minSum = pts[0].dx + pts[0].dy;
    var maxSum = minSum;

    for (var i = 1; i < 4; i++) {
      final s = pts[i].dx + pts[i].dy;
      if (s < minSum) {
        minSum = s;
        tl = pts[i];
      }
      if (s > maxSum) {
        maxSum = s;
        br = pts[i];
      }
    }

    // TR has minimum (y - x), BL has maximum (y - x)
    final remaining = pts.where((p) => p != tl && p != br).toList();
    if (remaining.length != 2) {
      // Degenerate tie fallback
      return pts;
    }

    final diff0 = remaining[0].dy - remaining[0].dx;
    final diff1 = remaining[1].dy - remaining[1].dx;

    final tr = diff0 < diff1 ? remaining[0] : remaining[1];
    final bl = diff0 < diff1 ? remaining[1] : remaining[0];

    return [tl, tr, br, bl];
  }

  /// Applies deterministic image enhancement.
  static img.Image _applyEnhancement(img.Image warped, ScanEnhancementMode mode) {
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
        final yVal = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
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
        final yVal = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
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
        gray[row + x] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
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
        final count = (x2 - x1) * (y2 - y1);

        // Sum over rectangle [x1, y1] to [x2, y2] using integral image
        final sum = integral[y2 * w + x2] -
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
  const _SobelResult({required this.mag, required this.angle, required this.maxMag});
  final Uint8List mag;
  final Uint8List angle;
  final int maxMag;
}
