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
  // fitted jointly they split the credit and neither coefficient means anything
  // without the other. Pairing a solo anchor with joint flow weights would
  // count that minute twice.
  static const double _wImbalance = .1287;
  static const double _wImpulse = 1.0494;
  static const double _wPersistence = .0671;

  /// How much of the anchor's own log-odds survives into the verdict.
  ///
  /// This used to be 0.48, and the reason was not the anchor: σ came from the
  /// ATR times a hand-picked constant, and once it became the EWMA of
  /// one-minute log returns the anchor fitted at 0.9943 ± 0.0336 on its own —
  /// a probability that can be taken at face value. What is left here is the
  /// share it keeps when the tape sits beside it, since the two overlap.
  ///
  /// On the held-back rounds: anchor alone 63.19% and 0.63458 of log-loss,
  /// anchor plus tape 64.66% and 0.63246.
  static const double anchorShrink = .6890;

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
