import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class C {
  static const bg = Color(0xFF0A0E13);
  static const surface = Color(0xFF121820);
  static const card = Color(0xFF171F29);
  static const cardHi = Color(0xFF1E2833);
  static const border = Color(0xFF243140);
  static const text = Color(0xFFF1F5F9);
  static const muted = Color(0xFF8A98A8);
  static const faint = Color(0xFF5B6878);
  static const primary = Color(0xFF3DDC97);
  static const win = Color(0xFF22C55E);
  static const loss = Color(0xFFF2545B);
  static const pending = Color(0xFFF5B83D);
  static const blue = Color(0xFF5B9CFF);
  static const violet = Color(0xFFA78BFA);

  static Color pl(double v) => v > 0.004 ? win : (v < -0.004 ? loss : muted);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.primary,
      brightness: Brightness.dark,
      primary: C.primary,
      surface: C.surface,
      error: C.loss,
    ),
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.text, letterSpacing: -0.3),
    ),
    cardTheme: CardThemeData(
      color: C.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: C.border, width: 0.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      indicatorColor: C.primary.withValues(alpha: 0.16),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? C.text : C.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? C.primary : C.muted,
          )),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.cardHi,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.primary, width: 1.4)),
      labelStyle: const TextStyle(color: C.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: C.primary,
      foregroundColor: Color(0xFF04140C),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.primary,
        foregroundColor: const Color(0xFF04140C),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: C.card,
      selectedColor: C.primary.withValues(alpha: 0.18),
      side: const BorderSide(color: C.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(color: C.text, fontWeight: FontWeight.w600),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: C.surface, surfaceTintColor: Colors.transparent),
    dividerTheme: const DividerThemeData(color: C.border, thickness: 0.6),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.cardHi,
      contentTextStyle: TextStyle(color: C.text),
    ),
  );
}

final _eurFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);
final _eurFmt0 = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);

String eur(double v, {bool compact = false}) =>
    (compact && v.abs() >= 1000 ? _eurFmt0 : _eurFmt).format(v);

String signedEur(double v) => '${v > 0.004 ? '+' : (v < -0.004 ? '−' : '')}${eur(v.abs())}';

String pct(double v, {bool signed = true}) {
  final p = v * 100;
  final s = p.abs() >= 100 ? p.toStringAsFixed(0) : p.toStringAsFixed(1);
  final txt = s.replaceAll('.', ',');
  if (!signed) return '$txt%';
  return '${p > 0.04 ? '+' : (p < -0.04 ? '−' : '')}${txt.replaceAll('-', '')}%';
}

String odds(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

String dateShort(DateTime d) => DateFormat('d MMM', 'it').format(d);
String dateTime(DateTime d) => DateFormat("EEE d MMM · HH:mm", 'it').format(d);

String dayHeader(DateTime d) {
  final today = DateTime.now();
  final t = DateTime(today.year, today.month, today.day);
  final x = DateTime(d.year, d.month, d.day);
  final diff = t.difference(x).inDays;
  if (diff == 0) return 'Oggi';
  if (diff == 1) return 'Ieri';
  final s = DateFormat('EEEE d MMMM', 'it').format(d);
  return s[0].toUpperCase() + s.substring(1);
}
