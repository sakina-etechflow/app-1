/// Engineered default thresholds for the compliance checks.
///
/// These are STARTING VALUES (spec-and-compliance data pack, Part B): they must
/// be calibrated against a labelled photo set before launch. They live here,
/// centralised and separate from check logic, so the calibration loop tunes a
/// number without touching a check. Pass a tuned [Thresholds] into `evaluate`.
library;

class Thresholds {
  const Thresholds({
    this.maxHeadAngleDeg = 5.0,
    this.eyeOpenMin = 0.7,
    this.smilingMaxStrict = 0.3,
    this.mouthOpenRatioMax = 0.18,
    this.centeringMaxOffsetPct = 5.0,
    this.bgUniformityMaxStdDev = 12.0,
    this.shadowBgGradientMax = 18.0,
    this.shadowFaceAsymmetryMaxPct = 15.0,
    this.exposureFaceMeanMin = 90.0,
    this.exposureFaceMeanMax = 210.0,
    this.exposureClippedMaxPct = 5.0,
    this.sharpnessLaplacianMin = 100.0,
    this.maskThreshold = 0.5,
  });

  /// C2: |yaw|, |pitch|, |roll| must be within this many degrees.
  final double maxHeadAngleDeg;

  /// C6: both per-eye open probabilities must exceed this.
  final double eyeOpenMin;

  /// C7 (strict docs): smiling probability must be below this.
  final double smilingMaxStrict;

  /// C7: mouth-open ratio (lip gap / face height) must be below this to count
  /// as mouth-closed.
  final double mouthOpenRatioMax;

  /// C5: face-centre horizontal offset must be within this % of image width.
  final double centeringMaxOffsetPct;

  /// C10: per-channel std dev over the background band must be at or below this.
  final double bgUniformityMaxStdDev;

  /// C12: background luminance gradient across the region must be below this.
  final double shadowBgGradientMax;

  /// C12: left-vs-right face luminance difference must be below this %.
  final double shadowFaceAsymmetryMaxPct;

  /// C13: face-region mean luminance must sit within this band.
  final double exposureFaceMeanMin;
  final double exposureFaceMeanMax;

  /// C13: % of clipped (blown) highlight pixels on the face must be below this.
  final double exposureClippedMaxPct;

  /// C14: Laplacian variance over the face region must exceed this.
  final double sharpnessLaplacianMin;

  /// Person-probability threshold applied to the segmentation mask.
  final double maskThreshold;

  static const Thresholds defaults = Thresholds();
}
