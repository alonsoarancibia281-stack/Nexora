import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/research_service.dart';
import '../data/scanner_service.dart';
import '../data/trade_history_repository.dart';
import '../domain/market_scanner.dart';
import '../domain/scan_candidate.dart';
import '../domain/setup_strategy.dart';
import '../domain/trade_plan.dart';
import '../domain/trade_record.dart';

/// Everything the idea screen needs about one candidate.
class TradeIdea {
  const TradeIdea({
    required this.candidate,
    required this.reports,
    required this.play,
    required this.plan,
    this.research,
  });

  final ScanCandidate candidate;
  final List<StrategyReport> reports;

  /// The rule that fires now with a favorable history, when there is one.
  final StrategyReport? play;

  /// Entry, stop, target and size. Null when no rule fires.
  final TradePlan? plan;

  final ResearchNote? research;

  bool get hasPlay => play != null && plan != null;

  TradeIdea withResearch(ResearchNote? note) => TradeIdea(
        candidate: candidate,
        reports: reports,
        play: play,
        plan: plan,
        research: note,
      );
}

/// Drives the five steps: scan, research, predict, plan, remember.
class ScannerController extends ChangeNotifier {
  ScannerController({
    ScannerService? scanner,
    this.research = const ResearchService(),
    this.history = const TradeHistoryRepository(),
    this.publisher = const SignalPublisher(),
    this.desk = const StrategyDesk(),
    this.planner = const TradePlanner(),
  }) : _scanner = scanner ?? ScannerService();

  final ScannerService _scanner;
  final ResearchService research;
  final TradeHistoryRepository history;
  final SignalPublisher publisher;
  final StrategyDesk desk;
  final TradePlanner planner;

  static const _capitalKey = 'nexora_bot_capital_v1';
  static const _riskKey = 'nexora_bot_risk_v1';

  List<ScanCandidate> _candidates = const [];
  List<TradeRecord> _records = const [];
  bool _scanning = false;
  double _progress = 0;
  String? _error;
  DateTime? _lastScan;
  double _capital = 1000;
  double _riskPercent = 1;
  bool _disposed = false;

  List<ScanCandidate> get candidates => _candidates;
  List<TradeRecord> get records => _records;
  TradeTally get tally => TradeTally.of(_records);
  bool get isScanning => _scanning;
  double get progress => _progress;
  String? get error => _error;
  DateTime? get lastScan => _lastScan;
  double get capital => _capital;
  double get riskPercent => _riskPercent;
  bool get researchReady => research.isConfigured;
  bool get publishReady => publisher.isConfigured;

  Future<void> load() async {
    _records = await history.load();
    try {
      final prefs = await SharedPreferences.getInstance();
      _capital = prefs.getDouble(_capitalKey) ?? _capital;
      _riskPercent = prefs.getDouble(_riskKey) ?? _riskPercent;
    } catch (_) {
      // Defaults are fine when storage is unavailable.
    }
    _notify();
  }

  Future<void> setCapital(double value) async {
    if (value <= 0) return;
    _capital = value;
    _notify();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_capitalKey, value);
    } catch (_) {
      // The value still applies for this session.
    }
  }

  Future<void> setRiskPercent(double value) async {
    if (value <= 0 || value > 100) return;
    _riskPercent = value;
    _notify();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_riskKey, value);
    } catch (_) {
      // The value still applies for this session.
    }
  }

  /// Step 01.
  Future<void> scan({ScanFilters filters = const ScanFilters()}) async {
    if (_scanning) return;
    _scanning = true;
    _progress = 0;
    _error = null;
    _notify();
    try {
      final found = await _scanner.scan(
        filters: filters,
        onProgress: (value) {
          _progress = value;
          _notify();
        },
      );
      _candidates = found;
      _lastScan = DateTime.now();
      _error = found.isEmpty
          ? 'Hoy no sube nada con fuerza en la semana y en el mes.'
          : null;
    } catch (_) {
      _error = 'No llegan los datos de Binance. Prueba otra vez.';
    } finally {
      _scanning = false;
      _progress = 1;
      _notify();
    }
  }

  /// Steps 03 and 04 for one candidate.
  Future<TradeIdea> openIdea(ScanCandidate candidate) async {
    final candles = await _scanner.dailyCandles(candidate.symbol);
    final series = DailySeries(candles);
    final reports = desk.review(series);
    final play = desk.bestPlay(reports);
    final plan = play == null
        ? null
        : planner.build(
            candidate: candidate,
            report: play,
            capital: _capital,
            riskPercent: _riskPercent,
          );
    return TradeIdea(
      candidate: candidate,
      reports: reports,
      play: play,
      plan: plan,
    );
  }

  /// Step 02. Returns the same idea with the note attached.
  Future<TradeIdea> addResearch(TradeIdea idea) async {
    final note = await research.review(
      candidate: idea.candidate,
      play: idea.play,
    );
    return idea.withResearch(note);
  }

  /// Step 05.
  Future<TradeRecord> save(TradePlan plan) async {
    final record = TradeRecord.fromPlan(plan, at: DateTime.now());
    _records = await history.add(record);
    _notify();
    return record;
  }

  Future<void> closeRecord(TradeRecord record, double exitPrice) async {
    _records = await history.replace(
      record.close(exitPrice: exitPrice, at: DateTime.now()),
    );
    _notify();
  }

  Future<void> markSkipped(TradeRecord record) async {
    _records = await history.replace(
      record.copyWith(outcome: TradeOutcome.skipped, closedAt: DateTime.now()),
    );
    _notify();
  }

  Future<void> removeRecord(TradeRecord record) async {
    _records = await history.remove(record.id);
    _notify();
  }

  /// Sends one record to the public table. Returns false when it did not go.
  Future<bool> publish(TradeRecord record) async {
    final sent = await publisher.publish(record);
    if (sent) {
      _records = await history.replace(record.copyWith(published: true));
      _notify();
    }
    return sent;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
