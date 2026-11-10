import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'parser.dart';

class _L {
  final String text;
  final double left, top, bottom;
  _L(this.text, this.left, this.top, this.bottom);
  double get cy => (top + bottom) / 2;
  double get h => bottom - top;
}

/// Ricostruisce le righe "visive" dello screenshot: etichetta a sinistra e valore a destra
/// (es. "Quota totale :" ... "13.00") finiscono sulla stessa riga di testo.
String rowsFromRecognized(RecognizedText t) {
  final lines = <_L>[];
  for (final b in t.blocks) {
    for (final l in b.lines) {
      final r = l.boundingBox;
      lines.add(_L(l.text, r.left, r.top, r.bottom));
    }
  }
  lines.sort((a, b) => a.cy.compareTo(b.cy));
  final rows = <List<_L>>[];
  for (final l in lines) {
    if (rows.isNotEmpty) {
      final row = rows.last;
      final ref = row.first;
      final tol = (ref.h < l.h ? ref.h : l.h) * 0.6;
      if ((l.cy - ref.cy).abs() <= tol) {
        row.add(l);
        continue;
      }
    }
    rows.add([l]);
  }
  return rows.map((r) {
    r.sort((a, b) => a.left.compareTo(b.left));
    return r.map((e) => e.text).join('   ');
  }).join('\n');
}

Future<SlipDraft> recognizeSlip(String path) async {
  final r = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final t = await r.processImage(InputImage.fromFilePath(path));
    final rows = rowsFromRecognized(t);
    final d = parseSlipText(rows);
    // se per righe non trova nulla, riprova con il testo grezzo
    if (d.stake == null || d.odds == null) {
      final raw = parseSlipText(t.text);
      d.stake ??= raw.stake;
      d.odds ??= raw.odds;
      d.potentialWin ??= raw.potentialWin;
      d.status ??= raw.status;
      d.ticket ??= raw.ticket;
      d.placedAt ??= raw.placedAt;
      if (d.odds == null && d.stake != null && d.potentialWin != null && d.stake! > 0) {
        d.odds = double.parse((d.potentialWin! / d.stake!).toStringAsFixed(2));
      }
    }
    return d;
  } catch (_) {
    return SlipDraft();
  } finally {
    await r.close();
  }
}
