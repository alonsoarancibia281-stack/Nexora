import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/pulse/domain/agent_scoreboard.dart';
import 'package:nexora_markets_ai/features/pulse/domain/market_agent.dart';
import 'package:nexora_markets_ai/features/pulse/domain/market_agent_desk.dart';
import 'package:nexora_markets_ai/features/pulse/domain/market_reading.dart';
import 'package:nexora_markets_ai/features/pulse/domain/prediction_horizon.dart';
import 'package:nexora_markets_ai/features/pulse/domain/prediction_outlook.dart';
import 'package:nexora_markets_ai/features/pulse/domain/round_clock.dart';

List<Candle> series({
  required double drift,
  int count = 80,
  double start = 100,
  double noise = 0,
  double volume = 120,
}) {
  final candles = <Candle>[];
  var price = start;
  for (var i = 0; i < count; i++) {
    final open = price;
    final wobble = noise == 0 ? 0.0 : (i.isEven ? noise : -noise);
    price = price + drift + wobble;
    candles.add(
      Candle(
        openTime: DateTime.fromMillisecondsSinceEpoch(i * 60000, isUtc: true),
        open: open,
        high: (open > price ? open : price) + 0.03,
        low: (open < price ? open : price) - 0.03,
        close: price,
        volume: volume + (i % 5),
      ),
    );
  }
  return candles;
}

MarketReading? reading({
  required double drift,
  PredictionHorizon horizon = PredictionHorizon.m5,
  double bookImbalance = 0,
  double flowImbalance = 0,
  double noise = 0,
  int secondsLeft = 150,
  double? startPriceOverride,
}) {
  final candles = series(drift: drift, noise: noise);
  final context = series(drift: drift * 3, count: 40);
  final startPrice = startPriceOverride ?? candles[candles.length - 5].close;
  return const MarketReadingBuilder().build(
    horizon: horizon,
    baseCandles: candles,
    contextCandles: context,
    startPrice: startPrice,
    secondsLeft: secondsLeft,
    book: BookSnapshotMetrics(
      bidVolume: 1000 * (1 + bookImbalance),
      askVolume: 1000 * (1 - bookImbalance),
      spreadBps: 1.2,
      micropriceEdgeBps: bookImbalance * 2,
    ),
    flow: TradeFlowMetrics(
      aggressorImbalance: flowImbalance,
      signedVolume: flowImbalance,
      tradeAcceleration: flowImbalance.abs(),
      priceImpulseBps: flowImbalance * 8,
    ),
  );
}

void main() {
  const desk = MarketAgentDesk();
  final now = DateTime.utc(2026, 8, 16, 14, 37);

  PredictionOutlook review(MarketReading value) => desk.review(
        reading: value,
        window: RoundWindow.at(value.horizon, now),
        now: now,
      );

  test('the desk keeps exactly six agents', () {
    expect(coreAgents.length, 6);
    expect(
      coreAgents.map((agent) => agent.id).toSet().length,
      coreAgents.length,
    );
  });

  test('reads a rising market as up', () {
    final value = reading(drift: .09, bookImbalance: .35, flowImbalance: .45);
    expect(value, isNotNull);
    final outlook = review(value!);
    expect(outlook.probabilityUp, greaterThan(.5));
    expect(outlook.call, PredictionCall.up);
    expect(outlook.confidence, greaterThan(50));
  });

  test('reads a falling market as down', () {
    final value = reading(drift: -.09, bookImbalance: -.35, flowImbalance: -.45);
    final outlook = review(value!);
    expect(outlook.probabilityUp, lessThan(.5));
    expect(outlook.call, PredictionCall.down);
  });

  test('waits when the market goes nowhere', () {
    final value = reading(drift: 0, noise: .05, startPriceOverride: 100);
    final outlook = review(value!);
    expect(outlook.call, PredictionCall.wait);
    expect(outlook.probabilityUp, closeTo(.5, .06));
  });

  test('never claims certainty', () {
    for (final horizon in PredictionHorizon.values) {
      final value = reading(
        drift: .6,
        horizon: horizon,
        bookImbalance: .9,
        flowImbalance: .9,
      );
      final outlook = review(value!);
      expect(outlook.probability, lessThanOrEqualTo(.90));
      expect(outlook.probability, greaterThanOrEqualTo(.5));
    }
  });

  test('the one hour desk leans on trend more than on the book', () {
    const trend = TrendAgent();
    const liquidity = LiquidityAgent();
    expect(
      trend.horizonWeight(PredictionHorizon.h1),
      greaterThan(liquidity.horizonWeight(PredictionHorizon.h1)),
    );
    expect(
      liquidity.horizonWeight(PredictionHorizon.m5),
      greaterThan(liquidity.horizonWeight(PredictionHorizon.h1)),
    );
  });

  test('every view carries a one line note', () {
    final value = reading(drift: .05, bookImbalance: .2, flowImbalance: .2);
    final outlook = review(value!);
    expect(outlook.views.length, 6);
    for (final view in outlook.views) {
      expect(view.note.contains('\n'), isFalse);
      expect(view.note.length, lessThan(60));
      expect(view.probabilityUp, inInclusiveRange(0.0, 1.0));
      expect(view.relevance, inInclusiveRange(0.0, 1.0));
    }
  });

  test('a proven agent weighs more than a broken one', () {
    var board = const AgentScoreboard();
    for (var i = 0; i < 30; i++) {
      board = board.settle(
        horizon: PredictionHorizon.m5,
        views: [
          const AgentView(
            id: 'trend',
            name: 'Tendencia',
            focus: 'test',
            probabilityUp: .8,
            relevance: .9,
            note: 'sube',
          ),
          const AgentView(
            id: 'flow',
            name: 'Flujo',
            focus: 'test',
            probabilityUp: .2,
            relevance: .9,
            note: 'baja',
          ),
        ],
        closedUp: true,
      );
    }
    final good = board.reliabilityOf(PredictionHorizon.m5, 'trend');
    final bad = board.reliabilityOf(PredictionHorizon.m5, 'flow');
    expect(good, greaterThan(bad));
    expect(good, lessThanOrEqualTo(1.35));
    expect(bad, greaterThanOrEqualTo(.65));
    expect(board.samplesOf(PredictionHorizon.m5), 60);
  });

  test('short history produces no reading', () {
    expect(
      const MarketReadingBuilder().build(
        horizon: PredictionHorizon.m5,
        baseCandles: series(drift: .1, count: 10),
        contextCandles: const [],
        startPrice: 100,
        secondsLeft: 120,
      ),
      isNull,
    );
  });
}
