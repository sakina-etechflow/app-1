/// Integrity check C15. Enforced in code, not a live measurement: for any
/// document with alterationAllowed == false, the pipeline must apply only
/// geometric formatting (crop, resize, rotate-to-level, DPI). No AI background
/// replacement, no smoothing, no colour/skin edits, no filters. For US
/// documents the AI-server path is hard-disabled upstream.
library;

import '../models/check_result.dart';
import '../models/document_config.dart';

/// C15. No alteration. [aiOrEnhancementApplied] is the pipeline's own record of
/// whether any generative/beautifying transform ran on the subject; it must be
/// false for every alterationAllowed == false document.
CheckResult checkNoAlteration(
  DocumentConfig c, {
  bool aiOrEnhancementApplied = false,
}) {
  if (c.alterationAllowed) {
    return const CheckResult(
      checkId: 'C15',
      name: 'no-alteration',
      pass: true,
      severity: Severity.error,
      message: 'Alteration is permitted for this document.',
      measuredValue: 'allowed',
    );
  }
  final pass = !aiOrEnhancementApplied;
  return CheckResult(
    checkId: 'C15',
    name: 'no-alteration',
    pass: pass,
    severity: Severity.error,
    message: pass
        ? 'Photo is unaltered, as required for this document.'
        : 'This document forbids AI edits, filters, or retouching. Export the '
            'unaltered photo.',
    measuredValue: aiOrEnhancementApplied ? 'altered' : 'unaltered',
  );
}
