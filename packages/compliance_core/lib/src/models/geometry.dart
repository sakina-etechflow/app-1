/// Small immutable value types shared across the compliance models.
///
/// Pure Dart, no Flutter and no ML Kit. See the calibration harness spec for
/// the signal contract these back.
library;

import 'dart:math' as math;

/// A 2D point in image pixel space (origin top-left, y grows downward).
class FacePoint {
  const FacePoint(this.x, this.y);

  final double x;
  final double y;

  @override
  String toString() => 'FacePoint($x, $y)';
}

/// An axis-aligned face bounding box in image pixel space.
class BoundingBox {
  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  @override
  String toString() => 'BoundingBox(x:$x, y:$y, w:$width, h:$height)';
}

/// A physical size in millimetres (width x height).
class SizeMm {
  const SizeMm(this.width, this.height);

  final double width;
  final double height;

  @override
  String toString() => 'SizeMm(${width}x$height mm)';
}

/// A pixel size (width x height).
class SizePx {
  const SizePx(this.width, this.height);

  final int width;
  final int height;

  @override
  String toString() => 'SizePx(${width}x$height px)';
}

/// An 8-bit-per-channel RGB colour.
class Rgb {
  const Rgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  /// Rec. 601 luma, 0..255. Used by the exposure and shadow checks.
  double get luminance => 0.299 * r + 0.587 * g + 0.114 * b;

  @override
  String toString() => 'Rgb($r, $g, $b)';
}

/// Clamp helper reused by the pixel checks.
int clamp255(num v) => v.clamp(0, 255).round();

/// Euclidean distance between two points.
double distance(FacePoint a, FacePoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
