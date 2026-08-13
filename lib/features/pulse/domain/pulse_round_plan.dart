import 'dart:math' as math;

import 'pulse_consensus_engine.dart';
import 'pulse_ensemble_100.dart';
import 'pulse_signal.dart';

enum RoundPlanStatus {
  building,
  onTrack,
  atRisk,
  invalidated,
  settledWin,
  settledLoss,
}

extension RoundPlanStatusLabel on RoundPlanStatus {
  String get label {
    switch (this) {
      case RoundPlanStatus.building:
        return 'Procesando gráfico';
      case RoundPlanStatus.onTrack:
        return 'Tesis en curso';
      case RoundPlanStatus.atRisk:
        return 'Tesis en riesgo';
      case RoundPlanStatus.invalidated:
        return 'Tesis invalidada';
      case RoundPlanStatus.settledWin:
        return 'Cerró a favor';
      case RoundPlanStatus.settledLoss:
        return 'Cerró en contra';
    }
  }
}

/// The strategy locked in when a 5-minute round opens.
///
/// It is computed once, from the chart as it stands at the open, and then left
/// untouched: that is what makes it a prediction rather than a running
/// commentary. Everything that happens afterwards is measured against it.
class PulseRoundPlan {
  const PulseRoundPlan({
    required this.roundStart,
    required this.roundEnd,
    required this.entryPrice,
    required this.direction,
    required this.probabilityUp,
    required this.expectedMovePct,
    required this.targetPrice,
    required this.invalidationPrice,
    required this.drivers,
    required this.strategy,
    required this.lockedAtSecondsRemaining,
    required this.analystAgreement,
    required this.councilAgreement,
  });

  final DateTime roundStart;
  final DateTime roundEnd;

  /// Opening price of the 5-minute candle, straight from Binance.
  final double entryPrice;

  final PulseDirection direction;
  final double probabilityUp;

  /// Movement the models expect over the full round, in percent.
  final double expectedMovePct;

  final double targetPrice;
  final double invalidationPrice;

  /// Short bullet reasons the plan exists.
  final List<String> drivers;

  /// One-paragraph plan in plain Spanish.
  final String strategy;

  final int lockedAtSecondsRemaining;
  final double analystAgreement;
  final double councilAgreement;

  bool get isUp => direction == PulseDirection.up;

  double get confidence => math.max(probabilityUp, 1 - probabilityUp) * 100;

  /// Builds the plan from the first consensus of the round.
  static PulseRoundPlan build({
    required DateTime roundStart,
    required DateTime roundEnd,
    required double entryPrice,
    required int secondsRemaining,
    required PulseConsensus consensus,
    required PulseSignal signal,
  }) {
    final up = consensus.direction == PulseDirection.up;
    final expected = math
        .max(signal.expectedRemainingMovePct.abs(), .035)
        .clamp(.035, 2.5)
        .toDouble();
    final target =
        entryPrice * (1 + (up ? expected : -expected) / 100);
    final invalidation =
        entryPrice * (1 - (up ? expected : -expected) * .85 / 100);

    final drivers = <String>[];
    final teams = [...consensus.ensemble.teamOpinions]..sort((a, b) =>
        (b.probabilityUp - .5).abs().compareTo((a.probabilityUp - .5).abs()));
    for (final team in teams.take(2)) {
      final pct = (team.probabilityUp * 100).toStringAsFixed(0);
      drivers.add(
          'Equipo ${team.family.label}: $pct% a favor de ${team.probabilityUp >= .5 ? 'subida' : 'bajada'}');
    }
    for (final theorem in consensus.briefing.topTheorems(3)) {
      final sense = theorem.signal >= 0 ? 'alza' : 'baja';
      drivers.add('${theorem.name} → $sense (${theorem.formula})');
    }
    if (signal.stability != MarketStability.stable) {
      drivers.add(
          'Mercado ${signal.stabilityLabel.toLowerCase()}: tamaño de la tesis reducido');
    }

    final directionWord = up ? 'ALZA' : 'BAJA';
    final invalidWord = up ? 'debajo' : 'encima';
    final strategy = StringBuffer()
      ..write(
          'Al abrir la ronda el motor procesó el gráfico y fijó una tesis de $directionWord '
          'con ${(math.max(consensus.probabilityUp, 1 - consensus.probabilityUp) * 100).toStringAsFixed(1)}% '
          'de probabilidad. ')
      ..write(
          'Referencia de apertura ${entryPrice.toStringAsFixed(2)} USDT y movimiento esperado '
          '${expected.toStringAsFixed(3)}% hasta el cierre. ')
      ..write(
          'La tesis se confirma si el cierre de los 5 minutos queda ${up ? 'por encima' : 'por debajo'} '
          'de la apertura, y queda invalidada si el precio se sostiene $invalidWord de '
          '${invalidation.toStringAsFixed(2)} USDT. ')
      ..write(
          '${consensus.ensemble.upVotes} analistas votaron alza y ${consensus.ensemble.downVotes} baja, '
          'con el consejo matemático ${consensus.briefing.consensusSignal >= 0 ? 'a favor del alza' : 'a favor de la baja'}.');

    return PulseRoundPlan(
      roundStart: roundStart,
      roundEnd: roundEnd,
      entryPrice: entryPrice,
      direction: consensus.direction,
      probabilityUp: consensus.probabilityUp,
      expectedMovePct: expected,
      targetPrice: target,
      invalidationPrice: invalidation,
      drivers: List<String>.unmodifiable(drivers),
      strategy: strategy.toString(),
      lockedAtSecondsRemaining: secondsRemaining,
      analystAgreement: consensus.agreement,
      councilAgreement: consensus.briefing.internalAgreement,
    );
  }
}

