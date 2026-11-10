import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Centra il contenuto e limita la larghezza su tablet/schermi grandi.
class Responsive extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const Responsive({super.key, required this.child, this.maxWidth = 760});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 680;

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final VoidCallback? onTap;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.gradient, this.onTap});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? C.card : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: C.border, width: 0.6),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: box),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;
  final Color? subColor;
  final IconData? icon;
  const StatTile({super.key, required this.label, required this.value, this.sub, this.valueColor, this.subColor, this.icon});

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: C.muted),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: C.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w800, color: valueColor ?? C.text, letterSpacing: -0.4)),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subColor ?? C.faint, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ]),
      );
}

/// Griglia di tile: 2 colonne su telefono, 4 su schermi larghi.
class TileGrid extends StatelessWidget {
  final List<Widget> children;
  const TileGrid({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 600 ? 4 : 2;
      const gap = 10.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;
  const Pill(this.text, {super.key, required this.color, this.icon, this.solid = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: solid ? color : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: solid ? Colors.black : color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  color: solid ? Colors.black : color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

Color statusColor(BetStatus s) => switch (s) {
      BetStatus.pending => C.pending,
      BetStatus.won => C.win,
      BetStatus.lost => C.loss,
      BetStatus.voided => C.blue,
      BetStatus.cashout => C.violet,
    };

IconData statusIcon(BetStatus s) => switch (s) {
      BetStatus.pending => Icons.schedule_rounded,
      BetStatus.won => Icons.check_circle_rounded,
      BetStatus.lost => Icons.cancel_rounded,
      BetStatus.voided => Icons.undo_rounded,
      BetStatus.cashout => Icons.payments_rounded,
    };

class BetTile extends StatelessWidget {
  final Bet bet;
  final VoidCallback? onTap;
  final void Function(BetStatus s)? onQuickSettle;
  const BetTile({super.key, required this.bet, this.onTap, this.onQuickSettle});

  @override
  Widget build(BuildContext context) {
    final sc = statusColor(bet.status);
    final pending = bet.status == BetStatus.pending;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: sc.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: bet.imagePath != null && File(bet.imagePath!).existsSync()
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(bet.imagePath!), fit: BoxFit.cover, cacheWidth: 120),
                  )
                : Icon(statusIcon(bet.status), color: sc, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bet.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 3),
              Row(children: [
                Text('${eur(bet.stake)} · @${odds(bet.odds)}',
                    style: const TextStyle(color: C.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Text(bet.category.short,
                    style: const TextStyle(color: C.faint, fontSize: 11.5, fontWeight: FontWeight.w700)),
                if (bet.autoSettled) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.notifications_active_rounded, size: 13, color: C.primary),
                ],
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              pending ? eur(bet.potentialWin) : signedEur(bet.profit),
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: pending ? C.text : C.pl(bet.profit)),
            ),
            const SizedBox(height: 3),
            Text(pending ? 'potenziale' : bet.status.label,
                style: TextStyle(color: sc, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ]),
        if (pending && onQuickSettle != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _QuickBtn(
                  label: 'Vinta', color: C.win, icon: Icons.check_rounded, onTap: () => onQuickSettle!(BetStatus.won)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickBtn(
                  label: 'Persa', color: C.loss, icon: Icons.close_rounded, onTap: () => onQuickSettle!(BetStatus.lost)),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickBtn({required this.label, required this.color, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: C.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: C.primary),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, height: 1.4)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
