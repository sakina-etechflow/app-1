/// Background, lighting, and sharpness checks C10-C14. These read decoded
/// pixels plus the person mask, so they run at capture time on the still (not
/// per frame) and in the calibration harness on desktop.
library;

import '../config/thresholds.dart';
import '../models/check_result.dart';
import '../models/document_config.dart';
import '../models/face_signals.dart';
import '../models/image_data.dart';
import '../models/person_mask.dart';
import 'pixel_stats.dart';

/// C10. Background uniformity: per-channel std dev over the background band.
CheckResult checkBackgroundUniformity(
    ImageData image, PersonMask mask, Thresholds t) {
  final stats = backgroundStats(image, mask);
  if (stats == null) {
    return const CheckResult(
      checkId: 'C10',
      name: 'background-uniformity',
      pass: false,
      severity: Severity.error,
      message: 'Use a plain, uniform background with no objects, patterns, or '
          'people behind you.',
      measuredValue: 'insufficient background pixels',
    );
  }
  final pass = stats.maxChannelStdDev <= t.bgUniformityMaxStdDev;
  return CheckResult(
    checkId: 'C10',
    name: 'background-uniformity',
    pass: pass,
    severity: Severity.error,
    message: pass
        ? 'Background is uniform.'
        : 'Use a plain, uniform background with no objects, patterns, or '
            'people behind you.',
    measuredValue: 'std ${stats.maxChannelStdDev.toStringAsFixed(1)} '
        '(<= ${t.bgUniformityMaxStdDev})',
  );
}

/// C11. Background colour correct: mean background colour within the document's
/// per-channel accept box. This enforces the white-required and anti-white
/// rules per document.
CheckResult checkBackgroundColor(
    ImageData image, PersonMask mask, DocumentConfig c) {
  final stats = backgroundStats(image, mask);
  if (stats == null) {
    return const CheckResult(
      checkId: 'C11',
      name: 'background-color',
      pass: false,
      severity: Severity.error,
      message: 'Could not read the background. Use a plain background.',
      measuredValue: null,
    );
  }
  final m = stats.mean;
  bool within(int v, int lo, int hi) => v >= lo && v <= hi;
  final pass = within(m.r, c.backgroundAcceptMin.r, c.backgroundAcceptMax.r) &&
      within(m.g, c.backgroundAcceptMin.g, c.backgroundAcceptMax.g) &&
      within(m.b, c.backgroundAcceptMin.b, c.backgroundAcceptMax.b);

  final wants = c.backgroundRule == BackgroundRule.whiteRequired
      ? 'white for this document'
      : 'light grey or cream (not white) for this document';
  return CheckResult(
    checkId: 'C11',
    name: 'background-color',
    pass: pass,
    severity: Severity.error,
    message: pass ? 'Background colour is correct.' : 'Background should be $wants.',
    measuredValue: 'mean $m',
  );
}

/// C12. Shadows: background luminance gradient across the region AND face
/// left-vs-right luminance asymmetry.
CheckResult checkShadows(
    ImageData image, PersonMask mask, FaceSignals s, Thresholds t) {
  const id = 'C12';
  const name = 'shadows';
  final third = image.width ~/ 3;
  final leftLum = backgroundColumnLuminance(image, mask, 0, third);
  final rightLum =
      backgroundColumnLuminance(image, mask, image.width - third, image.width);
  final bgGradient = (leftLum != null && rightLum != null)
      ? (leftLum - rightLum).abs()
      : 0.0;

  double faceAsymPct = 0;
  final box = s.boundingBox;
  if (box != null) {
    final r = faceRect(box, image.width, image.height);
    if (!r.isEmpty) {
      final halves = faceHalfLuminance(image, r);
      final mean = (halves.left + halves.right) / 2;
      if (mean > 0) {
        faceAsymPct = (halves.left - halves.right).abs() / mean * 100;
      }
    }
  }

  final pass = bgGradient <= t.shadowBgGradientMax &&
      faceAsymPct <= t.shadowFaceAsymmetryMaxPct;
  return CheckResult(
    checkId: id,
    name: name,
    pass: pass,
    severity: Severity.error,
    message: pass
        ? 'No shadows detected.'
        : 'Shadows detected. Face a light source directly and step away from '
            'the wall.',
    measuredValue: 'bgGradient ${bgGradient.toStringAsFixed(1)}, '
        'faceAsym ${faceAsymPct.toStringAsFixed(1)}%',
  );
}

/// C13. Exposure: face-region mean luminance within a mid band, and few clipped
/// highlights. Warning, not a hard block.
CheckResult checkExposure(ImageData image, FaceSignals s, Thresholds t) {
  const id = 'C13';
  const name = 'exposure';
  final box = s.boundingBox;
  if (box == null) {
    return const CheckResult(
      checkId: id,
      name: name,
      pass: true,
      severity: Severity.warning,
      message: 'Lighting could not be measured.',
      measuredValue: null,
    );
  }
  final r = faceRect(box, image.width, image.height);
  final stats = faceLumaStats(image, r);
  final clippedPct = stats.clippedFraction * 100;
  final pass = stats.meanLuminance >= t.exposureFaceMeanMin &&
      stats.meanLuminance <= t.exposureFaceMeanMax &&
      clippedPct < t.exposureClippedMaxPct;
  return CheckResult(
    checkId: id,
    name: name,
    pass: pass,
    severity: Severity.warning,
    message: pass
        ? 'Lighting looks even.'
        : 'Lighting looks too bright or too dark. Use even, diffused light.',
    measuredValue: 'faceMean ${stats.meanLuminance.toStringAsFixed(0)}, '
        'clipped ${clippedPct.toStringAsFixed(1)}%',
  );
}

/// C14. Sharpness and resolution: Laplacian variance over the face region AND
/// output dimensions meet the document minimum.
CheckResult checkSharpness(
    ImageData image, FaceSignals s, DocumentConfig c, Thresholds t) {
  const id = 'C14';
  const name = 'sharpness';
  final box = s.boundingBox;
  final rect = box == null
      ? IntRect(0, 0, image.width, image.height)
      : faceRect(box, image.width, image.height);
  final lapVar = laplacianVariance(image, rect);
  final resOk = image.width >= c.minResolutionPx.width &&
      image.height >= c.minResolutionPx.height;
  final sharpOk = lapVar >= t.sharpnessLaplacianMin;
  final pass = resOk && sharpOk;
  final message = !resOk
      ? 'Image resolution is too low for this document.'
      : (!sharpOk
          ? 'Image is blurry. Hold steady and ensure good light.'
          : 'Image is sharp and high enough resolution.');
  return CheckResult(
    checkId: id,
    name: name,
    pass: pass,
    severity: Severity.error,
    message: message,
    measuredValue: 'laplacianVar ${lapVar.toStringAsFixed(0)} '
        '(>= ${t.sharpnessLaplacianMin}), ${image.width}x${image.height}',
  );
}

