import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../parser.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

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

/// Avvia l'inserimento: da screenshot (condiviso o scelto) oppure a mano.
Future<void> startAddBet(BuildContext context, {String? sharedImage}) async {
  final store = AppScope.read(context);
  await store.ready;
  if (!context.mounted) return;
  String? image = sharedImage;
  if (image == null) {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text('Nuova schedina', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            ),
            _ChoiceTile(
              icon: Icons.image_search_rounded,
              color: C.primary,
              title: 'Da screenshot',
              text: 'Scegli lo screenshot della schedina: leggo importo, quota ed eventi.',
              onTap: () => Navigator.pop(ctx, 'shot'),
            ),
            const SizedBox(height: 10),
            _ChoiceTile(
              icon: Icons.edit_note_rounded,
              color: C.blue,
              title: 'Inserisci a mano',
              text: 'Importo e quota, gli eventi sono facoltativi.',
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Suggerimento: da Eplay fai lo screenshot, poi Condividi → Bet Tracker.',
              style: TextStyle(color: C.faint, fontSize: 12.5),
            ),
          ]),
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'shot') {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null) return;
      image = x.path;
    }
  }
  if (!context.mounted) return;

  SlipDraft draft = SlipDraft();
  String? kept;
  if (image != null) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Leggo la schedina…'),
            ]),
          ),
        ),
      ),
    );
    try {
      kept = await store.keepImage(image);
      draft = await recognizeSlip(kept);
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }
  if (!context.mounted) return;
  final bet = Bet(
    placedAt: draft.placedAt ?? DateTime.now(),
    stake: draft.stake ?? 0,
    odds: draft.odds ?? 0,
    potentialWinOverride: (draft.potentialWin != null &&
            draft.stake != null &&
            draft.odds != null &&
            (draft.potentialWin! - draft.stake! * draft.odds!).abs() > 0.05)
        ? draft.potentialWin
        : null,
    selections: draft.selections,
    imagePath: kept,
  );
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BetEditor(bet: bet, isNew: true, ocrText: image != null ? draft.rawText : null),
  ));
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, text;
  final VoidCallback onTap;
  const _ChoiceTile({required this.icon, required this.color, required this.title, required this.text, required this.onTap});
  @override
  Widget build(BuildContext context) => Panel(
        onTap: onTap,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              const SizedBox(height: 3),
              Text(text, style: const TextStyle(color: C.muted, fontSize: 13)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: C.faint),
        ]),
      );
}

class BetEditor extends StatefulWidget {
  final Bet bet;
  final bool isNew;
  final String? ocrText;
  const BetEditor({super.key, required this.bet, this.isNew = false, this.ocrText});
  @override
  State<BetEditor> createState() => _BetEditorState();
}

String _num(double? v) => v == null || v == 0 ? '' : v.toStringAsFixed(2).replaceAll('.', ',');

class _BetEditorState extends State<BetEditor> {
  late final TextEditingController stake, oddsC, potential, payout, note;
  late DateTime placedAt;
  late BetStatus status;
  late List<_SelCtl> sels;

  @override
  void initState() {
    super.initState();
    final b = widget.bet;
    stake = TextEditingController(text: _num(b.stake));
    oddsC = TextEditingController(text: _num(b.odds));
    potential = TextEditingController(text: _num(b.potentialWinOverride));
    payout = TextEditingController(text: _num(b.payout));
    note = TextEditingController(text: b.note);
    placedAt = b.placedAt;
    status = b.status;
    sels = b.selections.map((s) => _SelCtl(s.copy())).toList();
  }

  @override
  void dispose() {
    for (final c in [stake, oddsC, potential, payout, note]) {
      c.dispose();
    }
    for (final s in sels) {
      s.dispose();
    }
    super.dispose();
  }

  double? get _stake => parseNumber(stake.text);
  double? get _odds => parseNumber(oddsC.text);
  double? get _pot => parseNumber(potential.text);

  double get _computedWin => (_pot ?? ((_stake ?? 0) * (_odds ?? 0)));

