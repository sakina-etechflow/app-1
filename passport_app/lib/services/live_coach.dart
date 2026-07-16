import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// One frame's worth of live guidance for the capture screen.
class CoachStatus {
  const CoachStatus(this.message, {this.ready = false, this.faceSeen = false});

  /// Plain-language instruction shown over the preview.
  final String message;

  /// True when every live check passes and auto-capture may fire.
  final bool ready;

  /// True when at least one face is currently detected.
  final bool faceSeen;

  static const searching =
      CoachStatus('Line up your head in the oval', faceSeen: false);
}

/// Throttled per-frame face coaching. Runs a FAST-mode ML Kit detector on the
/// camera stream (never the accurate one — that stays in [SignalExtractor] for
/// capture-time checks) and turns the result into a single actionable hint.
///
/// The full pixel checks (background, lighting, sharpness) are deliberately
/// not run live, per the build brief: heavy work happens at capture time.
class LiveCoach {
  LiveCoach();

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // eyes-open + smiling probabilities
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);

  /// Minimum interval between processed frames (throttle).
  static const _interval = Duration(milliseconds: 250);

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  Future<void> dispose() => _detector.close();

  /// Analyse [frame]; returns null when the frame is skipped (throttled, busy,
  /// or unsupported format).
  Future<CoachStatus?> analyse(
    CameraImage frame,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) async {
    final now = DateTime.now();
    if (_busy || now.difference(_lastRun) < _interval) return null;
    _busy = true;
    _lastRun = now;
    try {
      final input = _toInputImage(frame, camera, deviceOrientation);
      if (input == null) return null;
      final faces = await _detector.processImage(input);

      // Upright frame dimensions (ML Kit coordinates are in the rotated frame).
      final rot = input.metadata!.rotation;
      final swap = rot == InputImageRotation.rotation90deg ||
          rot == InputImageRotation.rotation270deg;
      final w = swap ? frame.height.toDouble() : frame.width.toDouble();
      final h = swap ? frame.width.toDouble() : frame.height.toDouble();
      return _judge(faces, w, h);
    } catch (_) {
      return null; // Live coaching is best-effort; never crash the preview.
    } finally {
      _busy = false;
    }
  }

  CoachStatus _judge(List<Face> faces, double w, double h) {
    if (faces.isEmpty) return CoachStatus.searching;
    if (faces.length > 1) {
      return const CoachStatus('Only one person in the frame',
          faceSeen: true);
    }
    final f = faces.first;
    final box = f.boundingBox;

    // Distance: the ML Kit face box spans roughly eyebrow-to-chin, so the
    // full head is bigger. These bounds leave the auto-crop room to work.
    final headRatio = box.height / h;
    if (headRatio < 0.22) {
      return const CoachStatus('Move closer', faceSeen: true);
    }
    if (headRatio > 0.55) {
      return const CoachStatus('Move back a little', faceSeen: true);
    }

    // Centering: oval centre sits at (0.5 w, 0.44 h) — keep in sync with
    // OvalOverlay.
    final dx = (box.center.dx / w - 0.5).abs();
    final dy = (box.center.dy / h - 0.44).abs();
    if (dx > 0.12 || dy > 0.14) {
      return const CoachStatus('Center your head in the oval', faceSeen: true);
    }

    // Pose.
    final rollZ = f.headEulerAngleZ ?? 0;
    final yawY = f.headEulerAngleY ?? 0;
    final pitchX = f.headEulerAngleX ?? 0;
    if (rollZ.abs() > 8) {
      return const CoachStatus('Keep your head level', faceSeen: true);
    }
    if (yawY.abs() > 10) {
      return const CoachStatus('Look straight at the camera', faceSeen: true);
    }
    if (pitchX.abs() > 10) {
      return const CoachStatus('Keep your chin level', faceSeen: true);
    }

    // Expression.
    final le = f.leftEyeOpenProbability;
    final re = f.rightEyeOpenProbability;
    if ((le != null && le < 0.5) || (re != null && re < 0.5)) {
      return const CoachStatus('Open your eyes', faceSeen: true);
    }
    final smile = f.smilingProbability;
    if (smile != null && smile > 0.5) {
      return const CoachStatus('Neutral expression, mouth closed',
          faceSeen: true);
    }

    return const CoachStatus('Perfect — hold still…',
        ready: true, faceSeen: true);
  }

  /// Convert a camera stream frame into an ML Kit [InputImage] (NV21 on
  /// Android, BGRA8888 on iOS), following the ML Kit camera-stream recipe.
  InputImage? _toInputImage(
    CameraImage frame,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    // Rotation.
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else {
      var comp = _orientations[deviceOrientation];
      if (comp == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        comp = (sensorOrientation + comp) % 360;
      } else {
        comp = (sensorOrientation - comp + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(comp);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(frame.format.raw);
    // Only the formats we request in the controller are supported.
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (frame.planes.length != 1) return null;
    final plane = frame.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
