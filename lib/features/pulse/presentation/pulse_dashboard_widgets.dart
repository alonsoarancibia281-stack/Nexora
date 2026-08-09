import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../domain/pulse_decision_gate.dart';
import '../domain/pulse_ensemble_100.dart';
import '../domain/pulse_round_tracker.dart';
import '../domain/pulse_signal.dart';
import '../domain/futures_trade_planner.dart';

const nexoraGreen = Color(0xFF37E477);
const nexoraRed = Color(0xFFFF555F);
const nexoraAmber = Color(0xFFFFC23D);
const nexoraMuted = Color(0xFF8A98A5);

class ProbabilitySample {
  const ProbabilitySample({required this.at, required this.probabilityUp});

  final DateTime at;
  final double probabilityUp;
}

class KnowledgeEntry {
  const KnowledgeEntry({
    required this.source,
    required this.focus,
    required this.status,
    required this.positive,
  });

  final String source;
  final String focus;
  final String status;
  final bool positive;
}

class AuditEntry {
  const AuditEntry({
    required this.label,
    required this.status,
    required this.level,
  });

  final String label;
  final String status;
  final int level;
}

class BreakoutView {
  const BreakoutView({
    required this.status,
    required this.direction,
    required this.boxHigh,
    required this.boxLow,
    required this.confirmations,
  });

  final String status;
  final PulseDirection direction;
  final double boxHigh;
  final double boxLow;
  final List<String> confirmations;
}

class NexoraPanel extends StatelessWidget {
  const NexoraPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0B131B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF22303B)),
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 10),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFB8C2CA),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .65,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: nexoraMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}

class NexoraDashboardHeader extends StatelessWidget {
  const NexoraDashboardHeader({
    super.key,
    required this.price,
    required this.change24h,
    required this.countdown,
    required this.roundNumber,
    required this.loading,
    required this.onBack,
    this.brandTitle = 'NEXORA',
    this.brandSubtitle = 'META-MOTOR DE 100 ANALISTAS',
    this.symbolLabel = 'BTC/USDT',
    this.sourceLabel = 'BINANCE REAL',
  });

