/// A per-document spec record — the product's real IP (build brief §5).
///
/// One record per country+document. Every value here is transcribed from an
/// official source in the spec-and-compliance data pack; never retype these
/// from memory. Ship this as remotely-updatable config so a spec change does
/// not require a store resubmission.
library;

import 'geometry.dart';

/// Source-confidence, per the data pack. Do not ship a value below [high]
/// without the verification the data pack calls out.
enum Confidence { high, mediumHigh, medium, low }

/// Glasses policy. C8 severity is derived from this per document.
enum GlassesRule {
  /// Banned outright (US, UK, India passport). C8 is an error.
  banned,

  /// Allowed if no tint/glare and eyes visible (India OCI, India e-Visa).
  allowedNoGlare,

  /// Discouraged; if worn, eyes fully visible, no glare (Schengen). C8 warns.
  discouraged,
}

/// Expression policy.
enum ExpressionRule {
  /// Strictly neutral, no smile at all (UK, Schengen).
  neutralStrict,

  /// Neutral or a natural closed-mouth smile; only mouth-closed is enforced
  /// (US, India).
  neutralClosedMouthOk,
}

/// The background colour family, driving the anti-white / white-required
/// enforcement in C11. The numeric accept box lives in [backgroundAcceptMin]
/// and [backgroundAcceptMax]; this enum records the family for messaging.
enum BackgroundRule {
  /// White to off-white required; grey/coloured rejected (US, India passport,
  /// India e-Visa).
  whiteRequired,

  /// Light but explicitly NOT white; pure white rejected (UK, Schengen,
  /// India OCI).
  lightNotWhite,
}

class DocumentConfig {
  const DocumentConfig({
    required this.id,
    required this.country,
    required this.documentType,
    required this.displayName,
    required this.outputSizeMm,
    required this.minResolutionPx,
    required this.maxResolutionPx,
    required this.dpiMin,
    required this.headHeightMinPct,
    required this.headHeightMaxPct,
    required this.backgroundRule,
    required this.backgroundTarget,
    required this.backgroundAcceptMin,
    required this.backgroundAcceptMax,
    required this.glassesRule,
    required this.expressionRule,
    required this.alterationAllowed,
    required this.confidence,
    required this.sourceUrl,
    required this.lastVerifiedDate,
    this.eyeLineMinPctFromBottom,
    this.eyeLineMaxPctFromBottom,
    this.maxFileSizeKb,
    this.minFileSizeKb,
    this.recencyDays,
    this.printLayout,
    this.notes,
  });

  /// Stable id used by the picker and the harness manifest, e.g. 'us_passport'.
  final String id;
  final String country;
  final String documentType;
  final String displayName;

  final SizeMm outputSizeMm;
  final SizePx minResolutionPx;
  final SizePx maxResolutionPx;
  final int dpiMin;

  /// Head height (chin-to-crown) as a percentage of output image height.
  final double headHeightMinPct;
  final double headHeightMaxPct;

  /// Eye-line band as a percentage from the bottom edge. Null when the
  /// document specifies no explicit band (rely on head-height + centering).
  final double? eyeLineMinPctFromBottom;
  final double? eyeLineMaxPctFromBottom;

  final BackgroundRule backgroundRule;

  /// Target background colour (for messaging).
  final Rgb backgroundTarget;

  /// Per-channel inclusive accept box for the mean background colour (C11).
  final Rgb backgroundAcceptMin;
  final Rgb backgroundAcceptMax;

  final GlassesRule glassesRule;
  final ExpressionRule expressionRule;

  /// False for every MVP document: only geometric formatting is allowed and
  /// the AI-server path is hard-disabled (C15).
  final bool alterationAllowed;

  final int? maxFileSizeKb;
  final int? minFileSizeKb;
  final int? recencyDays;
  final String? printLayout;

  final Confidence confidence;
  final String sourceUrl;

  /// ISO-8601 date the values were last verified against the official source.
  final String lastVerifiedDate;

  final String? notes;
}
