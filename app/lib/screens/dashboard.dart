import 'package:flutter/material.dart';

import '../models.dart';
import '../native.dart';
import '../stats.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'bet_editor.dart';
import 'notices.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onOpenStats;
  final VoidCallback onOpenBets;
  final bool listenerEnabled;
  final VoidCallback onCheckListener;
  const DashboardScreen({
    super.key,
    required this.onOpenStats,
    required this.onOpenBets,
    required this.listenerEnabled,
    required this.onCheckListener,
  });
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int range = 30; // giorni del grafico, 0 = tutto

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final now = DateTime.now();
    final start = store.settings.startDate;
    final chartFrom = range == 0
        ? dayOf(start)
        : dayOf(now).subtract(Duration(days: range - 1)).isBefore(dayOf(start))
            ? dayOf(start)
            : DateTime(now.year, now.month, now.day - (range - 1));
    final series = balanceSeries(store, chartFrom, now);
    final growth = store.balance - (store.settings.startingBankroll + store.totalMovements);
    final base = store.settings.startingBankroll + store.totalMovements;

    final week = Period.containing(PeriodType.week, now);
    final w = statsFor(store.bets, week);
    final lw = statsFor(store.bets, week.previous);
    final pending = store.pendingBets;
    final recent = store.bets.where((b) => b.status.settled).take(5).toList();
    final todayStaked = store.stakedOn(now);
    final limit = store.settings.dailyLimit;
    final notices = store.openNotices;

    return RefreshIndicator(
      onRefresh: () async {
        await store.syncNotifications();
        widget.onCheckListener();
      },
      child: Responsive(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: [
            // ----- Saldo -----
            Panel(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (growth >= 0 ? C.win : C.loss).withValues(alpha: 0.22),
                  C.card,
                  C.card,
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Saldo attuale', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: store.balance),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(eur(v),
                      style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Pill(
                    '${signedEur(growth)}  ${base > 0 ? pct(growth / base) : ''}',
                    color: C.pl(growth),
                    icon: growth >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  ),
                  Text('dall\'inizio (${dateShort(start)})', style: const TextStyle(color: C.faint, fontSize: 12.5)),
                ]),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final r in const [7, 30, 90, 0])
                    _RangeChip(
                      label: r == 0 ? 'Tutto' : '${r}G',
                      selected: range == r,
                      onTap: () => setState(() => range = r),
                    ),
                ]),
                const SizedBox(height: 14),
                BalanceChart(series: series, height: 190),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: _MiniStat('In gioco', eur(store.pendingStake), C.pending)),
                  Expanded(child: _MiniStat('Vincita potenziale', eur(store.pendingPotential), C.text)),
                  Expanded(child: _MiniStat('Profitto netto', signedEur(store.netProfit), C.pl(store.netProfit))),
                ]),
              ]),
            ),

            // ----- Avvisi -----
            if (!widget.listenerEnabled) ...[
              const SizedBox(height: 12),
              Panel(
                onTap: () async {
                  await showNotificationHelp(context);
                  widget.onCheckListener();
                },
                child: Row(children: [
                  const Icon(Icons.notifications_off_rounded, color: C.pending),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Attiva la lettura delle notifiche Eplay per segnare le vincite in automatico',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: C.faint),
                ]),
              ),
            ],
            if (notices.isNotEmpty) ...[
              const SizedBox(height: 12),
              Panel(
                onTap: () => showNoticesSheet(context),
                gradient: LinearGradient(colors: [C.primary.withValues(alpha: 0.18), C.card]),
                child: Row(children: [
                  const Icon(Icons.mark_email_unread_rounded, color: C.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      notices.length == 1
                          ? '1 notifica Eplay da abbinare a una schedina'
                          : '${notices.length} notifiche Eplay da abbinare',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: C.faint),
                ]),
              ),
            ],

            // ----- Settimana vs scorsa -----
            SectionTitle('Questa settimana',
                trailing: TextButton(onPressed: widget.onOpenStats, child: const Text('Statistiche'))),
            Panel(
              onTap: widget.onOpenStats,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: _Compare(title: 'Questa', value: w.profit, roi: w.roi, settled: w.settled, highlight: true)),
                  Container(width: 0.6, height: 58, color: C.border),
                  const SizedBox(width: 14),
                  Expanded(child: _Compare(title: 'Scorsa', value: lw.profit, roi: lw.roi, settled: lw.settled)),
                ]),
                const SizedBox(height: 12),
                _VerdictBox(text: verdict(w, lw, week), good: w.profit >= lw.profit),
              ]),
            ),
            const SizedBox(height: 10),
            TileGrid(children: [
              StatTile(
                label: '% vinte (sett.)',
                icon: Icons.emoji_events_outlined,
                value: w.won + w.lost == 0 ? '–' : pct(w.winRate, signed: false),
                sub: '${w.won} vinte · ${w.lost} perse',
              ),
              StatTile(
                label: 'Giocato (sett.)',
                icon: Icons.payments_outlined,
                value: eur(w.staked),
                sub: lw.staked == 0 ? '${w.count} schedine' : 'scorsa ${eur(lw.staked)}',
              ),
              if (limit > 0)
                _LimitTile(spent: todayStaked, limit: limit)
              else
                StatTile(
                  label: 'Giocato oggi',
                  icon: Icons.today_outlined,
                  value: eur(todayStaked),
                  sub: 'nessun limite impostato',
                ),
              StatTile(
                label: 'Quota media (sett.)',
                icon: Icons.functions_rounded,
                value: w.count == 0 ? '–' : odds(w.avgOdds),
                sub: lw.count == 0 ? null : 'scorsa ${odds(lw.avgOdds)}',
              ),
            ]),

            // ----- In attesa -----
            SectionTitle('In attesa (${pending.length})',
                trailing: pending.isEmpty ? null : TextButton(onPressed: widget.onOpenBets, child: const Text('Tutte'))),
            if (pending.isEmpty)
              Panel(
                child: EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'Nessuna schedina in attesa',
                  text: 'Gioca su Eplay, fai lo screenshot e condividilo con Bet Tracker. Oppure tocca +.',
                  action: FilledButton.icon(
                    onPressed: () => startAddBet(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Aggiungi schedina'),
                  ),
                ),
              )
            else
              for (final b in pending.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BetTile(
                    bet: b,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BetEditor(bet: b))),
                    onQuickSettle: (s) async {
                      await store.settle(b, s);
                      if (context.mounted) {
                        toast(context, s == BetStatus.won ? 'Vinta! +${eur(b.profit)}' : 'Segnata come persa');
                      }
                    },
                  ),
                ),

            // ----- Ultime chiuse -----
            if (recent.isNotEmpty) ...[
              const SectionTitle('Ultime chiuse'),
              for (final b in recent)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BetTile(
                    bet: b,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BetEditor(bet: b))),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RangeChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? C.text : C.cardHi,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? C.bg : C.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      );
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.faint, fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14.5)),
        ),
      ]);
}

