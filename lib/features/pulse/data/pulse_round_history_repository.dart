import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/pulse_round_tracker.dart';
import '../domain/pulse_signal.dart';

class PulseRoundHistoryRepository {
  static const _key = 'nexora_pulse_round_history_v1';
  static const _maximumRounds = 250;

  Future<List<PulseRoundOutcome>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((row) => _outcomeFromJson(row as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  Future<List<PulseRoundOutcome>> add(PulseRoundOutcome outcome) async {
    final current = await load();
    final withoutDuplicate = current
        .where((item) => item.roundStart != outcome.roundStart)
        .toList(growable: true);
    withoutDuplicate.insert(0, outcome);
    final trimmed =
        withoutDuplicate.take(_maximumRounds).toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(trimmed.map(_outcomeToJson).toList(growable: false)),
    );
    return trimmed;
  }

  Map<String, dynamic> _outcomeToJson(PulseRoundOutcome outcome) => {
        'roundStart': outcome.roundStart.toUtc().toIso8601String(),
        'startPrice': outcome.startPrice,
        'endPrice': outcome.endPrice,
        'observations': outcome.observations
            .map((observation) => {
                  'observedAt':
                      observation.observedAt.toUtc().toIso8601String(),
                  'secondsRemaining': observation.secondsRemaining,
                  'observedPrice': observation.observedPrice,
                  'predictedDirection': observation.predictedDirection.name,
                  'probabilityUp': observation.probabilityUp,
                  'instability': observation.instability,
                })
            .toList(growable: false),
      };

  PulseRoundOutcome _outcomeFromJson(Map<String, dynamic> json) {
    final roundStart = DateTime.parse('${json['roundStart']}').toUtc();
    final startPrice = (json['startPrice'] as num).toDouble();
    return PulseRoundOutcome(
      roundStart: roundStart,
      startPrice: startPrice,
      endPrice: (json['endPrice'] as num).toDouble(),
      observations:
          ((json['observations'] as List<dynamic>?) ?? const []).map((raw) {
        final row = raw as Map<String, dynamic>;
        return PulseRoundObservation(
          roundStart: roundStart,
          observedAt: DateTime.parse('${row['observedAt']}').toUtc(),
          secondsRemaining: (row['secondsRemaining'] as num).toInt(),
          startPrice: startPrice,
          observedPrice: (row['observedPrice'] as num).toDouble(),
          predictedDirection: PulseDirection.values.firstWhere(
            (value) => value.name == row['predictedDirection'],
            orElse: () => PulseDirection.noTrade,
          ),
          probabilityUp: (row['probabilityUp'] as num).toDouble(),
          instability: (row['instability'] as num).toDouble(),
        );
      }).toList(growable: false),
    );
  }
}
