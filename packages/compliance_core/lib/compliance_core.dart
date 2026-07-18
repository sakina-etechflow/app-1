/// compliance_core — the pure-Dart passport & ID photo compliance engine.
///
/// Public surface: the `evaluate(...)` engine, the six document configs, the
/// tunable thresholds, and the models the app and calibration harness share.
/// This library has no Flutter and no ML Kit imports by design.
library;

// Engine.
export 'src/engine.dart';

// Config.
export 'src/config/documents.dart';
export 'src/config/thresholds.dart';

// Pipeline policy (the no-alteration gate the app pipeline routes transforms
// through; enforces spec item 4 / C15 in code, by document type).
export 'src/pipeline/alteration_policy.dart';

// Models.
export 'src/models/geometry.dart';
export 'src/models/face_signals.dart';
export 'src/models/person_mask.dart';
export 'src/models/image_data.dart';
export 'src/models/document_config.dart';
export 'src/models/check_result.dart';

// Individual checks (exposed so the app can run a single check for live
// coaching, and so tests can target one check in isolation).
export 'src/checks/geometry_checks.dart';
export 'src/checks/appearance_checks.dart';
export 'src/checks/background_checks.dart';
export 'src/checks/integrity_checks.dart';
