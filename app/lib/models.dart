import 'dart:math';

enum BetStatus { pending, won, lost, voided, cashout }

extension BetStatusX on BetStatus {
  String get label => switch (this) {
        BetStatus.pending => 'In attesa',
        BetStatus.won => 'Vinta',
        BetStatus.lost => 'Persa',
        BetStatus.voided => 'Rimborsata',
        BetStatus.cashout => 'Cash out',
      };
  bool get settled => this != BetStatus.pending;
}

/// Categoria in base alla quota totale (stesse regole del tracker web).
enum BetCategory { low, mid, high }

extension BetCategoryX on BetCategory {
  String get label => switch (this) {
        BetCategory.low => 'Singola/Doppia',
        BetCategory.mid => 'Quota 5',
        BetCategory.high => 'Quota 10',
      };
  /// Nome usato nella colonna `categoria` del tracker web.
  String get dbLabel => switch (this) {
        BetCategory.low => 'Singola/Doppia',
        BetCategory.mid => 'Multipla Quota 5',
        BetCategory.high => 'Multipla Quota 10',
      };
  String get short => switch (this) {
        BetCategory.low => 'S/D',
        BetCategory.mid => 'Q5',
        BetCategory.high => 'Q10',
      };
}

BetCategory categoryForOdds(double odds) {
  if (odds < 2.5) return BetCategory.low;
  if (odds < 7) return BetCategory.mid;
  return BetCategory.high;
}

String newId() {
  final r = Random();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 30).toRadixString(36)}';
}

double _d(dynamic v, [double def = 0]) =>
    v == null ? def : (v is num ? v.toDouble() : double.tryParse('$v') ?? def);

class Selection {
  String event;
  String pick;
  double? odds;
  Selection({required this.event, this.pick = '', this.odds});

  Map<String, dynamic> toJson() => {'event': event, 'pick': pick, 'odds': odds};
  factory Selection.fromJson(Map<String, dynamic> j) => Selection(
        event: j['event'] ?? '',
        pick: j['pick'] ?? '',
        odds: j['odds'] == null ? null : _d(j['odds']),
      );
  Selection copy() => Selection(event: event, pick: pick, odds: odds);
}

class Bet {
  String id;
  DateTime placedAt;
  double stake;
  double odds;

  /// Vincita potenziale (può includere bonus). Se null = stake * odds.
  double? potentialWinOverride;
  BetStatus status;

  /// Somma effettivamente incassata (vinta, cashout o rimborso).
  double? payout;
  DateTime? settledAt;
  List<Selection> selections;
  String note;
  String? imagePath;
  bool autoSettled;

  /// id della riga su Supabase (null = non ancora salvata online).
  String? remoteId;

  /// Arrivata da una condivisione ma senza importo/quota leggibili.
  bool needsReview;

  /// Codice della giocata (es. ADM di Eplay), serve a riconoscere la stessa schedina.
  String? ticket;

  Bet({
    String? id,
    required this.placedAt,
    required this.stake,
    required this.odds,
    this.potentialWinOverride,
    this.status = BetStatus.pending,
    this.payout,
    this.settledAt,
    List<Selection>? selections,
    this.note = '',
    this.imagePath,
    this.autoSettled = false,
    this.remoteId,
    this.needsReview = false,
    this.ticket,
  })  : id = id ?? newId(),
        selections = selections ?? [];

  double get potentialWin => potentialWinOverride ?? stake * odds;
  BetCategory get category => categoryForOdds(odds);

  /// Quanto è tornato indietro (0 se persa o in attesa).
  double get returned => switch (status) {
        BetStatus.won => payout ?? potentialWin,
        BetStatus.cashout => payout ?? 0,
        BetStatus.voided => payout ?? stake,
        _ => 0,
      };

  /// Profitto netto della schedina (solo se chiusa).
  double get profit => status.settled ? returned - stake : 0;

  /// Data in cui il risultato "conta" nei grafici.
  DateTime get resultDate => settledAt ?? placedAt;

