/// Appearance checks C6-C9: eyes, expression, glasses, head covering.
library;

import '../config/thresholds.dart';
import '../models/check_result.dart';
import '../models/document_config.dart';
import '../models/face_signals.dart';

/// C6. Both eyes open.
CheckResult checkEyesOpen(FaceSignals s, Thresholds t) {
  final l = s.leftEyeOpen;
  final r = s.rightEyeOpen;
  // Missing probabilities (ML Kit may omit them) do not block capture.
  if (l == null || r == null) {
    return const CheckResult(
      checkId: 'C6',
      name: 'eyes-open',
      pass: true,
      severity: Severity.error,
      message: 'Keep both eyes open and visible.',
      measuredValue: 'not measured',
    );
  }
  final pass = l > t.eyeOpenMin && r > t.eyeOpenMin;
  return CheckResult(
    checkId: 'C6',
    name: 'eyes-open',
    pass: pass,
    severity: Severity.error,
    message: pass
        ? 'Both eyes are open.'
        : 'Keep both eyes open and visible.',
    measuredValue: 'L ${l.toStringAsFixed(2)}, R ${r.toStringAsFixed(2)}',
  );
}

/// Rough mouth-open ratio (lip gap / face height) from ML Kit mouth landmarks,
/// or null when the landmarks are unavailable.
double? _mouthOpenRatio(FaceSignals s) {
  final left = s.landmarks[FaceLandmarkType.mouthLeft];
  final right = s.landmarks[FaceLandmarkType.mouthRight];
  final bottom = s.landmarks[FaceLandmarkType.mouthBottom];
  final box = s.boundingBox;
  if (left == null || right == null || bottom == null || box == null) {
    return null;
  }
  final mouthLineY = (left.y + right.y) / 2;
  final gap = (bottom.y - mouthLineY).abs();
  if (box.height <= 0) return null;
  return gap / box.height;
}

/// C7. Expression / mouth. Error for strict-neutral documents (UK, Schengen);
/// warning otherwise (US, India), where a closed-mouth smile is allowed.
CheckResult checkExpression(FaceSignals s, DocumentConfig c, Thresholds t) {
  final strict = c.expressionRule == ExpressionRule.neutralStrict;
  final severity = strict ? Severity.error : Severity.warning;
  final ratio = _mouthOpenRatio(s);
  final mouthClosed = ratio == null ? true : ratio <= t.mouthOpenRatioMax;
  final smiling = s.smiling;
  final smileOk = !strict || smiling == null || smiling < t.smilingMaxStrict;
  final pass = mouthClosed && smileOk;

  String message = 'Neutral expression looks good.';
  if (!pass) {
    message = 'Neutral expression, mouth closed.';
    if (strict && !smileOk) message = 'No smiling for this document.';
  }
  return CheckResult(
    checkId: 'C7',
    name: 'expression',
    pass: pass,
    severity: severity,
    message: message,
    measuredValue: 'mouthOpen '
        '${ratio == null ? "n/a" : ratio.toStringAsFixed(3)}, '
        'smiling ${smiling == null ? "n/a" : smiling.toStringAsFixed(2)}',
  );
}

/// C8. Glasses. ML Kit does not classify glasses reliably, so the app uses a
/// mandatory confirm step; [wearsGlasses] carries that answer. Severity is
/// derived from the document's [GlassesRule]: banned -> error, discouraged ->
/// warning, allowedNoGlare -> warning (glare guidance only).
CheckResult checkGlasses(FaceSignals s, DocumentConfig c, {bool? wearsGlasses}) {
  const id = 'C8';
  const name = 'glasses';
  switch (c.glassesRule) {
    case GlassesRule.banned:
      final pass = wearsGlasses != true;
      return CheckResult(
        checkId: id,
        name: name,
        pass: pass,
        severity: Severity.error,
        message: pass
            ? 'No glasses detected.'
            : 'Glasses are not allowed for this document. Please remove them.',
        measuredValue: wearsGlasses,
      );
    case GlassesRule.discouraged:
      final pass = wearsGlasses != true;
      return CheckResult(
        checkId: id,
        name: name,
        pass: pass,
        severity: Severity.warning,
        message: pass
            ? 'No glasses detected.'
            : 'Glasses are discouraged. If worn, ensure eyes are fully '
                'visible with no glare.',
        measuredValue: wearsGlasses,
      );
    case GlassesRule.allowedNoGlare:
      return CheckResult(
        checkId: id,
        name: name,
        pass: true,
        severity: Severity.warning,
        message: 'Glasses are allowed. Ensure no tint, no glare, and eyes '
            'fully visible.',
        measuredValue: wearsGlasses,
      );
  }
}

/// C9. Head covering. Warning only, never a hard block — religious and medical
/// coverings are allowed by every document here.
CheckResult checkHeadCovering() => const CheckResult(
      checkId: 'C9',
      name: 'head-covering',
      pass: true,
      severity: Severity.warning,
      message: 'If you wear a head covering for religious reasons, make sure '
          'your full face from chin to forehead and both edges is visible.',
    );
