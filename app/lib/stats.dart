import 'package:intl/intl.dart';

import 'models.dart';
import 'store.dart';

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

enum PeriodType { week, month, year, all }

extension PeriodTypeX on PeriodType {
  String get label => switch (this) {
        PeriodType.week => 'Settimana',
        PeriodType.month => 'Mese',
        PeriodType.year => 'Anno',
        PeriodType.all => 'Tutto',
      };
}

class Period {
  final PeriodType type;
  final DateTime start; // incluso
  final DateTime end; // escluso
  const Period(this.type, this.start, this.end);

  factory Period.containing(PeriodType type, DateTime d, {DateTime? allStart}) {
    final day = dayOf(d);
    switch (type) {
      case PeriodType.week:
        final s = DateTime(day.year, day.month, day.day - (day.weekday - 1));
        return Period(type, s, DateTime(s.year, s.month, s.day + 7));
      case PeriodType.month:
        return Period(type, DateTime(d.year, d.month), DateTime(d.year, d.month + 1));
      case PeriodType.year:
        return Period(type, DateTime(d.year), DateTime(d.year + 1));
      case PeriodType.all:
        return Period(type, dayOf(allStart ?? DateTime(2000)),
            DateTime(day.year, day.month, day.day + 1));
    }
  }

  Period get previous => switch (type) {
        PeriodType.week => Period(type, DateTime(start.year, start.month, start.day - 7), start),
        PeriodType.month => Period(type, DateTime(start.year, start.month - 1), start),
        PeriodType.year => Period(type, DateTime(start.year - 1), start),
        PeriodType.all => this,
      };

  Period get next => switch (type) {
        PeriodType.week => Period(type, end, DateTime(end.year, end.month, end.day + 7)),
        PeriodType.month => Period(type, end, DateTime(end.year, end.month + 1)),
        PeriodType.year => Period(type, end, DateTime(end.year + 1)),
        PeriodType.all => this,
      };

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
  bool get isCurrent => contains(DateTime.now());
  bool get isFuture => start.isAfter(DateTime.now());

  int get days => end.difference(start).inDays;

  String get label {
    switch (type) {
      case PeriodType.week:
        final last = end.subtract(const Duration(days: 1));
        if (isCurrent) return 'Questa settimana';
        if (previousOfNow) return 'Settimana scorsa';
        final f = DateFormat('d MMM', 'it');
        return '${f.format(start)} – ${f.format(last)}';
      case PeriodType.month:
        return _cap(DateFormat('MMMM yyyy', 'it').format(start));
      case PeriodType.year:
        return '${start.year}';
      case PeriodType.all:
        return 'Da sempre';
    }
  }

  bool get previousOfNow =>
      Period.containing(type, DateTime.now()).previous.start == start;

  String get previousLabel => switch (type) {
        PeriodType.week => 'sett. prima',
        PeriodType.month => 'mese prima',
        PeriodType.year => 'anno prima',
        PeriodType.all => '',
      };
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class CatStats {
  int count = 0, won = 0, lost = 0;
  double staked = 0, returned = 0;
  double get profit => returned - staked;
  double get roi => staked == 0 ? 0 : profit / staked;
  double get winRate => (won + lost) == 0 ? 0 : won / (won + lost);
}

class PeriodStats {
  int count = 0, won = 0, lost = 0, pending = 0, other = 0;
  double staked = 0; // tutte le puntate del periodo
  double stakedSettled = 0;
  double returned = 0;
  double oddsSum = 0;
  double bestWin = 0;
  Bet? bestBet;
  final Map<BetCategory, CatStats> byCategory = {
    for (final c in BetCategory.values) c: CatStats()
  };
  final Map<DateTime, double> dailyProfit = {};
  final Map<DateTime, double> dailyStaked = {};
  final List<double> weekdayProfit = List.filled(7, 0);
  final List<int> weekdayCount = List.filled(7, 0);

