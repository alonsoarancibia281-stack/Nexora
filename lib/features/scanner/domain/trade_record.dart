import 'trade_plan.dart';

/// How a saved idea ended.
enum TradeOutcome { open, win, loss, skipped }

extension TradeOutcomeInfo on TradeOutcome {
  String get label => switch (this) {
        TradeOutcome.open => 'Abierta',
        TradeOutcome.win => 'Gana',
        TradeOutcome.loss => 'Pierde',
        TradeOutcome.skipped => 'Sin entrar',
      };

  bool get isClosed => this == TradeOutcome.win || this == TradeOutcome.loss;
}

/// One idea saved to the history, win or lose.
///
/// Every signal is written down when it appears, not after the fact. That is
/// the only way a hit rate means anything.
class TradeRecord {
  const TradeRecord({
    required this.id,
    required this.symbol,
    required this.pair,
    required this.strategyId,
    required this.strategyName,
    required this.entry,
    required this.stop,
    required this.target,
    required this.hitRate,
    required this.trades,
    required this.createdAt,
    this.outcome = TradeOutcome.open,
    this.closedAt,
    this.resultPercent,
    this.published = false,
  });

  factory TradeRecord.fromPlan(TradePlan plan, {required DateTime at}) =>
      TradeRecord(
        id: '${plan.symbol}-${at.millisecondsSinceEpoch}',
        symbol: plan.symbol,
        pair: plan.pair,
        strategyId: plan.strategyId,
        strategyName: plan.strategyName,
        entry: plan.levels.entry,
        stop: plan.levels.stop,
        target: plan.levels.target,
        hitRate: plan.hitRate,
        trades: plan.trades,
        createdAt: at,
      );

  final String id;
  final String symbol;
  final String pair;
  final String strategyId;
  final String strategyName;
  final double entry;
  final double stop;
  final double target;

  /// The rule's historical hit rate when the idea was saved.
  final double hitRate;
  final int trades;

  final DateTime createdAt;
  final TradeOutcome outcome;
  final DateTime? closedAt;

  /// Result of the trade, in percent.
  final double? resultPercent;

  /// Already sent to the public history.
  final bool published;

  TradeRecord copyWith({
    TradeOutcome? outcome,
    DateTime? closedAt,
    double? resultPercent,
    bool? published,
  }) =>
      TradeRecord(
        id: id,
        symbol: symbol,
        pair: pair,
        strategyId: strategyId,
        strategyName: strategyName,
        entry: entry,
        stop: stop,
        target: target,
        hitRate: hitRate,
        trades: trades,
        createdAt: createdAt,
        outcome: outcome ?? this.outcome,
        closedAt: closedAt ?? this.closedAt,
        resultPercent: resultPercent ?? this.resultPercent,
        published: published ?? this.published,
      );

  /// Closes the record using the price the trade ended at.
  TradeRecord close({required double exitPrice, required DateTime at}) {
    final change = entry <= 0 ? 0.0 : (exitPrice - entry) / entry * 100;
    return copyWith(
      outcome: change >= 0 ? TradeOutcome.win : TradeOutcome.loss,
      closedAt: at,
      resultPercent: change,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'symbol': symbol,
        'pair': pair,
        'strategyId': strategyId,
        'strategyName': strategyName,
        'entry': entry,
        'stop': stop,
        'target': target,
        'hitRate': hitRate,
        'trades': trades,
        'createdAt': createdAt.toIso8601String(),
        'outcome': outcome.name,
        'closedAt': closedAt?.toIso8601String(),
        'resultPercent': resultPercent,
        'published': published,
      };

  factory TradeRecord.fromJson(Map<String, dynamic> json) => TradeRecord(
        id: json['id'] as String,
        symbol: json['symbol'] as String,
        pair: json['pair'] as String? ?? json['symbol'] as String,
        strategyId: json['strategyId'] as String? ?? 'unknown',
        strategyName: json['strategyName'] as String? ?? 'Estrategia',
        entry: (json['entry'] as num).toDouble(),
        stop: (json['stop'] as num).toDouble(),
        target: (json['target'] as num).toDouble(),
        hitRate: (json['hitRate'] as num?)?.toDouble() ?? 0,
        trades: (json['trades'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        outcome: TradeOutcome.values.firstWhere(
          (value) => value.name == json['outcome'],
          orElse: () => TradeOutcome.open,
        ),
        closedAt: json['closedAt'] == null
            ? null
            : DateTime.parse(json['closedAt'] as String),
        resultPercent: (json['resultPercent'] as num?)?.toDouble(),
        published: json['published'] as bool? ?? false,
      );
}

/// The honest score of the saved ideas.
class TradeTally {
  const TradeTally({
    required this.open,
    required this.wins,
    required this.losses,
    required this.skipped,
    required this.averageResultPercent,
  });

  final int open;
  final int wins;
  final int losses;
  final int skipped;
  final double averageResultPercent;

  int get closed => wins + losses;

  /// Null while nothing has closed yet.
  double? get hitRate => closed == 0 ? null : wins / closed;

  static TradeTally of(List<TradeRecord> records) {
    var open = 0, wins = 0, losses = 0, skipped = 0;
    var total = 0.0;
    for (final record in records) {
      switch (record.outcome) {
        case TradeOutcome.open:
          open++;
        case TradeOutcome.win:
          wins++;
          total += record.resultPercent ?? 0;
        case TradeOutcome.loss:
          losses++;
          total += record.resultPercent ?? 0;
        case TradeOutcome.skipped:
          skipped++;
      }
    }
    final closed = wins + losses;
    return TradeTally(
      open: open,
      wins: wins,
      losses: losses,
      skipped: skipped,
      averageResultPercent: closed == 0 ? 0 : total / closed,
    );
  }
}
