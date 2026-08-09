import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/data/binance_market_service.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_decision_gate.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_ensemble_100.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_round_tracker.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';
import 'package:nexora_markets_ai/features/pulse/presentation/pulse_dashboard_widgets.dart';

void main() {
  testWidgets('core dashboard panels fit a narrow mobile viewport',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final candles = List.generate(
      20,
      (index) => Candle(
        openTime: DateTime.utc(2026, 8, 8, 12, index * 5),
        open: 67000 + index * 5,
        high: 67020 + index * 5,
        low: 66980 + index * 5,
        close: 67010 + index * 5,
        volume: 100 + index.toDouble(),
      ),
    );
    const ensemble = PulseEnsemble100Result(
      probabilityUp: .63,
      confidence: 63,
      activeAnalysts: 100,
      upAnalysts: 68,
      downAnalysts: 17,
      neutralAnalysts: 15,
      agreement: .68,
      teamOpinions: [
        TeamOpinion(
          family: AnalystFamily.trend,
          probabilityUp: .63,
          quality: .35,
          disagreement: .12,
        ),
      ],
    );
    const book = OrderBookSnapshot(
      bids: [OrderBookLevel(price: 67000, quantity: 1.2)],
      asks: [OrderBookLevel(price: 67001, quantity: 1.1)],
    );
    const trades = AggTradeSnapshot(
      aggressorImbalance: .2,
      signedVolume: .18,
      tradeAcceleration: .1,
      priceImpulseBps: 2,
      trades: 500,
      buyQuantity: 10,
      sellQuantity: 8,
      tradesPerSecond: 14,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const NexoraDashboardHeader(
                  price: 67000,
                  change24h: 1.2,
                  countdown: '03:21',
                  roundNumber: 42,
                  loading: false,
                  onBack: null,
                ),
                PredictionPanel(
                  decision: LockedPulseDecision(
                    direction: PulseDirection.up,
                    probabilityUp: .63,
                    lockedAt: DateTime.utc(2026, 8, 8, 12, 1),
                  ),
                  calibrationProgress: 1,
                  ensemble: ensemble,
                  rawProbabilityUp: .61,
                  statisticalQuality: .35,
                  knowledgeMultiplier: .82,
                  auditPassed: true,
                ),
                const AnalystDistributionPanel(ensemble: ensemble),
                const AnalystTeamsPanel(ensemble: ensemble),
                MarketChartPanel(
                  candles: candles,
                  currentPrice: 67000,
                  boxHigh: 67100,
                  boxLow: 66900,
                ),
                const MicrostructurePanel(book: book, trades: trades),
                const QualityPanel(
                  metrics: PulseCalibrationMetrics(
                    samples: 0,
                    accuracy: 0,
                    brierScore: 0,
                    expectedCalibrationError: 0,
                  ),
                  statisticalQuality: .35,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('NEXORA'), findsOneWidget);
    expect(find.text('ALTA ↑'), findsOneWidget);
    expect(find.text('68 (68%)'), findsNWidgets(2));
    expect(find.textContaining('Tendencia'), findsOneWidget);
  });
}
