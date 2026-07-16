/// Pixel-sampling helpers shared by the background, lighting, and sharpness
/// checks. All sampling is driven off the person mask, never a fixed border
/// rectangle, so hair and shoulders do not contaminate the background sample
/// (data pack, "background sampling").
library;

import 'dart:math' as math;

import '../models/geometry.dart';
import '../models/image_data.dart';
import '../models/person_mask.dart';

/// Mean and per-channel standard deviation of a set of RGB samples.
class RgbStats {
  RgbStats(this.mean, this.stdDev, this.count);
  final Rgb mean;
  final Rgb stdDev;
  final int count;

  double get maxChannelStdDev =>
      [stdDev.r, stdDev.g, stdDev.b].map((v) => v.toDouble()).reduce(math.max);
}

/// Sample the background region: pixels the mask marks as clearly NOT person
/// (confidence below [bgThreshold], which leaves a halo around the subject).
/// Returns null when too few background pixels are found to be meaningful.
RgbStats? backgroundStats(
  ImageData image,
  PersonMask mask, {
  double bgThreshold = 0.3,
  int minSamples = 200,
}) {
  var n = 0;
  var sr = 0.0, sg = 0.0, sb = 0.0;
  var sr2 = 0.0, sg2 = 0.0, sb2 = 0.0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (mask.confidenceAt(x, y) >= bgThreshold) continue; // person or halo
      final p = image.pixelAt(x, y);
      sr += p.r;
      sg += p.g;
      sb += p.b;
      sr2 += p.r * p.r;
      sg2 += p.g * p.g;
      sb2 += p.b * p.b;
      n++;
    }
  }
  if (n < minSamples) return null;
  final mr = sr / n, mg = sg / n, mb = sb / n;
  double std(double sum2, double mean) =>
      math.sqrt(math.max(0, sum2 / n - mean * mean));
  return RgbStats(
    Rgb(clamp255(mr), clamp255(mg), clamp255(mb)),
    Rgb(clamp255(std(sr2, mr)), clamp255(std(sg2, mg)), clamp255(std(sb2, mb))),
    n,
  );
}

/// Mean luminance of background pixels within [x0,x1) columns (for the
/// left/right shadow-gradient check).
double? backgroundColumnLuminance(
  ImageData image,
  PersonMask mask,
  int x0,
  int x1, {
  double bgThreshold = 0.3,
}) {
  var n = 0;
  var sum = 0.0;
  for (var y = 0; y < image.height; y++) {
    for (var x = x0; x < x1; x++) {
      if (mask.confidenceAt(x, y) >= bgThreshold) continue;
      sum += image.luminanceAt(x, y);
      n++;
    }
  }
  return n == 0 ? null : sum / n;
}

/// Integer bounds of a bounding box clamped to the image.
class IntRect {
  IntRect(this.left, this.top, this.right, this.bottom);
  final int left, top, right, bottom;
  int get width => right - left;
  int get height => bottom - top;
  bool get isEmpty => width <= 0 || height <= 0;
}

IntRect faceRect(BoundingBox box, int imgW, int imgH) => IntRect(
      box.x.floor().clamp(0, imgW - 1),
      box.y.floor().clamp(0, imgH - 1),
      (box.x + box.width).ceil().clamp(0, imgW),
      (box.y + box.height).ceil().clamp(0, imgH),
    );

/// Mean luminance and clipped-highlight fraction over a rectangle.
class FaceLumaStats {
  FaceLumaStats(this.meanLuminance, this.clippedFraction);
  final double meanLuminance;
  final double clippedFraction; // 0..1 of pixels with luminance > 250
}

FaceLumaStats faceLumaStats(ImageData image, IntRect r) {
  var n = 0, clipped = 0;
  var sum = 0.0;
  for (var y = r.top; y < r.bottom; y++) {
    for (var x = r.left; x < r.right; x++) {
      final l = image.luminanceAt(x, y);
      sum += l;
      if (l > 250) clipped++;
      n++;
    }
  }
  if (n == 0) return FaceLumaStats(0, 0);
  return FaceLumaStats(sum / n, clipped / n);
}

/// Mean luminance of the left vs right half of a rectangle, for the
/// facial shadow-asymmetry check.
({double left, double right}) faceHalfLuminance(ImageData image, IntRect r) {
  final mid = r.left + r.width ~/ 2;
  var ln = 0, rn = 0;
  var ls = 0.0, rs = 0.0;
  for (var y = r.top; y < r.bottom; y++) {
    for (var x = r.left; x < r.right; x++) {
      final l = image.luminanceAt(x, y);
      if (x < mid) {
        ls += l;
        ln++;
      } else {
        rs += l;
        rn++;
      }
    }
  }
  return (left: ln == 0 ? 0 : ls / ln, right: rn == 0 ? 0 : rs / rn);
}

/// Variance of the Laplacian over a rectangle's luminance — the standard blur
/// metric. Higher = sharper.
double laplacianVariance(ImageData image, IntRect r) {
  if (r.width < 3 || r.height < 3) return 0;
  final vals = <double>[];
  for (var y = r.top + 1; y < r.bottom - 1; y++) {
    for (var x = r.left + 1; x < r.right - 1; x++) {
      final lap = image.luminanceAt(x, y) * 4 -
          image.luminanceAt(x - 1, y) -
          image.luminanceAt(x + 1, y) -
          image.luminanceAt(x, y - 1) -
          image.luminanceAt(x, y + 1);
      vals.add(lap);
    }
  }
  if (vals.isEmpty) return 0;
  final mean = vals.reduce((a, b) => a + b) / vals.length;
  final varc =
      vals.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          vals.length;
  return varc;
}
