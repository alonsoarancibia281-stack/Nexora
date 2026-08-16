import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../data/prediction_ai_service.dart';
import '../domain/agent_scoreboard.dart';
import '../domain/exit_watch.dart';
import '../domain/market_agent_desk.dart';
import '../domain/market_reading.dart';
import '../domain/prediction_alert.dart';
import '../domain/prediction_horizon.dart';
import '../domain/prediction_outlook.dart';
import '../domain/round_clock.dart';
import '../domain/round_journal.dart';

class _PendingRound {
  const _PendingRound(this.window, this.outlook);
  final RoundWindow window;
  final PredictionOutlook? outlook;
}

/// Runs the three rounds at once and keeps them alive.
///
/// One data refresh feeds the 5 minute, the 15 minute and the 1 hour desk, so
/// all three stay current with the same Binance call. When a round closes the
/// controller re-syncs the exchange clock, opens the next round and refreshes
/// straight away: the counter never needs a manual reload.
class PredictionController extends ChangeNotifier {
  PredictionController({
    BinanceMarketService? service,
    PredictionAiService ai = const PredictionAiService(),
    this.symbol = 'BTCUSDT',
  })  : _service = service ?? BinanceMarketService(),
        _ai = ai;

  final BinanceMarketService _service;
  final PredictionAiService _ai;
  final String symbol;

  static const refreshInterval = Duration(seconds: 5);
  static const clockSyncInterval = Duration(seconds: 20);
  static const _candleLimits = <String, int>{
    '1m': 150,
    '5m': 150,
    '15m': 100,
    '1h': 100,
    '4h': 80,
  };

  final _clock = ExchangeClock();
  final _desk = const MarketAgentDesk();
  final _builder = const MarketReadingBuilder();
  final _alertCenter = PredictionAlertCenter();
  final _journal = RoundJournal();

  final Map<PredictionHorizon, RoundWindow> _windows = {};
  final Map<PredictionHorizon, PredictionOutlook> _outlooks = {};
  final Map<PredictionHorizon, ExitAdvice> _advices = {};
  final Map<PredictionHorizon, ExitWatcher> _watchers = {
    for (final horizon in PredictionHorizon.values) horizon: ExitWatcher(),
  };
  final Map<PredictionHorizon, _PendingRound> _pending = {};
  final Set<String> _aiAsked = <String>{};
  Map<String, List<Candle>> _candles = const {};

  AgentScoreboard _scoreboard = const AgentScoreboard();
  Timer? _ticker;
  Timer? _dataTimer;
  Timer? _clockTimer;
  bool _refreshing = false;
  bool _loading = true;
  bool _disposed = false;
  String? _error;
  DateTime? _lastUpdate;
  int _lastPaintedSecond = -1;
  PredictionAlert? _flash;

  DateTime get now => _clock.now;
  bool get isClockSynced => _clock.isSynced;
  bool get isLoading => _loading;
  String? get error => _error;
  DateTime? get lastUpdate => _lastUpdate;
  AgentScoreboard get scoreboard => _scoreboard;
  RoundJournal get journal => _journal;
  List<PredictionAlert> get alerts => _alertCenter.alerts;

  /// Last alert the screen has not shown yet.
  PredictionAlert? takeFlash() {
    final flash = _flash;
    _flash = null;
    return flash;
  }

  RoundWindow windowFor(PredictionHorizon horizon) =>
      _windows[horizon] ?? RoundWindow.at(horizon, now);

  PredictionOutlook? outlookFor(PredictionHorizon horizon) =>
      _outlooks[horizon];

  ExitAdvice adviceFor(PredictionHorizon horizon) =>
      _advices[horizon] ?? const ExitAdvice.idle();

  double? startPriceFor(PredictionHorizon horizon) =>
      _outlooks[horizon]?.startPrice;

  int secondsLeftFor(PredictionHorizon horizon) =>
      windowFor(horizon).secondsLeft(now);

  double progressFor(PredictionHorizon horizon) =>
      windowFor(horizon).progress(now);

  Future<void> start() async {
    await _syncClock();
    for (final horizon in PredictionHorizon.values) {
      _windows[horizon] = RoundWindow.at(horizon, now);
    }
    _safeNotify();
    await refresh();

    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _dataTimer = Timer.periodic(refreshInterval, (_) => refresh());
    _clockTimer = Timer.periodic(clockSyncInterval, (_) => _syncClock());
  }

