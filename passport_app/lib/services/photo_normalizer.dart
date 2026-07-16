import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Result of normalising a captured/imported photo to an upright JPEG.
///
/// Both ML Kit and the pixel-based checks read the SAME normalised file, so
/// their coordinate spaces match (no EXIF-rotation mismatch between the mask
/// and the decoded pixels). This sidesteps the classic orientation bug.
class NormalizedPhoto {
  NormalizedPhoto(this.path, this.image);
  final String path;
  final img.Image image; // upright, EXIF baked in
}

class PhotoNormalizer {
  /// Decode [srcPath], bake EXIF orientation, optionally downscale very large
  /// captures, and re-encode as a clean JPEG with no rotation flag.
  static Future<NormalizedPhoto> normalize(String srcPath) async {
    final bytes = await File(srcPath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Could not decode the captured photo.');
    }
    var upright = img.bakeOrientation(decoded);

    // Keep the longest edge <= 2000px: plenty for a passport crop, and it
    // keeps the on-device segmentation + Laplacian passes fast.
    const maxEdge = 2000;
    final longest =
        upright.width > upright.height ? upright.width : upright.height;
    if (longest > maxEdge) {
      upright = upright.width >= upright.height
          ? img.copyResize(upright, width: maxEdge)
          : img.copyResize(upright, height: maxEdge);
    }

    final dir = await getTemporaryDirectory();
    final out =
        '${dir.path}/normalized_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(out).writeAsBytes(img.encodeJpg(upright, quality: 95));
    return NormalizedPhoto(out, upright);
  }
}
