import 'dart:math' as math;

import '../../market/domain/candle.dart';
import 'order_book_prediction.dart';
import 'order_book_snapshot.dart';

class OrderBookPredictionEngine {
  const OrderBookPredictionEngine();

  OrderBookPrediction analyze(
    OrderBookSnapshot snapshot, {
    int levels = 20,
    List<Candle> candles = const [],
  }) {
    final bids = snapshot.bids.take(levels).toList();
    final asks = snapshot.asks.take(levels).toList();
    if (bids.isEmpty || asks.isEmpty) {
      throw ArgumentError(
          'Se necesitan compras y ventas para analizar el libro.');
    }

    final midpoint = snapshot.midpoint;
    final spreadBps = midpoint <= 0
        ? 0.0
        : (snapshot.bestAsk - snapshot.bestBid) / midpoint * 10000;
    final topTotal = bids.first.quantity + asks.first.quantity;
    final microprice = topTotal <= 0
        ? midpoint
        : (snapshot.bestAsk * bids.first.quantity +
                snapshot.bestBid * asks.first.quantity) /
            topTotal;
    final micropriceEdgeBps =
        midpoint <= 0 ? 0.0 : (microprice - midpoint) / midpoint * 10000;

    final opinions = <_AnalystOpinion>[];
    for (final family in OrderBookAnalystFamily.values) {
      for (var variant = 0; variant < 10; variant++) {
        opinions.add(
          _runAnalyst(
            id: family.index * 10 + variant + 1,
            family: family,
            variant: variant,
            bids: bids,
            asks: asks,
            candles: candles,
            spreadBps: spreadBps,
            micropriceEdgeBps: micropriceEdgeBps,
          ),
        );
      }
    }

    final teams = OrderBookAnalystFamily.values
        .map(
          (family) => _aggregateTeam(
            family,
            opinions.where((opinion) => opinion.family == family).toList(),
          ),
        )
        .toList(growable: false);
    final usableTeams = teams.where((team) => team.quality > .01).toList();

    var probabilityUp = .5;
    if (usableTeams.isNotEmpty) {
      var weighted = 0.0;
      var weightSum = 0.0;
      for (final team in usableTeams) {
        final weight = team.quality * (1 - team.disagreement * .4);
        weighted += team.probabilityUp * weight;
        weightSum += weight;
      }
      if (weightSum > 0) probabilityUp = weighted / weightSum;
    }

    final teamDisagreement = teams.isEmpty
        ? 0.0
        : teams.map((team) => team.disagreement).reduce((a, b) => a + b) /
            teams.length;
    final spreadShrink = (1 / (1 + spreadBps / 8)).clamp(.25, 1.0);
    final disagreementShrink = (1 - teamDisagreement * .45).clamp(.45, 1.0);
    probabilityUp =
        .5 + (probabilityUp - .5) * spreadShrink * disagreementShrink;
    probabilityUp = probabilityUp.clamp(.15, .85).toDouble();

    final directional = opinions
        .where((opinion) => (opinion.probabilityUp - .5).abs() >= .02)
        .toList();
    final upVotes =
        directional.where((opinion) => opinion.probabilityUp > .5).length;
    final downVotes = directional.length - upVotes;
    final agreement = directional.isEmpty
        ? 0.0
        : math.max(upVotes, downVotes) / directional.length;
    final score = ((probabilityUp - .5) * 200).clamp(-100.0, 100.0).toDouble();
    final confidence = (50 + score.abs() * .32 - teamDisagreement * 12)
        .clamp(45.0, 82.0)
        .toDouble();
    final bias = score >= 18 && agreement >= .58
        ? OrderBookBias.bullish
        : score <= -18 && agreement >= .58
            ? OrderBookBias.bearish
            : OrderBookBias.neutral;
    final imbalance =
        _imbalance(bids, asks, math.min(bids.length, asks.length));

    return OrderBookPrediction(
      bias: bias,
      score: score,
      confidence: confidence,
      upProbability: probabilityUp * 100,
      imbalancePercent: imbalance * 100,
      spreadBps: spreadBps,
      micropriceEdgeBps: micropriceEdgeBps,
      activeAnalysts: opinions.length,
      agreement: agreement,
      teamOpinions: teams,
      summary: switch (bias) {
        OrderBookBias.bullish => 'Oportunidad de compra en observacion',
        OrderBookBias.bearish => 'Oportunidad de venta en observacion',
        OrderBookBias.neutral => 'Esperar: el pool no confirma una oportunidad',
      },
      reasons: [
        'Desequilibrio de profundidad ${imbalance >= 0 ? '+' : ''}${(imbalance * 100).toStringAsFixed(1)}%.',
        'Spread ${spreadBps.toStringAsFixed(2)} bps; un spread mayor reduce la confianza.',
        'Microprecio ${micropriceEdgeBps >= 0 ? '+' : ''}${micropriceEdgeBps.toStringAsFixed(2)} bps frente al punto medio.',
        if (candles.isNotEmpty)
          'Ultima vela ${candles.last.close >= candles.last.open ? 'alcista' : 'bajista'}; el pool exige confirmacion con tendencia y volumen.',
      ],
    );
  }

