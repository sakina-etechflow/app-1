import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart' as cc;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as mlf;
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart'
    as mls;
import 'package:image/image.dart' as img;

/// Bridges ML Kit (face detection + selfie segmentation) into the pure-Dart
/// `compliance_core.FaceSignals`. The engine never sees ML Kit; it only sees
/// this output, which keeps the rule logic testable off-device.
class SignalExtractor {
  final mlf.FaceDetector _detector = mlf.FaceDetector(
    options: mlf.FaceDetectorOptions(
      enableClassification: true, // eyes-open + smiling probabilities
      enableLandmarks: true,
      enableContours: true, // face contour -> chin (crown comes from the mask)
      performanceMode: mlf.FaceDetectorMode.accurate,
    ),
  );
  final mls.SelfieSegmenter _segmenter = mls.SelfieSegmenter(
    mode: mls.SegmenterMode.single,
    enableRawSizeMask: true, // mask dims == input image dims
  );

  Future<void> dispose() async {
    await _detector.close();
    await _segmenter.close();
  }

  /// Run both models on [normalizedPath] and assemble [cc.FaceSignals] plus the
  /// decoded [cc.ImageData], sharing [uprightImage] so pixel + mask coordinates
  /// line up.
  Future<({cc.FaceSignals signals, cc.ImageData image})> extract(
    String normalizedPath,
    img.Image uprightImage,
  ) async {
    final input = mlf.InputImage.fromFilePath(normalizedPath);
    final faces = await _detector.processImage(input);
    final segInput = mls.InputImage.fromFilePath(normalizedPath);
    final mask = await _segmenter.processImage(segInput);

    final personMask = _toPersonMask(mask, uprightImage.width, uprightImage.height);

    if (faces.isEmpty) {
      return (
        signals: cc.FaceSignals(
          faceCount: 0,
          imageWidth: uprightImage.width,
          imageHeight: uprightImage.height,
          personMask: personMask,
        ),
        image: cc.ImageData.fromImage(uprightImage),
      );
    }

    // Primary face = the largest by area.
    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
        .compareTo(a.boundingBox.width * a.boundingBox.height));
    final f = faces.first;

    final signals = cc.FaceSignals(
      faceCount: faces.length,
      imageWidth: uprightImage.width,
      imageHeight: uprightImage.height,
      boundingBox: cc.BoundingBox(
        x: f.boundingBox.left,
        y: f.boundingBox.top,
        width: f.boundingBox.width,
        height: f.boundingBox.height,
      ),
      landmarks: _landmarks(f),
      faceContour: _contour(f),
      eulerX: f.headEulerAngleX ?? 0,
      eulerY: f.headEulerAngleY ?? 0,
      eulerZ: f.headEulerAngleZ ?? 0,
      leftEyeOpen: f.leftEyeOpenProbability,
      rightEyeOpen: f.rightEyeOpenProbability,
      smiling: f.smilingProbability,
      personMask: personMask,
    );
    return (signals: signals, image: cc.ImageData.fromImage(uprightImage));
  }

  cc.PersonMask? _toPersonMask(mls.SegmentationMask? mask, int w, int h) {
    if (mask == null) return null;
    final conf = mask.confidences; // foreground (person) probability 0..1
    if (mask.width != w || mask.height != h) {
      // Raw-size mask should match; if not, skip rather than misalign.
      return null;
    }
    final buf = Uint8List(w * h);
    for (var i = 0; i < buf.length && i < conf.length; i++) {
      buf[i] = (conf[i] * 255).round().clamp(0, 255);
    }
    return cc.PersonMask(width: w, height: h, confidence: buf);
  }

  Map<cc.FaceLandmarkType, cc.FacePoint> _landmarks(mlf.Face f) {
    const map = {
      mlf.FaceLandmarkType.leftEye: cc.FaceLandmarkType.leftEye,
      mlf.FaceLandmarkType.rightEye: cc.FaceLandmarkType.rightEye,
      mlf.FaceLandmarkType.noseBase: cc.FaceLandmarkType.noseBase,
      mlf.FaceLandmarkType.leftMouth: cc.FaceLandmarkType.mouthLeft,
      mlf.FaceLandmarkType.rightMouth: cc.FaceLandmarkType.mouthRight,
      mlf.FaceLandmarkType.bottomMouth: cc.FaceLandmarkType.mouthBottom,
      mlf.FaceLandmarkType.leftCheek: cc.FaceLandmarkType.leftCheek,
      mlf.FaceLandmarkType.rightCheek: cc.FaceLandmarkType.rightCheek,
      mlf.FaceLandmarkType.leftEar: cc.FaceLandmarkType.leftEar,
      mlf.FaceLandmarkType.rightEar: cc.FaceLandmarkType.rightEar,
    };
    final out = <cc.FaceLandmarkType, cc.FacePoint>{};
    map.forEach((mlType, ccType) {
      final lm = f.landmarks[mlType];
      if (lm != null) {
        out[ccType] = cc.FacePoint(
            lm.position.x.toDouble(), lm.position.y.toDouble());
      }
    });
    return out;
  }

  List<cc.FacePoint> _contour(mlf.Face f) {
    final c = f.contours[mlf.FaceContourType.face];
    if (c == null) return const [];
    return c.points
        .map((p) => cc.FacePoint(p.x.toDouble(), p.y.toDouble()))
        .toList(growable: false);
  }
}
