import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> showNoticesSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _NoticesBody(scroll: scroll),
      ),
    );

class _NoticesBody extends StatelessWidget {
  final ScrollController scroll;
  const _NoticesBody({required this.scroll});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final open = store.openNotices;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Text('Notifiche da abbinare', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Text('Scegli a quale schedina si riferisce ogni notifica, oppure ignorala.',
              style: TextStyle(color: C.muted)),
        ),
        if (open.isEmpty)
          const EmptyState(icon: Icons.done_all_rounded, title: 'Tutto abbinato', text: 'Non ci sono notifiche in sospeso.'),
        for (final n in open) _NoticeCard(n: n),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final Notice n;
  const _NoticeCard({required this.n});
  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final exact = store.candidatesFor(n);
    final candidates = exact.isNotEmpty ? exact : store.pendingBets;
    final kindColor = switch (n.kind) {
      NoticeKind.win => C.win,
      NoticeKind.loss => C.loss,
      NoticeKind.unknown => C.muted,
    };
    final kindLabel = switch (n.kind) {
      NoticeKind.win => 'Vincita',
      NoticeKind.loss => 'Perdita',
      NoticeKind.unknown => 'Notifica',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pill(kindLabel, color: kindColor),
            if (n.amount != null) ...[const SizedBox(width: 8), Pill(eur(n.amount!), color: C.text)],
            const Spacer(),
            Text(dateTime(n.time), style: const TextStyle(color: C.faint, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          if (n.title.isNotEmpty) Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (n.text.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(n.text, style: const TextStyle(color: C.muted, height: 1.35)),
          ],
          const SizedBox(height: 12),
          if (candidates.isEmpty)
            const Text('Nessuna schedina in attesa a cui abbinarla.', style: TextStyle(color: C.faint))
          else ...[
            Text(exact.isNotEmpty && n.amount != null ? 'Schedine con questa vincita' : 'Schedine in attesa',
                style: const TextStyle(color: C.faint, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final b in candidates.take(6))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${eur(b.stake)} @${odds(b.odds)} → ${eur(b.potentialWin)}'),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    var notice = n;
                    if (notice.kind == NoticeKind.unknown) {
                      final k = await _askKind(context);
                      if (k == null) return;
                      notice.kind = k;
                    }
                    await store.resolveNotice(notice, b);
                  },
                  child: const Text('Abbina'),
                ),
              ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => store.resolveNotice(n, null),
              child: const Text('Ignora', style: TextStyle(color: C.muted)),
            ),
          ),
        ]),
      ),
    );
  }
}

Future<NoticeKind?> _askKind(BuildContext context) => showDialog<NoticeKind>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Com\'è andata?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, NoticeKind.loss), child: const Text('Persa', style: TextStyle(color: C.loss))),
          TextButton(onPressed: () => Navigator.pop(ctx, NoticeKind.win), child: const Text('Vinta', style: TextStyle(color: C.win))),
        ],
      ),
    );
