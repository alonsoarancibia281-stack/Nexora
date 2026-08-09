import 'dart:math' as math;

import '../../market/data/binance_futures_market_service.dart';
import '../../market/domain/candle.dart';
import '../../market/domain/symbol_trading_rules.dart';
import 'pulse_decision_gate.dart';
import 'pulse_signal.dart';

enum FuturesTradeAction { long, short, noTrade }

class FuturesTradePlan {
  const FuturesTradePlan({
    required this.action,
    required this.reason,
    required this.requestedMargin,
    required this.requiredMargin,
    required this.margin,
    required this.leverage,
    required this.notional,
    required this.quantity,
    required this.entryPrice,
    required this.stopLossPrice,
    required this.takeProfitPrice,
    required this.estimatedLiquidationPrice,
    required this.maximumLossUsd,
    required this.potentialProfitUsd,
    required this.expectedNetUsd,
    required this.riskRewardRatio,
    required this.atr,
    required this.fundingRate,
    required this.fundingCostUsd,
    required this.confidence,
  });

  final FuturesTradeAction action;
  final String reason;
  final double requestedMargin;
  final double requiredMargin;
  final double margin;
  final int leverage;
  final double notional;
  final double quantity;
  final double entryPrice;
  final double stopLossPrice;
  final double takeProfitPrice;
  final double estimatedLiquidationPrice;
  final double maximumLossUsd;
  final double potentialProfitUsd;
  final double expectedNetUsd;
  final double riskRewardRatio;
  final double atr;
  final double fundingRate;
  final double fundingCostUsd;
  final double confidence;

  bool get actionable => action != FuturesTradeAction.noTrade;

  factory FuturesTradePlan.noTrade({
    required String reason,
    double requestedMargin = 5,
    double requiredMargin = 0,
    int leverage = 3,
    double fundingRate = 0,
  }) =>
      FuturesTradePlan(
        action: FuturesTradeAction.noTrade,
        reason: reason,
        requestedMargin: requestedMargin,
        requiredMargin: requiredMargin,
        margin: 0,
        leverage: leverage,
        notional: 0,
        quantity: 0,
        entryPrice: 0,
        stopLossPrice: 0,
        takeProfitPrice: 0,
        estimatedLiquidationPrice: 0,
        maximumLossUsd: 0,
        potentialProfitUsd: 0,
        expectedNetUsd: 0,
        riskRewardRatio: 0,
        atr: 0,
        fundingRate: fundingRate,
        fundingCostUsd: 0,
        confidence: 0,
      );
}

class FuturesTradePlanner {
  const FuturesTradePlanner({
    this.minimumConfidence = 60,
    this.minimumAgreement = .62,
    this.minimumStatisticalQuality = .15,
    this.maximumInstability = 65,
    this.maximumSpreadBps = 5,
    this.maximumFundingRate = .001,
    this.riskRewardRatio = 1.8,
    this.estimatedFeeRatePerSide = .0005,
  });

  final double minimumConfidence;
  final double minimumAgreement;
  final double minimumStatisticalQuality;
  final double maximumInstability;
  final double maximumSpreadBps;
  final double maximumFundingRate;
  final double riskRewardRatio;
  final double estimatedFeeRatePerSide;

