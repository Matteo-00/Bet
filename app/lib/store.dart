import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'native.dart';
import 'parser.dart';

class AppStore extends ChangeNotifier {
  AppSettings settings = AppSettings();
  List<Bet> bets = [];
  List<Movement> movements = [];
  List<Notice> notices = [];

  /// Messaggi brevi da mostrare (es. "Schedina segnata vinta in automatico").
  final List<String> pendingToasts = [];

  bool loaded = false;
  late Directory _dir;
  final Completer<void> _ready = Completer<void>();
  Future<void> get ready => _ready.future;

  File get _file => File('${_dir.path}/bet_tracker.json');
  Directory get shotsDir => Directory('${_dir.path}/shots');

  Future<void> load() async {
    _dir = await getApplicationDocumentsDirectory();
    if (!await shotsDir.exists()) await shotsDir.create(recursive: true);
    try {
      if (await _file.exists()) {
        _apply(jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {
      // file corrotto: proviamo il backup automatico
      final bak = File('${_file.path}.bak');
      if (await bak.exists()) {
        try {
          _apply(jsonDecode(await bak.readAsString()) as Map<String, dynamic>);
        } catch (_) {}
      }
    }
    loaded = true;
    if (!_ready.isCompleted) _ready.complete();
    notifyListeners();
    await NativeNotifications.setKeywords(settings.notificationKeywords);
    await syncNotifications();
  }

  void _apply(Map<String, dynamic> j) {
    settings = AppSettings.fromJson(Map<String, dynamic>.from(j['settings'] ?? {}));
    bets = ((j['bets'] as List?) ?? [])
        .map((e) => Bet.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    movements = ((j['movements'] as List?) ?? [])
        .map((e) => Movement.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    notices = ((j['notices'] as List?) ?? [])
        .map((e) => Notice.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _sort();
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'settings': settings.toJson(),
        'bets': bets.map((e) => e.toJson()).toList(),
        'movements': movements.map((e) => e.toJson()).toList(),
        'notices': notices.map((e) => e.toJson()).toList(),
      };

  void _sort() {
    bets.sort((a, b) => b.placedAt.compareTo(a.placedAt));
    movements.sort((a, b) => b.date.compareTo(a.date));
    notices.sort((a, b) => b.time.compareTo(a.time));
  }

  Future<void> _save() async {
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

  // ---------- Saldo ----------

  double get totalMovements => movements.fold(0, (s, m) => s + m.amount);
  double get totalStaked => bets.fold(0, (s, b) => s + b.stake);
  double get totalReturned => bets.fold(0, (s, b) => s + b.returned);

  /// Saldo = budget iniziale + ricariche − prelievi − tutte le puntate (anche in attesa) + incassi.
  double get balance =>
      settings.startingBankroll + totalMovements - totalStaked + totalReturned;

  double get pendingStake => bets
      .where((b) => b.status == BetStatus.pending)
      .fold(0, (s, b) => s + b.stake);

  double get pendingPotential => bets
      .where((b) => b.status == BetStatus.pending)
      .fold(0, (s, b) => s + b.potentialWin);

  double get netProfit => bets.fold(0, (s, b) => s + b.profit);

  double stakedOn(DateTime day) => bets
      .where((b) =>
          b.placedAt.year == day.year &&
          b.placedAt.month == day.month &&
          b.placedAt.day == day.day)
      .fold(0, (s, b) => s + b.stake);

  List<Bet> get pendingBets =>
      bets.where((b) => b.status == BetStatus.pending).toList();

  List<Notice> get openNotices => notices.where((n) => !n.handled).toList();

  // ---------- Modifiche ----------

  Future<void> upsertBet(Bet bet) async {
    final i = bets.indexWhere((b) => b.id == bet.id);
    if (i >= 0) {
      bets[i] = bet;
    } else {
      bets.add(bet);
    }
    await _save();
  }

  Future<void> deleteBet(Bet bet) async {
    bets.removeWhere((b) => b.id == bet.id);
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
    await _save();
  }

  Future<void> deleteMovement(Movement m) async {
    movements.removeWhere((x) => x.id == m.id);
    await _save();
  }

  Future<void> updateSettings(void Function(AppSettings s) change) async {
    change(settings);
    await _save();
    await NativeNotifications.setKeywords(settings.notificationKeywords);
  }

  Future<String> keepImage(String path) async {
    final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '.jpg';
    final dest = '${shotsDir.path}/${newId()}$ext';
    await File(path).copy(dest);
    return dest;
  }

  // ---------- Notifiche Eplay ----------

  List<Bet> candidatesFor(Notice n) {
    final pending = pendingBets;
    if (n.amount == null) return pending;
    final a = n.amount!;
    bool close(double v) => (v - a).abs() <= (a * 0.01).clamp(0.05, 1.0);
    final exact = pending.where((b) => close(b.potentialWin) || close(b.stake * b.odds)).toList();
    return exact;
  }

  bool _syncing = false;

  Future<void> syncNotifications() async {
    if (!loaded || _syncing) return;
    _syncing = true;
    try {
      await _syncNow();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncNow() async {
    final raw = await NativeNotifications.drain();
    if (raw.isEmpty) return;
    for (final r in raw) {
      final title = '${r['title'] ?? ''}';
      final text = '${r['text'] ?? ''}';
      final time = DateTime.fromMillisecondsSinceEpoch(
          (r['time'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch);
      // evita doppioni
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
          pendingToasts.add(
              'Vincita da Eplay: ${b.title} segnata vinta (${n.amount!.toStringAsFixed(2)} €)');
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

  // ---------- Backup ----------

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
    await _save();
    await NativeNotifications.setKeywords(settings.notificationKeywords);
  }

  Future<void> resetAll() async {
    bets.clear();
    movements.clear();
    notices.clear();
    settings = AppSettings();
    try {
      await shotsDir.delete(recursive: true);
      await shotsDir.create(recursive: true);
    } catch (_) {}
    await _save();
  }
}

class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({super.key, required AppStore store, required super.child})
      : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
