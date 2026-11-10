import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../parser.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'dashboard.dart';
import 'notices.dart';

const releaseUrl = 'https://github.com/Matteo-00/Bet/releases/latest';

class SettingsScreen extends StatelessWidget {
  final bool listenerEnabled;
  final VoidCallback onCheckListener;
  const SettingsScreen({super.key, required this.listenerEnabled, required this.onCheckListener});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final st = store.settings;
    final dep = store.movements.where((m) => m.amount > 0).fold<double>(0, (s, m) => s + m.amount);
    final wd = store.movements.where((m) => m.amount < 0).fold<double>(0, (s, m) => s - m.amount);

    return Responsive(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          const SectionTitle('Budget'),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _Row(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Budget di partenza',
                value: eur(st.startingBankroll),
                onTap: () async {
                  final v = await askAmount(context, 'Budget di partenza', st.startingBankroll);
                  if (v != null) await store.updateSettings((s) => s.startingBankroll = v);
                },
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.flag_outlined,
                title: 'Data di inizio',
                value: dateShort(st.startDate),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: st.startDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) await store.updateSettings((s) => s.startDate = d);
                },
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.speed_rounded,
                title: 'Limite giornaliero',
                value: st.dailyLimit > 0 ? eur(st.dailyLimit) : 'Nessuno',
                onTap: () async {
                  final v = await askAmount(context, 'Limite giornaliero (0 = nessuno)', st.dailyLimit);
                  if (v != null) await store.updateSettings((s) => s.dailyLimit = v);
                },
              ),
            ]),
          ),
          SectionTitle(
            'Ricariche e prelievi',
            trailing: TextButton.icon(
              onPressed: () => _addMovement(context, store),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Aggiungi'),
            ),
          ),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _Mini('Ricaricato', eur(dep), C.win)),
                Expanded(child: _Mini('Prelevato', eur(wd), C.loss)),
              ]),
              if (store.movements.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('Se ricarichi o prelevi dal conto Eplay, segnalo qui: il saldo resta giusto e '
                      'il profitto non viene falsato.',
                      style: TextStyle(color: C.faint, fontSize: 13, height: 1.35)),
                ),
              for (final m in store.movements.take(10))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(m.amount >= 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
                      color: m.amount >= 0 ? C.win : C.loss),
                  title: Text(m.amount >= 0 ? 'Ricarica' : 'Prelievo'),
                  subtitle: Text('${dateShort(m.date)}${m.note.isEmpty ? '' : ' · ${m.note}'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(signedEur(m.amount), style: TextStyle(color: C.pl(m.amount), fontWeight: FontWeight.w800)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: C.faint),
                      onPressed: () => store.deleteMovement(m),
                    ),
                  ]),
                ),
            ]),
          ),
          const SectionTitle('Notifiche Eplay'),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _Row(
                icon: listenerEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                iconColor: listenerEnabled ? C.win : C.pending,
                title: 'Lettura notifiche',
                value: listenerEnabled ? 'Attiva' : 'Da attivare',
                onTap: () async {
                  await showNotificationHelp(context);
                  onCheckListener();
                },
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.filter_alt_outlined,
                title: 'Parole chiave',
                value: st.notificationKeywords,
                onTap: () async {
                  final v = await askText(context, 'Parole chiave (separate da virgola)', st.notificationKeywords,
                      help: 'Leggo solo le notifiche che contengono una di queste parole nel nome dell\'app, '
                          'nel titolo o nel testo. Es: eplay, eplay24');
                  if (v != null && v.trim().isNotEmpty) {
                    await store.updateSettings((s) => s.notificationKeywords = v.trim());
                  }
                },
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.history_rounded,
                title: 'Notifiche ricevute',
                value: '${store.notices.length}',
                onTap: () => _showLog(context, store),
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.science_outlined,
                title: 'Prova il riconoscimento',
                value: '',
                onTap: () => _testNotice(context),
              ),
            ]),
          ),
          if (store.openNotices.isNotEmpty) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => showNoticesSheet(context),
              icon: const Icon(Icons.mark_email_unread_rounded),
              label: Text('${store.openNotices.length} da abbinare'),
            ),
          ],
          const SectionTitle('Dati'),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _Row(
                icon: Icons.cloud_done_outlined,
                iconColor: store.syncState == SyncState.error
                    ? C.loss
                    : (store.pendingOps > 0 ? C.pending : C.primary),
                title: 'Database Supabase',
                value: store.syncState == SyncState.error
                    ? 'Errore'
                    : store.pendingOps > 0
                        ? '${store.pendingOps} in attesa'
                        : (store.lastSync == null ? 'Mai sincronizzato' : 'Aggiornato ${dateTime(store.lastSync!)}'),
                onTap: () async {
                  await store.sync();
                  if (context.mounted) {
                    toast(context, store.lastError ?? (store.pendingOps == 0 ? 'Tutto sincronizzato' : 'Sei offline'));
                  }
                },
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.ios_share_rounded,
                title: 'Esporta backup',
                value: '',
                onTap: () async {
                  final f = await store.exportBackup();
                  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Backup Bet Tracker'));
                },
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.download_rounded,
                title: 'Importa backup',
                value: '',
                onTap: () async {
                  final res = await FilePicker.platform.pickFiles(type: FileType.any);
                  final path = res?.files.single.path;
                  if (path == null || !context.mounted) return;
                  final ok = await _confirm(context, 'Importare il backup?', 'I dati attuali verranno sostituiti.');
                  if (!ok) return;
                  try {
                    await store.importBackup(path);
                    if (context.mounted) toast(context, 'Backup importato');
                  } catch (_) {
                    if (context.mounted) toast(context, 'File non valido');
                  }
                },
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.system_update_rounded,
                title: 'Aggiornamenti',
                value: 'Copia link',
                onTap: () async {
                  await Clipboard.setData(const ClipboardData(text: releaseUrl));
                  if (context.mounted) toast(context, 'Link copiato: aprilo nel browser per scaricare l\'ultima versione');
                },
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.cloud_download_outlined,
                title: 'Riscarica dal database',
                value: '',
                onTap: () async {
                  final ok = await _confirm(context, 'Riscaricare tutto?',
                      'La copia sul telefono viene sostituita con i dati su Supabase. Le modifiche non ancora inviate vanno perse.');
                  if (ok) await store.redownload();
                },
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text('Bet Tracker · dati su Supabase (stesso database del tracker web)',
                style: TextStyle(color: C.faint, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _addMovement(BuildContext context, AppStore store) async {
    final res = await showDialog<Movement>(context: context, builder: (_) => const _MovementDialog());
    if (res != null) await store.addMovement(res);
  }

  void _showLog(BuildContext context, AppStore store) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 10),
                child: Text('Notifiche ricevute', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              if (store.notices.isEmpty)
                const Text('Ancora nessuna. Quando arriva una notifica di Eplay la vedi qui.',
                    style: TextStyle(color: C.muted)),
              for (final n in store.notices.take(50))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    n.kind == NoticeKind.win
                        ? Icons.check_circle_rounded
                        : n.kind == NoticeKind.loss
                            ? Icons.cancel_rounded
                            : Icons.notifications_rounded,
                    color: n.kind == NoticeKind.win ? C.win : (n.kind == NoticeKind.loss ? C.loss : C.muted),
                  ),
                  title: Text(n.title.isEmpty ? n.app : n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${n.text}\n${dateTime(n.time)}${n.handled ? (n.betId != null ? ' · abbinata' : ' · ignorata') : ' · da abbinare'}'),
                  isThreeLine: true,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _testNotice(BuildContext context) async {
    final v = await askText(context, 'Incolla il testo di una notifica', 'Complimenti! Hai vinto 45,60 €',
        help: 'Ti mostro cosa capisce l\'app da quel testo.');
    if (v == null || !context.mounted) return;
    final p = parseNotification('', v);
    final kind = switch (p.kind) {
      NoticeKind.win => 'Vincita',
      NoticeKind.loss => 'Perdita',
      NoticeKind.unknown => 'Non riconosciuta',
    };
    toast(context, '$kind${p.amount != null ? ' · importo ${eur(p.amount!)}' : ' · nessun importo'}');
  }
}

Future<bool> _confirm(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Conferma')),
        ],
      ),
    ) ==
    true;

