import 'package:compliance_core/compliance_core.dart';
import 'package:test/test.dart';

import 'support/synthetic.dart';

void main() {
  group('evaluate() end-to-end', () {
    test('a compliant US passport scene passes every error check', () {
      final scene = compliantScene(usPassport);
      final report = evaluate(scene.signals, scene.image, usPassport,
          wearsGlasses: false);
      // Print any failures to make a regression obvious.
      final fails = report.results
          .where((r) => !r.pass && r.severity == Severity.error)
          .map((r) => '${r.checkId} ${r.name}: ${r.measuredValue}')
          .toList();
      expect(report.pass, isTrue, reason: 'unexpected failures: $fails');
    });

    test('flipping head-height out of band fails with C3 firing', () {
      // Crown pulled down so chin-to-crown is ~25% of the frame.
      final scene = compliantScene(usPassport, crownY: 700, chinY: 924);
      final report = evaluate(scene.signals, scene.image, usPassport,
          wearsGlasses: false);
      expect(report.pass, isFalse);
      expect(report['C3']!.pass, isFalse);
      expect(report.failingCheckIds, contains('C3'));
    });

    test('a compliant UK scene passes', () {
      final scene = compliantScene(ukPassport);
      final report =
          evaluate(scene.signals, scene.image, ukPassport, wearsGlasses: false);
      final fails = report.results
          .where((r) => !r.pass && r.severity == Severity.error)
          .map((r) => '${r.checkId}: ${r.measuredValue}')
          .toList();
      expect(report.pass, isTrue, reason: 'unexpected failures: $fails');
    });

    test('the same white background that passes US FAILS UK (anti-white rule)',
        () {
      // A pure-white scene is correct for US but wrong for UK.
      final white = compliantScene(ukPassport, bgColor: const Rgb(255, 255, 255));
      final ukReport =
          evaluate(white.signals, white.image, ukPassport, wearsGlasses: false);
      expect(ukReport['C11']!.pass, isFalse,
          reason: 'UK must reject a pure-white background');
      expect(ukReport.pass, isFalse);
    });

    test('signal-only evaluation (no image) omits the pixel checks', () {
      final scene = compliantScene(usPassport);
      final report =
          evaluate(scene.signals, null, usPassport, wearsGlasses: false);
      expect(report['C10'], isNull); // background checks skipped
      expect(report['C1'], isNotNull); // geometry still present
      expect(report['C15'], isNotNull); // integrity still enforced
    });

    test('US pipeline flags an altered photo via C15', () {
      final scene = compliantScene(usPassport);
      final report = evaluate(scene.signals, scene.image, usPassport,
          wearsGlasses: false, aiOrEnhancementApplied: true);
      expect(report['C15']!.pass, isFalse);
      expect(report.pass, isFalse);
    });
  });

  // A1-05: the engine must run every check and report a per-check status.
  group('per-check results model (A1-05)', () {
    // The full roster the engine produces with pixels available.
    const fullRoster = [
      'C1', 'C2', 'C3', 'C4', 'C5', // geometry
      'C6', 'C7', 'C8', 'C9', // appearance
      'C10', 'C11', 'C12', 'C13', 'C14', // background / lighting / sharpness
      'C15', // integrity
    ];
    // Checks that need decoded pixels + the person mask.
    const pixelChecks = ['C10', 'C11', 'C12', 'C13', 'C14'];

    test('a full run executes all 15 checks, each with a status', () {
      final scene = compliantScene(usPassport);
      final report = evaluate(scene.signals, scene.image, usPassport,
          wearsGlasses: false);

      // Every expected check ran, exactly once, and nothing extra.
      final ids = report.results.map((r) => r.checkId).toList();
      expect(ids.toSet(), equals(fullRoster.toSet()));
      expect(ids.length, equals(fullRoster.length),
          reason: 'no duplicate check ids');

      // Each result reports a usable per-check status.
      for (final r in report.results) {
        expect(r.checkId, matches(RegExp(r'^C\d+$')));
        expect(r.name, isNotEmpty, reason: '${r.checkId} needs a name');
        expect(r.message, isNotEmpty, reason: '${r.checkId} needs a message');
        expect(r.pass, isA<bool>());
        expect(Severity.values, contains(r.severity));
        // Reachable by id for the UI/harness.
        expect(report[r.checkId], isNotNull);
      }
    });

    test('summary counts reconcile with the per-check results', () {
      final scene = compliantScene(usPassport);
      final report = evaluate(scene.signals, scene.image, usPassport,
          wearsGlasses: false);
      expect(report.total, equals(report.results.length));
      expect(report.errorCount + report.warningCount, equals(report.total));
      expect(report.passedCount,
          equals(report.results.where((r) => r.pass).length));
      // Overall verdict is exactly "all blocking checks passed".
      expect(report.pass, equals(report.errorsPassed == report.errorCount));
    });

    test('signal-only run reports the non-pixel checks only', () {
      final scene = compliantScene(usPassport);
      final report =
          evaluate(scene.signals, null, usPassport, wearsGlasses: false);
      final ids = report.results.map((r) => r.checkId).toSet();
      final expected =
          fullRoster.where((id) => !pixelChecks.contains(id)).toSet();
      expect(ids, equals(expected));
      for (final id in pixelChecks) {
        expect(report[id], isNull, reason: '$id needs pixels; must be omitted');
      }
      // The checks that did run still each carry a status.
      for (final r in report.results) {
        expect(r.pass, isA<bool>());
        expect(Severity.values, contains(r.severity));
      }
    });
  });
}
