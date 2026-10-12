import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart' show BoxFit;

import 'classical_cv_engine.dart';

/// Explicit raw sensor -> oriented preview -> viewport transform. The preview
/// uses the same centered fit. Points outside a cover viewport are clipped by
/// the painter, NOT individually clamped (which would distort polygon edges).
class ScanPreviewGeometry {
  const ScanPreviewGeometry({
    required this.frameSize,
    this.clockwiseQuarterTurns = 0,
    this.mirrored = false,
  });

  final Size frameSize;
  final int clockwiseQuarterTurns;
  final bool mirrored;

  Size get orientedSize => clockwiseQuarterTurns.isOdd
      ? Size(frameSize.height, frameSize.width)
      : frameSize;

  Offset orient(Offset p) {
    final rotated = switch (clockwiseQuarterTurns % 4) {
      1 => Offset(1 - p.dy, p.dx),
      2 => Offset(1 - p.dx, 1 - p.dy),
      3 => Offset(p.dy, 1 - p.dx),
      _ => p,
    };
    return mirrored ? Offset(1 - rotated.dx, rotated.dy) : rotated;
  }

  Offset map(Offset point, Size viewport, {BoxFit fit = BoxFit.cover}) {
    final oriented = orient(point);
    final source = orientedSize;
    final sx = viewport.width / source.width;
    final sy = viewport.height / source.height;
    final scale = fit == BoxFit.contain ? math.min(sx, sy) : math.max(sx, sy);
    final rendered = Size(source.width * scale, source.height * scale);
    return Offset(
      (viewport.width - rendered.width) / 2 + oriented.dx * rendered.width,
      (viewport.height - rendered.height) / 2 + oriented.dy * rendered.height,
    );
  }

  /// CameraX does not expose its native crop rect through CameraImage. Refuse
  /// to guess a field-of-view crop if a device negotiates different aspects.
  bool matchesPreview(Size preview) =>
      (orientedSize.aspectRatio / preview.aspectRatio - 1).abs() < .015;

  @override
  bool operator ==(Object other) =>
      other is ScanPreviewGeometry &&
      other.frameSize == frameSize &&
      other.clockwiseQuarterTurns == clockwiseQuarterTurns &&
      other.mirrored == mirrored;
  @override
  int get hashCode => Object.hash(frameSize, clockwiseQuarterTurns, mirrored);
}

/// Copy only sampled luminance. Handles padded Y rows/pixel strides (Android
/// YUV/NV21) and padded BGRA rows (iOS), without allocating an RGB camera image.
GrayscaleFrame sampleCameraLuminance({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  required int bytesPerPixel,
  bool bgra = false,
  int maxDimension = 640,
}) {
  if (width <= 0 ||
      height <= 0 ||
      maxDimension < 50 ||
      maxDimension > 800 ||
      bytesPerPixel < (bgra ? 4 : 1) ||
      bytesPerRow < (width - 1) * bytesPerPixel + (bgra ? 4 : 1) ||
      bytes.length <
          (height - 1) * bytesPerRow +
              (width - 1) * bytesPerPixel +
              (bgra ? 4 : 1)) {
    throw const FormatException('Unsupported camera frame layout.');
  }
  final scale = math.min(1.0, maxDimension / math.max(width, height));
  final w = math.max(1, (width * scale).round());
  final h = math.max(1, (height * scale).round());
  final pixels = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final row =
        (h == 1 ? 0 : (y * (height - 1) / (h - 1)).round()) * bytesPerRow;
    for (var x = 0; x < w; x++) {
      final pos =
          row +
          (w == 1 ? 0 : (x * (width - 1) / (w - 1)).round()) * bytesPerPixel;
      pixels[y * w + x] = bgra
          ? (0.114 * bytes[pos] +
                    0.587 * bytes[pos + 1] +
                    0.299 * bytes[pos + 2])
                .round()
          : bytes[pos];
    }
  }
  return GrayscaleFrame(pixels, w, h);
}
