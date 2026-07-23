import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Longest edge of the normalised photo. Plenty for a passport crop, and it
/// keeps the on-device segmentation + Laplacian passes fast.
const int kNormalizedMaxEdge = 2000;

/// Prefix for the JPEGs [PhotoNormalizer] writes into the temporary directory.
const String kNormalizedPrefix = 'normalized_';

/// How many previous normalised files to keep when sweeping. One spare covers
/// the case where the user backs out of processing and the old path is still
/// referenced by app state.
const int _keepRecentOutputs = 2;

/// Result of normalising a captured/imported photo to an upright JPEG.
///
/// Both ML Kit and the pixel-based checks read the SAME normalised file, so
/// their coordinate spaces match (no EXIF-rotation mismatch between the mask
/// and the decoded pixels). This sidesteps the classic orientation bug.
///
/// Only the path and dimensions cross back from the worker isolate — the
/// decoded pixels stay inside it, so nothing large is copied between heaps.
class NormalizedPhoto {
  const NormalizedPhoto({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final int width; // upright, EXIF baked in
  final int height;
}

/// Decode [bytes], turning every failure mode into a [FormatException] carrying
/// [message].
///
/// `decodeImage` does not merely return null on a bad file: it probes the
/// candidate formats in turn, and a truncated or corrupt buffer makes one of
/// those probes read past its end and throw a raw `RangeError` first. A photo
/// truncated because the camera process was killed mid-write is exactly what
/// memory-pressured older hardware produces, so both outcomes have to funnel
/// into the one exception the screens already handle (A1-12).
img.Image decodeOrThrow(Uint8List bytes, String message) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw FormatException(message);
  }
  if (decoded == null) throw FormatException(message);
  return decoded;
}

class PhotoNormalizer {
  /// Decode [srcPath], bake EXIF orientation, downscale very large captures,
  /// and re-encode as a clean JPEG with no rotation flag.
  ///
  /// The decode runs on a worker isolate. A 12MP capture is ~48MB per RGBA
  /// copy and the decode/bake/resize chain holds more than one at a time; doing
  /// that on the UI isolate spikes the heap and blocks the frame pump long
  /// enough for iOS's watchdog or Android's low-memory killer to take the app
  /// down on 3GB-class hardware (iPhone XR/11, older Android) — A1-12.
  static Future<NormalizedPhoto> normalize(
    String srcPath, {
    int maxEdge = kNormalizedMaxEdge,
  }) async {
    // Plugin channels only work on the root isolate, so resolve the directory
    // here and hand the worker a plain path.
    final dir = await getTemporaryDirectory();
    await sweepStaleOutputs(dir);
    final outPath =
        '${dir.path}/$kNormalizedPrefix${DateTime.now().millisecondsSinceEpoch}.jpg';
    return Isolate.run(() => normalizeSync(srcPath, outPath, maxEdge));
  }

  /// The pure, synchronous core of [normalize] — no plugins, no isolates, so
  /// it runs directly under test.
  ///
  /// Each stage reassigns [image] rather than holding a second reference, which
  /// lets the previous buffer be collected instead of pinning two full-size
  /// copies at once.
  static NormalizedPhoto normalizeSync(
    String srcPath,
    String outPath,
    int maxEdge,
  ) {
    var image = decodeOrThrow(
      File(srcPath).readAsBytesSync(),
      'Could not decode the captured photo.',
    );
    image = img.bakeOrientation(image);

    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxEdge) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxEdge)
          : img.copyResize(image, height: maxEdge);
    }

    File(outPath).writeAsBytesSync(img.encodeJpg(image, quality: 95));
    return NormalizedPhoto(
      path: outPath,
      width: image.width,
      height: image.height,
    );
  }

  /// Delete normalised JPEGs left behind by earlier runs, keeping the most
  /// recent [_keepRecentOutputs]. Without this every capture leaks a multi-MB
  /// file into the temp directory for the lifetime of the install — which on a
  /// nearly-full older device eventually fails the write instead of the decode.
  ///
  /// Best-effort: a file we cannot stat or delete is skipped, never fatal.
  static Future<void> sweepStaleOutputs(Directory dir) async {
    try {
      final stale = <({File file, DateTime modified})>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith(kNormalizedPrefix) || !name.endsWith('.jpg')) {
          continue;
        }
        try {
          stale.add((file: entity, modified: await entity.lastModified()));
        } catch (_) {
          // Vanished or unreadable between listing and stat — nothing to do.
        }
      }
      stale.sort((a, b) => b.modified.compareTo(a.modified)); // newest first
      for (final entry in stale.skip(_keepRecentOutputs)) {
        try {
          await entry.file.delete();
        } catch (_) {
          // Locked or already gone; a leftover file is not worth failing over.
        }
      }
    } catch (_) {
      // Temp dir unreadable — normalisation itself can still succeed.
    }
  }
}
