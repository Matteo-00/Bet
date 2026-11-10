import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'native.dart';
import 'ocr.dart';
import 'parser.dart';
import 'remote.dart';
import 'stats.dart';

enum SyncState { idle, syncing, offline, error }

/// Dati dell'app: copia locale (funziona anche offline) sincronizzata con Supabase.
class AppStore extends ChangeNotifier {
  AppSettings settings = AppSettings();
  List<Bet> bets = [];
  List<Movement> movements = [];
  List<Notice> notices = [];

  /// Operazioni da inviare a Supabase (restano qui se si è offline).
  List<Map<String, dynamic>> outbox = [];
  bool remoteHasDetails = true;
  bool remoteHasMovements = true;
  DateTime? lastSync;
  String? lastError;
  SyncState syncState = SyncState.idle;

  /// Messaggi brevi da mostrare (es. "Schedina segnata vinta in automatico").
  final List<String> pendingToasts = [];

  bool loaded = false;
  late Directory _dir;
  final Completer<void> _ready = Completer<void>();
  Future<void> get ready => _ready.future;

  File get _file => File('${_dir.path}/bet_tracker.json');
  Directory get shotsDir => Directory('${_dir.path}/shots');

  // ======================================================================
  // Caricamento / salvataggio locale
  // ======================================================================

  Future<void> load({bool pull = true}) async {
    _dir = await getApplicationDocumentsDirectory();
    if (!await shotsDir.exists()) await shotsDir.create(recursive: true);
    await _readLocal();
    loaded = true;
    if (!_ready.isCompleted) _ready.complete();
    notifyListeners();
    await NativeNotifications.setKeywords(settings.notificationKeywords);
    if (pull) {
      await sync();
      await syncNotifications();
    }
  }

