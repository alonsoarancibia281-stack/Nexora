/// Quantifiable knowledge framework inspired by established market/investment
/// literature. It stores principles as testable model roles rather than
/// reproducing book text or treating any author as an oracle.
enum KnowledgePillar {
  safety,
  factorRanking,
  randomness,
  confirmation,
  breakout,
  technical,
  sentiment,
  benchmark,
  assetContext,
  robustness,
  behavioral,
  multiTimeframe,
}

class KnowledgeRule {
  const KnowledgeRule({
    required this.id,
    required this.pillar,
    required this.purpose,
    required this.metrics,
  });

  final String id;
  final KnowledgePillar pillar;
  final String purpose;
  final List<String> metrics;
}

class MarketKnowledgeFramework {
  const MarketKnowledgeFramework();

  static const rules = <KnowledgeRule>[
    KnowledgeRule(id:'margin_of_safety',pillar:KnowledgePillar.safety,purpose:'Reduce confidence when statistical edge is too small.',metrics:['calibrated_edge','instability','expected_move']),
    KnowledgeRule(id:'factor_ranking',pillar:KnowledgePillar.factorRanking,purpose:'Rank analysts by validated usefulness instead of equal voting.',metrics:['brier','log_loss','ece','sample_size']),
    KnowledgeRule(id:'random_walk_guard',pillar:KnowledgePillar.randomness,purpose:'Require models to beat simple/random baselines out of sample.',metrics:['baseline_accuracy','permutation_p','excess_brier']),
    KnowledgeRule(id:'market_confirmation',pillar:KnowledgePillar.confirmation,purpose:'Check whether price behaves as predicted after the initial hypothesis.',metrics:['price_response','signed_flow','acceptance','absorption']),
    KnowledgeRule(id:'micro_boxes',pillar:KnowledgePillar.breakout,purpose:'Detect compression, breakout, acceptance and failed breakout.',metrics:['range_width','atr','volume','breakout_hold']),
    KnowledgeRule(id:'technical_confluence',pillar:KnowledgePillar.technical,purpose:'Use trend, momentum, volatility and support/resistance as a confluence.',metrics:['ema','macd','rsi','adx','bollinger','atr','stochastic','vwap']),
    KnowledgeRule(id:'exuberance_guard',pillar:KnowledgePillar.sentiment,purpose:'Detect abnormal euphoria/panic without blindly fading strong moves.',metrics:['return_z','volume_z','volatility_z','flow_extreme']),
    KnowledgeRule(id:'cost_benchmark',pillar:KnowledgePillar.benchmark,purpose:'Reject complexity that does not improve simple benchmarks after friction.',metrics:['spread','turnover','baseline_delta']),
    KnowledgeRule(id:'btc_context',pillar:KnowledgePillar.assetContext,purpose:'Require context relevant to BTC rather than equity fundamentals.',metrics:['btc_flow','eth_confirmation','liquidity','cross_market']),
    KnowledgeRule(id:'robustness_audit',pillar:KnowledgePillar.robustness,purpose:'Penalize overfit strategies and unstable parameter choices.',metrics:['bootstrap_stability','walk_forward','parameter_sensitivity']),
    KnowledgeRule(id:'behavioral_guard',pillar:KnowledgePillar.behavioral,purpose:'Prevent recency, overconfidence, anchoring and loss-chasing from affecting confidence.',metrics:['streak_bias','confidence_gap','anchor_distance','recent_weight']),
    KnowledgeRule(id:'triple_context',pillar:KnowledgePillar.multiTimeframe,purpose:'Separate higher-timeframe regime, setup and short-term timing.',metrics:['1m','5m','15m','1h']),
  ];

  /// Returns a conservative confidence multiplier. A value below 1 means the
  /// knowledge/audit layer found reasons to distrust an otherwise strong vote.
  double confidenceMultiplier({
    required double instability,
    required double analystAgreement,
    required double statisticalEdge,
    required double baselineAdvantage,
    required double robustness,
  }) {
    final stable = (1 - instability.clamp(0.0, 1.0) * .45);
    final agreement = (.55 + analystAgreement.clamp(0.0, 1.0) * .45);
    final edge = (.45 + statisticalEdge.clamp(0.0, 1.0) * .55);
    final benchmark = (.50 + baselineAdvantage.clamp(0.0, 1.0) * .50);
    final robust = (.55 + robustness.clamp(0.0, 1.0) * .45);
    return (stable * agreement * edge * benchmark * robust).clamp(.18, 1.0).toDouble();
  }
}
