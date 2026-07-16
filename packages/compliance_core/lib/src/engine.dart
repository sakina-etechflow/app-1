/// The one rule engine both the app and the calibration harness call. Keep it
/// pure Dart (no Flutter, no ML Kit) so the harness tests the real engine, not
/// a copy (calibration harness spec, "rule engine contract").
library;

import 'checks/appearance_checks.dart';
import 'checks/background_checks.dart';
import 'checks/geometry_checks.dart';
import 'checks/integrity_checks.dart';
import 'config/thresholds.dart';
import 'models/check_result.dart';
import 'models/document_config.dart';
import 'models/face_signals.dart';
import 'models/image_data.dart';

/// Evaluate one photo against one document config.
///
/// [signals] carries the ML Kit outputs and (for C3/C10-C12) the person mask.
/// [image] is the decoded still; pass null to run only the signal-based checks
/// (C1-C9, C15) for throttled live coaching, in which case the pixel checks
/// (C10-C14) are omitted from the report rather than failed.
///
/// [wearsGlasses] is the answer to the mandatory confirm step (C8).
/// [aiOrEnhancementApplied] is the pipeline's own record for C15; it must stay
/// false for every US and alterationAllowed == false document.
ComplianceReport evaluate(
  FaceSignals signals,
  ImageData? image,
  DocumentConfig config, {
  Thresholds thresholds = Thresholds.defaults,
  bool? wearsGlasses,
  bool aiOrEnhancementApplied = false,
}) {
  final results = <CheckResult>[
    // Geometry (signal-based).
    checkSingleFace(signals),
    checkHeadOrientation(signals, thresholds),
    checkHeadHeight(signals, config, thresholds),
    checkEyeLine(signals, config),
    checkCentering(signals, thresholds),
    // Appearance (signal-based).
    checkEyesOpen(signals, thresholds),
    checkExpression(signals, config, thresholds),
    checkGlasses(signals, config, wearsGlasses: wearsGlasses),
    checkHeadCovering(),
  ];

  // Background / lighting / sharpness need decoded pixels and the person mask.
  final mask = signals.personMask;
  if (image != null && mask != null) {
    results.addAll([
      checkBackgroundUniformity(image, mask, thresholds),
      checkBackgroundColor(image, mask, config),
      checkShadows(image, mask, signals, thresholds),
      checkExposure(image, signals, thresholds),
      checkSharpness(image, signals, config, thresholds),
    ]);
  }

  // Integrity (enforced in code, always evaluated).
  results.add(checkNoAlteration(config,
      aiOrEnhancementApplied: aiOrEnhancementApplied));

  return ComplianceReport(documentId: config.id, results: results);
}
