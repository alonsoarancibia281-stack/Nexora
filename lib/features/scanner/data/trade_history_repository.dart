import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/trade_record.dart';

/// Step 05: every idea is written down, win or lose.
///
/// The history lives on the phone first. Publishing is a separate, explicit
/// step, so nothing leaves the device unless you ask for it.
class TradeHistoryRepository {
  const TradeHistoryRepository();

  static const _key = 'nexora_trade_history_v1';
  static const maxRecords = 300;

  Future<List<TradeRecord>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final rows = jsonDecode(raw) as List<dynamic>;
      return rows
          .cast<Map<String, dynamic>>()
          .map(TradeRecord.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<TradeRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed =
        records.length <= maxRecords ? records : records.sublist(0, maxRecords);
    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((record) => record.toJson()).toList()),
    );
  }

  /// Adds a record and returns the new history, newest first.
  Future<List<TradeRecord>> add(TradeRecord record) async {
    final current = [...await load()];
    current.removeWhere((item) => item.id == record.id);
    current.insert(0, record);
    await _save(current);
    return current;
  }

  Future<List<TradeRecord>> replace(TradeRecord record) async {
    final current = [...await load()];
    final index = current.indexWhere((item) => item.id == record.id);
    if (index < 0) return add(record);
    current[index] = record;
    await _save(current);
    return current;
  }

  Future<List<TradeRecord>> remove(String id) async {
    final current = [...await load()]..removeWhere((item) => item.id == id);
    await _save(current);
    return current;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Sends a record to the public history so anyone can check it.
class SignalPublisher {
  const SignalPublisher({http.Client? client}) : _client = client;

  final http.Client? _client;
  static const _endpoint = String.fromEnvironment('NEXORA_PUBLISH_ENDPOINT');
  static const _anonKey = String.fromEnvironment('NEXORA_SUPABASE_ANON_KEY');

  bool get isConfigured =>
      _endpoint.trim().isNotEmpty && _anonKey.trim().isNotEmpty;

  /// Returns true when the record reached the public table.
  Future<bool> publish(TradeRecord record) async {
    if (!isConfigured) return false;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'apikey': _anonKey,
              'authorization': 'Bearer $_anonKey',
            },
            body: jsonEncode(record.toJson()),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    } finally {
      if (_client == null) client.close();
    }
  }
}
