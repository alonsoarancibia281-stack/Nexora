import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/data/binance_market_service.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/pulse/domain/consensus_reversal_alert.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_decision_gate.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_ensemble_100.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_round_tracker.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';
import 'package:nexora_markets_ai/features/pulse/domain/futures_trade_planner.dart';
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
                FuturesTradePlanPanel(
                  symbol: 'BTCUSDT',
                  plan: const FuturesTradePlan(
                    action: FuturesTradeAction.long,
                    reason: 'Confluencia confirmada.',
                    requestedMargin: 25,
                    requiredMargin: 22.38,
                    margin: 22.33,
                    leverage: 3,
                    notional: 67,
                    quantity: .001,
                    entryPrice: 67001,
                    stopLossPrice: 66800,
                    takeProfitPrice: 67362.80,
                    estimatedLiquidationPrice: 44920,
                    maximumLossUsd: .026,
                    potentialProfitUsd: .018,
                    expectedNetUsd: .003,
                    riskRewardRatio: 1.8,
                    atr: 80,
                    fundingRate: .0000816,
                    fundingCostUsd: 0,
                    confidence: 63,
                  ),
                  updatedAt: DateTime.utc(2026, 8, 9, 12, 5),
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
    expect(find.text('COMPRAR / LONG'), findsOneWidget);
    expect(find.text('COMPRA · LONG'), findsOneWidget);
    expect(find.text('Take Profit'), findsOneWidget);
    expect(find.text('Stop Loss'), findsOneWidget);
    expect(find.text('22.33 USDT'), findsNWidgets(2));
  });

  testWidgets('selector Futures cambia el contrato perpetuo', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: FuturesSymbolSelector(
            symbols: const [
              'BTCUSDT',
              'ETHUSDT',
              'SOLUSDT',
              'BNBUSDT',
              'XRPUSDT',
            ],
            selectedSymbol: 'BTCUSDT',
            onChanged: (symbol) => selected = symbol,
          ),
        ),
      ),
    );

    expect(find.text('BTC / USDT Perpetual'), findsOneWidget);
    await tester.tap(find.text('BTC / USDT Perpetual'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SOL / USDT Perpetual').last);
    await tester.pumpAndSettle();

    expect(selected, 'SOLUSDT');
  });

  testWidgets('muestra alerta visual ante una reversión sostenida',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ConsensusDirectionAlertPanel(
            alert: ConsensusReversalAlert(
              publishedDirection: PulseDirection.down,
              consensusDirection: PulseDirection.up,
              supportingAnalysts: 67,
              detectedAt: DateTime.utc(2026, 8, 9, 20, 15, 9),
            ),
          ),
        ),
      ),
    );

    expect(find.text('ALERTA · CAMBIO DE DIRECCIÓN'), findsOneWidget);
    expect(find.textContaining('Señal publicada: BAJA'), findsOneWidget);
    expect(find.textContaining('Consenso actual: ALTA'), findsOneWidget);
    expect(find.textContaining('67 de 100 analistas'), findsOneWidget);
    expect(find.textContaining('no cambia automáticamente'), findsOneWidget);
  });

  testWidgets('Futures usa una identidad distinta de Predicciones',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NexoraDashboardHeader(
            price: 65000,
            change24h: .5,
            countdown: '04:15',
            roundNumber: 7,
            loading: false,
            onBack: null,
            brandTitle: 'NEXORA FUTURES',
            brandSubtitle: 'PLAN USDⓈ-M · POOL DE 100 ANALISTAS',
            symbolLabel: 'BTCUSDT PERP.',
            sourceLabel: 'BINANCE USDⓈ-M',
            continuousMode: true,
          ),
        ),
      ),
    );

    expect(find.text('NEXORA FUTURES'), findsOneWidget);
    expect(find.text('BTCUSDT PERP.'), findsOneWidget);
    expect(find.text('BINANCE USDⓈ-M'), findsOneWidget);
    expect(find.text('ANÁLISIS CONTINUO'), findsOneWidget);
    expect(find.text('PRÓXIMOS 5 MINUTOS'), findsNothing);
    expect(find.text('RONDA EN VIVO'), findsNothing);
    expect(find.text('PREDICCIÓN NEXORA'), findsNothing);
  });
}
