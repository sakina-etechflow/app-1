import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart';
import 'package:test/test.dart';

FaceSignals baseSignals({
  int faceCount = 1,
  int w = 1000,
  int h = 1000,
  BoundingBox? box,
  double eulerX = 0,
  double eulerY = 0,
  double eulerZ = 0,
}) =>
    FaceSignals(
      faceCount: faceCount,
      imageWidth: w,
      imageHeight: h,
      boundingBox: box ?? const BoundingBox(x: 300, y: 250, width: 400, height: 500),
      eulerX: eulerX,
      eulerY: eulerY,
      eulerZ: eulerZ,
    );

/// Mask whose topmost person pixel is at [topY], for the head-height check.
PersonMask maskTop(int topY, {int w = 100, int h = 100}) {
  final buf = Uint8List(w * h);
  for (var y = topY; y < h; y++) {
    for (var x = w ~/ 4; x < 3 * w ~/ 4; x++) {
      buf[y * w + x] = 255;
    }
  }
  return PersonMask(width: w, height: h, confidence: buf);
}

void main() {
  group('C1 single face', () {
    test('exactly one passes', () {
      expect(checkSingleFace(baseSignals(faceCount: 1)).pass, isTrue);
    });
    test('zero faces fails', () {
      expect(checkSingleFace(baseSignals(faceCount: 0)).pass, isFalse);
    });
    test('two faces fails', () {
      expect(checkSingleFace(baseSignals(faceCount: 2)).pass, isFalse);
    });
  });

  group('C2 head orientation', () {
    test('level head passes', () {
      expect(checkHeadOrientation(baseSignals(), Thresholds.defaults).pass,
          isTrue);
    });
    test('yaw beyond tolerance fails with a "face the camera" message', () {
      final r = checkHeadOrientation(
          baseSignals(eulerY: 12), Thresholds.defaults);
      expect(r.pass, isFalse);
      expect(r.message, contains('directly'));
    });
    test('roll beyond tolerance fails', () {
      expect(
          checkHeadOrientation(baseSignals(eulerZ: 9), Thresholds.defaults)
              .pass,
          isFalse);
    });
  });

  group('C3 head height', () {
    FaceSignals headSignals(int topY, int chinY) => FaceSignals(
          faceCount: 1,
          imageWidth: 100,
          imageHeight: 100,
          boundingBox: BoundingBox(
              x: 25, y: topY.toDouble(), width: 50, height: (chinY - topY).toDouble()),
          faceContour: [FacePoint(50, chinY.toDouble())],
          personMask: maskTop(topY),
        );

    test('mid-band head passes for US', () {
      // crown 20, chin 80 -> 60% of 100, within US 50-69.
      final r = checkHeadHeight(
          headSignals(20, 80), usPassport, Thresholds.defaults);
      expect(r.pass, isTrue);
    });
    test('too-small head fails with "move closer"', () {
      // crown 55, chin 85 -> 30%.
      final r = checkHeadHeight(
          headSignals(55, 85), usPassport, Thresholds.defaults);
      expect(r.pass, isFalse);
      expect(r.message, contains('closer'));
    });
    test('missing mask fails safe', () {
      final r = checkHeadHeight(
          baseSignals(), usPassport, Thresholds.defaults);
      expect(r.pass, isFalse);
    });
  });

  group('C4 eye line', () {
    test('US band enforced', () {
      final good = FaceSignals(
        faceCount: 1,
        imageWidth: 1000,
        imageHeight: 1000,
        landmarks: {
          FaceLandmarkType.leftEye: const FacePoint(460, 380),
          FaceLandmarkType.rightEye: const FacePoint(540, 380),
        },
      ); // 62% from bottom
      expect(checkEyeLine(good, usPassport).pass, isTrue);

      final tooHigh = FaceSignals(
        faceCount: 1,
        imageWidth: 1000,
        imageHeight: 1000,
        landmarks: {
          FaceLandmarkType.leftEye: const FacePoint(460, 100),
          FaceLandmarkType.rightEye: const FacePoint(540, 100),
        },
      ); // 90% from bottom
      expect(checkEyeLine(tooHigh, usPassport).pass, isFalse);
    });
    test('UK has no band -> passes as skip', () {
      expect(checkEyeLine(baseSignals(), ukPassport).pass, isTrue);
    });
  });

  group('C5 centering', () {
    test('centered passes', () {
      final s = baseSignals(
          box: const BoundingBox(x: 300, y: 200, width: 400, height: 500));
      expect(checkCentering(s, Thresholds.defaults).pass, isTrue);
    });
    test('off-center fails', () {
      final s = baseSignals(
          box: const BoundingBox(x: 600, y: 200, width: 400, height: 500));
      expect(checkCentering(s, Thresholds.defaults).pass, isFalse);
    });
  });

  group('C6 eyes open', () {
    FaceSignals eyes(double? l, double? r) => FaceSignals(
          faceCount: 1,
          imageWidth: 1000,
          imageHeight: 1000,
          leftEyeOpen: l,
          rightEyeOpen: r,
        );
    test('both open passes', () {
      expect(checkEyesOpen(eyes(0.95, 0.92), Thresholds.defaults).pass, isTrue);
    });
    test('one closed fails', () {
      expect(checkEyesOpen(eyes(0.95, 0.2), Thresholds.defaults).pass, isFalse);
    });
    test('missing probabilities do not block', () {
      expect(checkEyesOpen(eyes(null, null), Thresholds.defaults).pass, isTrue);
    });
  });

  group('C7 expression', () {
    FaceSignals expr({required double smiling, required double mouthGap}) =>
        FaceSignals(
          faceCount: 1,
          imageWidth: 1000,
          imageHeight: 1000,
          boundingBox: const BoundingBox(x: 300, y: 200, width: 400, height: 500),
          smiling: smiling,
          landmarks: {
            FaceLandmarkType.mouthLeft: const FacePoint(460, 600),
            FaceLandmarkType.mouthRight: const FacePoint(540, 600),
            FaceLandmarkType.mouthBottom: FacePoint(500, 600 + mouthGap),
          },
        );
    test('US allows closed-mouth smile (warning severity)', () {
      final r = checkExpression(
          expr(smiling: 0.8, mouthGap: 5), usPassport, Thresholds.defaults);
      expect(r.pass, isTrue);
      expect(r.severity, Severity.warning);
    });
    test('US open mouth fails', () {
      final r = checkExpression(
          expr(smiling: 0.1, mouthGap: 120), usPassport, Thresholds.defaults);
      expect(r.pass, isFalse);
    });
    test('UK strict rejects a smile (error severity)', () {
      final r = checkExpression(
          expr(smiling: 0.8, mouthGap: 5), ukPassport, Thresholds.defaults);
      expect(r.pass, isFalse);
      expect(r.severity, Severity.error);
      expect(r.message, contains('smiling'));
    });
  });

  group('C8 glasses', () {
    test('US banned + wearing -> error fail', () {
      final r = checkGlasses(baseSignals(), usPassport, wearsGlasses: true);
      expect(r.pass, isFalse);
      expect(r.severity, Severity.error);
    });
    test('US banned + not wearing -> pass', () {
      expect(checkGlasses(baseSignals(), usPassport, wearsGlasses: false).pass,
          isTrue);
    });
    test('OCI allows glasses -> pass (warning)', () {
      final r = checkGlasses(baseSignals(), indiaOci, wearsGlasses: true);
      expect(r.pass, isTrue);
      expect(r.severity, Severity.warning);
    });
    test('Schengen discouraged + wearing -> warning fail', () {
      final r = checkGlasses(baseSignals(), schengenVisa, wearsGlasses: true);
      expect(r.pass, isFalse);
      expect(r.severity, Severity.warning);
    });
  });

  group('C9 head covering', () {
    test('always passes as a warning (never hard-block)', () {
      final r = checkHeadCovering();
      expect(r.pass, isTrue);
      expect(r.severity, Severity.warning);
    });
  });

  group('C15 no alteration', () {
    test('US + altered -> error fail', () {
      final r = checkNoAlteration(usPassport, aiOrEnhancementApplied: true);
      expect(r.pass, isFalse);
      expect(r.severity, Severity.error);
    });
    test('US + unaltered -> pass', () {
      expect(checkNoAlteration(usPassport).pass, isTrue);
    });
  });
}
