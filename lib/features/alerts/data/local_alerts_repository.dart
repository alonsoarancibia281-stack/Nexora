import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/price_alert.dart';

class LocalAlertsRepository {
  static const _key = 'nexora_price_alerts_v1';

  Future<List<PriceAlert>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final rows = jsonDecode(raw) as List<dynamic>;
      return rows.map((e) => PriceAlert.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<PriceAlert> alerts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(alerts.map((e) => e.toJson()).toList()));
  }

  Future<void> add(PriceAlert alert) async {
    final alerts = await load();
    alerts.insert(0, alert);
    await save(alerts);
  }

  Future<void> remove(String id) async {
    final alerts = await load()..removeWhere((a) => a.id == id);
    await save(alerts);
  }

  Future<List<PriceAlert>> evaluate(Map<String, double> prices) async {
    final alerts = await load();
    var changed = false;
    final now = DateTime.now();
    final updated = alerts.map((alert) {
      final price = prices[alert.symbol];
      if (price != null && alert.shouldTrigger(price)) {
        changed = true;
        return alert.copyWith(triggeredAt: now);
      }
      return alert;
    }).toList();
    if (changed) await save(updated);
    return updated;
  }
}
