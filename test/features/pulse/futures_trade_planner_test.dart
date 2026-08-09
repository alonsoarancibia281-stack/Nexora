import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/data/binance_futures_market_service.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/market/domain/symbol_trading_rules.dart';
import 'package:nexora_markets_ai/features/pulse/domain/futures_trade_planner.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_decision_gate.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';

void main() {
  const planner = FuturesTradePlanner();
  const rules = SymbolTradingRules(
    symbol: 'BTCUSDT',
    tickSize: .1,
    quantityStep: .001,
    minimumQuantity: .001,
    minimumNotional: 50,
  );
  final now = DateTime.utc(2026, 8, 9, 12);
  final validUntil = now.add(const Duration(minutes: 5));
  final premium = FuturesPremiumSnapshot(
    markPrice: 65000,
    indexPrice: 65005,
    fundingRate: .00008,
    nextFundingTime: now.add(const Duration(hours: 4)),
  );

  test('no propone una orden de 5 USDT que Binance rechazaría', () {
    final plan = planner.build(
      decision: _decision(PulseDirection.up, .72, now),
      entryCandles: _candles(up: true, intervalMinutes: 1),
      contextCandles: _candles(up: true, intervalMinutes: 5),
      bestBid: 64999.9,
      bestAsk: 65000,
      analystAgreement: .70,
      statisticalQuality: .25,
      instability: 20,
      rules: rules,
      premium: premium,
      validUntil: validUntil,
    );

    expect(plan.action, FuturesTradeAction.noTrade);
    expect(plan.requiredMargin, greaterThan(21));
    expect(plan.reason, contains('Binance rechazaría'));
  });

  test('con margen suficiente crea LONG con stop antes de liquidación', () {
    final plan = planner.build(
      decision: _decision(PulseDirection.up, .72, now),
      entryCandles: _candles(up: true, intervalMinutes: 1),
      contextCandles: _candles(up: true, intervalMinutes: 5),
      bestBid: 64999.9,
      bestAsk: 65000,
      analystAgreement: .70,
      statisticalQuality: .25,
      instability: 20,
      rules: rules,
      premium: premium,
      validUntil: validUntil,
      requestedMargin: 25,
    );

    expect(plan.action, FuturesTradeAction.long);
    expect(plan.quantity, .001);
    expect(plan.stopLossPrice, lessThan(plan.entryPrice));
    expect(plan.takeProfitPrice, greaterThan(plan.entryPrice));
    expect(plan.estimatedLiquidationPrice, lessThan(plan.stopLossPrice));
    expect(plan.expectedNetUsd, greaterThan(0));
  });

  test('la misma lógica produce un SHORT protegido cuando la señal baja', () {
    final bearishPremium = FuturesPremiumSnapshot(
      markPrice: 65000,
      indexPrice: 64995,
      fundingRate: -.00008,
      nextFundingTime: now.add(const Duration(hours: 4)),
    );
    final plan = planner.build(
      decision: _decision(PulseDirection.down, .28, now),
      entryCandles: _candles(up: false, intervalMinutes: 1),
      contextCandles: _candles(up: false, intervalMinutes: 5),
      bestBid: 64999.9,
      bestAsk: 65000,
      analystAgreement: .70,
      statisticalQuality: .25,
      instability: 20,
      rules: rules,
      premium: bearishPremium,
      validUntil: validUntil,
      requestedMargin: 25,
    );

    expect(plan.action, FuturesTradeAction.short);
    expect(plan.stopLossPrice, greaterThan(plan.entryPrice));
    expect(plan.takeProfitPrice, lessThan(plan.entryPrice));
    expect(plan.estimatedLiquidationPrice, greaterThan(plan.stopLossPrice));
  });

  test('se abstiene cuando el pool no alcanza el consenso mínimo', () {
    final plan = planner.build(
      decision: _decision(PulseDirection.up, .72, now),
      entryCandles: _candles(up: true, intervalMinutes: 1),
      contextCandles: _candles(up: true, intervalMinutes: 5),
      bestBid: 64999.9,
      bestAsk: 65000,
      analystAgreement: .55,
      statisticalQuality: .25,
      instability: 20,
      rules: rules,
      premium: premium,
      validUntil: validUntil,
      requestedMargin: 25,
    );

    expect(plan.action, FuturesTradeAction.noTrade);
    expect(plan.reason, contains('confluencia'));
  });
}

LockedPulseDecision _decision(
  PulseDirection direction,
  double probabilityUp,
  DateTime lockedAt,
) =>
    LockedPulseDecision(
      direction: direction,
      probabilityUp: probabilityUp,
      lockedAt: lockedAt,
    );

List<Candle> _candles({
  required bool up,
  required int intervalMinutes,
}) =>
    List.generate(30, (index) {
      final direction = up ? 1 : -1;
      final close = 64850 + direction * index * 6.0;
      return Candle(
        openTime: DateTime.utc(2026, 8, 9, 8).add(
          Duration(minutes: intervalMinutes * index),
        ),
        open: close - direction * 2,
        high: close + 12,
        low: close - 12,
        close: close,
        volume: 100 + index.toDouble(),
      );
    });
