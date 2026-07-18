/// The no-alteration guarantee, enforced in code by document type (store
/// compliance spec item 4; C15). The app's processing pipeline routes EVERY
/// pixel transform through an [AlterationPolicy]. For any document whose
/// [DocumentConfig.alterationAllowed] is false — every US flow, every MVP
/// document — a beautifying or generative transform cannot run: the gate throws
/// before a single pixel is touched. That makes "no AI alteration" a structural
/// property of the pipeline, not UI copy.
///
/// Lives in compliance_core (pure Dart, no Flutter, no ML Kit) so the app
/// pipeline and the calibration harness share one source of truth for what may
/// touch the subject, and so the record the gate keeps is the SAME value fed to
/// `evaluate(aiOrEnhancementApplied: ...)` for C15 — never a hard-coded literal.
library;

import '../models/document_config.dart';

/// How a pixel transform relates to the no-alteration rule.
enum TransformKind {
  /// Crop, resize, rotate-to-level, DPI, background formatting. It reformats
  /// the photo; it does not alter the subject. Always permitted.
  geometric,

  /// Beautify, smoothing, skin/colour edits, face reshaping, generative fill.
  /// Alters the subject; permitted ONLY where the document allows alteration.
  enhancement,
}

/// Thrown when a [TransformKind.enhancement] transform is attempted on a
/// document whose [DocumentConfig.alterationAllowed] is false.
class AlterationNotPermitted implements Exception {
  const AlterationNotPermitted(this.documentId, this.transform);

  /// The document the transform was blocked for, e.g. 'us_passport'.
  final String documentId;

  /// The name of the blocked step, for diagnostics, e.g. 'skin-smoothing'.
  final String transform;

  @override
  String toString() =>
      'AlterationNotPermitted: "$transform" alters the subject and is '
      'forbidden for document "$documentId" (alterationAllowed == false).';
}

/// The gate the pipeline calls before running any pixel transform.
///
/// Geometric transforms always pass. Enhancement transforms pass only when the
/// document permits alteration, and are recorded so the pipeline can report
/// what actually ran to C15. There is no other way to set [enhancementApplied]
/// true, so a `true` C15 input can only mean an admitted enhancement really ran
/// — and for an alteration-forbidding document that path throws instead.
class AlterationPolicy {
  AlterationPolicy(this.doc);

  final DocumentConfig doc;

  bool _enhancementApplied = false;

  /// Whether an enhancement transform has actually been admitted and run. Feed
  /// this to `evaluate(aiOrEnhancementApplied: ...)` — never a literal.
  bool get enhancementApplied => _enhancementApplied;

  /// Whether this document permits subject-altering transforms at all. Callers
  /// use this to keep optional enhancement features off and unavailable in the
  /// forbidding flows (spec item 4), rather than calling [admit] and catching.
  bool get allowsEnhancement => doc.alterationAllowed;

  /// Admit a transform of [kind] before it runs. Returns normally for geometric
  /// transforms, and for enhancement transforms on alteration-allowed documents
  /// (recording the fact). Throws [AlterationNotPermitted] for an enhancement
  /// transform on a document that forbids alteration. [label] names the step.
  void admit(TransformKind kind, {required String label}) {
    if (kind == TransformKind.geometric) return;
    if (!doc.alterationAllowed) {
      throw AlterationNotPermitted(doc.id, label);
    }
    _enhancementApplied = true;
  }
}
