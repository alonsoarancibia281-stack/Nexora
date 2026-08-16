import 'package:flutter/material.dart';

import '../../../shared/format/simple_text.dart';
import '../../../shared/theme/nexora_theme.dart';
import '../../../shared/widgets/nexora_button.dart';
import '../../../shared/widgets/nexora_shell.dart';
import '../application/scanner_controller.dart';
import '../domain/scan_candidate.dart';
import '../domain/trade_record.dart';
import 'idea_screen.dart';

/// The five step system: scan, research, predict, plan, remember.
class BotScreen extends StatefulWidget {
  const BotScreen({super.key});

  @override
  State<BotScreen> createState() => _BotScreenState();
}

class _BotScreenState extends State<BotScreen> {
  final ScannerController _controller = ScannerController();
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openIdea(ScanCandidate candidate) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IdeaScreen(controller: _controller, candidate: candidate),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => NexoraShell(
        currentIndex: 6,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(title: const Text('Bot')),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: _body(context),
            ),
          ),
        ),
      );

  List<Widget> _body(BuildContext context) {
    final tally = _controller.tally;
    return [
      // The buttons live at the top: you decide before you read.
      NexoraButton(
        label: _controller.isScanning ? 'Escaneando…' : 'Escanear el mercado',
        icon: Icons.radar,
        expand: true,
        onPressed: _controller.isScanning ? null : _controller.scan,
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: NexoraButton(
              label: _showHistory ? 'Ver ideas' : 'Historial ${_controller.records.length}',
              icon: _showHistory ? Icons.lightbulb_outline : Icons.history,
              level: NexoraLevel.secondary,
              expand: true,
              compact: true,
              onPressed: () => setState(() => _showHistory = !_showHistory),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: NexoraButton(
              label: 'Ajustar riesgo',
              icon: Icons.tune,
              level: NexoraLevel.tertiary,
              expand: true,
              compact: true,
              onPressed: _openRiskSheet,
            ),
          ),
        ],
      ),
      if (_controller.isScanning) ...[
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: _controller.progress),
        ),
        const SizedBox(height: 6),
        Text(
          'Revisa el mercado de Binance y se queda solo con lo que sube fuerte.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 16),
      if (_showHistory)
        ..._historySection(context, tally)
      else
        ..._ideasSection(context),
      const SizedBox(height: 18),
      Text(
        'Nexora prepara el plan; tú colocas la orden. La app no toca tu cuenta '
        'ni ejecuta operaciones.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  List<Widget> _ideasSection(BuildContext context) {
    if (_controller.candidates.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
            child: Column(
              children: [
                const Icon(Icons.radar, size: 30),
                const SizedBox(height: 12),
                Text(
                  _controller.error ??
                      'Pulsa escanear. El bot revisa cientos de pares y se '
                          'queda con los que suben con fuerza en la semana y en el mes.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Lo que sube con fuerza',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          if (_controller.lastScan case final at?)
            Text(
              Simple.clock(at),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      const SizedBox(height: 10),
      for (final candidate in _controller.candidates) ...[
        _CandidateCard(candidate: candidate, onTap: () => _openIdea(candidate)),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _historySection(BuildContext context, TradeTally tally) {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Cómo va el bot',
                maxLines: 1,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _Stat(label: 'Abiertas', value: '${tally.open}')),
                  Expanded(child: _Stat(label: 'Ganan', value: '${tally.wins}')),
                  Expanded(child: _Stat(label: 'Pierden', value: '${tally.losses}')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tally.hitRate == null
                    ? 'Aún no cierras ninguna idea.'
                    : 'Aciertas ${Simple.outOf(tally.wins, tally.closed)} · '
                        'media ${Simple.signedPercent(tally.averageResultPercent)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (_controller.records.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'Aquí queda cada idea que guardas, gane o pierda.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        )
      else
        for (final record in _controller.records) ...[
          _RecordCard(
            record: record,
            onClose: (price) => _controller.closeRecord(record, price),
            onSkip: () => _controller.markSkipped(record),
            onPublish: _controller.publishReady
                ? () async {
                    final sent = await _controller.publish(record);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          sent
                              ? 'La idea ya está en el historial público.'
                              : 'No se pudo publicar ahora.',
                        ),
                      ),
                    );
                  }
                : null,
            onRemove: () => _controller.removeRecord(record),
          ),
          const SizedBox(height: 10),
        ],
    ];
  }

  Future<void> _openRiskSheet() async {
    final capital = TextEditingController(
      text: _controller.capital.toStringAsFixed(0),
    );
    final risk = TextEditingController(
      text: _controller.riskPercent.toStringAsFixed(1),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tu dinero',
              maxLines: 1,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Tú decides cuánto arriesgas. El plan se calcula con estos dos números.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: capital,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Capital (USDT)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: risk,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Riesgo por idea (%)',
                helperText: 'Lo normal es entre 0.5% y 2%.',
              ),
            ),
            const SizedBox(height: 18),
            NexoraButton(
              label: 'Guardar',
              icon: Icons.check,
              expand: true,
              onPressed: () {
                final capitalValue = double.tryParse(capital.text.replaceAll(',', '.'));
                final riskValue = double.tryParse(risk.text.replaceAll(',', '.'));
                if (capitalValue != null) _controller.setCapital(capitalValue);
                if (riskValue != null) _controller.setRiskPercent(riskValue);
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      ),
    );

    capital.dispose();
    risk.dispose();
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.onTap});

  final ScanCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(NexoraTheme.radius + 2),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      candidate.pair,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    Simple.price(candidate.price),
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (candidate.strength / 100).clamp(0.0, 1.0),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Fuerza ${candidate.strength.round()}',
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  NexoraTag(
                    'Semana ${Simple.signedPercent(candidate.weekChangePercent, decimals: 1)}',
                    tone: NexoraTheme.up,
                  ),
                  NexoraTag(
                    'Mes ${Simple.signedPercent(candidate.monthChangePercent, decimals: 1)}',
                    tone: NexoraTheme.up,
                  ),
                  NexoraTag('Volumen ${candidate.volumeSurge.toStringAsFixed(1)}x'),
                  if (candidate.isNearHigh)
                    const NexoraTag('En máximos', tone: NexoraTheme.brand),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.onClose,
    required this.onSkip,
    required this.onRemove,
    this.onPublish,
  });

  final TradeRecord record;
  final ValueChanged<double> onClose;
  final VoidCallback onSkip;
  final VoidCallback onRemove;
  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) {
    final tone = switch (record.outcome) {
      TradeOutcome.win => NexoraTheme.up,
      TradeOutcome.loss => NexoraTheme.down,
      TradeOutcome.skipped => Theme.of(context).colorScheme.onSurfaceVariant,
      TradeOutcome.open => NexoraTheme.warn,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${record.pair} · ${record.strategyName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                NexoraTag(record.outcome.label, tone: tone),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Entrada ${Simple.price(record.entry)} · Stop ${Simple.price(record.stop)} '
              '· Objetivo ${Simple.price(record.target)}',
              maxLines: 2,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (record.resultPercent case final result?) ...[
              const SizedBox(height: 4),
              Text(
                'Resultado ${Simple.signedPercent(result)}',
                maxLines: 1,
                style: TextStyle(fontWeight: FontWeight.w700, color: tone),
              ),
            ],
            const SizedBox(height: 10),
            if (record.outcome == TradeOutcome.open)
              Row(
                children: [
                  Expanded(
                    child: NexoraButton(
                      label: 'Cerrar en objetivo',
                      level: NexoraLevel.secondary,
                      expand: true,
                      compact: true,
                      tone: NexoraTheme.up,
                      onPressed: () => onClose(record.target),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NexoraButton(
                      label: 'Cerrar en stop',
                      level: NexoraLevel.secondary,
                      expand: true,
                      compact: true,
                      tone: NexoraTheme.down,
                      onPressed: () => onClose(record.stop),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (record.outcome == TradeOutcome.open)
                  Expanded(
                    child: NexoraButton(
                      label: 'No entré',
                      level: NexoraLevel.quiet,
                      expand: true,
                      compact: true,
                      onPressed: onSkip,
                    ),
                  ),
                if (onPublish != null) ...[
                  if (record.outcome == TradeOutcome.open) const SizedBox(width: 8),
                  Expanded(
                    child: NexoraButton(
                      label: record.published ? 'Publicada' : 'Publicar',
                      icon: record.published ? Icons.public : Icons.upload_outlined,
                      level: NexoraLevel.quiet,
                      expand: true,
                      compact: true,
                      onPressed: record.published ? null : onPublish,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: NexoraButton(
                    label: 'Borrar',
                    level: NexoraLevel.quiet,
                    expand: true,
                    compact: true,
                    onPressed: onRemove,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ],
      );
}
