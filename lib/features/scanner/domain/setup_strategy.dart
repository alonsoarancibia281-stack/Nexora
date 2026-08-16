import 'dart:math' as math;

import '../../market/domain/candle.dart';

/// Daily candles with the numbers every strategy needs, computed once.
class DailySeries {
  DailySeries(List<Candle> candles)
      : candles = List.unmodifiable(candles),
        ema20 = _ema(candles.map((c) => c.close).toList(growable: false), 20),
        ema50 = _ema(candles.map((c) => c.close).toList(growable: false), 50),
        atr = _atr(candles, 14),
        averageVolume20 = _rollingMean(
          candles.map((c) => c.volume).toList(growable: false),
          20,
        ),
        highestClose20 = _rollingMax(
          candles.map((c) => c.close).toList(growable: false),
          20,
        ),
        highestHigh10 = _rollingMax(
          candles.map((c) => c.high).toList(growable: false),
          10,
        ),
        range10 = _rollingRange(candles, 10),
        range30 = _rollingRange(candles, 30);

  final List<Candle> candles;
  final List<double> ema20;
  final List<double> ema50;
  final List<double> atr;
  final List<double> averageVolume20;
  final List<double> highestClose20;
  final List<double> highestHigh10;
  final List<double> range10;
  final List<double> range30;

  int get length => candles.length;
  int get last => candles.length - 1;
  double get price => candles.last.close;

  /// Bars needed before any strategy may fire.
  static const warmup = 55;

  bool get isUsable => candles.length >= warmup + 30;

  static List<double> _ema(List<double> values, int period) {
    final result = List<double>.filled(values.length, 0);
    if (values.isEmpty) return result;
    final k = 2 / (period + 1);
    var value = values.first;
    result[0] = value;
    for (var i = 1; i < values.length; i++) {
      value = values[i] * k + value * (1 - k);
      result[i] = value;
    }
    return result;
  }

  static List<double> _atr(List<Candle> candles, int period) {
    final result = List<double>.filled(candles.length, 0);
    var running = 0.0;
    for (var i = 0; i < candles.length; i++) {
      final candle = candles[i];
      final previousClose = i == 0 ? candle.open : candles[i - 1].close;
      final trueRange = math.max(
        candle.high - candle.low,
        math.max(
          (candle.high - previousClose).abs(),
          (candle.low - previousClose).abs(),
        ),
      );
      running = i == 0 ? trueRange : (running * (period - 1) + trueRange) / period;
      result[i] = running;
    }
    return result;
  }

  static List<double> _rollingMean(List<double> values, int window) {
    final result = List<double>.filled(values.length, 0);
    for (var i = 0; i < values.length; i++) {
      final start = math.max(0, i - window + 1);
      var sum = 0.0;
      for (var j = start; j <= i; j++) {
        sum += values[j];
      }
      result[i] = sum / (i - start + 1);
    }
    return result;
  }

  static List<double> _rollingMax(List<double> values, int window) {
    final result = List<double>.filled(values.length, 0);
    for (var i = 0; i < values.length; i++) {
      final start = math.max(0, i - window + 1);
      var best = values[start];
      for (var j = start; j <= i; j++) {
        if (values[j] > best) best = values[j];
      }
      result[i] = best;
    }
    return result;
  }

  /// Height of the last [window] bars as a share of price.
  static List<double> _rollingRange(List<Candle> candles, int window) {
    final result = List<double>.filled(candles.length, 0);
    for (var i = 0; i < candles.length; i++) {
      final start = math.max(0, i - window + 1);
      var high = candles[start].high;
      var low = candles[start].low;
      for (var j = start; j <= i; j++) {
        if (candles[j].high > high) high = candles[j].high;
        if (candles[j].low < low) low = candles[j].low;
      }
      final close = candles[i].close;
      result[i] = close <= 0 ? 0 : (high - low) / close;
    }
    return result;
  }
}

/// Entry, stop and target: the three numbers that matter.
class TradeLevels {
  const TradeLevels({
    required this.entry,
    required this.stop,
    required this.target,
  });

