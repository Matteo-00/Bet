import 'dart:convert';

import 'package:flutter/services.dart';

/// Ponte verso il servizio Android che legge le notifiche di Eplay.
class NativeNotifications {
  static const _ch = MethodChannel('bet_tracker/notifications');

  static void listen(void Function() onChanged) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'changed') onChanged();
      return null;
    });
  }

  static Future<bool> isEnabled() async {
    try {
      return await _ch.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {}
  }

  static Future<void> openAppDetails() async {
    try {
      await _ch.invokeMethod('openAppDetails');
    } catch (_) {}
  }

  static Future<void> setKeywords(String keywords) async {
    try {
      await _ch.invokeMethod('setFilter', {'filter': keywords});
    } catch (_) {}
  }

  /// Restituisce e svuota la coda di notifiche catturate.
  static Future<List<Map<String, dynamic>>> drain() async {
    try {
      final s = await _ch.invokeMethod<String>('drain') ?? '[]';
      final list = jsonDecode(s) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }
}