  Future<void> _readLocal() async {
    try {
      if (await _file.exists()) {
        _apply(jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {
      final bak = File('${_file.path}.bak');
      if (await bak.exists()) {
        try {
          _apply(jsonDecode(await bak.readAsString()) as Map<String, dynamic>);
        } catch (_) {}
      }
    }
  }

  /// Rilegge il file (può averlo scritto la condivisione in background) e sincronizza.
  Future<void> reload() async {
    if (!loaded) return;
    await _readLocal();
    notifyListeners();
    await sync();
  }

  void _apply(Map<String, dynamic> j) {
    settings = AppSettings.fromJson(Map<String, dynamic>.from(j['settings'] ?? {}));
    bets = ((j['bets'] as List?) ?? []).map((e) => Bet.fromJson(Map<String, dynamic>.from(e))).toList();
    movements =
        ((j['movements'] as List?) ?? []).map((e) => Movement.fromJson(Map<String, dynamic>.from(e))).toList();
    notices = ((j['notices'] as List?) ?? []).map((e) => Notice.fromJson(Map<String, dynamic>.from(e))).toList();
    outbox = ((j['outbox'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    final r = Map<String, dynamic>.from(j['remote'] ?? {});
    remoteHasDetails = r['hasDetails'] != false;
    remoteHasMovements = r['hasMovements'] != false;
    lastSync = DateTime.tryParse('${r['lastSync'] ?? ''}');
    _sort();
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'settings': settings.toJson(),
        'bets': bets.map((e) => e.toJson()).toList(),
        'movements': movements.map((e) => e.toJson()).toList(),
        'notices': notices.map((e) => e.toJson()).toList(),
        'outbox': outbox,
        'remote': {
          'hasDetails': remoteHasDetails,
          'hasMovements': remoteHasMovements,
          'lastSync': lastSync?.toIso8601String(),
        },
      };

  void _sort() {
    bets.sort((a, b) => b.placedAt.compareTo(a.placedAt));
    movements.sort((a, b) => b.date.compareTo(a.date));
    notices.sort((a, b) => b.time.compareTo(a.time));
  }

  Future<void> _saveLocal() async {
    _sort();
    notifyListeners();
    final data = const JsonEncoder.withIndent(' ').convert(toJson());
    if (await _file.exists()) {
      await _file.copy('${_file.path}.bak');
    }
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(_file.path);
  }

  /// Salva in locale e prova subito a mandare le modifiche su Supabase.
  Future<void> _save() async {
    await _saveLocal();
    unawaited(_flush());
  }

  // ======================================================================
  // Sincronizzazione con Supabase
  // ======================================================================

  void _enqueue(Map<String, dynamic> op) {
    outbox.removeWhere((o) => o['k'] == op['k'] && o['id'] != null && o['id'] == op['id']);
    if (op['k'] == 'bank') outbox.removeWhere((o) => o['k'] == 'bank');
    outbox.add(op);
  }

  int get pendingOps => outbox.length;

  bool _isNetwork(Object e) =>
      e is SocketException || e is TimeoutException || e is HttpException || e.toString().contains('ClientException');

  Future<void> sync() async {
    if (!loaded) return;
    await _flush();
    await _pull();
  }

  bool _flushing = false;

  Future<bool> _flush() async {
    if (_flushing) return false;
    _flushing = true;
    var changed = false;
    try {
      while (outbox.isNotEmpty) {
        final op = outbox.first;
        try {
          await _run(op);
          outbox.remove(op);
          changed = true;
        } on RemoteError catch (e) {
          if (e.missingColumn && remoteHasDetails) {
            remoteHasDetails = false;
            continue; // riprova senza la colonna `dettagli`
          }
          if (e.missingTable && op['k'].toString().startsWith('mov')) {
            remoteHasMovements = false;
            outbox.remove(op);
            continue;
          }
          lastError = e.toString();
          outbox.remove(op); // errore definitivo: non bloccare la coda
          changed = true;
        } catch (e) {
          if (_isNetwork(e)) {
            syncState = SyncState.offline;
            notifyListeners();
            break;
          }
          lastError = e.toString();
          outbox.remove(op);
          changed = true;
        }
      }
      if (outbox.isEmpty && syncState == SyncState.offline) syncState = SyncState.idle;
    } finally {
      _flushing = false;
    }
    if (changed) await _saveLocal();
    return outbox.isEmpty;
  }

  Future<void> _run(Map<String, dynamic> op) async {
    final k = op['k'];
    if (k == 'bet') {
      final b = bets.where((x) => x.id == op['id']).firstOrNull;
      if (b == null || b.needsReview) return;
      final row = b.toRow(withDetails: remoteHasDetails);
      if (b.remoteId == null) {
        final res = await Remote.insert('bets', row);
        b.remoteId = '${res['id']}';
      } else {
        await Remote.update('bets', b.remoteId!, row);
      }
    } else if (k == 'betDel') {
      await Remote.delete('bets', '${op['rid']}');
    } else if (k == 'bank') {
      await Remote.upsert('bankroll', {
        'id': appBankrollId,
        'start_amount': settings.startingBankroll,
        'start_date': Bet(placedAt: settings.startDate, stake: 0, odds: 1).toRow(withDetails: false)['data'],
      });
    } else if (k == 'mov') {
      if (!remoteHasMovements) return;
      final m = movements.where((x) => x.id == op['id']).firstOrNull;
      if (m == null) return;
      if (m.remoteId == null) {
        final res = await Remote.insert('movimenti', m.toRow());
        m.remoteId = '${res['id']}';
      } else {
        await Remote.update('movimenti', m.remoteId!, m.toRow());
      }
    } else if (k == 'movDel') {
      if (!remoteHasMovements) return;
      await Remote.delete('movimenti', '${op['rid']}');
    }
  }

  Future<void> _pull() async {
    syncState = SyncState.syncing;
    notifyListeners();
    try {
      // budget
      final bank = await Remote.select('bankroll', 'id=eq.$appBankrollId&select=*');
      if (bank.isNotEmpty && !outbox.any((o) => o['k'] == 'bank')) {
        settings.startingBankroll = double.tryParse('${bank.first['start_amount']}') ?? settings.startingBankroll;
        settings.startDate = DateTime.tryParse('${bank.first['start_date']}') ?? settings.startDate;
        settings.onboarded = true;
      }

      // schedine
      final rows = await Remote.select('bets', 'tipster=eq.$appTipster&select=*&order=data.desc');
      final byRemote = {for (final b in bets) if (b.remoteId != null) b.remoteId!: b};
      final pendingIds = outbox.where((o) => o['k'] == 'bet').map((o) => o['id']).toSet();
      final deleting = outbox.where((o) => o['k'] == 'betDel').map((o) => '${o['rid']}').toSet();
      final next = <Bet>[];
      final seen = <String>{};
      for (final r in rows) {
        final rid = '${r['id']}';
        if (deleting.contains(rid)) continue;
        seen.add(rid);
        final local = byRemote[rid];
        if (local != null && pendingIds.contains(local.id)) {
          next.add(local);
        } else {
          next.add(Bet.fromRow(r, local: local));
        }
      }
      // schedine solo locali (non ancora inviate o da completare)
      for (final b in bets) {
        if (b.remoteId == null) next.add(b);
      }
      bets = next;

      // ricariche / prelievi
      if (remoteHasMovements) {
        try {
          final mrows = await Remote.select('movimenti', 'select=*&order=data.desc');
          final byR = {for (final m in movements) if (m.remoteId != null) m.remoteId!: m};
          final mdel = outbox.where((o) => o['k'] == 'movDel').map((o) => '${o['rid']}').toSet();
          movements = [
            for (final r in mrows)
              if (!mdel.contains('${r['id']}')) Movement.fromRow(r, local: byR['${r['id']}']),
            ...movements.where((m) => m.remoteId == null),
          ];
        } on RemoteError catch (e) {
          if (e.missingTable) remoteHasMovements = false;
        }
      }

      lastSync = DateTime.now();
      lastError = null;
      syncState = outbox.isEmpty ? SyncState.idle : SyncState.offline;
    } on RemoteError catch (e) {
      lastError = e.toString();
      syncState = SyncState.error;
    } catch (e) {
      syncState = _isNetwork(e) ? SyncState.offline : SyncState.error;
      if (!_isNetwork(e)) lastError = e.toString();
    }
    await _saveLocal();
  }

  // ======================================================================
  // Saldo
  // ======================================================================

  bool _inRange(DateTime d) => !d.isBefore(dayOf(settings.startDate));

  Iterable<Bet> get activeBets => bets.where((b) => !b.needsReview && _inRange(b.placedAt));

  double get totalMovements => movements.where((m) => _inRange(m.date)).fold(0, (s, m) => s + m.amount);
  double get totalStaked => activeBets.fold(0, (s, b) => s + b.stake);
  double get totalReturned => activeBets.fold(0, (s, b) => s + b.returned);

  /// Saldo = budget iniziale + ricariche − prelievi − tutte le puntate (anche in attesa) + incassi.
  double get balance => settings.startingBankroll + totalMovements - totalStaked + totalReturned;

  double get pendingStake =>
      activeBets.where((b) => b.status == BetStatus.pending).fold(0, (s, b) => s + b.stake);

  double get pendingPotential =>
      activeBets.where((b) => b.status == BetStatus.pending).fold(0, (s, b) => s + b.potentialWin);

  double get netProfit => activeBets.fold(0, (s, b) => s + b.profit);

  double stakedOn(DateTime day) => bets
      .where((b) =>
          !b.needsReview &&
          b.placedAt.year == day.year &&
          b.placedAt.month == day.month &&
          b.placedAt.day == day.day)
      .fold(0, (s, b) => s + b.stake);

  List<Bet> get pendingBets => bets.where((b) => b.status == BetStatus.pending && !b.needsReview).toList();
  List<Bet> get reviewBets => bets.where((b) => b.needsReview).toList();

  List<Notice> get openNotices => notices.where((n) => !n.handled).toList();

  // ======================================================================
  // Modifiche
  // ======================================================================

  Future<void> upsertBet(Bet bet) async {
    final i = bets.indexWhere((b) => b.id == bet.id);
    if (i >= 0) {
      bets[i] = bet;
    } else {
      bets.add(bet);
    }
    _enqueue({'k': 'bet', 'id': bet.id});
    await _save();
  }

  Future<void> deleteBet(Bet bet) async {
    bets.removeWhere((b) => b.id == bet.id);
    outbox.removeWhere((o) => o['k'] == 'bet' && o['id'] == bet.id);
    if (bet.remoteId != null) _enqueue({'k': 'betDel', 'rid': bet.remoteId});
    if (bet.imagePath != null) {
      try {
        await File(bet.imagePath!).delete();
      } catch (_) {}
    }
    await _save();
  }

  Future<void> settle(Bet bet, BetStatus status, {double? payout}) async {
    bet.status = status;
    bet.payout = payout;
    bet.settledAt = status.settled ? (bet.settledAt ?? DateTime.now()) : null;
    if (!status.settled) bet.autoSettled = false;
    await upsertBet(bet);
  }

  Future<void> addMovement(Movement m) async {
    movements.add(m);
    _enqueue({'k': 'mov', 'id': m.id});
    await _save();
  }

  Future<void> deleteMovement(Movement m) async {
    movements.removeWhere((x) => x.id == m.id);
    outbox.removeWhere((o) => o['k'] == 'mov' && o['id'] == m.id);
    if (m.remoteId != null) _enqueue({'k': 'movDel', 'rid': m.remoteId});
    await _save();
  }

  Future<void> updateSettings(void Function(AppSettings s) change) async {
    final before = '${settings.startingBankroll}|${settings.startDate}';
    change(settings);
    if ('${settings.startingBankroll}|${settings.startDate}' != before) _enqueue({'k': 'bank'});
    await _save();
    await NativeNotifications.setKeywords(settings.notificationKeywords);
  }

  Future<String> keepImage(String path) async {
    final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '.jpg';
    final dest = '${shotsDir.path}/${newId()}${ext.length > 5 ? '.jpg' : ext}';
    await File(path).copy(dest);
    return dest;
  }

  // ======================================================================
  // Condivisione in background: screenshot -> schedina salvata
  // ======================================================================

  /// Usato dalla condivisione "silenziosa" (senza aprire l'app). Restituisce il messaggio da mostrare.
  Future<String> registerSharedImages(List<String> paths) async {
    final msgs = <String>[];
    for (final p in paths) {
      final kept = await keepImage(p);
      final d = await recognizeSlip(kept);
      final ok = d.stake != null && d.stake! > 0 && d.odds != null && d.odds! >= 1.01;
      final placed = d.placedAt ?? DateTime.now();
      if (ok) {
        final dup = bets.any((b) =>
            (b.stake - d.stake!).abs() < 0.01 &&
            (b.odds - d.odds!).abs() < 0.01 &&
            b.placedAt.difference(placed).inMinutes.abs() < 10);
        if (dup) {
          msgs.add('Schedina già registrata');
          try {
            await File(kept).delete();
          } catch (_) {}
          continue;
        }
      }
      final bet = Bet(
        placedAt: placed,
        stake: d.stake ?? 0,
        odds: d.odds ?? 0,
        potentialWinOverride: (ok && d.potentialWin != null && (d.potentialWin! - d.stake! * d.odds!).abs() > 0.05)
            ? d.potentialWin
            : null,
        selections: d.selections,
        imagePath: kept,
        needsReview: !ok,
      );
      bets.add(bet);
      if (ok) {
        _enqueue({'k': 'bet', 'id': bet.id});
        msgs.add('Schedina registrata: ${_e(bet.stake)} @ ${bet.odds.toStringAsFixed(2).replaceAll('.', ',')}'
            ' → ${_e(bet.potentialWin)}');
      } else {
        msgs.add('Screenshot salvato, ma non ho letto importo/quota: completala in Bet Tracker');
      }
    }
    await _saveLocal();
    await _flush();
    if (outbox.any((o) => o['k'] == 'bet')) {
      msgs.add('(sarà caricata online appena c\'è connessione)');
    }
    return msgs.join('\n');
  }

  String _e(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  // ======================================================================
  // Notifiche Eplay
  // ======================================================================

  List<Bet> candidatesFor(Notice n) {
    final pending = pendingBets;
    if (n.amount == null) return pending;
    final a = n.amount!;
    bool close(double v) => (v - a).abs() <= (a * 0.01).clamp(0.05, 1.0);
    return pending.where((b) => close(b.potentialWin) || close(b.stake * b.odds)).toList();
  }

  bool _syncingN = false;

  Future<void> syncNotifications() async {
    if (!loaded || _syncingN) return;
    _syncingN = true;
    try {
      await _syncNotificationsNow();
    } finally {
      _syncingN = false;
    }
  }

  Future<void> _syncNotificationsNow() async {
    final raw = await NativeNotifications.drain();
    if (raw.isEmpty) return;
    for (final r in raw) {
      final title = '${r['title'] ?? ''}';
      final text = '${r['text'] ?? ''}';
      final time = DateTime.fromMillisecondsSinceEpoch(
          (r['time'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch);
      if (notices.any((n) => n.time == time && n.text == text && n.title == title)) continue;
      final p = parseNotification(title, text);
      final n = Notice(
        time: time,
        app: '${r['app'] ?? r['pkg'] ?? ''}',
        title: title,
        text: text,
        kind: p.kind,
        amount: p.amount,
      );
      if (n.kind == NoticeKind.win) {
        final c = candidatesFor(n);
        if (n.amount != null && c.length == 1) {
          final b = c.first;
          b.status = BetStatus.won;
          b.payout = n.amount;
          b.settledAt = time;
          b.autoSettled = true;
          n.handled = true;
          n.betId = b.id;
          _enqueue({'k': 'bet', 'id': b.id});
          pendingToasts.add('Vincita da Eplay: ${b.title} segnata vinta (${_e(n.amount!)})');
        }
      }
      notices.add(n);
    }
    if (notices.length > 200) {
      _sort();
      notices = notices.take(200).toList();
    }
    await _save();
  }

  Future<void> resolveNotice(Notice n, Bet? bet) async {
    n.handled = true;
    if (bet != null) {
      n.betId = bet.id;
      if (n.kind == NoticeKind.loss) {
        bet.status = BetStatus.lost;
        bet.payout = null;
      } else {
        bet.status = BetStatus.won;
        bet.payout = n.amount ?? bet.potentialWin;
      }
      bet.settledAt = n.time;
      bet.autoSettled = true;
      await upsertBet(bet);
    } else {
      await _save();
    }
  }

  // ======================================================================
  // Backup
  // ======================================================================

  Future<File> exportBackup() async {
    final tmp = await getTemporaryDirectory();
    final now = DateTime.now();
    final f = File(
        '${tmp.path}/bet_tracker_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json');
    await f.writeAsString(const JsonEncoder.withIndent(' ').convert(toJson()));
    return f;
  }

  Future<void> importBackup(String path) async {
    final j = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    if (j['bets'] == null || j['settings'] == null) {
      throw const FormatException('File non valido');
    }
    _apply(j);
    for (final b in bets) {
      _enqueue({'k': 'bet', 'id': b.id});
    }
    _enqueue({'k': 'bank'});
    await _save();
    await NativeNotifications.setKeywords(settings.notificationKeywords);
  }

  /// Svuota la copia sul telefono e riscarica tutto dal database.
  Future<void> redownload() async {
    final keepSettings = settings;
    bets.clear();
    movements.clear();
    outbox.clear();
    settings = keepSettings;
    await _saveLocal();
    await _pull();
  }
}

class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppStore read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