  final double entry;
  final double stop;
  final double target;

  double get riskPerUnit => (entry - stop).abs();
  double get rewardPerUnit => (target - entry).abs();

  double get riskPercent => entry <= 0 ? 0 : riskPerUnit / entry * 100;
  double get rewardPercent => entry <= 0 ? 0 : rewardPerUnit / entry * 100;

  double get riskReward => riskPerUnit <= 0 ? 0 : rewardPerUnit / riskPerUnit;
}

/// What the same rule did on this asset's own history.
class BacktestResult {
  const BacktestResult({
    required this.trades,
    required this.wins,
    required this.averageR,
  });

  const BacktestResult.empty()
      : trades = 0,
        wins = 0,
        averageR = 0;

  final int trades;
  final int wins;

  /// Average result per trade, measured in units of the money risked.
  final double averageR;

  double get hitRate => trades == 0 ? 0 : wins / trades;

  /// Below this the sample says nothing.
  bool get hasSample => trades >= 12;

  /// The rule made money on this history, with enough trades to mean it.
  bool get isFavorable => hasSample && averageR > 0;
}

/// One trading rule with its own entry, stop and target.
///
/// Every rule is testable: the same code that fires the live signal walks the
/// asset's history bar by bar and counts how often it worked.
abstract class SetupStrategy {
  const SetupStrategy();

  String get id;
  String get name;

  /// One line, present tense.
  String get idea;

  /// How long a trade may stay open, in days.
  int get maxHoldDays => 10;

  /// True when the rule fires on bar [i], using only data up to [i].
  bool triggers(DailySeries series, int i);

  /// Stop and target for an entry at bar [i].
  TradeLevels levels(DailySeries series, int i);

  /// Runs the rule over the whole history and counts what happened.
  BacktestResult backtest(DailySeries series) {
    if (!series.isUsable) return const BacktestResult.empty();
    var trades = 0;
    var wins = 0;
    var totalR = 0.0;

    // The last bar is left out: it has no future to be judged against.
    for (var i = DailySeries.warmup; i < series.length - 1; i++) {
      if (!triggers(series, i)) continue;
      final level = levels(series, i);
      if (level.riskPerUnit <= 0) continue;

      final outcome = _walkForward(series, i, level);
      if (outcome == null) continue;
      trades++;
      totalR += outcome;
      if (outcome > 0) wins++;
    }

    return BacktestResult(
      trades: trades,
      wins: wins,
      averageR: trades == 0 ? 0 : totalR / trades,
    );
  }

  /// Result of one historical trade, in units of risk.
  ///
  /// When a bar touches the stop and the target on the same day the loss is
  /// counted. Nobody knows which came first, and the honest assumption is the
  /// one that hurts.
  double? _walkForward(DailySeries series, int entryIndex, TradeLevels level) {
    final lastBar = math.min(entryIndex + maxHoldDays, series.length - 1);
    for (var j = entryIndex + 1; j <= lastBar; j++) {
      final candle = series.candles[j];
      if (candle.low <= level.stop) return -1;
      if (candle.high >= level.target) {
        return level.rewardPerUnit / level.riskPerUnit;
      }
    }
    final exit = series.candles[lastBar].close;
    return (exit - level.entry) / level.riskPerUnit;
  }

  /// The live reading for this asset: the record always, the levels only when
  /// the rule fires on the last closed bar.
  StrategyReport review(DailySeries series) {
    final record = backtest(series);
    final fires = series.isUsable && triggers(series, series.last);
    return StrategyReport(
      strategy: this,
      record: record,
      live: fires ? levels(series, series.last) : null,
    );
  }
}

class StrategyReport {
  const StrategyReport({
    required this.strategy,
    required this.record,
    this.live,
  });

  final SetupStrategy strategy;
  final BacktestResult record;

  /// Set when the rule fires right now.
  final TradeLevels? live;

  bool get isLive => live != null;