  Future<void> _save() async {
    final st = _stake, od = _odds;
    if (st == null || st <= 0) {
      toast(context, 'Inserisci l\'importo giocato');
      return;
    }
    if (od == null || od < 1) {
      toast(context, 'Inserisci la quota totale (almeno 1,00)');
      return;
    }
    final b = widget.bet
      ..stake = st
      ..odds = od
      ..potentialWinOverride = (_pot != null && (_pot! - st * od).abs() > 0.009) ? _pot : null
      ..placedAt = placedAt
      ..note = note.text.trim()
      ..selections = sels
          .map((c) => Selection(
                event: c.event.text.trim(),
                pick: c.pick.text.trim(),
                odds: parseNumber(c.odds.text),
              ))
          .where((s) => s.event.isNotEmpty)
          .toList();
    if (status != b.status) {
      b.settledAt = status.settled ? DateTime.now() : null;
      if (!status.settled) b.autoSettled = false;
    }
    b.status = status;
    final p = parseNumber(payout.text);
    b.payout = (status == BetStatus.won || status == BetStatus.cashout || status == BetStatus.voided) ? p : null;
    await AppScope.read(context).upsertBet(b);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare la schedina?'),
        content: const Text('Verrà tolta anche dal saldo e dalle statistiche.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Elimina', style: TextStyle(color: C.loss))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.read(context).deleteBet(widget.bet);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: placedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(placedAt));
    setState(() => placedAt = DateTime(d.year, d.month, d.day, t?.hour ?? placedAt.hour, t?.minute ?? placedAt.minute));
  }

  InputDecoration _dec(String label, {String? suffix, String? hint}) =>
      InputDecoration(labelText: label, suffixText: suffix, hintText: hint);

  @override
  Widget build(BuildContext context) {
    final img = widget.bet.imagePath;
    final cat = (_odds ?? 0) >= 1 ? categoryForOdds(_odds!) : null;
    final numFmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Nuova schedina' : 'Schedina'),
        actions: [
          if (!widget.isNew)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded, color: C.loss)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(widget.isNew ? 'Salva schedina' : 'Salva modifiche'),
          ),
        ),
      ),
      body: Responsive(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (img != null && File(img).existsSync())
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: Colors.black,
                      appBar: AppBar(backgroundColor: Colors.black),
                      body: InteractiveViewer(maxScale: 5, child: Center(child: Image.file(File(img)))),
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(children: [
                    Image.file(File(img), height: 170, width: double.infinity, fit: BoxFit.cover, alignment: Alignment.topCenter),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Pill('Tocca per ingrandire', color: Colors.white, icon: Icons.zoom_in_rounded),
                    ),
                  ]),
                ),
              ),
            if (widget.ocrText != null) ...[
              const SizedBox(height: 10),
              Panel(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.auto_awesome_rounded, color: C.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.ocrText!.trim().isEmpty
                          ? 'Non sono riuscito a leggere il testo: compila tu i campi.'
                          : 'Ho compilato i campi dallo screenshot: controlla che siano giusti.',
                      style: const TextStyle(color: C.muted, fontSize: 13),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: stake,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: numFmt,
                  decoration: _dec('Importo', suffix: '€'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: oddsC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: numFmt,
                  decoration: _dec('Quota totale'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: potential,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: numFmt,
              decoration: _dec('Vincita potenziale (se diversa, es. con bonus)',
                  suffix: '€', hint: eur((_stake ?? 0) * (_odds ?? 0))),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  onTap: _pickDate,
                  child: Row(children: [
                    const Icon(Icons.event_rounded, size: 19, color: C.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(dateTime(placedAt), style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
              if (cat != null) ...[
                const SizedBox(width: 10),
                Pill(cat.label, color: C.blue),
              ],
            ]),
            const SizedBox(height: 10),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                const Text('Se vince incassi', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(eur(_computedWin), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(width: 8),
                Text(signedEur(_computedWin - (_stake ?? 0)),
                    style: TextStyle(color: C.pl(_computedWin - (_stake ?? 0)), fontWeight: FontWeight.w700)),
              ]),
            ),
            const SectionTitle('Esito'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in BetStatus.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: status == s,
                  avatar: Icon(statusIcon(s), size: 17, color: statusColor(s)),
                  showCheckmark: false,
                  selectedColor: statusColor(s).withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => status = s),
                ),
            ]),
            if (status == BetStatus.won || status == BetStatus.cashout || status == BetStatus.voided) ...[
              const SizedBox(height: 12),
              TextField(
                controller: payout,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numFmt,
                decoration: _dec(
                  status == BetStatus.won
                      ? 'Incasso effettivo (vuoto = vincita potenziale)'
                      : status == BetStatus.cashout
                          ? 'Importo del cash out'
                          : 'Rimborso (vuoto = importo giocato)',
                  suffix: '€',
                ),
              ),
            ],
            SectionTitle(
              'Eventi',
              trailing: TextButton.icon(
                onPressed: () => setState(() => sels.add(_SelCtl(Selection(event: '')))),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Aggiungi'),
              ),
            ),
            if (sels.isEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Facoltativi: servono per riconoscere la schedina a colpo d\'occhio.',
                    style: TextStyle(color: C.faint, fontSize: 13)),
              ),
            for (var i = 0; i < sels.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(children: [
                        TextField(controller: sels[i].event, decoration: _dec('Partita', hint: 'Inter - Milan')),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              flex: 3,
                              child: TextField(controller: sels[i].pick, decoration: _dec('Esito', hint: '1, X, Over 2.5'))),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: sels[i].odds,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: numFmt,
                              decoration: _dec('Quota'),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                    IconButton(
                      onPressed: () => setState(() => sels.removeAt(i).dispose()),
                      icon: const Icon(Icons.close_rounded, color: C.faint),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 6),
            TextField(controller: note, decoration: _dec('Nota'), maxLines: 2, minLines: 1),
            if (widget.ocrText != null && widget.ocrText!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Testo letto dallo screenshot', style: TextStyle(color: C.muted, fontSize: 14)),
                  children: [
                    SelectableText(widget.ocrText!, style: const TextStyle(color: C.faint, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelCtl {
  final TextEditingController event, pick, odds;
  _SelCtl(Selection s)
      : event = TextEditingController(text: s.event),
        pick = TextEditingController(text: s.pick),
        odds = TextEditingController(text: _num(s.odds));
  void dispose() {
    event.dispose();
    pick.dispose();
    odds.dispose();
  }
}
