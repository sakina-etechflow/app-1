import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart' as cc;
import 'package:image/image.dart' as img;

import 'photo_normalizer.dart';
import 'signal_extractor.dart';

/// Stages the on-device pipeline moves through, surfaced to S4 for progress.
enum ProcessingStage {
  normalizing,
  detecting,
  formatting,
  encoding,
}

extension ProcessingStageInfo on ProcessingStage {
  /// User-facing label shown on the processing screen.
  String get label {
    switch (this) {
      case ProcessingStage.normalizing:
        return 'Preparing photo…';
      case ProcessingStage.detecting:
        return 'Detecting face…';
      case ProcessingStage.formatting:
        return 'Cropping and sizing…';
      case ProcessingStage.encoding:
        return 'Finishing…';
    }
  }

  /// Rough completion fraction for a determinate progress bar.
  double get fraction {
    switch (this) {
      case ProcessingStage.normalizing:
        return 0.15;
      case ProcessingStage.detecting:
        return 0.5;
      case ProcessingStage.formatting:
        return 0.8;
      case ProcessingStage.encoding:
        return 0.95;
    }
  }
}

/// Cooperative cancellation token. The pipeline can't interrupt a running ML
/// Kit call, but it checks this between stages and bails out cleanly.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Thrown when processing is cancelled by the user via [CancelToken].
class ProcessingCancelled implements Exception {
  const ProcessingCancelled();
  @override
  String toString() => 'ProcessingCancelled';
}

/// Thrown when no face is found in the photo — drives the S4 no-face state.
class NoFaceDetected implements Exception {
  const NoFaceDetected();
  @override
  String toString() => 'NoFaceDetected';
}

/// An optional subject-enhancement step (e.g. skin smoothing). The pipeline
/// treats ANY enhancer as a subject-altering transform: it is gated by document
/// type through [cc.AlterationPolicy] and is never run for an
/// `alterationAllowed == false` document (all US flows, all MVP docs).
typedef SubjectEnhancer = img.Image Function(img.Image src);

/// The full output of running one photo through the on-device pipeline.
class PipelineResult {
  PipelineResult({
    required this.report,
    required this.cleanJpg,
    required this.previewJpg,
    required this.outputWidth,
    required this.outputHeight,
  });

  final cc.ComplianceReport report;
  final Uint8List cleanJpg; // formatted to spec, no watermark (unlock to export)
  final Uint8List previewJpg; // same, watermarked for the free tier
  final int outputWidth;
  final int outputHeight;
}

/// On-device only. No network, no upload. For `alterationAllowed == false`
/// documents (all MVP docs, every US flow) the ONLY transforms applied are
/// geometric: crop, resize. No beautify, no generative fill — enforced here by
/// document type, not just UI copy (store compliance spec item 4).
///
/// The enforcement is structural: every pixel transform is admitted through a
/// [cc.AlterationPolicy] keyed on [cc.DocumentConfig.alterationAllowed], and the
/// value reported to C15 is the policy's own record of what actually ran, never
/// a hard-coded literal. An [enhancer] is off by default and, when supplied,
/// throws [cc.AlterationNotPermitted] for a forbidding document before it runs.
class ProcessingService {
  Future<PipelineResult> run({
    required String rawPhotoPath,
    required cc.DocumentConfig doc,
    required bool wearsGlasses,
    void Function(ProcessingStage stage)? onStage,
    CancelToken? cancelToken,
    SubjectEnhancer? enhancer,
  }) async {
    void checkCancel() {
      if (cancelToken?.isCancelled ?? false) throw const ProcessingCancelled();
    }

    onStage?.call(ProcessingStage.normalizing);
    final np = await PhotoNormalizer.normalize(rawPhotoPath);
    checkCancel();

    onStage?.call(ProcessingStage.detecting);
    final extractor = SignalExtractor();
    late final ({cc.FaceSignals signals, cc.ImageData image}) ex;
    try {
      ex = await extractor.extract(np.path, np.image);
    } finally {
      await extractor.dispose();
    }
    checkCancel();

    // No face -> fail fast into the S4 no-face state rather than producing a
    // meaningless centre-crop candidate.
    if (ex.signals.faceCount == 0 || ex.signals.boundingBox == null) {
      throw const NoFaceDetected();
    }

    onStage?.call(ProcessingStage.formatting);

    // The single gate every pixel transform is admitted through. For a
    // forbidding document the enhancement branch below cannot run at all.
    final policy = cc.AlterationPolicy(doc);
    var formatted = _formatForDocument(np.image, doc, ex.signals.boundingBox,
        policy);
    formatted = _maybeEnhance(formatted, policy, enhancer);
    checkCancel();

    // C15 reads the policy's record of what actually touched the subject — not
    // a literal — so "unaltered" cannot drift out of sync with the pipeline.
    final report = cc.evaluate(
      ex.signals,
      ex.image,
      doc,
      wearsGlasses: wearsGlasses,
      aiOrEnhancementApplied: policy.enhancementApplied,
    );

    onStage?.call(ProcessingStage.encoding);
    final cleanJpg = Uint8List.fromList(img.encodeJpg(formatted, quality: 95));
    final previewJpg = Uint8List.fromList(
        img.encodeJpg(_watermark(img.Image.from(formatted)), quality: 92));
    checkCancel();

    return PipelineResult(
      report: report,
      cleanJpg: cleanJpg,
      previewJpg: previewJpg,
      outputWidth: formatted.width,
      outputHeight: formatted.height,
    );
  }