  String get title {
    if (selections.isEmpty) return note.isNotEmpty ? note : 'Schedina';
    if (selections.length == 1) return selections.first.event;
    return 'Multipla · ${selections.length} eventi';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'placedAt': placedAt.toIso8601String(),
        'stake': stake,
        'odds': odds,
        'potentialWin': potentialWinOverride,
        'status': status.name,
        'payout': payout,
        'settledAt': settledAt?.toIso8601String(),
        'selections': selections.map((e) => e.toJson()).toList(),
        'note': note,
        'imagePath': imagePath,
        'autoSettled': autoSettled,
        'remoteId': remoteId,
        'needsReview': needsReview,
        'ticket': ticket,
      };

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get esitoDb => switch (status) {
        BetStatus.won || BetStatus.cashout => 'win',
        BetStatus.lost || BetStatus.voided => 'lose',
        BetStatus.pending => 'pending',
      };

  /// Riga per la tabella `bets` (stesse colonne del tracker web + `dettagli` facoltativa).
  Map<String, dynamic> toRow({bool withDetails = true}) => {
        'tipster': 'Tu',
        'data': _date(placedAt),
        'categoria': category.dbLabel,
        'quota': odds,
        'importo': stake,
        'esito': esitoDb,
        if (withDetails)
          'dettagli': {
            'placedAt': placedAt.toIso8601String(),
            'potentialWin': potentialWinOverride,
            'payout': payout,
            'status': status.name,
            'settledAt': settledAt?.toIso8601String(),
            'selections': selections.map((e) => e.toJson()).toList(),
            'note': note,
            'autoSettled': autoSettled,
            'ticket': ticket,
          },
      };

  factory Bet.fromRow(Map<String, dynamic> r, {Bet? local}) {
    final det = r['dettagli'] is Map ? Map<String, dynamic>.from(r['dettagli']) : <String, dynamic>{};
    final esito = '${r['esito'] ?? 'pending'}';
    var status = esito == 'win'
        ? BetStatus.won
        : esito == 'lose'
            ? BetStatus.lost
            : BetStatus.pending;
    final detStatus = BetStatus.values.where((s) => s.name == det['status']).firstOrNull;
    // lo stato dettagliato vale solo se coerente con l'esito (il web può averlo cambiato)
    if (detStatus != null && Bet(placedAt: DateTime.now(), stake: 0, odds: 1, status: detStatus).esitoDb == esito) {
      status = detStatus;
    }
    final day = DateTime.tryParse('${r['data']}') ?? DateTime.now();
    var placed = DateTime.tryParse('${det['placedAt'] ?? ''}') ?? local?.placedAt;
    if (placed == null || placed.year != day.year || placed.month != day.month || placed.day != day.day) {
      placed = DateTime(day.year, day.month, day.day, 12);
    }
    final settledAt = DateTime.tryParse('${det['settledAt'] ?? ''}') ?? (status.settled ? (local?.settledAt ?? placed) : null);
    return Bet(
      id: local?.id,
      remoteId: '${r['id']}',
      placedAt: placed,
      stake: _d(r['importo']),
      odds: _d(r['quota'], 1),
      potentialWinOverride: det['potentialWin'] == null ? null : _d(det['potentialWin']),
      status: status,
      payout: status.settled && det['payout'] != null ? _d(det['payout']) : null,
      settledAt: status.settled ? settledAt : null,
      selections: det['selections'] is List
          ? (det['selections'] as List).map((e) => Selection.fromJson(Map<String, dynamic>.from(e))).toList()
          : (local?.selections ?? []),
      note: '${det['note'] ?? local?.note ?? ''}',
      imagePath: local?.imagePath,
      autoSettled: det['autoSettled'] == true || (local?.autoSettled ?? false),
      ticket: det['ticket'] ?? local?.ticket,
    );
  }