  double get profit => returned - stakedSettled;
  double get roi => stakedSettled == 0 ? 0 : profit / stakedSettled;
  double get winRate => (won + lost) == 0 ? 0 : won / (won + lost);
  double get avgOdds => count == 0 ? 0 : oddsSum / count;
  double get avgStake => count == 0 ? 0 : staked / count;
  int get settled => won + lost + other;
}

PeriodStats statsFor(Iterable<Bet> bets, Period p) {
  final s = PeriodStats();
  for (final b in bets) {
    if (b.needsReview || !p.contains(b.placedAt)) continue;
    final day = dayOf(b.placedAt);
    s.count++;
    s.staked += b.stake;
    s.oddsSum += b.odds;
    s.dailyStaked[day] = (s.dailyStaked[day] ?? 0) + b.stake;
    final c = s.byCategory[b.category]!;
    c.count++;
    switch (b.status) {
      case BetStatus.pending:
        s.pending++;
        continue;
      case BetStatus.won:
        s.won++;
        c.won++;
      case BetStatus.lost:
        s.lost++;
        c.lost++;
      default:
        s.other++;
    }
    s.stakedSettled += b.stake;
    s.returned += b.returned;
    c.staked += b.stake;
    c.returned += b.returned;
    s.dailyProfit[day] = (s.dailyProfit[day] ?? 0) + b.profit;
    s.weekdayProfit[b.placedAt.weekday - 1] += b.profit;
    s.weekdayCount[b.placedAt.weekday - 1]++;
    if (b.profit > s.bestWin) {
      s.bestWin = b.profit;
      s.bestBet = b;
    }
  }
  return s;
}

/// Andamento del saldo giorno per giorno (valore a fine giornata).
List<MapEntry<DateTime, double>> balanceSeries(AppStore store, DateTime from, DateTime to) {
  final events = <MapEntry<DateTime, double>>[];
  final startDay = dayOf(store.settings.startDate);
  for (final m in store.movements) {
    if (!m.date.isBefore(startDay)) events.add(MapEntry(m.date, m.amount));
  }
  for (final b in store.activeBets) {
    events.add(MapEntry(b.placedAt, -b.stake));
    if (b.status.settled && b.returned != 0) {
      events.add(MapEntry(b.resultDate, b.returned));
    }
  }
  events.sort((a, b) => a.key.compareTo(b.key));
  var bal = store.settings.startingBankroll;
  var i = 0;
  final start = dayOf(from);
  // tutto quello che è successo prima dell'inizio
  while (i < events.length && events[i].key.isBefore(start)) {
    bal += events[i].value;
    i++;
  }
  final out = <MapEntry<DateTime, double>>[];
  for (var d = start; !d.isAfter(dayOf(to)); d = DateTime(d.year, d.month, d.day + 1)) {
    final next = DateTime(d.year, d.month, d.day + 1);
    while (i < events.length && events[i].key.isBefore(next)) {
      bal += events[i].value;
      i++;
    }
    out.add(MapEntry(d, bal));
  }
  return out;
}

/// Statistiche per fascia di quota.
class OddsBucket {
  final String label;
  final double min, max;
  final CatStats stats = CatStats();
  OddsBucket(this.label, this.min, this.max);
}

List<OddsBucket> oddsBuckets(Iterable<Bet> bets, Period p) {
  final buckets = [
    OddsBucket('< 1,50', 0, 1.5),
    OddsBucket('1,50–2,50', 1.5, 2.5),
    OddsBucket('2,50–5', 2.5, 5),
    OddsBucket('5–10', 5, 10),
    OddsBucket('> 10', 10, double.infinity),
  ];
  for (final b in bets) {
    if (b.needsReview || !p.contains(b.placedAt) || !b.status.settled) continue;
    final k = buckets.firstWhere((x) => b.odds >= x.min && b.odds < x.max,
        orElse: () => buckets.last);
    k.stats.count++;
    if (b.status == BetStatus.won) k.stats.won++;
    if (b.status == BetStatus.lost) k.stats.lost++;
    k.stats.staked += b.stake;
    k.stats.returned += b.returned;
  }
  return buckets;
}

class Streaks {
  int current = 0; // >0 vittorie di fila, <0 sconfitte di fila
  int bestWin = 0;
  int worstLoss = 0;
}

Streaks streaksFor(Iterable<Bet> bets) {
  final settled = bets
      .where((b) => b.status == BetStatus.won || b.status == BetStatus.lost)
      .toList()
    ..sort((a, b) => a.resultDate.compareTo(b.resultDate));
  final s = Streaks();
  var run = 0;
  for (final b in settled) {
    final w = b.status == BetStatus.won;
    if (w) {
      run = run > 0 ? run + 1 : 1;
      if (run > s.bestWin) s.bestWin = run;
    } else {
      run = run < 0 ? run - 1 : -1;
      if (-run > s.worstLoss) s.worstLoss = -run;
    }
  }
  s.current = run;
  return s;
}

/// Frase riassuntiva: sto andando meglio o peggio del periodo precedente?
String verdict(PeriodStats now, PeriodStats before, Period p) {
  final prevName = switch (p.type) {
    PeriodType.week => 'della settimana prima',
    PeriodType.month => 'del mese prima',
    PeriodType.year => "dell'anno prima",
    PeriodType.all => '',
  };
  if (now.settled == 0 && now.pending == 0) {
    return 'Nessuna schedina in questo periodo.';
  }
  if (now.settled == 0) {
    return 'Hai ${now.pending} schedin${now.pending == 1 ? 'a' : 'e'} in attesa: il bilancio arriverà con i risultati.';
  }
  if (p.type == PeriodType.all) {
    return now.profit >= 0
        ? 'In totale sei in attivo: ogni 10 € giocati ne sono tornati ${(10 * (1 + now.roi)).toStringAsFixed(2).replaceAll('.', ',')}.'
        : 'In totale sei in passivo: ogni 10 € giocati ne sono tornati ${(10 * (1 + now.roi)).toStringAsFixed(2).replaceAll('.', ',')}.';
  }
  if (before.settled == 0) {
    return now.profit >= 0
        ? 'Periodo in attivo. Non ci sono dati $prevName per confrontare.'
        : 'Periodo in passivo. Non ci sono dati $prevName per confrontare.';
  }
  final diff = now.profit - before.profit;
  final roiDiff = (now.roi - before.roi) * 100;
  if (diff.abs() < 0.5) return 'Risultato in linea con quello $prevName.';
  final better = diff > 0;
  return better
      ? 'Stai facendo meglio $prevName: ${_eur(diff)} in più e rendimento ${roiDiff >= 0 ? '+' : ''}${roiDiff.toStringAsFixed(0)} punti.'
      : 'Stai facendo peggio $prevName: ${_eur(-diff)} in meno e rendimento ${roiDiff >= 0 ? '+' : ''}${roiDiff.toStringAsFixed(0)} punti.';
}

String _eur(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';
