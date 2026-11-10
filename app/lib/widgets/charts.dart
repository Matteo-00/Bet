import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../stats.dart';
import '../theme.dart';

const _axis = TextStyle(color: C.faint, fontSize: 10.5, fontWeight: FontWeight.w600);

String _short(double v) {
  final a = v.abs();
  if (a >= 1000) return '${(v / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
  return v.toStringAsFixed(0);
}

double _niceStep(double range, int ticks) {
  if (range <= 0) return 1;
  final raw = range / ticks;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final n = raw / mag;
  final double step = n <= 1 ? 1.0 : n <= 2 ? 2.0 : n <= 5 ? 5.0 : 10.0;
  return step * mag;
}

/// Linea del saldo nel tempo, con riferimento al valore di partenza del periodo.
class BalanceChart extends StatelessWidget {
  final List<MapEntry<DateTime, double>> series;
  final double height;
  const BalanceChart({super.key, required this.series, this.height = 210});

  @override
  Widget build(BuildContext context) {
    if (series.length < 2) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('Servono almeno due giorni di dati', style: TextStyle(color: C.muted))),
      );
    }
    final first = series.first.value;
    final last = series.last.value;
    final up = last >= first;
    final color = up ? C.win : C.loss;
    var minY = series.map((e) => e.value).reduce(math.min);
    var maxY = series.map((e) => e.value).reduce(math.max);
    if ((maxY - minY).abs() < 1) {
      minY -= 5;
      maxY += 5;
    }
    final step = _niceStep(maxY - minY, 4);
    minY = ((minY / step).floor() * step).toDouble();
    maxY = ((maxY / step).ceil() * step).toDouble();
    final n = series.length;
    final labelEvery = math.max(1, (n / 4).ceil());
    final df = DateFormat(n > 120 ? 'MMM yy' : 'd MMM', 'it');

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: 0,
          maxX: (n - 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: step,
            getDrawingHorizontalLine: (_) => const FlLine(color: C.border, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: step,
                getTitlesWidget: (v, meta) {
                  if (v == meta.max || v == meta.min && v != minY) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(_short(v), style: _axis, textAlign: TextAlign.right),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= n || (i % labelEvery != 0 && i != n - 1)) return const SizedBox.shrink();
                  if (i != n - 1 && n - 1 - i < labelEvery / 2) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(df.format(series[i].key), style: _axis),
                  );
                },
              ),
            ),
          ),
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(y: first, color: C.faint.withValues(alpha: 0.6), strokeWidth: 1, dashArray: [4, 4]),
          ]),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => C.cardHi,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => spots.map((s) {
                final e = series[s.x.round().clamp(0, n - 1)];
                return LineTooltipItem(
                  '${DateFormat('EEE d MMM', 'it').format(e.key)}\n',
                  const TextStyle(color: C.muted, fontSize: 11.5, fontWeight: FontWeight.w600),
                  children: [
                    TextSpan(
                        text: eur(e.value),
                        style: const TextStyle(color: C.text, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < n; i++) FlSpot(i.toDouble(), series[i].value)],
              isCurved: true,
              curveSmoothness: 0.22,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 2.6,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, bar) => spot.x == n - 1,
                getDotPainter: (spot, p, bar, i) => FlDotCirclePainter(
                  radius: 4,
                  color: color,
                  strokeWidth: 3,
                  strokeColor: C.card,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 350),
      ),
    );
  }
}

