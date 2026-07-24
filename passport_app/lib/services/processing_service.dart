import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
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
/// Kit call or a worker isolate, but it checks this between stages and bails
/// out cleanly.
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

/// Everything the pixel stage needs, in a form that can be copied to a worker
/// isolate: plain data only, no closures, no plugin handles.
class PixelStageInput {
  const PixelStageInput({
    required this.normalizedPath,
    required this.signals,
    required this.doc,
    required this.wearsGlasses,
  });

  final String normalizedPath;
  final cc.FaceSignals signals;
  final cc.DocumentConfig doc;
  final bool wearsGlasses;
}

/// On-device only. No network, no upload. For `alterationAllowed == false`
/// documents (all MVP docs, every US flow) the ONLY transforms applied are
/// geometric: crop, resize. No beautify, no generative fill — enforced by
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
    final cc.FaceSignals signals;
    try {
      signals = await extractor.extract(
        np.path,
        width: np.width,
        height: np.height,
      );
    } finally {
      await extractor.dispose();
    }
    checkCancel();

    // No face -> fail fast into the S4 no-face state rather than producing a
    // meaningless centre-crop candidate.
    if (signals.faceCount == 0 || signals.boundingBox == null) {
      throw const NoFaceDetected();
    }

    onStage?.call(ProcessingStage.formatting);
    final input = PixelStageInput(
      normalizedPath: np.path,
      signals: signals,
      doc: doc,
      wearsGlasses: wearsGlasses,
    );

    // The pixel stage decodes the full normalised image and walks every pixel
    // several times (background stats, shadow, sharpness), then crops, resizes
    // and encodes twice. On 3GB-class hardware that is seconds of work; on the
    // UI isolate it blocks the frame pump long enough to be killed as
    // unresponsive (A1-12). Run it on a worker whenever we can.
    //
    // A [SubjectEnhancer] is a closure and therefore not sendable, so that path
    // — test-only, and structurally unavailable for every MVP document — stays
    // inline. Both branches call the SAME function, so the AlterationPolicy
    // gate and the C15 wiring cannot diverge between them.
    final result = enhancer == null
        ? await Isolate.run(() => runPixelStage(input))
        : runPixelStage(input, enhancer: enhancer);
    checkCancel();
    onStage?.call(ProcessingStage.encoding);

    return result;
  }
}

