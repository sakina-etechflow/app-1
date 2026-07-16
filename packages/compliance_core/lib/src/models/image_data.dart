/// Decoded still-image pixels for the pixel-based checks (background
/// uniformity/colour, shadows, exposure, sharpness).
///
/// Wraps the `image` package so the whole pipeline runs in pure Dart on
/// desktop and in the calibration harness, not just on a device.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'geometry.dart';

class ImageData {
  ImageData(this._image);

  final img.Image _image;

  int get width => _image.width;
  int get height => _image.height;

  /// Decode an encoded image (JPEG/PNG/...) into [ImageData].
  factory ImageData.decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Could not decode image bytes');
    }
    return ImageData(decoded);
  }

  /// Build directly from an `image` package [img.Image] (used by tests that
  /// synthesise scenes).
  factory ImageData.fromImage(img.Image image) => ImageData(image);

  Rgb pixelAt(int x, int y) {
    final p = _image.getPixel(x.clamp(0, width - 1), y.clamp(0, height - 1));
    return Rgb(p.r.toInt(), p.g.toInt(), p.b.toInt());
  }

  double luminanceAt(int x, int y) => pixelAt(x, y).luminance;
}