  final double price;
  final double change24h;
  final String countdown;
  final int roundNumber;
  final bool loading;
  final VoidCallback? onBack;
  final String brandTitle;
  final String brandSubtitle;
  final String symbolLabel;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    final changeColor = change24h >= 0 ? nexoraGreen : nexoraRed;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081018),
        border: Border.all(color: const Color(0xFF22303B)),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onBack != null)
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, size: 19),
                  visualDensity: VisualDensity.compact,
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    brandTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                  Text(
                    brandSubtitle,
                    style: const TextStyle(color: nexoraMuted, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          _HeaderBlock(
            label: 'RONDA EN VIVO',
            value: '#$roundNumber',
          ),
          _HeaderBlock(
            label: symbolLabel,
            value: price <= 0 ? '—' : _price(price),
            valueColor: nexoraGreen,
            suffix: price <= 0
                ? null
                : '${change24h >= 0 ? '+' : ''}${change24h.toStringAsFixed(2)}%',
            suffixColor: changeColor,
          ),
          _HeaderBlock(
            label: 'PRÓXIMOS 5 MINUTOS',
            value: countdown,
          ),
          _HeaderBlock(
            label: 'FUENTE',
            value: loading ? 'ACTUALIZANDO' : sourceLabel,
            valueColor: loading ? nexoraAmber : nexoraGreen,
          ),
        ],
      ),
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({
    required this.label,
    required this.value,
    this.valueColor,
    this.suffix,
    this.suffixColor,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? suffix;
  final Color? suffixColor;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 125),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: nexoraMuted, fontSize: 9),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 7),
                  Text(
                    suffix!,
                    style: TextStyle(
                      color: suffixColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
}

class PredictionPanel extends StatelessWidget {
  const PredictionPanel({
    super.key,
    required this.decision,
    required this.calibrationProgress,
    required this.ensemble,
    required this.rawProbabilityUp,
    required this.statisticalQuality,
    required this.knowledgeMultiplier,
    required this.auditPassed,
  });

  final LockedPulseDecision? decision;
  final double calibrationProgress;
  final PulseEnsemble100Result? ensemble;
  final double rawProbabilityUp;
  final double statisticalQuality;
  final double knowledgeMultiplier;
  final bool auditPassed;

  @override
  Widget build(BuildContext context) {
    final direction = decision?.direction;
    final calibrating = decision == null && calibrationProgress < 1;
    final color = direction == PulseDirection.up
        ? nexoraGreen
        : direction == PulseDirection.down
            ? nexoraRed
            : nexoraAmber;
    final label = direction == PulseDirection.up
        ? 'ALTA ↑'
        : direction == PulseDirection.down
            ? 'BAJA ↓'
            : calibrating
                ? 'CALIBRANDO'
                : 'SIN SEÑAL';
    final up = ensemble?.upAnalysts ?? 0;
    final down = ensemble?.downAnalysts ?? 0;
    final neutral = ensemble?.neutralAnalysts ?? 100;
    final agreement = ensemble?.agreement ?? 0;
    final displayedProbability = decision?.confidence;
    return NexoraPanel(
      title: 'Predicción Nexora',
      subtitle: 'Resultado agregado con filtros y controles reales',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: decision == null ? 28 : 40,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            displayedProbability == null
                ? calibrating
                    ? '${(calibrationProgress * 100).toStringAsFixed(0)}%'
                    : '—'
                : '${displayedProbability.toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontSize: 42,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            displayedProbability == null
                ? calibrating
                    ? 'calibración completada'
                    : 'evidencia insuficiente para publicar dirección'
                : 'probabilidad final calibrada y bloqueada',
            textAlign: TextAlign.center,
            style: const TextStyle(color: nexoraMuted, fontSize: 10),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: displayedProbability == null
                ? calibrationProgress
                : displayedProbability / 100,
            color: color,
            backgroundColor: const Color(0xFF26333D),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0%', style: TextStyle(color: nexoraMuted, fontSize: 8)),
                Text('25%', style: TextStyle(color: nexoraMuted, fontSize: 8)),
                Text('50%', style: TextStyle(color: nexoraMuted, fontSize: 8)),
                Text('75%', style: TextStyle(color: nexoraMuted, fontSize: 8)),
                Text('100%', style: TextStyle(color: nexoraMuted, fontSize: 8)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'ALTA',
                  value: '$up ($up%)',
                  color: nexoraGreen,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatBox(
                  label: 'BAJA',
                  value: '$down ($down%)',
                  color: nexoraRed,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatBox(
                  label: 'INCIERTO',
                  value: '$neutral ($neutral%)',
                  color: nexoraAmber,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          NexoraMetricRow(
            label: 'Consenso bruto',
            value: '${(agreement * 100).toStringAsFixed(1)}%',
            color: agreement >= .58 ? nexoraGreen : nexoraAmber,
          ),
          NexoraMetricRow(
            label: 'Probabilidad antes del bloqueo',
            value: '${(rawProbabilityUp * 100).toStringAsFixed(1)}% ALTA',
          ),
          NexoraMetricRow(
            label: 'Calidad estadística',
            value: '${(statisticalQuality * 100).toStringAsFixed(1)}%',
            color: statisticalQuality >= .12 ? nexoraGreen : nexoraAmber,
          ),
          NexoraMetricRow(
            label: 'Multiplicador de conocimiento',
            value: 'x${knowledgeMultiplier.toStringAsFixed(2)}',
          ),
          NexoraMetricRow(
            label: 'Auditoría histórica',
            value: auditPassed ? 'HABILITADA' : 'VETO ACTIVO',
            color: auditPassed ? nexoraGreen : nexoraRed,
          ),
          const SizedBox(height: 8),
          const Text(
            'La dirección publicada no cambia dentro de la misma ronda. Si la evidencia es débil, Nexora se abstiene.',
            textAlign: TextAlign.center,
            style: TextStyle(color: nexoraMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class FuturesSymbolSelector extends StatelessWidget {
  const FuturesSymbolSelector({
    super.key,
    required this.symbols,
    required this.selectedSymbol,
    required this.onChanged,
  });

  final List<String> symbols;
  final String selectedSymbol;
  final ValueChanged<String> onChanged;

  String _labelFor(String symbol) {
    final base = symbol.endsWith('USDT')
        ? symbol.substring(0, symbol.length - 'USDT'.length)
        : symbol;
    return '$base / USDT Perpetual';
  }

  @override
  Widget build(BuildContext context) => NexoraPanel(
        title: 'Mercado Futures',
        subtitle: 'El pool analizará el contrato seleccionado con datos reales',
        child: DropdownButtonFormField<String>(
          value: selectedSymbol,
          isExpanded: true,
          dropdownColor: const Color(0xFF101820),
          decoration: const InputDecoration(
            labelText: 'Criptomoneda',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: symbols
              .map(
                (symbol) => DropdownMenuItem<String>(
                  value: symbol,
                  child: Text(_labelFor(symbol)),
                ),
              )
              .toList(growable: false),
          onChanged: (symbol) {
            if (symbol != null) onChanged(symbol);
          },
        ),
      );
}

class FuturesTradePlanPanel extends StatelessWidget {
  const FuturesTradePlanPanel({
    super.key,
    required this.symbol,
    required this.plan,
    required this.validUntil,
  });

  final String symbol;
  final FuturesTradePlan? plan;
  final DateTime? validUntil;

  @override
  Widget build(BuildContext context) {
    final current = plan;
    final actionable = current?.actionable == true;
    final isLong = current?.action == FuturesTradeAction.long;
    final color = !actionable
        ? nexoraAmber
        : isLong
            ? nexoraGreen
            : nexoraRed;
    final end = validUntil?.toLocal();
    final validity = end == null
        ? '—'
        : '${end.hour.toString().padLeft(2, '0')}:'
            '${end.minute.toString().padLeft(2, '0')}:'
            '${end.second.toString().padLeft(2, '0')}';
    final baseAsset = symbol.endsWith('USDT')
        ? symbol.substring(0, symbol.length - 'USDT'.length)
        : symbol;
    return NexoraPanel(
      title: 'Plan Futures $symbol Perpetual',
      subtitle: 'USDⓈ-M · margen aislado · riesgo calculado',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          border: Border.all(color: color.withValues(alpha: .55)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'AISLADO · ${current?.leverage ?? 3}x',
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            !actionable
                ? 'NO OPERAR'
                : isLong
                    ? 'COMPRAR / LONG'
                    : 'VENDER / SHORT',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (actionable) ...[
            Text(
              '${current!.margin.toStringAsFixed(2)} USDT',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Divider(height: 20),
            NexoraMetricRow(
              label: 'Operación',
              value: isLong ? 'COMPRA · LONG' : 'VENTA · SHORT',
              color: color,
            ),
            NexoraMetricRow(
              label: 'Modo',
              value: 'USDⓈ-M · AISLADO · ${current.leverage}x',
            ),
            NexoraMetricRow(
              label: 'Margen asignado',
              value: '${current.margin.toStringAsFixed(2)} USDT',
            ),
            NexoraMetricRow(
              label: 'Valor nocional',
              value: '${current.notional.toStringAsFixed(2)} USDT',
            ),
            NexoraMetricRow(
              label: 'Entrada límite',
              value: '${_price(current.entryPrice)} USDT',
              color: color,
            ),
            NexoraMetricRow(
              label: 'Cantidad estimada',
              value: '${current.quantity.toStringAsFixed(3)} $baseAsset',
            ),
            NexoraMetricRow(
              label: 'Take Profit',
              value: '${_price(current.takeProfitPrice)} USDT',
              color: nexoraGreen,
            ),
            NexoraMetricRow(
              label: 'Stop Loss',
              value: '${_price(current.stopLossPrice)} USDT',
              color: nexoraRed,
            ),
            NexoraMetricRow(
              label: 'Liquidación aproximada',
              value: '${_price(current.estimatedLiquidationPrice)} USDT',
              color: nexoraAmber,
            ),
            NexoraMetricRow(
              label: 'Riesgo máximo estimado',
              value: '${current.maximumLossUsd.toStringAsFixed(4)} USDT',
              color: nexoraRed,
            ),
            NexoraMetricRow(
              label: 'Ganancia objetivo neta estimada',
              value: '${current.potentialProfitUsd.toStringAsFixed(4)} USDT',
              color: nexoraGreen,
            ),
            NexoraMetricRow(
              label: 'Valor esperado estimado',
              value: '+${current.expectedNetUsd.toStringAsFixed(4)} USDT',
              color: nexoraGreen,
            ),
            NexoraMetricRow(
              label: 'Financiación vigente',
              value: '${(current.fundingRate * 100).toStringAsFixed(4)}%',
              color:
                  current.fundingRate.abs() > .0005 ? nexoraAmber : nexoraMuted,
            ),
            NexoraMetricRow(
              label: 'Riesgo/beneficio bruto',
              value: '1:${current.riskRewardRatio.toStringAsFixed(1)}',
            ),
            NexoraMetricRow(label: 'Válido hasta', value: validity),
          ] else ...[
            const SizedBox(height: 7),
            Text(
              current?.reason ?? 'Esperando datos reales y señal bloqueada.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: nexoraMuted, fontSize: 11),
            ),
            if ((current?.requiredMargin ?? 0) > 0) ...[
              const Divider(height: 20),
              NexoraMetricRow(
                label: 'Margen solicitado',
                value: '${current!.requestedMargin.toStringAsFixed(2)} USDT',
              ),
              NexoraMetricRow(
                label: 'Margen mínimo estimado',
                value: '${current.requiredMargin.toStringAsFixed(2)} USDT',
                color: nexoraAmber,
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            actionable
                ? 'No persigas el precio. Si ejecutas el plan manualmente, usa '
                    'STOP_MARKET y TAKE_PROFIT_MARKET para cerrar la posición.'
                : 'La abstención protege capital cuando la evidencia no compensa el riesgo.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: nexoraMuted, fontSize: 9),
          ),
          const SizedBox(height: 5),
          const Text(
            'Nexora no envía órdenes. La liquidación es aproximada y ninguna estrategia garantiza ganancias.',
            textAlign: TextAlign.center,
            style: TextStyle(color: nexoraMuted, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class AnalystDistributionPanel extends StatelessWidget {
  const AnalystDistributionPanel({super.key, required this.ensemble});

  final PulseEnsemble100Result? ensemble;

  @override
  Widget build(BuildContext context) {
    final up = ensemble?.upAnalysts ?? 0;
    final down = ensemble?.downAnalysts ?? 0;
    final neutral = ensemble?.neutralAnalysts ?? 100;
    return NexoraPanel(
      title: 'Distribución de los 100 analistas',
      subtitle: 'Consenso bruto antes de filtros y bloqueo',
      child: Row(
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: CustomPaint(
              painter: _DonutPainter(up: up, down: down, neutral: neutral),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${ensemble?.activeAnalysts ?? 100}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'TOTAL',
                      style: TextStyle(color: nexoraMuted, fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                _LegendRow(label: 'ALTA', value: up, color: nexoraGreen),
                _LegendRow(label: 'BAJA', value: down, color: nexoraRed),
                _LegendRow(
                  label: 'INCIERTO',
                  value: neutral,
                  color: nexoraAmber,
                ),
                const Divider(height: 20),
                NexoraMetricRow(
                  label: 'Nivel de acuerdo',
                  value: ensemble == null
                      ? '—'
                      : ensemble!.agreement.toStringAsFixed(2),
                ),
                NexoraMetricRow(
                  label: 'Dispersión',
                  value: ensemble == null
                      ? '—'
                      : (1 - ensemble!.agreement).toStringAsFixed(2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AnalystTeamsPanel extends StatelessWidget {
  const AnalystTeamsPanel({super.key, required this.ensemble});

  final PulseEnsemble100Result? ensemble;

  @override
  Widget build(BuildContext context) {
    final teams = ensemble?.teamOpinions ?? const <TeamOpinion>[];
    return NexoraPanel(
      title: 'Equipos de analistas · 10 × 10',
      subtitle: 'Probabilidad y calidad calculadas por familia',
      child: teams.isEmpty
          ? const Text(
              'Recopilando datos suficientes para activar los 100 analistas.',
              style: TextStyle(color: nexoraMuted, fontSize: 10),
            )
          : Column(
              children: teams.map((team) {
                final edge = team.probabilityUp - .5;
                final directional = edge.abs() >= .02;
                final up = edge >= 0;
                final color = !directional
                    ? nexoraAmber
                    : up
                        ? nexoraGreen
                        : nexoraRed;
                final direction = !directional
                    ? 'NEUTRO'
                    : up
                        ? 'ALTA'
                        : 'BAJA';
                return NexoraMetricRow(
                  label: _analystFamilyLabel(team.family),
                  value:
                      '$direction ${(team.probabilityUp * 100).toStringAsFixed(1)}%  ·  Q ${(team.quality * 100).toStringAsFixed(0)}%',
                  color: color,
                );
              }).toList(growable: false),
            ),
    );
  }
}

class KnowledgePanel extends StatelessWidget {
  const KnowledgePanel({super.key, required this.entries});

  final List<KnowledgeEntry> entries;

  @override
  Widget build(BuildContext context) => NexoraPanel(
        title: 'Marco de conocimiento aplicado',
        subtitle: 'Principios convertidos en controles medibles',
        child: Column(
          children: entries
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(
                          '${entry.source} · ${entry.focus}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Text(
                          entry.status,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: entry.positive ? nexoraGreen : nexoraAmber,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
        ),
      );
}

class MarketChartPanel extends StatelessWidget {
  const MarketChartPanel({
    super.key,
    required this.candles,
    required this.currentPrice,
    required this.boxHigh,
    required this.boxLow,
    this.title = 'Gráfico BTC/USDT · 5m',
  });

  final List<Candle> candles;
  final double currentPrice;
  final double boxHigh;
  final double boxLow;
  final String title;

  @override
  Widget build(BuildContext context) => NexoraPanel(
        title: title,
        subtitle: 'Velas y volumen reales de Binance',
        trailing: Text(
          currentPrice <= 0 ? '—' : _price(currentPrice),
          style: const TextStyle(
            color: nexoraGreen,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: SizedBox(
          height: 275,
          width: double.infinity,
          child: CustomPaint(
            painter: _MarketChartPainter(
              candles: candles,
              boxHigh: boxHigh,
              boxLow: boxLow,
            ),
          ),
        ),
      );
}

class MicrostructurePanel extends StatelessWidget {
  const MicrostructurePanel({
    super.key,
    required this.book,
    required this.trades,
    this.baseAsset = 'BTC',
  });

  final OrderBookSnapshot? book;
  final AggTradeSnapshot? trades;
  final String baseAsset;

  @override
  Widget build(BuildContext context) {
    final bidVolume = book?.bidVolume ?? 0;
    final askVolume = book?.askVolume ?? 0;
    final total = bidVolume + askVolume;
    final imbalance = total <= 0 ? 0.0 : (bidVolume - askVolume) / total;
    return NexoraPanel(
      title: 'Microestructura · aggTrades',
      subtitle: 'Flujo agresor y libro de órdenes real',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'FLUJO NETO',
                  value: trades == null
                      ? '—'
                      : '${trades!.signedVolume >= 0 ? '+' : ''}${(trades!.signedVolume * 100).toStringAsFixed(1)}%',
                  color: (trades?.signedVolume ?? 0) >= 0
                      ? nexoraGreen
                      : nexoraRed,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _StatBox(
                  label: 'TRADES/SEG',
                  value: trades?.tradesPerSecond.toStringAsFixed(1) ?? '—',
                  color: nexoraGreen,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _StatBox(
                  label: 'DESEQUILIBRIO',
                  value: '${(imbalance * 100).toStringAsFixed(1)}%',
                  color: imbalance >= 0 ? nexoraGreen : nexoraRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _BookSide(
                  label: 'COMPRAS',
                  color: nexoraGreen,
                  levels: book?.bids.take(7).toList() ?? const [],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BookSide(
                  label: 'VENTAS',
                  color: nexoraRed,
                  levels: book?.asks.take(7).toList() ?? const [],
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          NexoraMetricRow(
            label: 'Spread',
            value: book == null
                ? '—'
                : '${book!.spreadBps.toStringAsFixed(3)} bps',
          ),
          NexoraMetricRow(
            label: 'Microprecio',
            value: book == null
                ? '—'
                : '${book!.micropriceEdge.toStringAsFixed(3)} bps',
          ),
          NexoraMetricRow(
            label: 'Volumen comprador / vendedor',
            value: trades == null
                ? '—'
                : '${trades!.buyQuantity.toStringAsFixed(2)} / ${trades!.sellQuantity.toStringAsFixed(2)} $baseAsset',
          ),
        ],
      ),
    );
  }
}

class QualityPanel extends StatelessWidget {
  const QualityPanel({
    super.key,
    required this.metrics,
    required this.statisticalQuality,
  });

  final PulseCalibrationMetrics metrics;
  final double statisticalQuality;

  @override
  Widget build(BuildContext context) {
    final hasSamples = metrics.samples > 0;
    return NexoraPanel(
      title: '¿Mejora vs azar?',
      subtitle: 'Solo rondas reales cerradas en este dispositivo',
      child: Column(
        children: [
          NexoraMetricRow(
              label: 'Rondas auditadas', value: '${metrics.samples}'),
          NexoraMetricRow(
            label: 'Accuracy Nexora',
            value: hasSamples ? _percent(metrics.accuracy) : 'RECOPILANDO',
            color: !hasSamples
                ? nexoraAmber
                : metrics.accuracy > .5
                    ? nexoraGreen
                    : nexoraRed,
          ),
          const NexoraMetricRow(label: 'Accuracy azar', value: '50.0%'),
          NexoraMetricRow(
            label: 'Brier Nexora',
            value: hasSamples ? metrics.brierScore.toStringAsFixed(3) : '—',
          ),
          const NexoraMetricRow(label: 'Brier azar', value: '0.250'),
          NexoraMetricRow(
            label: 'Error calibración',
            value: hasSamples
                ? metrics.expectedCalibrationError.toStringAsFixed(3)
                : '—',
          ),
          NexoraMetricRow(
            label: 'Calidad señal actual',
            value: _percent(statisticalQuality),
          ),
          const SizedBox(height: 8),
          Text(
            metrics.samples < 30
                ? 'Se requieren al menos 30 rondas con señal para una primera auditoría; 100 para una muestra útil.'
                : 'El bloqueo histórico se activa si Nexora deja de superar simultáneamente accuracy 50% y Brier 0.250.',
            style: const TextStyle(color: nexoraMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class AuditPanel extends StatelessWidget {
  const AuditPanel({
    super.key,
    required this.title,
    required this.entries,
  });

  final String title;
  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context) => NexoraPanel(
        title: title,
        child: Column(
          children: entries
              .map(
                (entry) => NexoraMetricRow(
                  label: entry.label,
                  value: entry.status,
                  color: switch (entry.level) {
                    0 => nexoraGreen,
                    1 => nexoraAmber,
                    _ => nexoraRed,
                  },
                ),
              )
              .toList(growable: false),
        ),
      );
}

class BreakoutPanel extends StatelessWidget {
  const BreakoutPanel({super.key, required this.breakout});

  final BreakoutView breakout;

  @override
  Widget build(BuildContext context) {
    final color = breakout.direction == PulseDirection.up
        ? nexoraGreen
        : breakout.direction == PulseDirection.down
            ? nexoraRed
            : nexoraAmber;
    return NexoraPanel(
      title: 'Darvas box y Livermore',
      subtitle: 'Ruptura con confirmación de precio, volumen y flujo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            breakout.status,
            style: TextStyle(
              color: color,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          NexoraMetricRow(
            label: 'Techo de caja',
            value: breakout.boxHigh <= 0 ? '—' : _price(breakout.boxHigh),
          ),
          NexoraMetricRow(
            label: 'Piso de caja',
            value: breakout.boxLow <= 0 ? '—' : _price(breakout.boxLow),
          ),
          const Divider(height: 18),
          ...breakout.confirmations.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    item.startsWith('✓') ? Icons.check_circle : Icons.cancel,
                    size: 14,
                    color: item.startsWith('✓') ? nexoraGreen : nexoraRed,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      item.substring(2),
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProbabilityEvolutionPanel extends StatelessWidget {
  const ProbabilityEvolutionPanel({super.key, required this.samples});

  final List<ProbabilitySample> samples;

  @override
  Widget build(BuildContext context) => NexoraPanel(
        title: 'Evolución del consenso bruto',
        subtitle:
            'La señal final permanece bloqueada aunque el consenso interno fluctúe',
        child: SizedBox(
          height: 165,
          width: double.infinity,
          child: CustomPaint(painter: _ProbabilityPainter(samples)),
        ),
      );
}

class RoundHistoryPanel extends StatelessWidget {
  const RoundHistoryPanel({super.key, required this.outcomes});

  final List<PulseRoundOutcome> outcomes;

  @override
  Widget build(BuildContext context) => NexoraPanel(
        title: 'Historial reciente de rondas reales',
        subtitle: 'Registrado localmente; no contiene resultados simulados',
        child: outcomes.isEmpty
            ? const Text(
                'Aún no hay rondas cerradas. Mantén Nexora abierta para iniciar el registro auditable.',
                style: TextStyle(color: nexoraMuted, fontSize: 11),
              )
            : Column(
                children: outcomes.take(6).map(_row).toList(growable: false),
              ),
      );

  Widget _row(PulseRoundOutcome outcome) {
    final observation = _representativeObservation(outcome);
    final predictedUp = observation?.probabilityUp != null
        ? observation!.probabilityUp >= .5
        : null;
    final correct =
        predictedUp == null ? null : predictedUp == outcome.finishedUp;
    final brier = observation == null
        ? null
        : math.pow(
            observation.probabilityUp - (outcome.finishedUp ? 1 : 0),
            2,
          );
    final time = outcome.roundStart.toLocal();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1D2A34))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 10),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              predictedUp == null
                  ? 'SIN SEÑAL'
                  : (predictedUp ? 'ALTA' : 'BAJA'),
              style: TextStyle(
                color: predictedUp == null
                    ? nexoraAmber
                    : predictedUp
                        ? nexoraGreen
                        : nexoraRed,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              outcome.finishedUp ? 'ALTA' : 'BAJA',
              style: TextStyle(
                color: outcome.finishedUp ? nexoraGreen : nexoraRed,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              correct == null ? '—' : (correct ? '✓' : '✕'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: correct == true ? nexoraGreen : nexoraRed,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              brier?.toStringAsFixed(3) ?? '—',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class AggregatePerformancePanel extends StatelessWidget {
  const AggregatePerformancePanel({super.key, required this.metrics});

  final PulseCalibrationMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final advantage = metrics.samples == 0 ? 0.0 : metrics.accuracy - .5;
    return NexoraPanel(
      title: 'Rendimiento agregado real',
      child: Column(
        children: [
          NexoraMetricRow(
              label: 'Rondas con señal', value: '${metrics.samples}'),
          NexoraMetricRow(
            label: 'Accuracy Nexora',
            value: metrics.samples == 0 ? '—' : _percent(metrics.accuracy),
          ),
          const NexoraMetricRow(label: 'Accuracy azar', value: '50.0%'),
          NexoraMetricRow(
            label: 'Brier Score',
            value: metrics.samples == 0
                ? '—'
                : metrics.brierScore.toStringAsFixed(3),
          ),
          NexoraMetricRow(
            label: 'Ventaja observada',
            value: metrics.samples == 0
                ? '—'
                : '${advantage >= 0 ? '+' : ''}${(advantage * 100).toStringAsFixed(1)} pp',
            color: advantage > 0 ? nexoraGreen : nexoraRed,
          ),
          const SizedBox(height: 8),
          const Text(
            'Estas métricas describen la muestra local observada; no garantizan resultados futuros.',
            style: TextStyle(color: nexoraMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class NexoraMetricRow extends StatelessWidget {
  const NexoraMetricRow({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: nexoraMuted, fontSize: 10.5),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                color: color ?? const Color(0xFFD8E0E6),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF071018),
          border: Border.all(color: const Color(0xFF1F2D38)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: nexoraMuted, fontSize: 8),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(width: 8, height: 8, color: color),
            const SizedBox(width: 7),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 10))),
            Text(
              '$value ($value%)',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

class _BookSide extends StatelessWidget {
  const _BookSide({
    required this.label,
    required this.color,
    required this.levels,
  });

  final String label;
  final Color color;
  final List<OrderBookLevel> levels;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          if (levels.isEmpty)
            const Text('—', style: TextStyle(color: nexoraMuted))
          else
            ...levels.map(
              (level) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        level.quantity.toStringAsFixed(3),
                        style: TextStyle(color: color, fontSize: 9),
                      ),
                    ),
                    Text(_price(level.price),
                        style: const TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ),
        ],
      );
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.up,
    required this.down,
    required this.neutral,
  });

  final int up;
  final int down;
  final int neutral;

  @override
  void paint(Canvas canvas, Size size) {
    final total = math.max(1, up + down + neutral);
    final rect = Offset.zero & size;
    const start = -math.pi / 2;
    var angle = start;
    for (final segment in [
      (value: up, color: nexoraGreen),
      (value: down, color: nexoraRed),
      (value: neutral, color: nexoraAmber),
    ]) {
      final sweep = segment.value / total * math.pi * 2;
      canvas.drawArc(
        rect.deflate(8),
        angle,
        sweep,
        false,
        Paint()
          ..color = segment.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18,
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      up != oldDelegate.up ||
      down != oldDelegate.down ||
      neutral != oldDelegate.neutral;
}

class _MarketChartPainter extends CustomPainter {
  const _MarketChartPainter({
    required this.candles,
    required this.boxHigh,
    required this.boxLow,
  });

  final List<Candle> candles;
  final double boxHigh;
  final double boxLow;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final visible =
        candles.length > 32 ? candles.sublist(candles.length - 32) : candles;
    final chartHeight = size.height * .78;
    final volumeTop = chartHeight + 12;
    final minLow = visible.map((c) => c.low).reduce(math.min);
    final maxHigh = visible.map((c) => c.high).reduce(math.max);
    final range = math.max(maxHigh - minLow, .0001);
    final maxVolume = math.max(
      visible.map((c) => c.volume).reduce(math.max),
      .0001,
    );
    final step = size.width / visible.length;
    final grid = Paint()
      ..color = const Color(0xFF1C2B35)
      ..strokeWidth = .8;
    for (var i = 1; i < 5; i++) {
      final y = chartHeight * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    double y(double price) =>
        chartHeight - ((price - minLow) / range) * chartHeight;
    for (var i = 0; i < visible.length; i++) {
      final candle = visible[i];
      final rising = candle.close >= candle.open;
      final color = rising ? nexoraGreen : nexoraRed;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1;
      final x = i * step + step / 2;
      canvas.drawLine(
        Offset(x, y(candle.high)),
        Offset(x, y(candle.low)),
        paint,
      );
      final top = math.min(y(candle.open), y(candle.close));
      final bottom = math.max(y(candle.open), y(candle.close));
      canvas.drawRect(
        Rect.fromLTRB(
          x - step * .28,
          top,
          x + step * .28,
          math.max(bottom, top + 1.4),
        ),
        paint,
      );
      final volumeHeight =
          candle.volume / maxVolume * (size.height - volumeTop);
      canvas.drawRect(
        Rect.fromLTWH(
          x - step * .28,
          size.height - volumeHeight,
          step * .56,
          volumeHeight,
        ),
        Paint()..color = color.withValues(alpha: .45),
      );
    }
    void level(double value, Color color) {
      if (value < minLow || value > maxHigh) return;
      final levelY = y(value);
      canvas.drawLine(
        Offset(0, levelY),
        Offset(size.width, levelY),
        Paint()
          ..color = color.withValues(alpha: .65)
          ..strokeWidth = 1,
      );
    }

    level(boxHigh, nexoraGreen);
    level(boxLow, nexoraRed);
  }

  @override
  bool shouldRepaint(covariant _MarketChartPainter oldDelegate) =>
      oldDelegate.candles != candles ||
      oldDelegate.boxHigh != boxHigh ||
      oldDelegate.boxLow != boxLow;
}

class _ProbabilityPainter extends CustomPainter {
  const _ProbabilityPainter(this.samples);

  final List<ProbabilitySample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF1C2B35)
      ..strokeWidth = .8;
    for (final value in [.25, .5, .75]) {
      final y = size.height * (1 - value);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (samples.length < 2) return;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = i / (samples.length - 1) * size.width;
      final y = size.height * (1 - samples[i].probabilityUp);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = nexoraGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ProbabilityPainter oldDelegate) =>
      oldDelegate.samples != samples;
}

PulseRoundObservation? _representativeObservation(PulseRoundOutcome outcome) {
  if (outcome.observations.isEmpty) return null;
  return outcome.observations.reduce(
    (a, b) =>
        (a.secondsRemaining - 240).abs() <= (b.secondsRemaining - 240).abs()
            ? a
            : b,
  );
}

String _analystFamilyLabel(AnalystFamily family) => switch (family) {
      AnalystFamily.momentum => 'Momentum',
      AnalystFamily.trend => 'Tendencia',
      AnalystFamily.volatility => 'Volatilidad',
      AnalystFamily.meanReversion => 'Reversión a la media',
      AnalystFamily.orderBook => 'Libro de órdenes',
      AnalystFamily.tradeFlow => 'Flujo agresor',
      AnalystFamily.volume => 'Volumen',
      AnalystFamily.priceAction => 'Acción del precio',
      AnalystFamily.intermarket => 'Confirmación BTC/ETH',
      AnalystFamily.regime => 'Régimen',
    };

String _price(double value) {
  final decimals = value.abs() < 10
      ? 4
      : value.abs() < 100
          ? 3
          : 2;
  final fixed = value.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${buffer.toString()}.${parts.last}';
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