  /// The rule fires and its history says the odds are on your side.
  bool get isPlayable => isLive && record.isFavorable;
}

/// Price closes at a 20 day high with volume behind it.
class BreakoutStrategy extends SetupStrategy {
  const BreakoutStrategy();

  @override
  String get id => 'breakout';

  @override
  String get name => 'Ruptura';

  @override
  String get idea => 'El precio rompe su techo de 20 días con volumen.';

  @override
  bool triggers(DailySeries series, int i) {
    final candle = series.candles[i];
    if (candle.close < series.highestClose20[i]) return false;
    if (series.averageVolume20[i] <= 0) return false;
    if (candle.volume < series.averageVolume20[i] * 1.2) return false;
    return series.ema20[i] > series.ema50[i];
  }

  @override
  TradeLevels levels(DailySeries series, int i) {
    final entry = series.candles[i].close;
    final unit = series.atr[i];
    return TradeLevels(
      entry: entry,
      stop: entry - unit * 1.5,
      target: entry + unit * 3.0,
    );
  }
}

/// Price walks up and comes back to its average without breaking it.
class PullbackStrategy extends SetupStrategy {
  const PullbackStrategy();

  @override
  String get id => 'pullback';

  @override
  String get name => 'Retroceso';

  @override
  String get idea => 'El precio sube, descansa sobre su media y vuelve a girar.';

  @override
  bool triggers(DailySeries series, int i) {
    if (series.ema20[i] <= series.ema50[i]) return false;
    final candle = series.candles[i];
    if (candle.close <= candle.open) return false;
    final unit = series.atr[i];
    if (unit <= 0) return false;
    // The low tags the average, the close stays above it.
    if (candle.low > series.ema20[i] + unit * .3) return false;
    return candle.close > series.ema20[i];
  }

  @override
  TradeLevels levels(DailySeries series, int i) {
    final candle = series.candles[i];
    final entry = candle.close;
    final unit = series.atr[i];
    final stop = math.min(candle.low, series.ema20[i]) - unit * .5;
    final risk = entry - stop;
    return TradeLevels(
      entry: entry,
      stop: stop,
      target: entry + risk * 2,
    );
  }
}

/// The range squeezes shut and then the price jumps out of it.
class SqueezeStrategy extends SetupStrategy {
  const SqueezeStrategy();

  @override
  String get id => 'squeeze';

  @override
  String get name => 'Compresión';

  @override
  String get idea => 'El rango se cierra y el precio salta fuera de él.';

  @override
  bool triggers(DailySeries series, int i) {
    if (i < 1) return false;
    final wide = series.range30[i - 1];
    if (wide <= 0) return false;
    // Yesterday the market was quiet.
    if (series.range10[i - 1] > wide * .55) return false;
    // Today it leaves the range behind.
    if (series.candles[i].close <= series.highestHigh10[i - 1]) return false;
    return series.ema20[i] >= series.ema50[i];
  }

  @override
  TradeLevels levels(DailySeries series, int i) {
    final entry = series.candles[i].close;
    final unit = series.atr[i];
    return TradeLevels(
      entry: entry,
      stop: entry - unit * 1.2,
      target: entry + unit * 2.6,
    );
  }
}

/// The rules Nexora runs on every candidate.
const List<SetupStrategy> coreStrategies = <SetupStrategy>[
  BreakoutStrategy(),
  PullbackStrategy(),
  SqueezeStrategy(),
];

/// Reads every rule and picks the one worth showing.
class StrategyDesk {
  const StrategyDesk({this.strategies = coreStrategies});

  final List<SetupStrategy> strategies;

  List<StrategyReport> review(DailySeries series) =>
      strategies.map((strategy) => strategy.review(series)).toList(growable: false);

  /// The rule that fires now and has the best history behind it.
  StrategyReport? bestPlay(List<StrategyReport> reports) {
    final playable = reports.where((report) => report.isPlayable).toList()
      ..sort((a, b) => b.record.averageR.compareTo(a.record.averageR));
    return playable.isEmpty ? null : playable.first;
  }
}
