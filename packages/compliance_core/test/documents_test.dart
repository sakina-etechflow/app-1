import 'package:compliance_core/compliance_core.dart';
import 'package:test/test.dart';

bool _within(int v, int lo, int hi) => v >= lo && v <= hi;

void main() {
  group('config integrity', () {
    test('there are six MVP documents with unique ids', () {
      expect(mvpDocuments.length, 6);
      expect(mvpDocuments.map((d) => d.id).toSet().length, 6);
    });

    test('every document forbids alteration and cites a source + date', () {
      for (final d in mvpDocuments) {
        expect(d.alterationAllowed, isFalse, reason: d.id);
        expect(d.sourceUrl, isNotEmpty, reason: d.id);
        expect(d.lastVerifiedDate, isNotEmpty, reason: d.id);
      }
    });

    test('lookup by id works and is null for unknown', () {
      expect(documentById('us_passport'), same(usPassport));
      expect(documentById('nope'), isNull);
    });
  });

  group('the India trio are distinct (top rejection cause)', () {
    test('India passport is 35x45 and WHITE', () {
      expect(indiaPassport.outputSizeMm.width, 35);
      expect(indiaPassport.outputSizeMm.height, 45);
      expect(indiaPassport.backgroundRule, BackgroundRule.whiteRequired);
    });
    test('India OCI is 51x51 and LIGHT (not white)', () {
      expect(indiaOci.outputSizeMm.width, 51);
      expect(indiaOci.outputSizeMm.height, 51);
      expect(indiaOci.backgroundRule, BackgroundRule.lightNotWhite);
    });
    test('OCI and passport never share size + background', () {
      final same = indiaOci.outputSizeMm.width == indiaPassport.outputSizeMm.width &&
          indiaOci.outputSizeMm.height == indiaPassport.outputSizeMm.height &&
          indiaOci.backgroundRule == indiaPassport.backgroundRule;
      expect(same, isFalse);
    });
  });

  group('white-required docs accept pure white; anti-white docs reject it', () {
    bool acceptsPureWhite(DocumentConfig d) =>
        _within(255, d.backgroundAcceptMin.r, d.backgroundAcceptMax.r) &&
        _within(255, d.backgroundAcceptMin.g, d.backgroundAcceptMax.g) &&
        _within(255, d.backgroundAcceptMin.b, d.backgroundAcceptMax.b);

    test('US passport/visa and India passport accept pure white', () {
      expect(acceptsPureWhite(usPassport), isTrue);
      expect(acceptsPureWhite(usVisaDs160), isTrue);
      expect(acceptsPureWhite(indiaPassport), isTrue);
    });

    test('UK, Schengen, and OCI reject pure white', () {
      expect(acceptsPureWhite(ukPassport), isFalse);
      expect(acceptsPureWhite(schengenVisa), isFalse);
      expect(acceptsPureWhite(indiaOci), isFalse);
    });

    test('every anti-white doc also rejects dark backgrounds', () {
      for (final d in [ukPassport, schengenVisa, indiaOci]) {
        expect(d.backgroundAcceptMin.r, greaterThan(150), reason: d.id);
      }
    });
  });

  group('glasses and expression rules match the data pack', () {
    test('US and UK ban glasses; OCI allows them', () {
      expect(usPassport.glassesRule, GlassesRule.banned);
      expect(ukPassport.glassesRule, GlassesRule.banned);
      expect(indiaOci.glassesRule, GlassesRule.allowedNoGlare);
    });
    test('UK and Schengen are strict-neutral; US and India allow closed smile', () {
      expect(ukPassport.expressionRule, ExpressionRule.neutralStrict);
      expect(schengenVisa.expressionRule, ExpressionRule.neutralStrict);
      expect(usPassport.expressionRule, ExpressionRule.neutralClosedMouthOk);
      expect(indiaPassport.expressionRule, ExpressionRule.neutralClosedMouthOk);
    });
  });
}
