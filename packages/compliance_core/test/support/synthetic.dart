/// Synthetic scene + signal builders for the compliance tests. Everything here
/// is deterministic (no randomness), so a passing scene stays passing.
library;

import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart';
import 'package:image/image.dart' as img;

/// A compliant synthetic scene for a document: uniform background of [bgColor],
/// a textured "person" silhouette (so the sharpness check has content), a
/// matching person mask, and landmarks/box placed inside the required bands.
class Scene {
  Scene(this.signals, this.image);
  final FaceSignals signals;
  final ImageData image;
}

Scene compliantScene(
  DocumentConfig doc, {
  int imageW = 1200,
  int imageH = 1200,
  Rgb? bgColor,
  int? crownY,
  int? chinY,
}) {
  final bg = bgColor ?? doc.backgroundTarget;

  // Head geometry: place crown/chin so head-height lands mid-band.
  final midPct = (doc.headHeightMinPct + doc.headHeightMaxPct) / 2;
  final headPx = (midPct / 100 * imageH).round();
  final chin = chinY ?? (imageH * 0.77).round();
  final crown = crownY ?? (chin - headPx);

  // Person silhouette: from crown down to the image bottom (shoulders),
  // centred horizontally, ~1/3 of the width.
  final personW = imageW ~/ 3;
  final personLeft = (imageW - personW) ~/ 2;
  final personRight = personLeft + personW;

  final image = img.Image(width: imageW, height: imageH);
  final mask = Uint8List(imageW * imageH);
  for (var y = 0; y < imageH; y++) {
    for (var x = 0; x < imageW; x++) {
      final inPerson = x >= personLeft && x < personRight && y >= crown;
      if (inPerson) {
        // Symmetric high-frequency texture: mean ~150, high Laplacian variance.
        final v = ((x + y) % 2 == 0) ? 120 : 180;
        image.setPixelRgb(x, y, v, v, v);
        mask[y * imageW + x] = 255;
      } else {
        image.setPixelRgb(x, y, bg.r, bg.g, bg.b);
        mask[y * imageW + x] = 0;
      }
    }
  }

  // Face bounding box (excludes hair): a bit below the crown, down to the chin.
  final boxTop = crown + (headPx * 0.15).round();
  final box = BoundingBox(
    x: personLeft.toDouble(),
    y: boxTop.toDouble(),
    width: personW.toDouble(),
    height: (chin - boxTop).toDouble(),
  );

  // Eye line: mid of the document band (or 62% from bottom when unspecified).
  final eyeMin = doc.eyeLineMinPctFromBottom ?? 56;
  final eyeMax = doc.eyeLineMaxPctFromBottom ?? 69;
  final eyePctFromBottom = (eyeMin + eyeMax) / 2;
  final eyeY = imageH - eyePctFromBottom / 100 * imageH;
  final cx = imageW / 2;

  final mouthY = chin - (chin - boxTop) * 0.18;
  final signals = FaceSignals(
    faceCount: 1,
    imageWidth: imageW,
    imageHeight: imageH,
    boundingBox: box,
    faceContour: [FacePoint(cx, chin.toDouble())],
    landmarks: {
      FaceLandmarkType.leftEye: FacePoint(cx - 60, eyeY),
      FaceLandmarkType.rightEye: FacePoint(cx + 60, eyeY),
      FaceLandmarkType.mouthLeft: FacePoint(cx - 40, mouthY),
      FaceLandmarkType.mouthRight: FacePoint(cx + 40, mouthY),
      FaceLandmarkType.mouthBottom: FacePoint(cx, mouthY + 6),
    },
    eulerX: 0,
    eulerY: 0,
    eulerZ: 0,
    leftEyeOpen: 0.95,
    rightEyeOpen: 0.95,
    smiling: 0.05,
    personMask:
        PersonMask(width: imageW, height: imageH, confidence: mask),
  );

  return Scene(signals, ImageData.fromImage(image));
}
