import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/pulse_analyst_evolution.dart';

/// Persists what the analyst population has learned between app sessions.
///
/// Without this the council would be reborn naive every time the screen is
/// opened, which would make "evolution" a purely cosmetic claim.
class PulseEvolutionStore {
  const PulseEvolutionStore();

  static const _key = 'nexora_pulse_evolution_v3';

  Future<PulseEvolutionState> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return PulseEvolutionState.bootstrap();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return PulseEvolutionState.bootstrap();
      }
      return PulseEvolutionState.fromJson(decoded) ??
          PulseEvolutionState.bootstrap();
    } catch (_) {
      return PulseEvolutionState.bootstrap();
    }
  }

  Future<void> save(PulseEvolutionState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state.toJson()));
    } catch (_) {
      // Losing one checkpoint is preferable to breaking the round.
    }
  }

  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Nothing to do.
    }
  }
}