  _AnalystOpinion _runAnalyst({
    required int id,
    required OrderBookAnalystFamily family,
    required int variant,
    required List<OrderBookLevel> bids,
    required List<OrderBookLevel> asks,
    required List<Candle> candles,
    required double spreadBps,
    required double micropriceEdgeBps,
  }) {
    final maxDepth = math.min(bids.length, asks.length);
    final depth = math.min(maxDepth, math.max(1, variant + 1));
    final fullDepth = math.min(maxDepth, math.max(1, 5 + variant));
    final spreadQuality = (1 / (1 + spreadBps / 20)).clamp(.05, 1.0);
    late double edge;

    switch (family) {
      case OrderBookAnalystFamily.topOfBook:
        edge = _imbalance(bids, asks, math.min(depth, 3));
      case OrderBookAnalystFamily.depthBalance:
        edge = _imbalance(bids, asks, fullDepth);
      case OrderBookAnalystFamily.weightedDepth:
        edge = _weightedImbalance(bids, asks, fullDepth, 1 + variant / 12);
      case OrderBookAnalystFamily.microprice:
        edge = (micropriceEdgeBps / (1.2 + variant * .18)).clamp(-1.0, 1.0);
      case OrderBookAnalystFamily.walls:
        edge = _wallImbalance(bids, asks, fullDepth);
      case OrderBookAnalystFamily.trend:
        edge = _trendEdge(candles, variant);
      case OrderBookAnalystFamily.momentum:
        edge = _momentumEdge(candles, variant);
      case OrderBookAnalystFamily.candleStructure:
        edge = _candlePressure(candles, variant);
      case OrderBookAnalystFamily.volume:
        edge = _volumeEdge(candles, variant);
      case OrderBookAnalystFamily.volatility:
        edge = _volatilityBreakout(candles, variant);
    }

    edge = edge.clamp(-1.0, 1.0).toDouble();
    final temperature = .22 + variant * .008;
    final probabilityUp = 1 / (1 + math.exp(-edge / temperature));
    final candleFamily = family.index >= OrderBookAnalystFamily.trend.index;
    final qualityFactor =
        candleFamily ? .8 + spreadQuality * .2 : spreadQuality;
    return _AnalystOpinion(
      id: id,
      family: family,
      task: candleFamily
          ? '${family.label} · ventana ${variant + 2}'
          : '${family.label} · profundidad $depth',
      probabilityUp: probabilityUp,
      quality: (edge.abs() * qualityFactor).clamp(0.0, 1.0).toDouble(),
    );
  }

  OrderBookTeamOpinion _aggregateTeam(
    OrderBookAnalystFamily family,
    List<_AnalystOpinion> members,
  ) {
    var weighted = 0.0;
    var weightSum = 0.0;
    for (final member in members) {
      final weight = member.quality.clamp(.01, 1.0);
      weighted += member.probabilityUp * weight;
      weightSum += weight;
    }
    final mean = weightSum <= 0 ? .5 : weighted / weightSum;
    final variance = members.isEmpty
        ? 0.0
        : members
                .map((member) => math.pow(member.probabilityUp - mean, 2))
                .reduce((a, b) => a + b) /
            members.length;
    final quality = members.isEmpty
        ? 0.0
        : members.map((member) => member.quality).reduce((a, b) => a + b) /
            members.length;
    final firstId = members.isEmpty ? 0 : members.first.id;
    final lastId = members.isEmpty ? 0 : members.last.id;
    return OrderBookTeamOpinion(
      family: family,
      task:
          'Analistas $firstId-$lastId · ${members.isEmpty ? family.label : members.first.task}',
      probabilityUp: mean,
      quality: quality,
      disagreement: (math.sqrt(variance) * 2).clamp(0.0, 1.0).toDouble(),
    );
  }

