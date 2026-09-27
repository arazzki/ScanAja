import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ScannerService {
  static const MethodChannel _channel = MethodChannel('com.example.scanaja/scanner');

  static Future<List<String>?> startScan() async {
    final List<dynamic>? result = await _channel.invokeMethod('startScan');
    if (result != null) {
      return result.cast<String>();
    }
    return null;
  }

  static Future<String> extractText(String imagePath) async {
    try {
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      return recognizedText.text;
    } catch (e) {
      print("Failed to extract text: $e");
      return "";
    }
  }
}
