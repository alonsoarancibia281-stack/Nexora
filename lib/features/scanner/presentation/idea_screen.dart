import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/format/simple_text.dart';
import '../../../shared/theme/nexora_theme.dart';
import '../../../shared/widgets/nexora_button.dart';
import '../application/scanner_controller.dart';
import '../domain/scan_candidate.dart';
import '../domain/setup_strategy.dart';
import '../domain/trade_plan.dart';

/// One idea end to end: what it is, why it moves, what the rule says, and the
/// plan you would place yourself.
class IdeaScreen extends StatefulWidget {
  const IdeaScreen({
    super.key,
    required this.controller,
    required this.candidate,
  });

  final ScannerController controller;
  final ScanCandidate candidate;

  @override
  State<IdeaScreen> createState() => _IdeaScreenState();
}

class _IdeaScreenState extends State<IdeaScreen> {
  TradeIdea? _idea;
  bool _loading = true;
  bool _loadingResearch = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final idea = await widget.controller.openIdea(widget.candidate);
      if (!mounted) return;
      setState(() {
        _idea = idea;
        _loading = false;
        _loadingResearch = widget.controller.researchReady;
      });
      if (!widget.controller.researchReady) return;
      final withNote = await widget.controller.addResearch(idea);
      if (!mounted) return;
      setState(() {
        _idea = withNote;
        _loadingResearch = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingResearch = false;
        _error = 'No llegan las velas de este par. Prueba otra vez.';
      });
    }
  }

  Future<void> _copyPlan(TradePlan plan) async {
    await Clipboard.setData(ClipboardData(text: plan.toClipboardText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Plan copiado. Colócalo tú en Binance.')),
    );
  }

  Future<void> _save(TradePlan plan) async {
    await widget.controller.save(plan);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Idea guardada en tu historial.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idea = _idea;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(widget.candidate.pair)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(_error!),
                    ),
                  )
                else if (idea != null) ...[
                  if (idea.plan case final plan?) ...[
                    // The action sits above everything you read.
                    NexoraButton(
                      label: 'Copiar plan',
                      icon: Icons.copy_all_outlined,
                      expand: true,
                      onPressed: () => _copyPlan(plan),
                    ),
                    const SizedBox(height: 10),
                    NexoraButton(
                      label: _saved ? 'Guardada' : 'Guardar en el historial',
                      icon: _saved ? Icons.check : Icons.bookmark_add_outlined,
                      level: NexoraLevel.secondary,
                      expand: true,
                      compact: true,
                      onPressed: _saved ? null : () => _save(plan),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _SnapshotCard(candidate: idea.candidate),
                  const SizedBox(height: 12),
                  _ResearchCard(
                    idea: idea,
                    loading: _loadingResearch,
                    available: widget.controller.researchReady,
                  ),
                  const SizedBox(height: 12),
                  _StrategiesCard(reports: idea.reports, play: idea.play),
                  const SizedBox(height: 12),
                  if (idea.plan case final plan?)
                    _PlanCard(plan: plan)
                  else
                    _NoPlayCard(reports: idea.reports),
                ],
                const SizedBox(height: 16),
                Text(
                  'Nexora no ejecuta órdenes ni toca tu cuenta. El plan es una '
                  'lectura de datos públicos, no un consejo de inversión.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.candidate});

  final ScanCandidate candidate;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      Simple.price(candidate.price),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  NexoraTag(
                    'Fuerza ${candidate.strength.round()}',
                    tone: NexoraTheme.brand,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  NexoraTag(
                    'Día ${Simple.signedPercent(candidate.changePercent24h, decimals: 1)}',
                    tone: candidate.changePercent24h >= 0
                        ? NexoraTheme.up
                        : NexoraTheme.down,
                  ),
                  NexoraTag(
                    'Semana ${Simple.signedPercent(candidate.weekChangePercent, decimals: 1)}',
                    tone: NexoraTheme.up,
                  ),
                  NexoraTag(
                    'Mes ${Simple.signedPercent(candidate.monthChangePercent, decimals: 1)}',
                    tone: NexoraTheme.up,
                  ),
                  NexoraTag('Volumen ${candidate.volumeSurge.toStringAsFixed(1)}x'),
                  NexoraTag(
                    candidate.isNearHigh
                        ? 'En máximos del mes'
                        : 'A ${candidate.distanceFromMonthHighPercent.toStringAsFixed(1)}% del máximo',
                  ),
                  NexoraTag(
                    'Días verdes ${Simple.percent(candidate.upDayRatio)}',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _ResearchCard extends StatelessWidget {
  const _ResearchCard({
    required this.idea,
    required this.loading,
    required this.available,
  });

  final TradeIdea idea;
  final bool loading;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final note = idea.research;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Lectura de los números',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                if (note != null)
                  NexoraTag(
                    note.grade,
                    tone: note.isStrong ? NexoraTheme.up : null,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else if (!available)
              Text(
                'La investigación con Claude está apagada. Añade la clave en '
                'Supabase para verla aquí.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (note == null)
              Text(
                'No llegó la lectura esta vez. Los números de arriba siguen valiendo.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else ...[
              _Line(icon: Icons.trending_up, label: 'Por qué se mueve', text: note.why),
              _Line(icon: Icons.savings_outlined, label: 'El dinero', text: note.money),
              _Line(icon: Icons.visibility_outlined, label: 'Qué vigilar', text: note.watch),
              _Line(icon: Icons.warning_amber_outlined, label: 'El riesgo', text: note.risk),
              const SizedBox(height: 4),
              Text(
                '${note.provider} lee solo estos números. No tiene noticias ni redes.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.label, required this.text});

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(text, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      );
}

class _StrategiesCard extends StatelessWidget {
  const _StrategiesCard({required this.reports, required this.play});

  final List<StrategyReport> reports;
  final StrategyReport? play;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Las estrategias',
                maxLines: 1,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Cada regla se prueba sobre el histórico de este par. Verás '
                'cuántas veces acierta antes de entrar.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              for (final report in reports) ...[
                _StrategyRow(
                  report: report,
                  isChosen: play?.strategy.id == report.strategy.id,
                ),
                if (report != reports.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      );
}

class _StrategyRow extends StatelessWidget {
  const _StrategyRow({required this.report, required this.isChosen});

  final StrategyReport report;
  final bool isChosen;

  @override
  Widget build(BuildContext context) {
    final record = report.record;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      report.strategy.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (isChosen) ...[
                    const SizedBox(width: 8),
                    const NexoraTag('Suena ahora', tone: NexoraTheme.up),
                  ] else if (report.isLive) ...[
                    const SizedBox(width: 8),
                    const NexoraTag('Salta, pero no convence'),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                report.strategy.idea,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                record.hasSample ? Simple.percent(record.hitRate) : '--',
                maxLines: 1,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: record.isFavorable
                      ? NexoraTheme.up
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                record.hasSample
                    ? Simple.outOf(record.wins, record.trades)
                    : 'poca historia',
                maxLines: 1,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final TradePlan plan;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'El plan · ${plan.strategyName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  NexoraTag('Gana ${plan.riskReward.toStringAsFixed(1)}x lo que arriesgas'),
                ],
              ),
              const SizedBox(height: 12),
              _PlanRow(
                label: 'Entras en',
                value: Simple.price(plan.levels.entry),
                tone: NexoraTheme.brand,
              ),
              _PlanRow(
                label: 'Sales si sale mal',
                value: Simple.price(plan.levels.stop),
                tone: NexoraTheme.down,
              ),
              _PlanRow(
                label: 'Hasta dónde puede llegar',
                value: Simple.price(plan.levels.target),
                tone: NexoraTheme.up,
              ),
              const Divider(height: 24),
              _PlanRow(
                label: 'Cantidad',
                value: plan.units >= 1
                    ? plan.units.toStringAsFixed(2)
                    : plan.units.toStringAsPrecision(4),
              ),
              _PlanRow(
                label: 'Te cuesta',
                value: '${Simple.price(plan.positionValue)} USDT',
              ),
              _PlanRow(
                label: 'Pierdes como mucho',
                value: '${plan.maxLoss.toStringAsFixed(2)} USDT',
                tone: NexoraTheme.down,
              ),
              _PlanRow(
                label: 'Puedes ganar',
                value: '${plan.possibleGain.toStringAsFixed(2)} USDT',
                tone: NexoraTheme.up,
              ),
              const SizedBox(height: 8),
              Text(
                'Calculado con ${plan.capital.toStringAsFixed(0)} USDT y '
                '${plan.riskPercent.toStringAsFixed(1)}% de riesgo. Cámbialo '
                'en Ajustar riesgo.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: tone ?? Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      );
}

class _NoPlayCard extends StatelessWidget {
  const _NoPlayCard({required this.reports});

  final List<StrategyReport> reports;

  @override
  Widget build(BuildContext context) {
    final live = reports.where((report) => report.isLive).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.pause_circle_outline, size: 28),
            const SizedBox(height: 12),
            Text(
              live.isEmpty
                  ? 'Ninguna regla suena hoy en este par. Sube fuerte, pero no '
                      'hay un punto de entrada con reglas.'
                  : 'Alguna regla salta, pero su histórico no da ventaja. '
                      'El bot solo avisa cuando las probabilidades acompañan.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