  factory Bet.fromJson(Map<String, dynamic> j) => Bet(
        id: j['id'],
        placedAt: DateTime.tryParse(j['placedAt'] ?? '') ?? DateTime.now(),
        stake: _d(j['stake']),
        odds: _d(j['odds'], 1),
        potentialWinOverride:
            j['potentialWin'] == null ? null : _d(j['potentialWin']),
        status: BetStatus.values.firstWhere((s) => s.name == j['status'],
            orElse: () => BetStatus.pending),
        payout: j['payout'] == null ? null : _d(j['payout']),
        settledAt: j['settledAt'] == null
            ? null
            : DateTime.tryParse(j['settledAt']),
        selections: ((j['selections'] as List?) ?? [])
            .map((e) => Selection.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        note: j['note'] ?? '',
        imagePath: j['imagePath'],
        autoSettled: j['autoSettled'] == true,
        remoteId: j['remoteId'],
        needsReview: j['needsReview'] == true,
        ticket: j['ticket'],
      );
}

/// Ricarica (+) o prelievo (-) dal conto.
class Movement {
  String id;
  DateTime date;
  double amount;
  String note;
  String? remoteId;
  Movement({String? id, required this.date, required this.amount, this.note = '', this.remoteId})
      : id = id ?? newId();

  Map<String, dynamic> toRow() => {
        'data': Bet._date(date),
        'importo': amount,
        'nota': note,
      };
  factory Movement.fromRow(Map<String, dynamic> r, {Movement? local}) => Movement(
        id: local?.id,
        remoteId: '${r['id']}',
        date: DateTime.tryParse('${r['data']}') ?? DateTime.now(),
        amount: _d(r['importo']),
        note: '${r['nota'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'amount': amount,
        'note': note,
        'remoteId': remoteId,
      };
  factory Movement.fromJson(Map<String, dynamic> j) => Movement(
        id: j['id'],
        remoteId: j['remoteId'],
        date: DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
        amount: _d(j['amount']),
        note: j['note'] ?? '',
      );
}

enum NoticeKind { win, loss, unknown }

/// Notifica arrivata da Eplay che non è stato possibile abbinare da sola.
class Notice {
  String id;
  DateTime time;
  String app;
  String title;
  String text;
  NoticeKind kind;
  double? amount;
  bool handled;
  String? betId;

  Notice({
    String? id,
    required this.time,
    this.app = '',
    this.title = '',
    this.text = '',
    this.kind = NoticeKind.unknown,
    this.amount,
    this.handled = false,
    this.betId,
  }) : id = id ?? newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'app': app,
        'title': title,
        'text': text,
        'kind': kind.name,
        'amount': amount,
        'handled': handled,
        'betId': betId,
      };
  factory Notice.fromJson(Map<String, dynamic> j) => Notice(
        id: j['id'],
        time: DateTime.tryParse(j['time'] ?? '') ?? DateTime.now(),
        app: j['app'] ?? '',
        title: j['title'] ?? '',
        text: j['text'] ?? '',
        kind: NoticeKind.values.firstWhere((k) => k.name == j['kind'],
            orElse: () => NoticeKind.unknown),
        amount: j['amount'] == null ? null : _d(j['amount']),
        handled: j['handled'] == true,
        betId: j['betId'],
      );
}

class AppSettings {
  double startingBankroll;
  DateTime startDate;
  double dailyLimit; // 0 = nessun limite
  String notificationKeywords;
  bool onboarded;

  AppSettings({
    this.startingBankroll = 0,
    DateTime? startDate,
    this.dailyLimit = 0,
    this.notificationKeywords = 'eplay',
    this.onboarded = false,
  }) : startDate = startDate ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'startingBankroll': startingBankroll,
        'startDate': startDate.toIso8601String(),
        'dailyLimit': dailyLimit,
        'notificationKeywords': notificationKeywords,
        'onboarded': onboarded,
      };
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        startingBankroll: _d(j['startingBankroll']),
        startDate: DateTime.tryParse(j['startDate'] ?? ''),
        dailyLimit: _d(j['dailyLimit']),
        notificationKeywords: j['notificationKeywords'] ?? 'eplay',
        onboarded: j['onboarded'] == true,
      );
}
