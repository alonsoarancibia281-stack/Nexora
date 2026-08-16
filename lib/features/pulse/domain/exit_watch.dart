import 'dart:math' as math;

import 'prediction_horizon.dart';
import 'prediction_outlook.dart';

/// How safe the open call looks right now.
enum ExitLevel { calm, watch, exit }

extension ExitLevelInfo on ExitLevel {
  String get label => switch (this) {
        ExitLevel.calm => 'Tranquilo',
        ExitLevel.watch => 'Atento',
        ExitLevel.exit => 'Sal ahora',
      };
}

/// The early warning the user asked for: it tells you to step out before the
/// round closes against the call.
class ExitAdvice {
  const ExitAdvice({
    required this.level,
    required this.title,
    required this.detail,
    required this.call,
    required this.currentProbability,
    required this.peakProbability,
    required this.slopePerMinute,
    this.lockedAt,
  });

  const ExitAdvice.idle()
      : level = ExitLevel.calm,
        title = 'Sin apuesta abierta',
        detail = 'El equipo aún no toma partido.',
        call = PredictionCall.wait,
        currentProbability = .5,
        peakProbability = .5,
        slopePerMinute = 0,
        lockedAt = null;

  final ExitLevel level;
  final String title;
  final String detail;

  /// The call this advice protects.
  final PredictionCall call;

  /// Chance the call still wins, from 0 to 1.
  final double currentProbability;

  /// Best chance seen since the call opened.
  final double peakProbability;

  /// How fast that chance moves, per minute.
  final double slopePerMinute;

  /// Exact time the call opened.
  final DateTime? lockedAt;

  /// How much of the edge is already gone, from 0 to 1.
  double get drop => (peakProbability - currentProbability).clamp(0.0, 1.0);

  bool get isOpen => call.isDirectional;
}

class _Sample {
  const _Sample(this.at, this.probability);
  final DateTime at;
  final double probability;
}

/// Watches one horizon during the round and grades the open call.
class ExitWatcher {
  ExitWatcher();

  /// A call opens once the desk reaches this much confidence.
  static const openThreshold = .58;

  DateTime? _roundStart;
  PredictionCall _call = PredictionCall.wait;
  DateTime? _lockedAt;
  double _peak = .5;
  final List<_Sample> _history = <_Sample>[];

  PredictionCall get call => _call;
  DateTime? get lockedAt => _lockedAt;

  void reset() {
    _roundStart = null;
    _call = PredictionCall.wait;
    _lockedAt = null;
    _peak = .5;
    _history.clear();
  }

  ExitAdvice update(PredictionOutlook outlook) {
    if (_roundStart == null || !_roundStart!.isAtSameMomentAs(outlook.window.start)) {
      reset();
      _roundStart = outlook.window.start;
    }

    if (!_call.isDirectional &&
        outlook.call.isDirectional &&
        outlook.probability >= openThreshold) {
      _call = outlook.call;
      _lockedAt = outlook.updatedAt;
      _peak = outlook.probability;
    }

    if (!_call.isDirectional) return const ExitAdvice.idle();

    final current = _call == PredictionCall.up
        ? outlook.probabilityUp
        : 1 - outlook.probabilityUp;
    _peak = math.max(_peak, current);
    _history.add(_Sample(outlook.updatedAt, current));
    if (_history.length > 240) _history.removeAt(0);

    final slope = _slopePerMinute();
    final drop = (_peak - current).clamp(0.0, 1.0);
    final elapsed = 1 -
        outlook.secondsLeft / outlook.horizon.totalSeconds.toDouble();
    final against = _call == PredictionCall.up
        ? outlook.distancePercent < 0
        : outlook.distancePercent > 0;
    final travelled = outlook.expectedMovePercent <= 0
        ? 0.0
        : (outlook.distancePercent.abs() / outlook.expectedMovePercent);

    ExitAdvice advice(ExitLevel level, String title, String detail) => ExitAdvice(
          level: level,
          title: title,
          detail: detail,
          call: _call,
          currentProbability: current,
          peakProbability: _peak,
          slopePerMinute: slope,
          lockedAt: _lockedAt,
        );

    if (outlook.call.isDirectional && outlook.call != _call) {
      return advice(
        ExitLevel.exit,
        'Sal ahora',
        'El equipo cambia de lado. La ronda va en tu contra.',
      );
    }
    if (current < .5) {
      return advice(
        ExitLevel.exit,
        'Sal ahora',
        'La jugada pierde ventaja. Ya vale menos que una moneda al aire.',
      );
    }
    if (against && elapsed > .55 && travelled > .55) {
      return advice(
        ExitLevel.exit,
        'Sal ahora',
        'El precio se va en contra y queda poco tiempo para volver.',
      );
    }
    if (drop >= .12) {
      return advice(
        current < .56 ? ExitLevel.exit : ExitLevel.watch,
        current < .56 ? 'Sal ahora' : 'Atento',
        'La ventaja cae ${(drop * 100).round()} puntos desde su mejor momento.',
      );
    }
    if (slope <= -.04) {
      return advice(
        ExitLevel.watch,
        'Atento',
        'La ventaja baja rápido. Prepara la salida.',
      );
    }
    if (against && elapsed > .35) {
      return advice(
        ExitLevel.watch,
        'Atento',
        'El precio anda del otro lado de la apertura.',
      );
    }
    if (outlook.instability > 72 && current < .62) {
      return advice(
        ExitLevel.watch,
        'Atento',
        'El mercado se agita y la señal pierde apoyo.',
      );
    }
    if (outlook.agreement < .5) {
      return advice(
        ExitLevel.watch,
        'Atento',
        'El equipo se divide sobre esta ronda.',
      );
    }
    return advice(
      ExitLevel.calm,
      'Tranquilo',
      'La jugada aguanta con ${(current * 100).round()}% a favor.',
    );
  }

  /// Change of the winning chance per minute, read over the last two minutes.
  double _slopePerMinute() {
    if (_history.length < 3) return 0;
    final last = _history.last;
    final from = _history.firstWhere(
      (sample) => last.at.difference(sample.at).inSeconds <= 120,
      orElse: () => _history.first,
    );
    final minutes = last.at.difference(from.at).inMilliseconds / 60000;
    if (minutes <= .05) return 0;
    return (last.probability - from.probability) / minutes;
  }
}