  FuturesTradePlan build({
    required LockedPulseDecision? decision,
    required List<Candle> entryCandles,
    required List<Candle> contextCandles,
    required double bestBid,
    required double bestAsk,
    required double analystAgreement,
    required double statisticalQuality,
    required double instability,
    required SymbolTradingRules rules,
    required FuturesPremiumSnapshot premium,
    required DateTime validUntil,
    double requestedMargin = 5,
    int leverage = 3,
  }) {
    final safeLeverage = leverage.clamp(1, 3);
    FuturesTradePlan abstain(String reason, {double requiredMargin = 0}) =>
        FuturesTradePlan.noTrade(
          reason: reason,
          requestedMargin: requestedMargin,
          requiredMargin: requiredMargin,
          leverage: safeLeverage,
          fundingRate: premium.fundingRate,
        );

    if (decision == null || decision.direction == PulseDirection.noTrade) {
      return abstain(
          'Esperando una señal bloqueada del pool de 100 analistas.');
    }
    if (decision.confidence < minimumConfidence ||
        analystAgreement < minimumAgreement ||
        statisticalQuality < minimumStatisticalQuality ||
        instability > maximumInstability) {
      return abstain('La confluencia no supera los controles de riesgo.');
    }
    if (entryCandles.length < 16 || contextCandles.length < 15) {
      return abstain(
          'Aún no hay suficiente historial real para calcular el riesgo.');
    }
    if (bestBid <= 0 || bestAsk <= bestBid) {
      return abstain('El libro de órdenes no tiene precios válidos.');
    }

    final midPrice = (bestBid + bestAsk) / 2;
    final spreadBps = (bestAsk - bestBid) / midPrice * 10000;
    if (spreadBps > maximumSpreadBps) {
      return abstain(
        'Spread demasiado amplio (${spreadBps.toStringAsFixed(2)} bps).',
      );
    }

    final action = decision.direction == PulseDirection.up
        ? FuturesTradeAction.long
        : FuturesTradeAction.short;
    final trend = _contextTrend(contextCandles);
    if (action == FuturesTradeAction.long && trend < -.0003) {
      return abstain('LONG vetado: la tendencia cerrada de 5m sigue bajista.');
    }
    if (action == FuturesTradeAction.short && trend > .0003) {
      return abstain('SHORT vetado: la tendencia cerrada de 5m sigue alcista.');
    }
    if (action == FuturesTradeAction.long &&
        premium.fundingRate > maximumFundingRate) {
      return abstain('LONG vetado: financiación positiva excesiva.');
    }
    if (action == FuturesTradeAction.short &&
        premium.fundingRate < -maximumFundingRate) {
      return abstain('SHORT vetado: financiación negativa excesiva.');
    }

    final entry = action == FuturesTradeAction.long
        ? _ceilToStep(bestAsk, rules.tickSize)
        : _floorToStep(bestBid, rules.tickSize);
    final quantityByNotional = _ceilToStep(
      rules.minimumNotional / entry,
      rules.quantityStep,
    );
    final minimumQuantity = math.max(
      rules.minimumQuantity,
      quantityByNotional,
    );
    final requiredNotional = minimumQuantity * entry;
    final requiredMargin = _ceilCents(requiredNotional / safeLeverage * 1.002);
    if (requestedMargin + .000001 < requiredMargin) {
      return abstain(
        'Con ${requestedMargin.toStringAsFixed(2)} USDT y ${safeLeverage}x '
        'Binance rechazaría la orden. El mínimo actual de '
        '${minimumQuantity.toStringAsFixed(3)} BTC requiere cerca de '
        '${requiredMargin.toStringAsFixed(2)} USDT de margen aislado.',
        requiredMargin: requiredMargin,
      );
    }

    final maximumNotional = requestedMargin * safeLeverage;
    final quantity = _floorToStep(
      maximumNotional / entry,
      rules.quantityStep,
    );
    final notional = quantity * entry;
    if (quantity < minimumQuantity || notional < rules.minimumNotional) {
      return abstain(
        'El tamaño calculado no supera los filtros vigentes de Binance.',
        requiredMargin: requiredMargin,
      );
    }

    final atr = _atr(entryCandles);
    final riskDistance = math.max(
      math.max(atr * 1.35, entry * .003),
      (bestAsk - bestBid) * 4,
    );
    final rewardDistance = riskDistance * riskRewardRatio;
    final stop = action == FuturesTradeAction.long
        ? _floorToStep(entry - riskDistance, rules.tickSize)
        : _ceilToStep(entry + riskDistance, rules.tickSize);
    final target = action == FuturesTradeAction.long
        ? _ceilToStep(entry + rewardDistance, rules.tickSize)
        : _floorToStep(entry - rewardDistance, rules.tickSize);
    final liquidation = action == FuturesTradeAction.long
        ? entry * (1 - 1 / safeLeverage + .004)
        : entry * (1 + 1 / safeLeverage - .004);
    final estimatedFees = notional * estimatedFeeRatePerSide * 2;
    final maximumLoss = (entry - stop).abs() * quantity + estimatedFees;
    final potentialProfit =
        math.max(0.0, (target - entry).abs() * quantity - estimatedFees);
    final fundingApplies = !premium.nextFundingTime.isAfter(validUntil);
    final adverseFundingRate = action == FuturesTradeAction.long
        ? math.max(0.0, premium.fundingRate)
        : math.max(0.0, -premium.fundingRate);
    final fundingCost = fundingApplies ? notional * adverseFundingRate : 0.0;
    final directionalProbability = action == FuturesTradeAction.long
        ? decision.probabilityUp
        : 1 - decision.probabilityUp;
    final expectedNet = directionalProbability * potentialProfit -
        (1 - directionalProbability) * maximumLoss -
        fundingCost;
    if (expectedNet <= 0) {
      return abstain(
        'El valor esperado neto no compensa comisiones, riesgo y financiación.',
        requiredMargin: requiredMargin,
      );
    }

    return FuturesTradePlan(
      action: action,
      reason: 'Confluencia confirmada; usar exclusivamente margen aislado.',
      requestedMargin: requestedMargin,
      requiredMargin: requiredMargin,
      margin: notional / safeLeverage,
      leverage: safeLeverage,
      notional: notional,
      quantity: quantity,
      entryPrice: entry,
      stopLossPrice: stop,
      takeProfitPrice: target,
      estimatedLiquidationPrice: liquidation,
      maximumLossUsd: maximumLoss,
      potentialProfitUsd: potentialProfit,
      expectedNetUsd: expectedNet,
      riskRewardRatio: riskRewardRatio,
      atr: atr,
      fundingRate: premium.fundingRate,
      fundingCostUsd: fundingCost,
      confidence: decision.confidence,
    );
  }

  double _contextTrend(List<Candle> candles) {
    final closed =
        candles.length > 15 ? candles.sublist(0, candles.length - 1) : candles;
    final closes = closed.map((candle) => candle.close).toList(growable: false);
    final fast = _ema(closes, 5);
    final slow = _ema(closes, 13);
    return slow == 0 ? 0 : (fast - slow) / slow;
  }

  double _ema(List<double> values, int period) {
    final start = math.max(0, values.length - period * 3);
    var result = values[start];
    final multiplier = 2 / (period + 1);
    for (var index = start + 1; index < values.length; index++) {
      result += (values[index] - result) * multiplier;
    }
    return result;
  }

  double _atr(List<Candle> candles) {
    final closed = candles.sublist(0, candles.length - 1);
    final ranges = <double>[];
    for (var index = 1; index < closed.length; index++) {
      final candle = closed[index];
      final previousClose = closed[index - 1].close;
      ranges.add(
        math.max(
          candle.high - candle.low,
          math.max(
            (candle.high - previousClose).abs(),
            (candle.low - previousClose).abs(),
          ),
        ),
      );
    }
    final recent = ranges.sublist(math.max(0, ranges.length - 14));
    return recent.reduce((a, b) => a + b) / recent.length;
  }

  double _floorToStep(double value, double step) =>
      (value / step + 1e-9).floor() * step;

  double _ceilToStep(double value, double step) =>
      (value / step - 1e-9).ceil() * step;

  double _ceilCents(double value) => (value * 100 - 1e-9).ceil() / 100;
}