  void _tick() {
    if (_disposed) return;
    var rolled = false;
    for (final horizon in PredictionHorizon.values) {
      final window = _windows[horizon];
      if (window == null) continue;
      if (window.isClosed(now)) {
        _pending[horizon] = _PendingRound(window, _outlooks[horizon]);
        _windows[horizon] = window.next;
        _outlooks.remove(horizon);
        _advices.remove(horizon);
        _watchers[horizon]?.reset();
        rolled = true;
      }
    }

    if (rolled) {
      _safeNotify();
      unawaited(_onRoundRolled());
      return;
    }

    final second = secondsLeftFor(PredictionHorizon.m5);
    if (second != _lastPaintedSecond) {
      _lastPaintedSecond = second;
      _safeNotify();
    }
  }

  Future<void> _onRoundRolled() async {
    await _syncClock();
    await refresh();
  }

  Future<void> _syncClock() async {
    try {
      final before = DateTime.now().toUtc();
      final serverTime = await _service.loadServerTime();
      _clock.apply(
        before: before,
        serverTime: serverTime,
        after: DateTime.now().toUtc(),
      );
      _safeNotify();
    } catch (_) {
      // Keep the last good sync.
    }
  }

  Future<void> refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      final intervals = PredictionHorizonInfo.allIntervals;
      final results = await Future.wait<dynamic>([
        for (final interval in intervals)
          _service.loadCandles(
            symbol,
            interval,
            limit: _candleLimits[interval] ?? 120,
          ),
        _service.loadDepthMetrics(symbol, limit: 100),
        _service.loadAggTradeMetrics(symbol, limit: 500),
      ]);

      final candles = <String, List<Candle>>{};
      for (var i = 0; i < intervals.length; i++) {
        candles[intervals[i]] = results[i] as List<Candle>;
      }
      final depth = results[intervals.length] as ({
        double bidVolume,
        double askVolume,
        double bestBid,
        double bestAsk,
        double spreadBps,
        double micropriceEdge,
      });
      final flow = results[intervals.length + 1] as ({
        double aggressorImbalance,
        double signedVolume,
        double tradeAcceleration,
        double priceImpulseBps,
        int trades,
      });

      _candles = candles;
      _settlePendingRounds(candles);

      final book = BookSnapshotMetrics(
        bidVolume: depth.bidVolume,
        askVolume: depth.askVolume,
        spreadBps: depth.spreadBps,
        micropriceEdgeBps: depth.micropriceEdge,
      );
      final trades = TradeFlowMetrics(
        aggressorImbalance: flow.aggressorImbalance,
        signedVolume: flow.signedVolume,
        tradeAcceleration: flow.tradeAcceleration,
        priceImpulseBps: flow.priceImpulseBps,
      );

      for (final horizon in PredictionHorizon.values) {
        _review(horizon, book: book, flow: trades);
      }