/// The pure-Dart pixel stage: decode, evaluate, format, watermark, encode.
///
/// Top-level and free of plugins/closures (unless [enhancer] is passed) so it
/// can run unchanged either inside [Isolate.run] or directly under test.
PipelineResult runPixelStage(
  PixelStageInput input, {
  SubjectEnhancer? enhancer,
}) {
  final decoded = decodeOrThrow(
    File(input.normalizedPath).readAsBytesSync(),
    'Could not decode the normalised photo.',
  );

  // The single gate every pixel transform is admitted through. For a
  // forbidding document the enhancement branch below cannot run at all.
  final policy = cc.AlterationPolicy(input.doc);
  var formatted = _formatForDocument(
    decoded,
    input.doc,
    input.signals,
    policy,
  );
  formatted = _maybeEnhance(formatted, policy, enhancer);

  // C15 reads the policy's record of what actually touched the subject — not a
  // literal — so "unaltered" cannot drift out of sync with the pipeline.
  final report = cc.evaluate(
    input.signals,
    cc.ImageData.fromImage(decoded),
    input.doc,
    wearsGlasses: input.wearsGlasses,
    aiOrEnhancementApplied: policy.enhancementApplied,
  );

  final cleanJpg = Uint8List.fromList(img.encodeJpg(formatted, quality: 95));
  final previewJpg = Uint8List.fromList(
      img.encodeJpg(_watermark(img.Image.from(formatted)), quality: 92));

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

/// Aspect-correct crop that sizes the head to the document's head-height spec,
/// resized to a spec-compliant output size. Purely geometric — admitted through
/// [policy] to document and enforce that the formatting step never alters the
/// subject.
///
/// The crop height is chosen so the subject's head (crown→chin) fills the middle
/// of the document's head-height band, so the EXPORTED photo — not merely the
/// uncropped capture the verdict was measured on — meets the spec. Without this
/// the auto-crop center-cropped to aspect and the output head size was
/// unconstrained (QA week-3 correctness fix).
///
/// Every dimension is clamped into range before it is used as a bound. Document
/// specs are remotely updatable, so a bad config value must degrade to a sane
/// crop rather than throw an ArgumentError out of `clamp` or run `copyCrop`
/// past the edge of the source.
img.Image _formatForDocument(
  img.Image src,
  cc.DocumentConfig doc,
  cc.FaceSignals signals,
  cc.AlterationPolicy policy,
) {
  policy.admit(cc.TransformKind.geometric, label: 'crop+resize');

  final srcW = src.width;
  final srcH = src.height;
  final aspect = _safeAspect(doc); // w/h
  final faceBox = signals.boundingBox;

  // Crown = topmost person pixel (hair included) from the mask; chin = lowest
  // contour point; both fall back to the face box when unavailable.
  final crownY =
      signals.personMask?.topmostPersonY()?.toDouble() ?? faceBox?.y ?? 0.0;
  final chinY = signals.chinY ??
      (faceBox == null ? srcH.toDouble() : faceBox.y + faceBox.height);
  final targetFrac =
      (doc.headHeightMinPct + doc.headHeightMaxPct) / 2 / 100;

  final crop = computeSpecCrop(
    srcW: srcW,
    srcH: srcH,
    aspect: aspect,
    crownY: crownY,
    chinY: chinY,
    faceCenterX: faceBox?.centerX ?? srcW / 2,
    targetFrac: targetFrac,
  );

  final cropped = img.copyCrop(src,
      x: crop.left, y: crop.top, width: crop.width, height: crop.height);

  // Target size: 900px on the height edge, clamped to the doc's stated range.
  final targetH = _clampToRange(
      900, doc.minResolutionPx.height, doc.maxResolutionPx.height);
  final targetW = _clampToRange((targetH * aspect).round(),
      doc.minResolutionPx.width, doc.maxResolutionPx.width);

  return img.copyResize(cropped,
      width: targetW, height: targetH, interpolation: img.Interpolation.cubic);
}

/// The crop rectangle (in source pixels) that places the head (crown→chin,
/// [chinY] − [crownY] tall) at the middle of the document's head-height band,
/// centred horizontally on [faceCenterX]. Because the later resize scales
/// uniformly, the head keeps the same fraction of the OUTPUT height — so the
/// exported photo lands in the document's head-height spec.
///
/// Pure and deterministic (no pixels), so the geometry is unit-tested directly.
/// Degenerate inputs (non-positive head or fraction) fall back to a full-height
/// crop, and every returned bound is clamped inside the source so `copyCrop`
/// can never run past the edge.
({int left, int top, int width, int height}) computeSpecCrop({
  required int srcW,
  required int srcH,
  required double aspect,
  required double crownY,
  required double chinY,
  required double faceCenterX,
  required double targetFrac,
}) {
  final headPx = chinY - crownY;
  double cropH;
  double cropTop;
  if (headPx.isFinite && headPx > 0 && targetFrac > 0) {
    cropH = headPx / targetFrac;
    // Centre the head block vertically within the crop.
    cropTop = crownY - (cropH - headPx) / 2;
  } else {
    // Degenerate signals: fall back to the previous full-height crop.
    cropH = srcH.toDouble();
    cropTop = 0;
  }

  var cropW = cropH * aspect;
  // If the width does not fit, constrain by width and keep the aspect (the head
  // ends up slightly larger than target rather than the image distorting).
  if (cropW > srcW) {
    cropW = srcW.toDouble();
    cropH = cropW / aspect;
    cropTop = crownY - (cropH - headPx) / 2;
  }

  final cw = cropW.round().clamp(1, srcW);
  final ch = cropH.round().clamp(1, srcH);
  final left = (faceCenterX - cw / 2).round().clamp(0, srcW - cw);
  final top = cropTop.round().clamp(0, srcH - ch);
  return (left: left, top: top, width: cw, height: ch);
}

/// Output aspect ratio (w/h), falling back to square if a config carries a zero
/// or non-finite size rather than producing an infinite crop dimension.
double _safeAspect(cc.DocumentConfig doc) {
  final w = doc.outputSizeMm.width;
  final h = doc.outputSizeMm.height;
  final aspect = w / h;
  if (!aspect.isFinite || aspect <= 0) return 1.0;
  return aspect;
}

/// Clamp [value] into [lo]..[hi], tolerating a config where the two are
/// inverted or non-positive.
int _clampToRange(int value, int lo, int hi) {
  final low = math.max(1, math.min(lo, hi));
  final high = math.max(low, math.max(lo, hi));
  return value.clamp(low, high);
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
