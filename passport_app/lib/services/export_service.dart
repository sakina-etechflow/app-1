import 'dart:io';
import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart' as cc;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Saving, sharing, and the print sheet. Available after unlock or a rewarded
/// view.
class ExportService {
  /// Write the single digital photo to a temp file and open the share sheet
  /// (lets the user save to Photos, or attach to an online application).
  static Future<void> shareDigital(Uint8List jpg, String docId) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${docId}_photo.jpg';
    await File(path).writeAsBytes(jpg);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: 'Passport photo formatted for $docId',
      ),
    );
  }

  /// Compose a 4x6 inch print sheet with as many correctly-sized copies as fit,
  /// each with a thin cut guide, then hand it to the OS print/share dialog.
  static Future<void> printSheet(Uint8List jpg, cc.DocumentConfig doc) async {
    final bytes = await _buildSheet(jpg, doc);
    await Printing.sharePdf(bytes: bytes, filename: '${doc.id}_print_sheet.pdf');
  }

  static Future<Uint8List> _buildSheet(
      Uint8List jpg, cc.DocumentConfig doc) async {
    final pdfImage = pw.MemoryImage(jpg);
    final pageFormat = PdfPageFormat(4 * PdfPageFormat.inch, 6 * PdfPageFormat.inch,
        marginAll: 0.2 * PdfPageFormat.inch);

    final photoW = doc.outputSizeMm.width * PdfPageFormat.mm;
    final photoH = doc.outputSizeMm.height * PdfPageFormat.mm;
    const gap = 6.0;

    final usableW = pageFormat.availableWidth;
    final usableH = pageFormat.availableHeight;
    final cols = ((usableW + gap) / (photoW + gap)).floor().clamp(1, 10);
    final rows = ((usableH + gap) / (photoH + gap)).floor().clamp(1, 10);

    final doc0 = pw.Document();
    doc0.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Center(
          child: pw.Wrap(
            spacing: gap,
            runSpacing: gap,
            children: List.generate(
              cols * rows,
              (_) => pw.Container(
                width: photoW,
                height: photoH,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.grey400, width: 0.5),
                ),
                child: pw.Image(pdfImage, fit: pw.BoxFit.cover),
              ),
            ),
          ),
        ),
      ),
    );
    return doc0.save();
  }
}