/// Live measurement of the locked plan against what the market is doing now.
class PulseRoundTracking {
  const PulseRoundTracking({
    required this.status,
    required this.currentPrice,
    required this.movePct,
    required this.progressToTarget,
    required this.liveProbabilityUp,
    required this.probabilityDrift,
    required this.secondsRemaining,
    required this.needsPct,
    required this.commentary,
  });

  final RoundPlanStatus status;
  final double currentPrice;

  /// Signed distance from the round open, in percent.
  final double movePct;

  /// 0..1 progress toward the plan's target (negative excursions clamp to 0).
  final double progressToTarget;

  final double liveProbabilityUp;

  /// How much the live probability moved since the plan was locked.
  final double probabilityDrift;

  final int secondsRemaining;

  /// Percentage the price still has to travel to finish on the planned side.
  final double needsPct;

  final String commentary;

  bool get settled =>
      status == RoundPlanStatus.settledWin ||
      status == RoundPlanStatus.settledLoss;

  static PulseRoundTracking evaluate({
    required PulseRoundPlan plan,
    required double currentPrice,
    required int secondsRemaining,
    required double liveProbabilityUp,
    bool closed = false,
  }) {
    final entry = plan.entryPrice;
    final movePct = entry <= 0 ? 0.0 : (currentPrice - entry) / entry * 100;
    final favourable = plan.isUp ? movePct > 0 : movePct < 0;
    final magnitude = movePct.abs();
    final progress = plan.expectedMovePct <= 0
        ? 0.0
        : (favourable ? (magnitude / plan.expectedMovePct) : 0.0)
            .clamp(0.0, 1.0)
            .toDouble();

    final invalidationDistance = entry <= 0
        ? 0.0
        : (plan.invalidationPrice - entry) / entry * 100;
    final breached = plan.isUp
        ? movePct <= invalidationDistance
        : movePct >= invalidationDistance;

    RoundPlanStatus status;
    if (closed) {
      status = favourable ? RoundPlanStatus.settledWin : RoundPlanStatus.settledLoss;
    } else if (secondsRemaining >= 285 && magnitude < .002) {
      status = RoundPlanStatus.building;
    } else if (breached) {
      status = RoundPlanStatus.invalidated;
    } else if (favourable) {
      status = RoundPlanStatus.onTrack;
    } else {
      status = RoundPlanStatus.atRisk;
    }

    final needs = favourable ? 0.0 : magnitude;
    final drift = liveProbabilityUp - plan.probabilityUp;

    final commentary = _commentary(
      plan: plan,
      status: status,
      movePct: movePct,
      needsPct: needs,
      secondsRemaining: secondsRemaining,
      drift: drift,
    );

    return PulseRoundTracking(
      status: status,
      currentPrice: currentPrice,
      movePct: movePct,
      progressToTarget: progress,
      liveProbabilityUp: liveProbabilityUp,
      probabilityDrift: drift,
      secondsRemaining: secondsRemaining,
      needsPct: needs,
      commentary: commentary,
    );
  }

  static String _commentary({
    required PulseRoundPlan plan,
    required RoundPlanStatus status,
    required double movePct,
    required double needsPct,
    required int secondsRemaining,
    required double drift,
  }) {
    final side = plan.isUp ? 'alza' : 'baja';
    final moveText = '${movePct >= 0 ? '+' : ''}${movePct.toStringAsFixed(3)}%';
    final driftText = drift.abs() < .01
        ? 'la probabilidad se mantiene estable'
        : drift > 0
            ? 'la probabilidad de subida creció ${(drift * 100).toStringAsFixed(1)} puntos'
            : 'la probabilidad de subida cayó ${(drift.abs() * 100).toStringAsFixed(1)} puntos';

    switch (status) {
      case RoundPlanStatus.building:
        return 'Procesando el gráfico de apertura para fijar la tesis de la ronda.';
      case RoundPlanStatus.onTrack:
        return 'El precio va $moveText desde la apertura, a favor de la tesis de $side. '
            'Quedan ${_mmss(secondsRemaining)} y $driftText.';
      case RoundPlanStatus.atRisk:
        return 'El precio va $moveText, en contra de la tesis de $side. '
            'Necesita recuperar ${needsPct.toStringAsFixed(3)}% en ${_mmss(secondsRemaining)} para cerrar a favor; $driftText.';
      case RoundPlanStatus.invalidated:
        return 'El precio rompió el nivel de invalidación con $moveText. '
            'La tesis de $side queda anulada para esta ronda; el motor registra el fallo y aprende de él.';
      case RoundPlanStatus.settledWin:
        return 'La ronda cerró $moveText: la tesis de $side se cumplió. El resultado alimenta la evolución de los analistas.';
      case RoundPlanStatus.settledLoss:
        return 'La ronda cerró $moveText: la tesis de $side falló. Los analistas responsables pierden peso en la próxima ronda.';
    }
  }

  static String _mmss(int seconds) {
    final s = seconds.clamp(0, 3600);
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }
}
