import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

/// Deterministic camera-like fixture; no model, network, or personal documents.
img.Image scannerPhoto({
  int width = 400,
  int height = 320,
  List<Offset> corners = const [
    Offset(.15, .12),
    Offset(.85, .12),
    Offset(.85, .88),
    Offset(.15, .88),
  ],
  int paper = 230,
  int background = 45,
  int noise = 0,
  bool shadow = false,
}) {
  final image = img.Image(width: width, height: height);
  final random = math.Random(77);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final point = Offset(x / (width - 1), y / (height - 1));
      var inside = true;
      for (var i = 0; i < 4; i++) {
        final a = corners[i], b = corners[(i + 1) % 4];
        if ((b.dx - a.dx) * (point.dy - a.dy) -
                (b.dy - a.dy) * (point.dx - a.dx) <
            0) {
          inside = false;
        }
      }
      final shade = shadow && inside ? (60 * x / width).round() : 0;
      final jitter = noise == 0 ? 0 : random.nextInt(noise * 2 + 1) - noise;
      final value = ((inside ? paper : background) - shade + jitter).clamp(
        0,
        255,
      );
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

Uint8List scannerBytes(img.Image image) =>
    Uint8List.fromList(img.encodeJpg(image, quality: 95));
