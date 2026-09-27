import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

class ConversionService {
  /// Converts a list of image file paths into a single PDF document
  static Future<File> imagesToPdf({
    required List<String> imagePaths,
    required String outputFileName,
  }) async {
    final pdf = pw.Document();

    for (String path in imagePaths) {
      final file = File(path);
      if (await file.exists()) {
        final imageBytes = await file.readAsBytes();
        final image = pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              );
            },
          ),
        );
      }
    }

    final outputDir = await getApplicationDocumentsDirectory();
    final sanitizedName = outputFileName.replaceAll(RegExp(r'[^\w\s\.-]'), '_');
    final pdfFile = File('${outputDir.path}/$sanitizedName.pdf');
    await pdfFile.writeAsBytes(await pdf.save());
    return pdfFile;
  }

  /// Extracts all pages from a PDF file as JPEG images
  static Future<List<String>> pdfToImages({
    required String pdfPath,
    String? outputPrefix,
  }) async {
    final List<String> extractedImagePaths = [];
    final document = await pdfx.PdfDocument.openFile(pdfPath);
    final outputDir = await getApplicationDocumentsDirectory();
    final prefix = outputPrefix ?? 'PdfPage_${DateTime.now().millisecondsSinceEpoch}';

    for (int i = 1; i <= document.pagesCount; i++) {
      final page = await document.getPage(i);
      final pageImage = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: pdfx.PdfPageImageFormat.jpeg,
      );

      if (pageImage != null) {
        final imageFile = File('${outputDir.path}/${prefix}_page_$i.jpg');
        await imageFile.writeAsBytes(pageImage.bytes);
        extractedImagePaths.add(imageFile.path);
      }

      await page.close();
    }

    await document.close();
    return extractedImagePaths;
  }
}
