import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'parser.dart';

Future<SlipDraft> recognizeSlip(String path) async {
  final r = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final t = await r.processImage(InputImage.fromFilePath(path));
    return parseSlipText(t.text);
  } catch (_) {
    return SlipDraft();
  } finally {
    await r.close();
  }
}