  /// Optional subject enhancement — the ONLY place the pipeline may alter the
  /// subject, and it is OFF unless the caller injects an [enhancer]. Gated by
  /// [cc.AlterationPolicy.admit]: for any `alterationAllowed == false` document
  /// (all US flows, all MVP docs) this throws [cc.AlterationNotPermitted] before
  /// the enhancer runs, so enhancement is structurally unavailable there
  /// (spec item 4), not merely hidden in the UI.
  img.Image _maybeEnhance(
    img.Image formatted,
    cc.AlterationPolicy policy,
    SubjectEnhancer? enhancer,
  ) {
    if (enhancer == null) return formatted; // off by default
    policy.admit(cc.TransformKind.enhancement, label: 'subject-enhancement');
    return enhancer(formatted);
  }

  /// Aspect-correct crop centred on the face, resized to a spec-compliant
  /// output size. Purely geometric — admitted through [policy] to document and
  /// enforce that the formatting step never alters the subject.
  img.Image _formatForDocument(img.Image src, cc.DocumentConfig doc,
      cc.BoundingBox? faceBox, cc.AlterationPolicy policy) {
    policy.admit(cc.TransformKind.geometric, label: 'crop+resize');
    final aspect = doc.outputSizeMm.width / doc.outputSizeMm.height; // w/h

    // Largest rect of the right aspect that fits, centred on the face.
    var cropH = src.height.toDouble();
    var cropW = cropH * aspect;
    if (cropW > src.width) {
      cropW = src.width.toDouble();
      cropH = cropW / aspect;
    }
    final cx = faceBox?.centerX ?? src.width / 2;
    // Bias the crop slightly above the face centre to leave headroom.
    final cy = (faceBox?.centerY ?? src.height / 2) - cropH * 0.05;
    var left = (cx - cropW / 2).round();
    var top = (cy - cropH / 2).round();
    left = left.clamp(0, src.width - cropW.round());
    top = top.clamp(0, src.height - cropH.round());

    final cropped = img.copyCrop(src,
        x: left, y: top, width: cropW.round(), height: cropH.round());

    // Target size: 900px on the short/height edge, clamped to the doc's max.
    var targetH = 900;
    var targetW = (targetH * aspect).round();
    targetW = targetW.clamp(doc.minResolutionPx.width, doc.maxResolutionPx.width);
    targetH =
        targetH.clamp(doc.minResolutionPx.height, doc.maxResolutionPx.height);

    return img.copyResize(cropped,
        width: targetW, height: targetH, interpolation: img.Interpolation.cubic);
  }

  /// Tiled translucent "PREVIEW" watermark for the free tier. Removed by the
  /// one-time unlock or a rewarded video.
  img.Image _watermark(img.Image image) {
    final color = img.ColorRgba8(255, 255, 255, 140);
    final shadow = img.ColorRgba8(0, 0, 0, 90);
    const step = 150;
    for (var y = 20; y < image.height; y += step) {
      for (var x = -40; x < image.width; x += 260) {
        img.drawString(image, 'PREVIEW',
            font: img.arial24, x: x + 1, y: y + 1, color: shadow);
        img.drawString(image, 'PREVIEW',
            font: img.arial24, x: x, y: y, color: color);
      }
    }
    return image;
  }
}