  double _imbalance(
      List<OrderBookLevel> bids, List<OrderBookLevel> asks, int depth) {
    final safeDepth = math.min(depth, math.min(bids.length, asks.length));
    final bid = bids
        .take(safeDepth)
        .fold<double>(0, (sum, level) => sum + level.quantity);
    final ask = asks
        .take(safeDepth)
        .fold<double>(0, (sum, level) => sum + level.quantity);
    return bid + ask <= 0 ? 0 : (bid - ask) / (bid + ask);
  }

  double _weightedImbalance(
    List<OrderBookLevel> bids,
    List<OrderBookLevel> asks,
    int depth,
    double power,
  ) {
    var bid = 0.0;
    var ask = 0.0;
    for (var i = 0; i < depth; i++) {
      final weight = 1 / math.pow(i + 1, power);
      bid += bids[i].quantity * weight;
      ask += asks[i].quantity * weight;
    }
    return bid + ask <= 0 ? 0 : (bid - ask) / (bid + ask);
  }

  double _wallImbalance(
      List<OrderBookLevel> bids, List<OrderBookLevel> asks, int depth) {
    final bidWall =
        bids.take(depth).map((level) => level.quantity).reduce(math.max);
    final askWall =
        asks.take(depth).map((level) => level.quantity).reduce(math.max);
    return bidWall + askWall <= 0
        ? 0
        : (bidWall - askWall) / (bidWall + askWall);
  }

  double _trendEdge(List<Candle> candles, int variant) {
    if (candles.length < 8) return 0;
    final closes = candles.map((candle) => candle.close).toList();
    final fast = _ema(closes, math.min(3 + variant, closes.length));
    final slow = _ema(closes, math.min(8 + variant * 2, closes.length));
    if (slow == 0) return 0;
    return ((fast - slow) / slow * 10000 / (3 + variant * .25))
        .clamp(-1.0, 1.0)
        .toDouble();
  }

  double _momentumEdge(List<Candle> candles, int variant) {
    final lookback = 2 + variant;
    if (candles.length <= lookback) return 0;
    final from = candles[candles.length - 1 - lookback].close;
    if (from == 0) return 0;
    final returnBps = (candles.last.close - from) / from * 10000;
    return (returnBps / (8 + variant * 2)).clamp(-1.0, 1.0).toDouble();
  }

  double _candlePressure(List<Candle> candles, int variant) {
    if (candles.isEmpty) return 0;
    final count = math.min(candles.length, 1 + variant);
    final recent = candles.skip(candles.length - count);
    var pressure = 0.0;
    for (final candle in recent) {
      final range = candle.high - candle.low;
      if (range > 0) pressure += (candle.close - candle.open) / range;
    }
    return (pressure / count).clamp(-1.0, 1.0).toDouble();
  }

  double _volumeEdge(List<Candle> candles, int variant) {
    if (candles.length < 8) return 0;
    final recentCount = math.min(candles.length ~/ 2, 2 + variant);
    final recent = candles.sublist(candles.length - recentCount);
    final baseline = candles.sublist(math.max(0, candles.length - 20));
    final recentVolume =
        recent.map((candle) => candle.volume).reduce((a, b) => a + b) /
            recent.length;
    final baselineVolume =
        baseline.map((candle) => candle.volume).reduce((a, b) => a + b) /
            baseline.length;
    if (baselineVolume <= 0) return 0;
    final priceDirection = (recent.last.close - recent.first.open).sign;
    return (((recentVolume / baselineVolume) - 1) / 1.5 * priceDirection)
        .clamp(-1.0, 1.0)
        .toDouble();
  }

  double _volatilityBreakout(List<Candle> candles, int variant) {
    if (candles.length < 10) return 0;
    final count = math.min(candles.length - 1, 8 + variant);
    final prior =
        candles.sublist(candles.length - 1 - count, candles.length - 1);
    final mean = prior.map((candle) => candle.close).reduce((a, b) => a + b) /
        prior.length;
    final variance = prior
            .map((candle) => math.pow(candle.close - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        prior.length;
    final deviation = math.sqrt(variance);
    if (deviation <= 0) return 0;
    return ((candles.last.close - mean) / (deviation * 2))
        .clamp(-1.0, 1.0)
        .toDouble();
  }

  double _ema(List<double> values, int period) {
    final multiplier = 2 / (period + 1);
    var value = values.first;
    for (final next in values.skip(1)) {
      value = next * multiplier + value * (1 - multiplier);
    }
    return value;
  }
}

class _AnalystOpinion {
  const _AnalystOpinion({
    required this.id,
    required this.family,
    required this.task,
    required this.probabilityUp,
    required this.quality,
  });

  final int id;
  final OrderBookAnalystFamily family;
  final String task;
  final double probabilityUp;
  final double quality;
}
