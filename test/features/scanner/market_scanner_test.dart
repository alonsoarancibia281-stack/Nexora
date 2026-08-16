import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/market/domain/market_asset.dart';
import 'package:nexora_markets_ai/features/scanner/domain/market_scanner.dart';
import 'package:nexora_markets_ai/features/scanner/domain/setup_strategy.dart';
import 'package:nexora_markets_ai/features/scanner/domain/trade_plan.dart';
import 'package:nexora_markets_ai/features/scanner/domain/trade_record.dart';

MarketAsset asset(
  String base, {
  double price = 10,
  double change = 2,
  double volume = 50000000,
}) =>
    MarketAsset(
      symbol: '${base}USDT',
      baseAsset: base,
      quoteAsset: 'USDT',
      price: price,
      changePercent24h: change,
      volume24h: volume,
    );

/// Daily candles with a steady drift and a volume spike every fifth day.
List<Candle> daily({
  required double drift,
  int count = 200,
  double start = 100,
}) {
  final candles = <Candle>[];
  var price = start;
  for (var i = 0; i < count; i++) {
    final open = price;
    price = math.max(price + drift, 1);
    candles.add(
      Candle(
        openTime: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
        open: open,
        high: math.max(open, price) + .4,
        low: math.min(open, price) - .4,
        close: price,
        volume: i % 5 == 0 ? 300 : 100,
      ),
    );
  }
  return candles;
}