class _Compare extends StatelessWidget {
  final String title;
  final double value, roi;
  final int settled;
  final bool highlight;
  const _Compare({required this.title, required this.value, required this.roi, required this.settled, this.highlight = false});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: highlight ? C.text : C.muted, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(settled == 0 ? '–' : signedEur(value),
              style: TextStyle(
                  fontSize: highlight ? 24 : 20,
                  fontWeight: FontWeight.w900,
                  color: settled == 0 ? C.faint : C.pl(value),
                  letterSpacing: -0.5)),
        ),
        const SizedBox(height: 2),
        Text(settled == 0 ? 'nessuna chiusa' : 'rendimento ${pct(roi)}',
            style: const TextStyle(color: C.faint, fontSize: 12, fontWeight: FontWeight.w600)),
      ]);
}

class _VerdictBox extends StatelessWidget {
  final String text;
  final bool good;
  const _VerdictBox({required this.text, required this.good});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (good ? C.win : C.loss).withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(good ? Icons.insights_rounded : Icons.warning_amber_rounded, size: 18, color: good ? C.win : C.loss),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35, fontSize: 13.5))),
        ]),
      );
}

class _LimitTile extends StatelessWidget {
  final double spent, limit;
  const _LimitTile({required this.spent, required this.limit});
  @override
  Widget build(BuildContext context) {
    final f = (spent / limit).clamp(0.0, 1.0);
    final over = spent > limit;
    final color = over ? C.loss : (f > 0.8 ? C.pending : C.primary);
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.speed_rounded, size: 15, color: C.muted),
          SizedBox(width: 6),
          Text('Limite di oggi', style: TextStyle(color: C.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('${eur(spent)} / ${eur(limit, compact: true)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: over ? C.loss : C.text)),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(value: f, minHeight: 7, color: color, backgroundColor: C.border),
        ),
      ]),
    );
  }
}

/// Spiega come attivare l'accesso alle notifiche (anche le "impostazioni con restrizioni" di Android 13+).
Future<void> showNotificationHelp(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Vincite automatiche da Eplay',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
            'Quando Eplay ti manda la notifica di una vincita, Bet Tracker la legge, trova la schedina con '
            'la stessa vincita potenziale e la segna vinta da sola. Legge solo le notifiche che contengono '
            '"eplay" (puoi cambiarlo nelle impostazioni).',
            style: TextStyle(color: C.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          const _Step(n: 1, text: 'Tocca "Apri impostazioni notifiche" e attiva Bet Tracker.'),
          const _Step(
              n: 2,
              text: 'Se l\'interruttore è grigio ("Impostazione con restrizioni"): tocca "Info app", '
                  'poi i tre puntini in alto a destra → "Consenti impostazioni con restrizioni", e riprova.'),
          const _Step(n: 3, text: 'Torna qui: il banner sparirà quando l\'accesso è attivo.'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: NativeNotifications.openAppDetails,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Info app'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: NativeNotifications.openSettings,
                child: const Text('Apri impostazioni notifiche'),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: C.primary.withValues(alpha: 0.18),
            child: Text('$n', style: const TextStyle(color: C.primary, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ]),
      );
}
