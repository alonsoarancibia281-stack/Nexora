import 'dart:math' as math;

/// What the trade tape adds to the diffusion anchor, as a log-odds correction.
///
/// The 100 analysts already read the flow, but their vote is one of many inside
/// a pool that is then clamped to ±0.70: a real but small edge arrives at the
/// verdict divided by the crowd and truncated by the bound. Measured over 8639
/// rounds, three tape features carry information the anchor does not have
/// (aggressor imbalance z=5.06, price impulse z=3.39, persistence z=3.55, all
/// past a Bonferroni threshold of 0.005, joint chi-square 49.09 on 5 d.f.),
/// while every candle-derived control came back null — the anchor already
/// absorbs everything the candles know.
///
/// So the flow enters here, once, with the weight it was measured to deserve,
/// outside the council's bound.
class PulseFlowEdge {
  const PulseFlowEdge({
    required this.aggressorImbalance,
    required this.priceImpulseBps,
    required this.flowPersistence,
    required this.trades,
  });

  /// Signed share of volume that crossed the spread, in [-1,1].
  final double aggressorImbalance;

  /// Price travelled over the flow window, in basis points.
  final double priceImpulseBps;

  /// How consistently the tape leaned the same way, in [-1,1].
  final double flowPersistence;

  /// Prints behind the reading. Zero means there is no tape to read.
  final int trades;

  static const PulseFlowEdge empty = PulseFlowEdge(
    aggressorImbalance: 0,
    priceImpulseBps: 0,
    flowPersistence: 0,
    trades: 0,
  );

  // --- Fitted coefficients ---------------------------------------------------
  //
  // Joint logistic fit of the round outcome on the anchor plus these three
  // features in raw units, trained on the first 6047 of 8639 rounds with the
  // remaining 2592 held back. Copied from tool/flow_information.dart; nothing
  // here is tuned by hand.
  //
  // They must be copied together. Price impulse and the anchor measure almost
  // the same thing — the ground covered during the minute that just closed — so
  // fitted jointly they split the credit, and the anchor lands at 0.48 instead
  // of the 0.7754 it takes when it is the only term in the model. Pairing the
  // solo anchor with the joint flow weights would count that minute twice.
  static const double _wImbalance = .1629;
  static const double _wImpulse = 1.3077;
  static const double _wPersistence = .0581;

  /// How much of the anchor's own log-odds survives into the verdict.
  ///
  /// Well under 1 either way: the diffusion formula points in the right
  /// direction but claims more certainty than the outcomes grant it. On the
  /// held-back rounds the recalibration alone moved the log-loss from 0.64068
  /// to 0.63674, and adding the tape took it to 0.63400.
  static const double anchorShrink = .4800;

  /// Ceiling on the tape's own contribution, in log-odds.
  ///
  /// The impulse term reaches 1.31 only when the minute travelled the full
  /// 20 bps the reading is clipped at, which is rare; the bound exists so a
  /// single degenerate window cannot swamp everything else.
  static const double bound = 1.20;

  bool get isReady => trades > 0;

  /// Log-odds the tape adds on top of the anchor.
  double get logOdds {
    if (!isReady) return 0;
    final imbalance = aggressorImbalance.clamp(-1.0, 1.0).toDouble();
    final impulse = (priceImpulseBps / 20).clamp(-1.0, 1.0).toDouble();
    final persistence = flowPersistence.clamp(-1.0, 1.0).toDouble();
    final raw = _wImbalance * imbalance +
        _wImpulse * impulse +
        _wPersistence * persistence;
    if (!raw.isFinite) return 0;
    return raw.clamp(-bound, bound).toDouble();
  }

  /// Probability the tape alone would imply, for display.
  double get probabilityUp => 1 / (1 + math.exp(-logOdds.clamp(-30.0, 30.0)));
}
