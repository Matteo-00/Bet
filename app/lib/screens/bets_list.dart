import 'package:flutter/material.dart';

import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'bet_editor.dart';

class BetsListScreen extends StatefulWidget {
  const BetsListScreen({super.key});
  @override
  State<BetsListScreen> createState() => _BetsListScreenState();
}

class _BetsListScreenState extends State<BetsListScreen> {
  BetStatus? filter;
  BetCategory? cat;
  String query = '';

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final q = query.toLowerCase();
    final list = store.bets.where((b) {
      if (filter != null && b.status != filter) return false;
      if (cat != null && b.category != cat) return false;
      if (q.isNotEmpty) {
        final hay = '${b.title} ${b.note} ${b.selections.map((s) => '${s.event} ${s.pick}').join(' ')}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    final groups = <DateTime, List<Bet>>{};
    for (final b in list) {
      groups.putIfAbsent(dayOf(b.placedAt), () => []).add(b);
    }

    return Responsive(
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Cerca squadra, esito, nota…',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _chip('Tutte', filter == null, () => setState(() => filter = null)),
                for (final s in [BetStatus.pending, BetStatus.won, BetStatus.lost])
                  _chip(s.label, filter == s, () => setState(() => filter = filter == s ? null : s), color: statusColor(s)),
                const SizedBox(width: 10),
                for (final c in BetCategory.values)
                  _chip(c.label, cat == c, () => setState(() => cat = cat == c ? null : c), color: C.blue),
              ],
            ),
          ),
        ),
        if (list.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.inbox_rounded,
              title: 'Nessuna schedina',
              text: 'Qui trovi tutte le schedine salvate, divise per giorno.',
            ),
          ),
        for (final e in groups.entries) ...[
          SliverToBoxAdapter(child: _DayHeader(day: e.key, bets: e.value)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: e.value.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final b = e.value[i];
                return BetTile(
                  bet: b,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BetEditor(bet: b))),
                  onQuickSettle: (s) => store.settle(b, s),
                );
              },
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ]),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap, {Color color = C.primary}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label),
          selected: sel,
          showCheckmark: false,
          selectedColor: color.withValues(alpha: 0.2),
          side: BorderSide(color: sel ? color : C.border),
          onSelected: (_) => onTap(),
        ),
      );
}

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final List<Bet> bets;
  const _DayHeader({required this.day, required this.bets});
  @override
  Widget build(BuildContext context) {
    final staked = bets.fold<double>(0, (s, b) => s + b.stake);
    final settled = bets.where((b) => b.status.settled);
    final profit = settled.fold<double>(0, (s, b) => s + b.profit);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(children: [
        Expanded(child: Text(dayHeader(day), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
        Text('giocati ${eur(staked)}', style: const TextStyle(color: C.faint, fontSize: 12.5, fontWeight: FontWeight.w600)),
        if (settled.isNotEmpty) ...[
          const SizedBox(width: 10),
          Text(signedEur(profit), style: TextStyle(color: C.pl(profit), fontWeight: FontWeight.w800, fontSize: 13.5)),
        ],
      ]),
    );
  }
}
