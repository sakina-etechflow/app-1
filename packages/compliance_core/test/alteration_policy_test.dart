import 'package:compliance_core/compliance_core.dart';
import 'package:test/test.dart';

/// A minimal alteration-allowed document, for the "other flow" branch. Every
/// shipped MVP document forbids alteration, so we synthesise one here to prove
/// the gate is keyed on the document, not hard-wired shut.
final _alterationAllowedDoc = DocumentConfig(
  id: 'test_altered_ok',
  country: 'XX',
  documentType: 'novelty',
  displayName: 'Test (alteration allowed)',
  outputSizeMm: const SizeMm(51, 51),
  minResolutionPx: const SizePx(600, 600),
  maxResolutionPx: const SizePx(1200, 1200),
  dpiMin: 300,
  headHeightMinPct: 50,
  headHeightMaxPct: 69,
  backgroundRule: BackgroundRule.whiteRequired,
  backgroundTarget: const Rgb(255, 255, 255),
  backgroundAcceptMin: const Rgb(235, 235, 235),
  backgroundAcceptMax: const Rgb(255, 255, 255),
  glassesRule: GlassesRule.allowedNoGlare,
  expressionRule: ExpressionRule.neutralClosedMouthOk,
  alterationAllowed: true,
  confidence: Confidence.low,
  sourceUrl: 'test',
  lastVerifiedDate: '2026-07-18',
);

void main() {
  group('AlterationPolicy — no-alteration enforced by doc type (spec 4 / C15)',
      () {
    test('US passport forbids enhancement: admit() throws, nothing recorded',
        () {
      final policy = AlterationPolicy(usPassport);
      expect(policy.allowsEnhancement, isFalse);
      expect(
        () => policy.admit(TransformKind.enhancement, label: 'skin-smoothing'),
        throwsA(isA<AlterationNotPermitted>()),
      );
      // A blocked attempt must NOT flip the record used for C15.
      expect(policy.enhancementApplied, isFalse);
    });

    test('every shipped MVP document forbids enhancement', () {
      for (final doc in mvpDocuments) {
        final policy = AlterationPolicy(doc);
        expect(policy.allowsEnhancement, isFalse, reason: doc.id);
        expect(
          () =>
              policy.admit(TransformKind.enhancement, label: 'generative-fill'),
          throwsA(isA<AlterationNotPermitted>()),
          reason: doc.id,
        );
      }
    });

    test('geometric transforms always pass and never count as alteration', () {
      final policy = AlterationPolicy(usPassport);
      // Crop + resize on a forbidding document: fine, and not "altered".
      policy.admit(TransformKind.geometric, label: 'crop');
      policy.admit(TransformKind.geometric, label: 'resize');
      expect(policy.enhancementApplied, isFalse);
    });

    test('an alteration-allowed document records an admitted enhancement', () {
      final policy = AlterationPolicy(_alterationAllowedDoc);
      expect(policy.allowsEnhancement, isTrue);
      policy.admit(TransformKind.enhancement, label: 'skin-smoothing');
      expect(policy.enhancementApplied, isTrue);
    });

    test('the exception names the document and the blocked step', () {
      final policy = AlterationPolicy(usPassport);
      try {
        policy.admit(TransformKind.enhancement, label: 'face-reshape');
        fail('expected AlterationNotPermitted');
      } on AlterationNotPermitted catch (e) {
        expect(e.documentId, 'us_passport');
        expect(e.transform, 'face-reshape');
        expect(e.toString(), contains('us_passport'));
      }
    });
  });
}
