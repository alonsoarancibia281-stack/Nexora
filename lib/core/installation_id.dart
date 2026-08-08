import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class InstallationId {
  static const _key = 'nexora_installation_id';

  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(_key, value);
    return value;
  }
}
