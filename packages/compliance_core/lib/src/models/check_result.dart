/// Per-check result and the overall compliance report.
///
/// Contract (calibration harness spec): every check returns
/// `{pass, severity, message, measuredValue}`; the overall verdict passes when
/// every error-severity check passes. Warnings surface but never block.
library;

enum Severity { error, warning }

class CheckResult {
  const CheckResult({
    required this.checkId,
    required this.name,
    required this.pass,
    required this.severity,
    required this.message,
    this.measuredValue,
  });

  /// 'C1'..'C15'.
  final String checkId;

  /// Stable slug, e.g. 'head-height'.
  final String name;

  final bool pass;
  final Severity severity;

  /// Plain-language coaching message shown to the user when the check fails.
  final String message;

  /// The measured number the check compared against its threshold. Lets the
  /// calibration harness print "measured X vs threshold Y".
  final Object? measuredValue;

  CheckResult copyWith({bool? pass, String? message, Object? measuredValue}) =>
      CheckResult(
        checkId: checkId,
        name: name,
        pass: pass ?? this.pass,
        severity: severity,
        message: message ?? this.message,
        measuredValue: measuredValue ?? this.measuredValue,
      );

  @override
  String toString() =>
      '$checkId $name ${pass ? "PASS" : "FAIL"} (${severity.name})'
      '${measuredValue == null ? "" : " [$measuredValue]"}';
}

/// The full result of evaluating one photo against one document config.
class ComplianceReport {
  ComplianceReport({required this.documentId, required this.results});

  final String documentId;
  final List<CheckResult> results;

  /// Overall verdict: pass iff every error-severity check passes. Warnings
  /// (e.g. head covering, exposure) do not block.
  bool get pass => results
      .where((r) => r.severity == Severity.error)
      .every((r) => r.pass);

  List<CheckResult> get failing =>
      results.where((r) => !r.pass).toList(growable: false);

  // --- Per-check status summaries (feed S5) --------------------------------

  /// Total number of checks that actually ran.
  int get total => results.length;

  /// How many checks (of any severity) passed.
  int get passedCount => results.where((r) => r.pass).length;

  /// Blocking (error-severity) checks and how many passed. These drive the
  /// overall verdict; warnings are advisory.
  int get errorCount =>
      results.where((r) => r.severity == Severity.error).length;
  int get errorsPassed => results
      .where((r) => r.severity == Severity.error && r.pass)
      .length;

  /// Advisory (warning-severity) checks and how many are currently flagged.
  int get warningCount =>
      results.where((r) => r.severity == Severity.warning).length;
  int get warningsFlagged => results
      .where((r) => r.severity == Severity.warning && !r.pass)
      .length;

  /// Ids of the checks that fired, for harness comparison against
  /// `expected_failing_checks`.
  List<String> get failingCheckIds =>
      failing.map((r) => r.checkId).toList(growable: false);

  CheckResult? operator [](String checkId) {
    for (final r in results) {
      if (r.checkId == checkId) return r;
    }
    return null;
  }
}
