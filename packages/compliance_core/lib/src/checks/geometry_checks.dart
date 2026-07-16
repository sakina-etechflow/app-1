/// Geometry checks C1-C5. These read only [FaceSignals] (plus the person mask
/// for the crown estimate), so they are cheap enough for throttled live
/// coaching and fully unit-testable without pixels.
library;

import 'dart:math' as math;

import '../config/thresholds.dart';
import '../models/check_result.dart';
import '../models/document_config.dart';
import '../models/face_signals.dart';

/// C1. Exactly one face present.
CheckResult checkSingleFace(FaceSignals s) {
  final pass = s.faceCount == 1;
  final message = s.faceCount == 0
      ? 'No face detected. Center your face in the oval.'
      : 'Only you should be in the frame. Remove anyone else.';
  return CheckResult(
    checkId: 'C1',
    name: 'single-face',
    pass: pass,
    severity: Severity.error,
    message: pass ? 'One face detected.' : message,
    measuredValue: s.faceCount,
  );
}

/// C2. Head orientation: no tilt or turn. |yaw|,|pitch|,|roll| within tolerance.
CheckResult checkHeadOrientation(FaceSignals s, Thresholds t) {
  final maxAngle =
      [s.eulerX.abs(), s.eulerY.abs(), s.eulerZ.abs()].reduce(math.max);
  final pass = maxAngle <= t.maxHeadAngleDeg;
  String message = 'Head is straight.';
  if (!pass) {
    if (s.eulerY.abs() >= s.eulerX.abs() && s.eulerY.abs() >= s.eulerZ.abs()) {
      message = 'Face the camera directly.';
    } else if (s.eulerZ.abs() >= s.eulerX.abs()) {
      message = 'Keep your head level, do not tilt.';
    } else {
      message = 'Level your chin, do not look up or down.';
    }
  }
  return CheckResult(
    checkId: 'C2',
    name: 'head-orientation',
    pass: pass,
    severity: Severity.error,
    message: message,
    measuredValue: 'yaw ${s.eulerY}, pitch ${s.eulerX}, roll ${s.eulerZ}',
  );
}

/// C3. Head height, chin to crown, as a percent of output image height.
///
/// Crown = topmost person pixel from the mask (captures hair, which the face
/// box does not). Chin = lowest face-contour point. This is the number-one
/// real-world rejection cause.
CheckResult checkHeadHeight(FaceSignals s, DocumentConfig c, Thresholds t) {
  const id = 'C3';
  const name = 'head-height';
  final mask = s.personMask;
  final crownY = mask?.topmostPersonY(threshold: t.maskThreshold);
  final chinY = s.chinY;
  if (crownY == null || chinY == null || s.imageHeight <= 0) {
    return const CheckResult(
      checkId: id,
      name: name,
      pass: false,
      severity: Severity.error,
      message: 'Center your face in the oval so your whole head is visible.',
      measuredValue: null,
    );
  }
  final pct = (chinY - crownY) / s.imageHeight * 100;
  final pass = pct >= c.headHeightMinPct && pct <= c.headHeightMaxPct;
  String message = 'Head size looks right.';
  if (pct < c.headHeightMinPct) {
    message = 'Move closer, your head is too small in the frame.';
  } else if (pct > c.headHeightMaxPct) {
    message = 'Move back, your head is too large in the frame.';
  }
  return CheckResult(
    checkId: id,
    name: name,
    pass: pass,
    severity: Severity.error,
    message: message,
    measuredValue: '${pct.toStringAsFixed(1)}% '
        '(want ${c.headHeightMinPct}-${c.headHeightMaxPct}%)',
  );
}

/// C4. Eye-line position, as a percent from the bottom edge. Only enforced
/// where the document specifies a band; otherwise reported as a passing skip.
CheckResult checkEyeLine(FaceSignals s, DocumentConfig c) {
  const id = 'C4';
  const name = 'eye-line';
  final min = c.eyeLineMinPctFromBottom;
  final max = c.eyeLineMaxPctFromBottom;
  if (min == null || max == null) {
    return const CheckResult(
      checkId: id,
      name: name,
      pass: true,
      severity: Severity.error,
      message: 'No eye-line band for this document.',
      measuredValue: 'n/a',
    );
  }
  final eyeY = s.eyeLineY;
  if (eyeY == null || s.imageHeight <= 0) {
    return const CheckResult(
      checkId: id,
      name: name,
      pass: false,
      severity: Severity.error,
      message: 'Position your eyes within the guide band.',
      measuredValue: null,
    );
  }
  final pctFromBottom = (s.imageHeight - eyeY) / s.imageHeight * 100;
  final pass = pctFromBottom >= min && pctFromBottom <= max;
  return CheckResult(
    checkId: id,
    name: name,
    pass: pass,
    severity: Severity.error,
    message: pass
        ? 'Eyes are within the guide band.'
        : 'Position your eyes within the guide band.',
    measuredValue: '${pctFromBottom.toStringAsFixed(1)}% (want $min-$max%)',
  );
}

/// C5. Horizontal centering: face-box centre vs image centre.
CheckResult checkCentering(FaceSignals s, Thresholds t) {
  const id = 'C5';
  const name = 'centering';
  final box = s.boundingBox;
  if (box == null || s.imageWidth <= 0) {
    return const CheckResult(
      checkId: id,
      name: name,
      pass: false,
      severity: Severity.error,
      message: 'Center your head horizontally.',
      measuredValue: null,
    );
  }
  final offsetPct =
      (box.centerX - s.imageWidth / 2).abs() / s.imageWidth * 100;
  final pass = offsetPct <= t.centeringMaxOffsetPct;
  return CheckResult(
    checkId: id,
    name: name,
    pass: pass,
    severity: Severity.error,
    message: pass ? 'Head is centered.' : 'Center your head horizontally.',
    measuredValue: '${offsetPct.toStringAsFixed(1)}% off center',
  );
}
