import 'models.dart';

/// Converte un numero in formato italiano/inglese ("1.234,50", "12.5", "3,20").
double? parseNumber(String raw) {
  var s = raw.replaceAll(RegExp(r'[€\s]'), '');
  if (s.isEmpty) return null;
  final hasComma = s.contains(',');
  final hasDot = s.contains('.');
  if (hasComma && hasDot) {
    // il separatore decimale è quello più a destra
    if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (hasComma) {
    s = s.replaceAll(',', '.');
  }
  return double.tryParse(s);
}

final _numRe = RegExp(r'\d{1,3}(?:[.\s]\d{3})*(?:[.,]\d{1,2})|\d+(?:[.,]\d{1,2})?');

List<double> numbersIn(String line) => _numRe
    .allMatches(line)
    .map((m) => parseNumber(m.group(0)!))
    .whereType<double>()
    .toList();

class SlipDraft {
  double? stake;
  double? odds;
  double? potentialWin;
  DateTime? placedAt;
  List<Selection> selections = [];
  String rawText = '';

  bool get isEmpty =>
      stake == null && odds == null && potentialWin == null && selections.isEmpty;
}

/// Legge il testo OCR di uno screenshot di una schedina e prova a estrarre i dati.
/// È volutamente tollerante: l'utente rivede sempre tutto prima di salvare.
SlipDraft parseSlipText(String text) {
  final d = SlipDraft()..rawText = text;
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  double? valueFor(int i) {
    final own = numbersIn(lines[i].replaceAll(RegExp(r'\d{1,2}[/.]\d{1,2}[/.]\d{2,4}'), ''));
    if (own.isNotEmpty) return own.last;
    for (var k = i + 1; k < lines.length && k <= i + 2; k++) {
      final n = numbersIn(lines[k]);
      if (n.isNotEmpty) return n.first;
    }
    return null;
  }

  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].toLowerCase();
    if (d.potentialWin == null &&
        (l.contains('vincita') || l.contains('potenziale') || l.contains('vinci'))) {
      d.potentialWin = valueFor(i);
    } else if (d.odds == null && l.contains('quota') && (l.contains('tot') || l.contains('complessiva'))) {
      d.odds = valueFor(i);
    } else if (d.stake == null &&
        (l.contains('importo') || l.contains('puntata') || l.contains('scommesso') || l.contains('giocato') || l == 'giocata')) {
      d.stake = valueFor(i);
    }
    final dm = RegExp(r'(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})(?:\D+(\d{1,2})[:.](\d{2}))?')
        .firstMatch(lines[i]);
    if (d.placedAt == null && dm != null) {
      var y = int.parse(dm.group(3)!);
      if (y < 100) y += 2000;
      final mo = int.parse(dm.group(2)!), da = int.parse(dm.group(1)!);
      if (mo >= 1 && mo <= 12 && da >= 1 && da <= 31 && y > 2000) {
        d.placedAt = DateTime(y, mo, da, int.tryParse(dm.group(4) ?? '') ?? 12,
            int.tryParse(dm.group(5) ?? '') ?? 0);
      }
    }
  }

  // Eventi: righe tipo "Inter - Milan" (lettere da entrambe le parti).
  final eventRe = RegExp(r'^(.*[A-Za-zÀ-ÿ].*?)\s+(?:-|–|—|vs\.?|v)\s+(.*[A-Za-zÀ-ÿ].*)$', caseSensitive: false);
  final keywordRe = RegExp(r'importo|quota|vincita|bonus|saldo|totale|puntata|codice|data', caseSensitive: false);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (keywordRe.hasMatch(line)) continue;
    final m = eventRe.firstMatch(line);
    if (m == null) continue;
    if (line.length > 60) continue;
    final event = line.replaceAll(RegExp(r'\s+\d+[.,]\d{2}$'), '').trim();
    String pick = '';
    double? odds;
    final trailing = RegExp(r'(\d+[.,]\d{2})$').firstMatch(line);
    if (trailing != null) {
      final v = parseNumber(trailing.group(1)!);
      if (v != null && v >= 1.01 && v <= 100) odds = v;
    }
    for (var k = i + 1; k < lines.length && k <= i + 3; k++) {
      final next = lines[k];
      if (eventRe.hasMatch(next) && !keywordRe.hasMatch(next)) break;
      final nums = numbersIn(next).where((v) => v >= 1.01 && v <= 100).toList();
      final hasDecimals = RegExp(r'\d+[.,]\d{2}').hasMatch(next);
      final letters = next.replaceAll(RegExp(r'[\d.,]+'), '').trim();
      if (pick.isEmpty && letters.isNotEmpty && letters.length <= 30 && !keywordRe.hasMatch(next)) {
        pick = letters;
      } else if (pick.isEmpty && next.length <= 4 && RegExp(r'^(1|x|2|1x|x2|12)$', caseSensitive: false).hasMatch(next)) {
        pick = next.toUpperCase();
      }
      if (odds == null && hasDecimals && nums.isNotEmpty) odds = nums.last;
    }
    d.selections.add(Selection(event: event, pick: pick, odds: odds));
  }

  // Coerenza tra i valori.
  if (d.odds == null && d.selections.isNotEmpty && d.selections.every((s) => s.odds != null)) {
    d.odds = d.selections.fold<double>(1, (p, s) => p * s.odds!);
    d.odds = double.parse(d.odds!.toStringAsFixed(2));
  }
  if (d.odds == null && d.stake != null && d.potentialWin != null && d.stake! > 0) {
    d.odds = double.parse((d.potentialWin! / d.stake!).toStringAsFixed(2));
  }
  if (d.stake == null && d.odds != null && d.potentialWin != null && d.odds! > 0) {
    d.stake = double.parse((d.potentialWin! / d.odds!).toStringAsFixed(2));
  }
  return d;
}

class ParsedNotice {
  final NoticeKind kind;
  final double? amount;
  ParsedNotice(this.kind, this.amount);
}

/// Capisce se una notifica parla di una vincita o di una perdita.
ParsedNotice parseNotification(String title, String text) {
  final all = '$title\n$text';
  final l = all.toLowerCase();
  NoticeKind kind = NoticeKind.unknown;
  if (RegExp(r'perdent|pers[ao]\b|non vincente|non è vincente|non e vincente').hasMatch(l)) {
    kind = NoticeKind.loss;
  } else if (RegExp(r'vint|vincit|vincente|pagat|complimenti|accredit').hasMatch(l)) {
    kind = NoticeKind.win;
  }
  double? amount;
  final euro = RegExp(r'(\d{1,3}(?:[.\s]\d{3})*(?:[.,]\d{1,2})|\d+(?:[.,]\d{1,2})?)\s*(?:€|eur)|€\s*(\d{1,3}(?:[.\s]\d{3})*(?:[.,]\d{1,2})|\d+(?:[.,]\d{1,2})?)', caseSensitive: false)
      .firstMatch(all);
  if (euro != null) {
    amount = parseNumber(euro.group(1) ?? euro.group(2)!);
  } else {
    final n = numbersIn(all).where((v) => v > 0).toList();
    final withDec = RegExp(r'\d+[.,]\d{2}').allMatches(all).map((m) => parseNumber(m.group(0)!)).whereType<double>().toList();
    if (withDec.isNotEmpty) {
      amount = withDec.reduce((a, b) => a > b ? a : b);
    } else if (n.length == 1) {
      amount = n.first;
    }
  }
  return ParsedNotice(kind, amount);
}
