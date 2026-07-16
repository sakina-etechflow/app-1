/// The ML Kit outputs the rule engine reads. This is the engine's only face
/// input: the engine never calls ML Kit directly, so it stays testable and
/// deterministic (calibration harness spec, "the core design decision").
///
/// On-device these come from `google_mlkit_face_detection` +
/// selfie segmentation; in the harness they come from the cached Stage-1 JSON.
library;

import 'geometry.dart';
import 'person_mask.dart';

/// Named face landmarks used by the checks. Values are ML Kit landmark
/// positions in image pixel space; any may be absent.
enum FaceLandmarkType {
  leftEye,
  rightEye,
  noseBase,
  mouthLeft,
  mouthRight,
  mouthBottom,
  leftCheek,
  rightCheek,
  leftEar,
  rightEar,
}

class FaceSignals {
  const FaceSignals({
    required this.faceCount,
    required this.imageWidth,
    required this.imageHeight,
    this.boundingBox,
    this.landmarks = const {},
    this.faceContour = const [],
    this.eulerX = 0,
    this.eulerY = 0,
    this.eulerZ = 0,
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.smiling,
    this.personMask,
  });

  /// Number of faces ML Kit detected (C1).
  final int faceCount;

  final int imageWidth;
  final int imageHeight;

  /// Bounding box of the primary face (null when [faceCount] == 0).
  final BoundingBox? boundingBox;

  final Map<FaceLandmarkType, FacePoint> landmarks;

  /// Optional face-contour points; the lowest one is the chin used by C3.
  final List<FacePoint> faceContour;

  /// Head Euler angles in degrees. X = pitch (up/down), Y = yaw (left/right),
  /// Z = roll (tilt). Matches ML Kit headEulerAngleX/Y/Z.
  final double eulerX;
  final double eulerY;
  final double eulerZ;

  final double? leftEyeOpen;
  final double? rightEyeOpen;
  final double? smiling;

  /// Person segmentation mask, if available. Required for C3 and C10-C12.
  final PersonMask? personMask;

  /// Mean eye y in pixels, or null if either eye landmark is missing.
  double? get eyeLineY {
    final l = landmarks[FaceLandmarkType.leftEye];
    final r = landmarks[FaceLandmarkType.rightEye];
    if (l == null || r == null) return null;
    return (l.y + r.y) / 2;
  }

  /// Lowest (largest y) contour point = chin. Falls back to the bottom of the
  /// bounding box when no contour is provided.
  double? get chinY {
    if (faceContour.isNotEmpty) {
      return faceContour.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    }
    final box = boundingBox;
    return box == null ? null : box.y + box.height;
  }
}