void main() {
  const scanner = MarketScanner();

  group('scanner', () {
    test('drops stablecoins, leveraged tokens and thin pairs', () {
      expect(scanner.isTradable(asset('BTC')), isTrue);
      expect(scanner.isTradable(asset('USDC')), isFalse);
      expect(scanner.isTradable(asset('FDUSD')), isFalse);
      expect(scanner.isTradable(asset('BTCUP')), isFalse);
      expect(scanner.isTradable(asset('ETHDOWN')), isFalse);
      expect(scanner.isTradable(asset('SOL', price: 0)), isFalse);
    });

    test('keeps the pairs that move up with money behind them', () {
      final shortlist = scanner.shortlist([
        asset('BTC', volume: 900000000),
        asset('ETH', volume: 500000000),
        asset('TINY', volume: 100000),
        asset('RED', volume: 400000000, change: -3),
        asset('USDC', volume: 800000000),
      ]);

      expect(
        shortlist.map((a) => a.baseAsset).toList(),
        ['BTC', 'ETH'],
      );
    });

    test('short history produces no measurement', () {
      expect(scanner.measure(asset('BTC'), daily(drift: 1, count: 10)), isNull);
    });

    test('measures the week, the month and the strength', () {
      final candidate = scanner.measure(asset('BTC'), daily(drift: 1));
      expect(candidate, isNotNull);
      expect(candidate!.weekChangePercent, greaterThan(0));
      expect(candidate.monthChangePercent, greaterThan(candidate.weekChangePercent));
      expect(candidate.isNearHigh, isTrue);
      expect(candidate.upDayRatio, 1);
      expect(candidate.strength, inInclusiveRange(0, 100));
    });

    test('a falling market never reaches the results', () {
      final falling = scanner.measure(asset('BTC'), daily(drift: -1));
      expect(falling, isNotNull);
      expect(scanner.rank([falling!]), isEmpty);
    });
  });

  group('strategy backtest', () {
    test('a rule that wins on this history reports a real hit rate', () {
      const strategy = BreakoutStrategy();
      final record = strategy.backtest(DailySeries(daily(drift: .8)));

      expect(record.hasSample, isTrue);
      expect(record.trades, greaterThanOrEqualTo(12));
      expect(record.hitRate, 1);
      // Two to one on every trade, minus the last one, which runs out of
      // history and is closed at the price it had.
      expect(record.averageR, inInclusiveRange(1.8, 2));
      expect(record.isFavorable, isTrue);
    });

    test('the same rule finds nothing in a falling market', () {
      const strategy = BreakoutStrategy();
      final record = strategy.backtest(DailySeries(daily(drift: -.8)));

      expect(record.trades, 0);
      expect(record.hasSample, isFalse);
      expect(record.isFavorable, isFalse);
    });

    test('short history means no backtest at all', () {
      const strategy = BreakoutStrategy();
      final record = strategy.backtest(DailySeries(daily(drift: 1, count: 40)));
      expect(record.trades, 0);
    });

    test('the live signal fires on the last closed bar', () {
      // 201 bars puts a volume spike on the final one.
      final series = DailySeries(daily(drift: .8, count: 201));
      final report = const BreakoutStrategy().review(series);

      expect(report.isLive, isTrue);
      expect(report.isPlayable, isTrue);
      final levels = report.live!;
      expect(levels.stop, lessThan(levels.entry));
      expect(levels.target, greaterThan(levels.entry));
      expect(levels.riskReward, closeTo(2, .001));
    });

    test('the desk only plays a rule with the odds on its side', () {
      const desk = StrategyDesk();
      final rising = desk.review(DailySeries(daily(drift: .8, count: 201)));
      expect(desk.bestPlay(rising), isNotNull);

      final falling = desk.review(DailySeries(daily(drift: -.8, count: 201)));
      expect(desk.bestPlay(falling), isNull);
    });
  });

  group('trade plan', () {
    test('the size comes from the money you accept losing', () {
      final candidate = scanner.measure(asset('BTC'), daily(drift: 1))!;
      final report = const BreakoutStrategy()
          .review(DailySeries(daily(drift: .8, count: 201)));

      final plan = const TradePlanner().build(
        candidate: candidate,
        report: report,
        capital: 2000,
        riskPercent: 1,
      );

      expect(plan, isNotNull);
      expect(plan!.maxLoss, closeTo(20, .0001));
      expect(
        plan.units * plan.levels.riskPerUnit,
        closeTo(20, .0001),
      );
      expect(plan.possibleGain, closeTo(40, .001));
      expect(plan.toClipboardText(), contains('Nexora no ejecuta órdenes'));
    });

    test('no live rule means no plan', () {
      final candidate = scanner.measure(asset('BTC'), daily(drift: 1))!;
      final quiet = const BreakoutStrategy()
          .review(DailySeries(daily(drift: -.8, count: 201)));

      expect(
        const TradePlanner().build(
          candidate: candidate,
          report: quiet,
          capital: 2000,
          riskPercent: 1,
        ),
        isNull,
      );
    });
  });

  group('history', () {
    test('counts only the ideas that closed', () {
      final now = DateTime.utc(2026, 8, 16, 12);
      final records = [
        TradeRecord(
          id: '1',
          symbol: 'BTCUSDT',
          pair: 'BTC/USDT',
          strategyId: 'breakout',
          strategyName: 'Ruptura',
          entry: 100,
          stop: 95,
          target: 110,
          hitRate: .6,
          trades: 20,
          createdAt: now,
        ).close(exitPrice: 110, at: now),
        TradeRecord(
          id: '2',
          symbol: 'ETHUSDT',
          pair: 'ETH/USDT',
          strategyId: 'breakout',
          strategyName: 'Ruptura',
          entry: 100,
          stop: 95,
          target: 110,
          hitRate: .6,
          trades: 20,
          createdAt: now,
        ).close(exitPrice: 95, at: now),
        TradeRecord(
          id: '3',
          symbol: 'SOLUSDT',
          pair: 'SOL/USDT',
          strategyId: 'squeeze',
          strategyName: 'Compresión',
          entry: 100,
          stop: 95,
          target: 110,
          hitRate: .6,
          trades: 20,
          createdAt: now,
        ),
      ];

      final tally = TradeTally.of(records);
      expect(tally.wins, 1);
      expect(tally.losses, 1);
      expect(tally.open, 1);
      expect(tally.closed, 2);
      expect(tally.hitRate, .5);
      expect(tally.averageResultPercent, closeTo(2.5, .001));
    });

    test('a record survives a round trip through storage', () {
      final record = TradeRecord(
        id: 'x',
        symbol: 'BTCUSDT',
        pair: 'BTC/USDT',
        strategyId: 'pullback',
        strategyName: 'Retroceso',
        entry: 100,
        stop: 96,
        target: 108,
        hitRate: .55,
        trades: 18,
        createdAt: DateTime.utc(2026, 8, 16, 9),
      );

      final restored = TradeRecord.fromJson(record.toJson());
      expect(restored.id, record.id);
      expect(restored.entry, record.entry);
      expect(restored.strategyName, record.strategyName);
      expect(restored.outcome, TradeOutcome.open);
    });
  });
}
