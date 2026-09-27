import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/document_model.dart';

class PdfService {
  static Future<File> generatePdf(DocumentModel document) async {
    final pdf = pw.Document();

    if (document.pages != null && document.pages!.isNotEmpty) {
      for (var page in document.pages!) {
        final imageFile = File(page.imagePath);
        if (await imageFile.exists()) {
          final image = pw.MemoryImage(imageFile.readAsBytesSync());
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
    }

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/${document.title}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}

