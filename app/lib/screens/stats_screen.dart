import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'bet_editor.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  PeriodType type = PeriodType.week;
  late Period period = Period.containing(PeriodType.week, DateTime.now());

  DateTime _allStart(AppStore s) {
    var d = s.settings.startDate;
    for (final b in s.bets) {
      if (b.placedAt.isBefore(d)) d = b.placedAt;
    }
    return d;
  }

  void _setType(PeriodType t, AppStore s) => setState(() {
        type = t;
        period = Period.containing(t, DateTime.now(), allStart: _allStart(s));
      });

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (type == PeriodType.all) {
      period = Period.containing(PeriodType.all, DateTime.now(), allStart: _allStart(store));
    }
    final p = period;
    final s = statsFor(store.bets, p);
    final prev = statsFor(store.bets, p.previous);
    final showPrev = type != PeriodType.all;
    final periodBets = store.bets.where((b) => p.contains(b.placedAt));
    final streak = streaksFor(periodBets);

    // ---- serie per il grafico a barre ----
    final labels = <String>[];
    final tips = <String>[];
    final values = <double>[];
    if (type == PeriodType.week || type == PeriodType.month) {
      for (var d = p.start; d.isBefore(p.end); d = DateTime(d.year, d.month, d.day + 1)) {
        labels.add(type == PeriodType.week ? DateFormat('E', 'it').format(d).substring(0, 2) : '${d.day}');
        tips.add(DateFormat('EEE d MMM', 'it').format(d));
        values.add(s.dailyProfit[d] ?? 0);
      }
    } else {
      final months = <DateTime>[];
      for (var m = DateTime(p.start.year, p.start.month); m.isBefore(p.end); m = DateTime(m.year, m.month + 1)) {
        months.add(m);
      }
      final shown = months.length > 24 ? months.sublist(months.length - 24) : months;
      for (final m in shown) {
        final next = DateTime(m.year, m.month + 1);
        var v = 0.0;
        s.dailyProfit.forEach((d, x) {
          if (!d.isBefore(m) && d.isBefore(next)) v += x;
        });
        labels.add(DateFormat(shown.length > 12 ? 'MMM' : 'MMM', 'it').format(m).substring(0, 3));
        tips.add(DateFormat('MMMM yyyy', 'it').format(m));
        values.add(v);
      }
    }

    final now = DateTime.now();
    final seriesEnd = p.end.isAfter(now) ? now : p.end.subtract(const Duration(days: 1));
    final series = p.isFuture ? <MapEntry<DateTime, double>>[] : balanceSeries(store, p.start, seriesEnd);
    final buckets = oddsBuckets(store.bets, p);
    final maxCatAbs = s.byCategory.values.fold<double>(0.01, (m, c) => math.max(m, c.profit.abs()));
    final maxBucket = buckets.fold<double>(0.01, (m, b) => math.max(m, b.stats.profit.abs()));

    return Responsive(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          // ---- selettore periodo ----
          SegmentedButton<PeriodType>(
            segments: [
              for (final t in PeriodType.values) ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {type},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: C.primary.withValues(alpha: 0.18),
              selectedForegroundColor: C.text,
              foregroundColor: C.muted,
              side: const BorderSide(color: C.border),
            ),
            onSelectionChanged: (v) => _setType(v.first, store),
          ),
          const SizedBox(height: 10),
          Row(children: [
            IconButton.filledTonal(
              onPressed: type == PeriodType.all ? null : () => setState(() => period = period.previous),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: GestureDetector(
                onTap: type == PeriodType.all ? null : () => _pickDay(context),
                child: Column(children: [
                  Text(p.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  if (type == PeriodType.week || type == PeriodType.all)
                    Text(
                      '${DateFormat('d MMM', 'it').format(p.start)} – ${DateFormat('d MMM yyyy', 'it').format(p.end.subtract(const Duration(days: 1)))}',
                      style: const TextStyle(color: C.faint, fontSize: 12),
                    ),
                ]),
              ),
            ),
            IconButton.filledTonal(
              onPressed: type == PeriodType.all || p.isCurrent || p.next.isFuture ? null : () => setState(() => period = period.next),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
          const SizedBox(height: 12),

          // ---- profitto + anello ----
          Panel(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [C.pl(s.profit).withValues(alpha: 0.18), C.card, C.card],
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Profitto', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(s.settled == 0 ? '–' : signedEur(s.profit),
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: s.settled == 0 ? C.faint : C.pl(s.profit), letterSpacing: -1)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    Pill('Rendimento ${pct(s.roi)}', color: C.pl(s.roi)),
                    if (showPrev && prev.settled > 0)
                      Pill('${signedEur(s.profit - prev.profit)} vs ${p.previousLabel}',
                          color: C.pl(s.profit - prev.profit),
                          icon: s.profit >= prev.profit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              RingGauge(
                value: s.winRate,
                color: s.winRate >= 0.5 ? C.win : C.pending,
                center: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(s.won + s.lost == 0 ? '–' : '${(s.winRate * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                  const Text('vinte', style: TextStyle(color: C.faint, fontSize: 11)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Panel(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(s.profit >= prev.profit ? Icons.insights_rounded : Icons.warning_amber_rounded,
                  size: 18, color: s.profit >= prev.profit ? C.win : C.loss),
              const SizedBox(width: 10),
              Expanded(child: Text(verdict(s, prev, p), style: const TextStyle(height: 1.35, fontSize: 13.5))),
            ]),
          ),
          const SizedBox(height: 10),
          TileGrid(children: [
            StatTile(
              label: 'Giocato',
              icon: Icons.payments_outlined,
              value: eur(s.staked),
              sub: showPrev ? _vs(prev.staked == 0 ? null : eur(prev.staked), p) : '${s.count} schedine',
            ),
            StatTile(
              label: 'Incassato',
              icon: Icons.savings_outlined,
              value: eur(s.returned),
              sub: showPrev ? _vs(prev.returned == 0 ? null : eur(prev.returned), p) : null,
            ),
            StatTile(
              label: 'Schedine',
              icon: Icons.receipt_long_outlined,
              value: '${s.count}',
              sub: '${s.won} V · ${s.lost} P · ${s.pending} in attesa',
            ),
            StatTile(
              label: 'Quota media',
              icon: Icons.functions_rounded,
              value: s.count == 0 ? '–' : odds(s.avgOdds),
              sub: 'puntata media ${eur(s.avgStake)}',
            ),
            StatTile(
              label: 'Miglior vincita',
              icon: Icons.emoji_events_outlined,
              value: s.bestWin <= 0 ? '–' : signedEur(s.bestWin),
              valueColor: s.bestWin > 0 ? C.win : null,
              sub: s.bestBet == null ? null : s.bestBet!.title,
            ),
            StatTile(
              label: 'Serie',
              icon: Icons.local_fire_department_outlined,
              value: streak.current == 0
                  ? '–'
                  : streak.current > 0
                      ? '${streak.current} vinte'
                      : '${-streak.current} perse',
              valueColor: streak.current > 0 ? C.win : (streak.current < 0 ? C.loss : null),
              sub: 'record ${streak.bestWin} vinte di fila',
            ),
          ]),

          // ---- grafici ----
          SectionTitle(type == PeriodType.week || type == PeriodType.month ? 'Profitto giorno per giorno' : 'Profitto mese per mese'),
          Panel(
            padding: const EdgeInsets.fromLTRB(8, 18, 14, 10),
            child: ProfitBars(labels: labels, values: values, tooltips: tips),
          ),
          const SectionTitle('Saldo nel periodo'),
          Panel(
            padding: const EdgeInsets.fromLTRB(8, 18, 14, 10),
            child: BalanceChart(series: series),
          ),
          if (type == PeriodType.month) ...[
            const SectionTitle('Calendario'),
            Panel(
              child: Column(children: [
                MonthHeatmap(
                  month: p.start,
                  dailyProfit: s.dailyProfit,
                  dailyStaked: s.dailyStaked,
                  onDayTap: (d) => _showDay(context, store, d),
                ),
                const SizedBox(height: 12),
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _Legend(color: C.win, text: 'in attivo'),
                  SizedBox(width: 14),
                  _Legend(color: C.loss, text: 'in passivo'),
                  SizedBox(width: 14),
                  _Legend(color: C.pending, text: 'in attesa'),
                ]),
              ]),
            ),
          ],

          // ---- categorie ----
          const SectionTitle('Per tipo di schedina'),
          Panel(
            child: Column(children: [
              for (final c in BetCategory.values)
                HBar(
                  label: c.label,
                  trailing: s.byCategory[c]!.staked == 0 ? '–' : signedEur(s.byCategory[c]!.profit),
                  fraction: s.byCategory[c]!.profit.abs() / maxCatAbs,
                  color: C.pl(s.byCategory[c]!.profit),
                  sub: s.byCategory[c]!.count == 0
                      ? 'nessuna schedina'
                      : '${s.byCategory[c]!.count} giocate · ${s.byCategory[c]!.won} vinte'
                          '${s.byCategory[c]!.won + s.byCategory[c]!.lost > 0 ? ' (${pct(s.byCategory[c]!.winRate, signed: false)})' : ''}'
                          ' · rendimento ${pct(s.byCategory[c]!.roi)}',
                ),
            ]),
          ),

          // ---- fasce di quota ----
          const SectionTitle('Per fascia di quota'),
          Panel(
            child: Column(children: [
              for (final b in buckets)
                HBar(
                  label: 'Quota ${b.label}',
                  trailing: b.stats.count == 0 ? '–' : signedEur(b.stats.profit),
                  fraction: b.stats.profit.abs() / maxBucket,
                  color: C.pl(b.stats.profit),
                  sub: b.stats.count == 0
                      ? 'nessuna schedina chiusa'
                      : '${b.stats.count} chiuse · ${pct(b.stats.winRate, signed: false)} vinte · rendimento ${pct(b.stats.roi)}',
                ),
            ]),
          ),

          // ---- giorni della settimana ----
          if (type != PeriodType.week) ...[
            const SectionTitle('Per giorno della settimana'),
            Panel(
              padding: const EdgeInsets.fromLTRB(8, 18, 14, 10),
              child: ProfitBars(
                labels: const ['Lu', 'Ma', 'Me', 'Gi', 'Ve', 'Sa', 'Do'],
                tooltips: const ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'],
                values: s.weekdayProfit,
                height: 170,
              ),
            ),
          ],

          // ---- confronto ----
          if (showPrev) ...[
            SectionTitle('Confronto con ${p.previousLabel}'),
            Panel(
              child: Column(children: [
                _CmpRow('Profitto', signedEur(s.profit), signedEur(prev.profit), s.profit - prev.profit, prev.settled > 0),
                _CmpRow('Rendimento', pct(s.roi), pct(prev.roi), s.roi - prev.roi, prev.settled > 0),
                _CmpRow('% vinte', pct(s.winRate, signed: false), pct(prev.winRate, signed: false), s.winRate - prev.winRate,
                    prev.won + prev.lost > 0),
                _CmpRow('Giocato', eur(s.staked), eur(prev.staked), prev.staked - s.staked, prev.count > 0, neutral: true),
                _CmpRow('Schedine', '${s.count}', '${prev.count}', 0, prev.count > 0, neutral: true),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  String? _vs(String? v, Period p) => v == null ? null : '${p.previousLabel}: $v';

  Future<void> _pickDay(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: period.start.isAfter(DateTime.now()) ? DateTime.now() : period.start,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Vai al periodo che contiene il giorno',
    );
    if (d != null) setState(() => period = Period.containing(type, d));
  }

  void _showDay(BuildContext context, AppStore store, DateTime day) {
    final bets = store.bets.where((b) => dayOf(b.placedAt) == day).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(dayHeader(day), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              if (bets.isEmpty) const Text('Nessuna schedina in questo giorno.', style: TextStyle(color: C.muted)),
              for (final b in bets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BetTile(
                    bet: b,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => BetEditor(bet: b)));
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend({required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: C.faint, fontSize: 12)),
      ]);
}

class _CmpRow extends StatelessWidget {
  final String label, now, before;
  final double diff;
  final bool hasPrev;
  final bool neutral;
  const _CmpRow(this.label, this.now, this.before, this.diff, this.hasPrev, {this.neutral = false});
  @override
  Widget build(BuildContext context) {
    final up = diff > 0.0001;
    final down = diff < -0.0001;
    final color = neutral ? C.muted : (up ? C.win : (down ? C.loss : C.muted));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(flex: 3, child: Text(label, style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600))),
        Expanded(
          flex: 3,
          child: Text(now, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        SizedBox(
          width: 30,
          child: !hasPrev || neutral
              ? const SizedBox.shrink()
              : Icon(up ? Icons.arrow_upward_rounded : (down ? Icons.arrow_downward_rounded : Icons.remove_rounded),
                  size: 16, color: color),
        ),
        Expanded(
          flex: 3,
          child: Text(hasPrev ? before : '–',
              textAlign: TextAlign.right, style: const TextStyle(color: C.faint, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
