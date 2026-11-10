import 'dart:convert';

import 'package:http/http.dart' as http;

/// Stesso progetto Supabase del tracker web (index.html del repo Bet).
const supabaseUrl = 'https://wdinlazhjttgrkxdzyoa.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndkaW5sYXpoanR0Z3JreGR6eW9hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1MTEwNTgsImV4cCI6MjA4NzA4NzA1OH0.C9AIZLk_mYVxGh4Po0OPyr_RcQtkplytCjyRLRB-IM4';

/// Le schedine dell'app sono quelle del tipster "Tu" nel tracker web.
const appTipster = 'Tu';

/// Riga di bankroll usata dall'app (la 1 è quella del tracker web con tutti i tipster).
const appBankrollId = 2;

class RemoteError implements Exception {
  final int status;
  final String body;
  RemoteError(this.status, this.body);
  bool get missingColumn => body.contains('PGRST204') || (body.contains('column') && body.contains('dettagli'));
  bool get missingTable => status == 404 || body.contains('42P01') || body.contains('PGRST205');
  @override
  String toString() => 'Supabase $status: $body';
}

class Remote {
  static final _client = http.Client();
  static Map<String, String> _h({String? prefer}) => {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $supabaseAnonKey',
        'Content-Type': 'application/json',
        if (prefer != null) 'Prefer': prefer,
      };

  static Uri _u(String path) => Uri.parse('$supabaseUrl/rest/v1/$path');

  static dynamic _check(http.Response r) {
    if (r.statusCode >= 300) throw RemoteError(r.statusCode, r.body);
    if (r.body.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  static const _timeout = Duration(seconds: 15);

  static Future<List<Map<String, dynamic>>> select(String table, String query) async {
    final r = await _client.get(_u('$table?$query'), headers: _h()).timeout(_timeout);
    final d = _check(r) as List;
    return d.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> insert(String table, Map<String, dynamic> row) async {
    final r = await _client
        .post(_u(table), headers: _h(prefer: 'return=representation'), body: jsonEncode(row))
        .timeout(_timeout);
    final d = _check(r) as List;
    return Map<String, dynamic>.from(d.first as Map);
  }

  static Future<void> update(String table, String id, Map<String, dynamic> row) async {
    final r = await _client
        .patch(_u('$table?id=eq.$id'), headers: _h(prefer: 'return=minimal'), body: jsonEncode(row))
        .timeout(_timeout);
    _check(r);
  }

  static Future<void> upsert(String table, Map<String, dynamic> row) async {
    final r = await _client
        .post(_u(table),
            headers: _h(prefer: 'resolution=merge-duplicates,return=minimal'), body: jsonEncode(row))
        .timeout(_timeout);
    _check(r);
  }

  static Future<void> delete(String table, String id) async {
    final r = await _client.delete(_u('$table?id=eq.$id'), headers: _h()).timeout(_timeout);
    _check(r);
  }
}
