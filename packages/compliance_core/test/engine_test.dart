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
}
