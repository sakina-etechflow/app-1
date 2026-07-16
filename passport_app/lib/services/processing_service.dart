import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart' as cc;
import 'package:image/image.dart' as img;

import 'photo_normalizer.dart';
import 'signal_extractor.dart';

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
class ProcessingService {
  Future<PipelineResult> run({
    required String rawPhotoPath,
    required cc.DocumentConfig doc,
    required bool wearsGlasses,
  }) async {
    final np = await PhotoNormalizer.normalize(rawPhotoPath);

    final extractor = SignalExtractor();
    late final ({cc.FaceSignals signals, cc.ImageData image}) ex;
    try {
      ex = await extractor.extract(np.path, np.image);
    } finally {
      await extractor.dispose();
    }

    final report = cc.evaluate(
      ex.signals,
      ex.image,
      doc,
      wearsGlasses: wearsGlasses,
      aiOrEnhancementApplied: false, // hard-false: we never alter US docs
    );

    final formatted = _formatForDocument(np.image, doc, ex.signals.boundingBox);
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

  /// Aspect-correct crop centred on the face, resized to a spec-compliant
  /// output size. Purely geometric.
  img.Image _formatForDocument(
      img.Image src, cc.DocumentConfig doc, cc.BoundingBox? faceBox) {
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
