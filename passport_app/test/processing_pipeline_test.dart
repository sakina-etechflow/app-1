// A1-12 — old-device hardening for the on-device pixel pipeline.
//
// These cover the pure, plugin-free halves of the pipeline: the synchronous
// core of PhotoNormalizer and the whole pixel stage (decode → evaluate →
// crop/resize → watermark → encode). The isolate wrappers and the ML Kit stage
// in between need a real device and are covered by the A1-12 device checklist.
//
// The crop cases exist because document specs are remotely updatable: a bad
// config or an unusual source aspect must degrade to a sane crop, never throw
// out of `clamp` or run `copyCrop` past the edge of the source.

import 'dart:io';
import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart' as cc;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:passport_app/services/photo_normalizer.dart';
import 'package:passport_app/services/processing_service.dart';

/// A plain light-grey scene with a darker oval where the face is, so the
/// background checks have something to sample and the crop has a subject.
img.Image _scene(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(248, 248, 248));
  img.fillCircle(
    image,
    x: width ~/ 2,
    y: height ~/ 3,
    radius: (width < height ? width : height) ~/ 6,
    color: img.ColorRgb8(150, 130, 120),
  );
  return image;
}

/// Face signals with the bounding box centred on the oval [_scene] draws.
cc.FaceSignals _signals(int width, int height) {
  final r = (width < height ? width : height) / 6;
  return cc.FaceSignals(
    faceCount: 1,
    imageWidth: width,
    imageHeight: height,
    boundingBox: cc.BoundingBox(
      x: width / 2 - r,
      y: height / 3 - r,
      width: r * 2,
      height: r * 2,
    ),
    personMask: cc.PersonMask(
      width: width,
      height: height,
      confidence: Uint8List(width * height), // all background
    ),
  );
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('a12_pipeline_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String writeScene(int width, int height, {String name = 'src.jpg'}) {
    final path = '${tmp.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(img.encodeJpg(_scene(width, height)));
    return path;
  }

  group('PhotoNormalizer.normalizeSync', () {
    test('downscales an oversized capture to the max edge, keeping aspect', () {
      final src = writeScene(3000, 2000);
      final out = '${tmp.path}${Platform.pathSeparator}out.jpg';

      final result = PhotoNormalizer.normalizeSync(src, out, 2000);

      expect(result.width, 2000);
      expect(result.height, closeTo(1333, 2)); // 3:2 preserved
      expect(result.path, out);
      expect(File(out).existsSync(), isTrue);
    });

    test('scales the long edge when the capture is portrait', () {
      final src = writeScene(1200, 2400);
      final out = '${tmp.path}${Platform.pathSeparator}out.jpg';

      final result = PhotoNormalizer.normalizeSync(src, out, 2000);

      expect(result.height, 2000);
      expect(result.width, closeTo(1000, 2));
    });

    test('leaves an already-small capture at its original size', () {
      final src = writeScene(800, 600);
      final out = '${tmp.path}${Platform.pathSeparator}out.jpg';

      final result = PhotoNormalizer.normalizeSync(src, out, 2000);

      expect(result.width, 800);
      expect(result.height, 600);
    });

    test('reports the written dimensions, not the source dimensions', () {
      final src = writeScene(4032, 3024);
      final out = '${tmp.path}${Platform.pathSeparator}out.jpg';

      final result = PhotoNormalizer.normalizeSync(src, out, 2000);
      final written = img.decodeImage(File(out).readAsBytesSync())!;

      expect(result.width, written.width);
      expect(result.height, written.height);
    });

    test('throws a FormatException on an undecodable file', () {
      final junk = '${tmp.path}${Platform.pathSeparator}junk.jpg';
      File(junk).writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));

      expect(
        () => PhotoNormalizer.normalizeSync(
            junk, '${tmp.path}${Platform.pathSeparator}o.jpg', 2000),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('PhotoNormalizer.sweepStaleOutputs', () {
    test('keeps the two newest normalised files and deletes the rest',
        () async {
      final now = DateTime.now();
      for (var i = 0; i < 5; i++) {
        final f = File('${tmp.path}${Platform.pathSeparator}'
            '$kNormalizedPrefix$i.jpg');
        f.writeAsBytesSync(const [0]);
        f.setLastModifiedSync(now.subtract(Duration(minutes: i)));
      }

      await PhotoNormalizer.sweepStaleOutputs(tmp);

      final left = tmp
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith(kNormalizedPrefix))
          .toList();
      expect(left, hasLength(2));
      expect(left, containsAll(['${kNormalizedPrefix}0.jpg',
          '${kNormalizedPrefix}1.jpg']));
    });

    test('never touches files it did not write', () async {
      File('${tmp.path}${Platform.pathSeparator}keep_me.jpg')
          .writeAsBytesSync(const [0]);
      File('${tmp.path}${Platform.pathSeparator}${kNormalizedPrefix}a.png')
          .writeAsBytesSync(const [0]);
      for (var i = 0; i < 4; i++) {
        File('${tmp.path}${Platform.pathSeparator}$kNormalizedPrefix$i.jpg')
            .writeAsBytesSync(const [0]);
      }

      await PhotoNormalizer.sweepStaleOutputs(tmp);

      expect(File('${tmp.path}${Platform.pathSeparator}keep_me.jpg').existsSync(),
          isTrue);
      expect(
        File('${tmp.path}${Platform.pathSeparator}${kNormalizedPrefix}a.png')
            .existsSync(),
        isTrue,
      );
    });

    test('is a no-op on a missing directory rather than throwing', () async {
      final gone = Directory('${tmp.path}${Platform.pathSeparator}nope');
      await expectLater(PhotoNormalizer.sweepStaleOutputs(gone), completes);
    });
  });

  group('runPixelStage', () {
    PipelineResult runOn(int width, int height, cc.DocumentConfig doc) {
      final src = writeScene(width, height, name: 'norm_${width}x$height.jpg');
      return runPixelStage(PixelStageInput(
        normalizedPath: src,
        signals: _signals(width, height),
        doc: doc,
        wearsGlasses: false,
      ));
    }

    test('emits an output at the document aspect ratio', () {
      final result = runOn(1500, 2000, cc.usPassport);

      expect(result.outputWidth, result.outputHeight); // 51x51mm is square
      expect(result.outputWidth,
          inInclusiveRange(cc.usPassport.minResolutionPx.width,
              cc.usPassport.maxResolutionPx.width));
    });

    test('produces a watermarked preview that differs from the clean output',
        () {
      final result = runOn(1500, 2000, cc.usPassport);

      expect(result.cleanJpg, isNotEmpty);
      expect(result.previewJpg, isNotEmpty);
      expect(result.previewJpg, isNot(equals(result.cleanJpg)));
      final clean = img.decodeImage(result.cleanJpg)!;
      expect(clean.width, result.outputWidth);
      expect(clean.height, result.outputHeight);
    });

    test('reports C15 unaltered when no enhancer is supplied', () {
      final result = runOn(1500, 2000, cc.usPassport);

      final c15 = result.report['C15'];
      expect(c15, isNotNull);
      expect(c15!.pass, isTrue);
    });

    test('refuses an enhancer for a no-alteration document', () {
      final src = writeScene(1500, 2000, name: 'enh.jpg');

      expect(
        () => runPixelStage(
          PixelStageInput(
            normalizedPath: src,
            signals: _signals(1500, 2000),
            doc: cc.usPassport, // alterationAllowed == false
            wearsGlasses: false,
          ),
          enhancer: (image) => image,
        ),
        throwsA(isA<cc.AlterationNotPermitted>()),
      );
    });

    test('throws a FormatException when the normalised file is unreadable', () {
      final junk = '${tmp.path}${Platform.pathSeparator}bad.jpg';
      File(junk).writeAsBytesSync(Uint8List.fromList([9, 9, 9]));

      expect(
        () => runPixelStage(PixelStageInput(
          normalizedPath: junk,
          signals: _signals(100, 100),
          doc: cc.usPassport,
          wearsGlasses: false,
        )),
        throwsA(isA<FormatException>()),
      );
    });

    // The crop offsets used to be clamped against a bound derived from the
    // *unrounded* crop size, so a source whose rounded crop matched an edge
    // could build an inverted clamp range and throw ArgumentError.
    // Small scenes on purpose: this asserts the crop arithmetic over 24
    // size/document combinations, and the arithmetic does not care about the
    // pixel count. Full-resolution behaviour is covered by the cases above.
    test('handles landscape, square and extreme-aspect sources', () {
      for (final size in const [
        [400, 200], // wide landscape
        [200, 200], // square
        [200, 480], // tall portrait
        [480, 201], // odd height, rounding-sensitive
      ]) {
        for (final doc in cc.mvpDocuments) {
          expect(
            () => runOn(size[0], size[1], doc),
            returnsNormally,
            reason: '${size[0]}x${size[1]} / ${doc.id}',
          );
        }
      }
    });

    test('handles a source smaller than the document output size', () {
      final result = runOn(120, 160, cc.usPassport);

      // Upscaled to the document minimum rather than crashing or emitting 120px.
      expect(result.outputWidth,
          greaterThanOrEqualTo(cc.usPassport.minResolutionPx.width));
    });

    test('keeps the crop inside the source when the face sits on an edge', () {
      final src = writeScene(300, 400, name: 'edge.jpg');

      for (final centre in const [
        [0.0, 0.0], // top-left corner
        [300.0, 400.0], // bottom-right corner
        [-500.0, -500.0], // wholly outside, as a bad detection would report
      ]) {
        expect(
          () => runPixelStage(PixelStageInput(
            normalizedPath: src,
            signals: cc.FaceSignals(
              faceCount: 1,
              imageWidth: 300,
              imageHeight: 400,
              boundingBox: cc.BoundingBox(
                  x: centre[0], y: centre[1], width: 60, height: 60),
              personMask: cc.PersonMask(
                width: 300,
                height: 400,
                confidence: Uint8List(300 * 400),
              ),
            ),
            doc: cc.usPassport,
            wearsGlasses: false,
          )),
          returnsNormally,
          reason: 'face box at $centre',
        );
      }
    });
  });

  group('computeSpecCrop', () {
    // The crop must size the head (crown→chin) to the MIDDLE of each document's
    // head-height band, so the exported photo — not just the capture — meets
    // spec. Under the old full-height crop the head was ~30% of the frame here,
    // outside every band, so this guards the regression directly.
    test('sizes the head into each document head-height band', () {
      const srcW = 1500, srcH = 2000;
      const crownY = 500.0, chinY = 1100.0; // 600px head

      for (final doc in cc.mvpDocuments) {
        final targetFrac =
            (doc.headHeightMinPct + doc.headHeightMaxPct) / 2 / 100;
        final crop = computeSpecCrop(
          srcW: srcW,
          srcH: srcH,
          aspect: doc.outputSizeMm.width / doc.outputSizeMm.height,
          crownY: crownY,
          chinY: chinY,
          faceCenterX: srcW / 2,
          targetFrac: targetFrac,
        );

        // Head as a fraction of the crop height == fraction of the resized
        // output height (the resize scales uniformly).
        final headPct = (chinY - crownY) / crop.height * 100;
        expect(
          headPct,
          inInclusiveRange(
              doc.headHeightMinPct.toDouble(), doc.headHeightMaxPct.toDouble()),
          reason: doc.id,
        );

        // The crop stays fully inside the source.
        expect(crop.left, inInclusiveRange(0, srcW - crop.width), reason: doc.id);
        expect(crop.top, inInclusiveRange(0, srcH - crop.height), reason: doc.id);
      }
    });

    test('falls back to a full-height crop for degenerate signals', () {
      final crop = computeSpecCrop(
        srcW: 1000,
        srcH: 1000,
        aspect: 1.0,
        crownY: 0,
        chinY: 0, // zero head → fallback
        faceCenterX: 500,
        targetFrac: 0.6,
      );
      expect(crop.height, 1000);
    });
  });
}