Future<double?> askAmount(BuildContext context, String title, double initial) async {
  final c = TextEditingController(text: initial == 0 ? '' : initial.toStringAsFixed(2).replaceAll('.', ','));
  final r = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: const InputDecoration(suffixText: '€'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        TextButton(onPressed: () => Navigator.pop(ctx, parseNumber(c.text) ?? 0), child: const Text('Salva')),
      ],
    ),
  );
  return r;
}

Future<String?> askText(BuildContext context, String title, String initial, {String? help}) async {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: c, autofocus: true, maxLines: 3, minLines: 1),
        if (help != null) ...[
          const SizedBox(height: 10),
          Text(help, style: const TextStyle(color: C.muted, fontSize: 13)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
      ],
    ),
  );
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog();
  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  bool deposit = true;
  final amount = TextEditingController();
  final note = TextEditingController();
  DateTime date = DateTime.now();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Movimento'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Ricarica')),
              ButtonSegment(value: false, label: Text('Prelievo')),
            ],
            selected: {deposit},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => deposit = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(labelText: 'Importo', suffixText: '€'),
          ),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Nota (facoltativa)')),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                  context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setState(() => date = d);
            },
            icon: const Icon(Icons.event_rounded, size: 18),
            label: Text(dateShort(date)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          TextButton(
            onPressed: () {
              final v = parseNumber(amount.text);
              if (v == null || v <= 0) return;
              Navigator.pop(context, Movement(date: date, amount: deposit ? v : -v, note: note.text.trim()));
            },
            child: const Text('Salva'),
          ),
        ],
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title, value;
  final VoidCallback onTap;
  const _Row({required this.icon, required this.title, required this.value, required this.onTap, this.iconColor});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(children: [
            Icon(icon, size: 21, color: iconColor ?? C.muted),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: C.faint),
          ]),
        ),
      );
}

class _Mini extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Mini(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: C.faint, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17)),
      ]);
}
