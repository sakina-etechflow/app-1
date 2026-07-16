/// Person segmentation mask (from ML Kit selfie segmentation on-device, or a
/// cached `.mask.png` in the calibration harness).
///
/// The mask drives the crown estimate (C3) and the background sampling for
/// C10-C12, so those checks never read a fixed border rectangle that hair or
/// shoulders could contaminate.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

class PersonMask {
  PersonMask({
    required this.width,
    required this.height,
    required Uint8List confidence,
  })  : _confidence = confidence,
        assert(confidence.length == width * height,
            'mask buffer must be width*height');

  /// Row-major person-probability, one byte per pixel, 0 (background) .. 255
  /// (definitely person).
  final Uint8List _confidence;
  final int width;
  final int height;

  /// Decode a single-channel (or grayscale) PNG mask as produced by the
  /// Stage-1 signal extractor. Uses the luminance of each pixel as confidence.
  factory PersonMask.fromPng(Uint8List pngBytes) {
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) {
      throw const FormatException('Could not decode person mask PNG');
    }
    final buf = Uint8List(decoded.width * decoded.height);
    var i = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        buf[i++] = (decoded.getPixel(x, y).luminanceNormalized * 255).round();
      }
    }
    return PersonMask(
        width: decoded.width, height: decoded.height, confidence: buf);
  }

  double confidenceAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    return _confidence[y * width + x] / 255.0;
  }

  bool isPerson(int x, int y, {double threshold = 0.5}) =>
      confidenceAt(x, y) >= threshold;

  /// Topmost y (smallest y) with a person pixel, i.e. the crown including hair.
  /// Returns null when the mask is empty. This is the crown estimate C3 needs.
  int? topmostPersonY({double threshold = 0.5}) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (isPerson(x, y, threshold: threshold)) return y;
      }
    }
    return null;
  }
}