/// Barre di profitto/perdita (verde sopra lo zero, rosso sotto).
class ProfitBars extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final List<String>? tooltips;
  final double height;
  const ProfitBars({super.key, required this.labels, required this.values, this.tooltips, this.height = 190});

  @override
  Widget build(BuildContext context) {
    if (values.every((v) => v == 0)) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('Nessun risultato in questo periodo', style: TextStyle(color: C.muted))),
      );
    }
    var maxAbs = values.map((v) => v.abs()).reduce(math.max);
    if (maxAbs == 0) maxAbs = 1;
    final hasNeg = values.any((v) => v < 0);
    final hasPos = values.any((v) => v > 0);
    final step = _niceStep(hasNeg && hasPos ? maxAbs * 2 : maxAbs, 4);
    final double maxY = hasPos ? ((values.reduce(math.max) / step).ceil() * step).toDouble() : step;
    final double minY = hasNeg ? ((values.reduce(math.min) / step).floor() * step).toDouble() : 0.0;
    final n = values.length;
    final labelEvery = n <= 12 ? 1 : (n / 8).ceil();

    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, c) {
        final w = ((c.maxWidth - 44) / n * 0.62).clamp(3.0, 26.0);
        return BarChart(
          BarChartData(
            maxY: maxY.toDouble(),
            minY: minY.toDouble(),
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: step,
              getDrawingHorizontalLine: (v) => FlLine(
                color: v == 0 ? C.faint : C.border,
                strokeWidth: v == 0 ? 0.9 : 0.5,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: step,
                  getTitlesWidget: (v, meta) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(_short(v), style: _axis, textAlign: TextAlign.right),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= n || i % labelEvery != 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(labels[i], style: _axis),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => C.cardHi,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, gi, rod, ri) {
                  final i = group.x;
                  return BarTooltipItem(
                    '${tooltips?[i] ?? labels[i]}\n',
                    const TextStyle(color: C.muted, fontSize: 11.5, fontWeight: FontWeight.w600),
                    children: [
                      TextSpan(
                        text: signedEur(values[i]),
                        style: TextStyle(color: C.pl(values[i]), fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ],
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < n; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: values[i],
                    width: w,
                    color: values[i] >= 0 ? C.win : C.loss,
                    borderRadius: values[i] >= 0
                        ? const BorderRadius.vertical(top: Radius.circular(5))
                        : const BorderRadius.vertical(bottom: Radius.circular(5)),
                  ),
                ]),
            ],
          ),
          duration: const Duration(milliseconds: 350),
        );
      }),
    );
  }
}

/// Anello percentuale (es. % schedine vinte).
class RingGauge extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double size;
  final Widget center;
  const RingGauge({super.key, required this.value, required this.color, required this.center, this.size = 92});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1)),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(v, color),
            child: Center(child: center),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  _RingPainter(this.v, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.11;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final bg = Paint()
      ..color = C.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(r, 0, math.pi * 2, false, bg);
    if (v > 0) canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color;
}

/// Calendario mensile colorato in base al profitto giornaliero.
class MonthHeatmap extends StatelessWidget {
  final DateTime month;
  final Map<DateTime, double> dailyProfit;
  final Map<DateTime, double> dailyStaked;
  final void Function(DateTime day)? onDayTap;
  const MonthHeatmap({super.key, required this.month, required this.dailyProfit, required this.dailyStaked, this.onDayTap});

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final maxAbs = dailyProfit.values.fold<double>(1, (m, v) => math.max(m, v.abs()));
    final today = dayOf(DateTime.now());
    const wd = ['L', 'M', 'M', 'G', 'V', 'S', 'D'];
    return Column(children: [
      Row(children: [
        for (final d in wd)
          Expanded(child: Center(child: Text(d, style: _axis))),
      ]),
      const SizedBox(height: 6),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: lead + daysInMonth,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, mainAxisSpacing: 5, crossAxisSpacing: 5),
        itemBuilder: (context, i) {
          if (i < lead) return const SizedBox.shrink();
          final day = DateTime(month.year, month.month, i - lead + 1);
          final p = dailyProfit[day];
          final played = dailyStaked.containsKey(day);
          Color bg = C.cardHi.withValues(alpha: 0.5);
          Color fg = C.faint;
          if (p != null) {
            final t = (p.abs() / maxAbs).clamp(0.25, 1.0);
            final base = p >= 0 ? C.win : C.loss;
            bg = base.withValues(alpha: 0.18 + 0.62 * t);
            fg = Colors.white;
          } else if (played) {
            bg = C.pending.withValues(alpha: 0.22);
            fg = C.text;
          }
          final isToday = day == today;
          return GestureDetector(
            onTap: onDayTap == null ? null : () => onDayTap!(day),
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(9),
                border: isToday ? Border.all(color: C.primary, width: 1.6) : null,
              ),
              alignment: Alignment.center,
              child: Text('${day.day}',
                  style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          );
        },
      ),
    ]);
  }
}

/// Barra orizzontale semplice con etichetta, valore e percentuale.
class HBar extends StatelessWidget {
  final String label;
  final String trailing;
  final double fraction; // 0..1
  final Color color;
  final String? sub;
  const HBar({super.key, required this.label, required this.trailing, required this.fraction, required this.color, this.sub});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(trailing, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Stack(children: [
              Container(height: 8, color: C.border),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(height: 8, color: color),
              ),
            ]),
          ),
          if (sub != null) ...[
            const SizedBox(height: 5),
            Text(sub!, style: const TextStyle(color: C.faint, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ]),
      );
}