      _loading = false;
      _error = null;
      _lastUpdate = now;
      _safeNotify();
      unawaited(_askSecondOpinions());
    } catch (_) {
      _loading = false;
      _error = 'No hay datos de Binance ahora. Lo intentamos de nuevo solos.';
      _safeNotify();
    } finally {
      _refreshing = false;
    }
  }

  void _review(
    PredictionHorizon horizon, {
    required BookSnapshotMetrics book,
    required TradeFlowMetrics flow,
  }) {
    final window = _windows[horizon] ?? RoundWindow.at(horizon, now);
    _windows[horizon] = window;
    final baseCandles = _candles[horizon.baseInterval] ?? const <Candle>[];
    final contextCandles = _candles[horizon.contextInterval] ?? const <Candle>[];
    final startPrice = _openPriceOf(horizon, window);
    if (startPrice == null || baseCandles.isEmpty) return;

    final reading = _builder.build(
      horizon: horizon,
      baseCandles: baseCandles,
      contextCandles: contextCandles,
      startPrice: startPrice,
      secondsLeft: window.secondsLeft(now),
      book: book,
      flow: flow,
    );
    if (reading == null) return;

    var outlook = _desk.review(
      reading: reading,
      window: window,
      now: now,
      scoreboard: _scoreboard,
    );

    final watcher = _watchers[horizon]!;
    final advice = watcher.update(outlook);
    outlook = outlook.copyWith(
      lockedAt: watcher.lockedAt,
      secondOpinion: _outlooks[horizon]?.secondOpinion,
    );

    _outlooks[horizon] = outlook;
    _advices[horizon] = advice;

    final born = _alertCenter.ingest(
      outlook: outlook,
      advice: advice,
      closeClock: _clockText(window.end),
    );
    if (born.isNotEmpty) {
      _flash = born.firstWhere(
        (alert) => alert.isUrgent,
        orElse: () => born.first,
      );
    }
  }

  /// Price the round opened at, taken from the candle that settles it.
  double? _openPriceOf(PredictionHorizon horizon, RoundWindow window) {
    final settlement = _candles[horizon.settlementInterval];
    if (settlement != null) {
      for (final candle in settlement.reversed) {
        if (candle.openTime.toUtc().millisecondsSinceEpoch ==
            window.start.millisecondsSinceEpoch) {
          return candle.open;
        }
      }
    }
    final base = _candles[horizon.baseInterval];
    if (base != null) {
      for (final candle in base) {
        if (!candle.openTime.toUtc().isBefore(window.start)) return candle.open;
      }
    }
    return _outlooks[horizon]?.startPrice;
  }

  void _settlePendingRounds(Map<String, List<Candle>> candles) {
    if (_pending.isEmpty) return;
    for (final horizon in PredictionHorizon.values) {
      final pending = _pending[horizon];
      if (pending == null) continue;
      // Give the exchange a moment to close the candle.
      if (now.difference(pending.window.end).inSeconds < 3) continue;
      final settlement = candles[horizon.settlementInterval];
      if (settlement == null) continue;
      Candle? closed;
      for (final candle in settlement.reversed) {
        if (candle.openTime.toUtc().millisecondsSinceEpoch ==
            pending.window.start.millisecondsSinceEpoch) {
          closed = candle;
          break;
        }
      }
      if (closed == null) continue;

      final outlook = pending.outlook;
      final call = outlook?.call ?? PredictionCall.wait;
      final result = RoundResult(
        horizon: horizon,
        window: pending.window,
        call: call,
        probability: outlook?.probability ?? .5,
        startPrice: closed.open,
        endPrice: closed.close,
      );
      _journal.add(result);
      if (outlook != null) {
        _scoreboard = _scoreboard.settle(
          horizon: horizon,
          views: outlook.views,
          closedUp: result.closedUp,
        );
      }
      final alert = _alertCenter.announceResult(
        horizon: horizon,
        window: pending.window,
        call: call,
        closedUp: result.closedUp,
        changePercent: result.changePercent,
        at: now,
        closeClock: _clockText(pending.window.end),
      );
      if (alert != null) _flash ??= alert;
      _pending.remove(horizon);
    }
  }

  Future<void> _askSecondOpinions() async {
    if (!_ai.isConfigured) return;
    for (final horizon in PredictionHorizon.values) {
      final outlook = _outlooks[horizon];
      if (outlook == null || !outlook.call.isDirectional) continue;
      final key = '${horizon.name}/${outlook.window.start.millisecondsSinceEpoch}';
      if (!_aiAsked.add(key)) continue;
      final opinion = await _ai.review(
        symbol: symbol,
        horizon: horizon.tag,
        startPrice: outlook.startPrice,
        currentPrice: outlook.price,
        secondsRemaining: outlook.secondsLeft,
        desk: {
          'direction': outlook.call.name,
          'probabilityUp': outlook.probabilityUp,
          'agreement': outlook.agreement,
          'instability': outlook.instability,
          'distancePercent': outlook.distancePercent,
          'expectedMovePercent': outlook.expectedMovePercent,
          'agents': [
            for (final view in outlook.views)
              {
                'name': view.name,
                'probabilityUp': view.probabilityUp,
                'relevance': view.relevance,
              },
          ],
        },
      );
      if (opinion == null || _disposed) continue;
      final current = _outlooks[horizon];
      if (current == null || current.window.start != outlook.window.start) {
        continue;
      }
      _outlooks[horizon] =
          current.copyWith(secondOpinion: opinion.explanation);
      _safeNotify();
    }
  }

  String _clockText(DateTime utc) {
    final local = utc.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _dataTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }
}
