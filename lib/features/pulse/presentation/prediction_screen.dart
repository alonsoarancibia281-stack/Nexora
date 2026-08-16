import 'package:flutter/material.dart';

import '../../../shared/format/simple_text.dart';
import '../../../shared/theme/nexora_theme.dart';
import '../../../shared/widgets/nexora_button.dart';
import '../../../shared/widgets/nexora_shell.dart';
import '../application/prediction_controller.dart';
import '../domain/exit_watch.dart';
import '../domain/market_agent.dart';
import '../domain/prediction_alert.dart';
import '../domain/prediction_horizon.dart';
import '../domain/prediction_outlook.dart';

/// The prediction desk: one screen, three rounds.
class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  final PredictionController _controller = PredictionController();
  PredictionHorizon _horizon = PredictionHorizon.m5;
  bool _showAlerts = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onUpdate);
    _controller.start();
  }

  void _onUpdate() {
    final flash = _controller.takeFlash();
    if (flash == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: Duration(seconds: flash.isUrgent ? 6 : 4),
          backgroundColor: flash.isUrgent ? NexoraTheme.down : null,
          content: Text(
            '${flash.title} · ${flash.message}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NexoraShell(
        currentIndex: 5,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text('Predicción BTC'),
              actions: [
                IconButton(
                  tooltip: 'Actualizar ahora',
                  onPressed: _controller.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: RefreshIndicator(
              onRefresh: _controller.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: _body(context),
              ),
            ),
          ),
        ),
      );

  List<Widget> _body(BuildContext context) {
    final outlook = _controller.outlookFor(_horizon);
    final advice = _controller.adviceFor(_horizon);
    final window = _controller.windowFor(_horizon);
    final alerts = _controller.alerts;

    return [
      // Buttons first: the choices live at the top of the screen.
      NexoraSegmented<PredictionHorizon>(
        values: PredictionHorizon.values,
        selected: _horizon,
        labelOf: (value) => value.tag,
        onSelected: (value) => setState(() => _horizon = value),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: NexoraButton(
              label: 'Actualizar',
              icon: Icons.refresh,
              level: NexoraLevel.secondary,
              expand: true,
              compact: true,
              onPressed: _controller.refresh,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: NexoraButton(
              label: alerts.isEmpty ? 'Avisos' : 'Avisos ${alerts.length}',
              icon: Icons.notifications_active_outlined,
              level: _showAlerts ? NexoraLevel.secondary : NexoraLevel.tertiary,
              expand: true,
              compact: true,
              onPressed: () => setState(() => _showAlerts = !_showAlerts),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _CountdownCard(
        horizon: _horizon,
        secondsLeft: _controller.secondsLeftFor(_horizon),
        progress: _controller.progressFor(_horizon),
        opensAt: window.start,
        closesAt: window.end,
        nextCloses: window.nextCloses(3),
        synced: _controller.isClockSynced,
      ),
      const SizedBox(height: 12),
      if (outlook == null)
        _LoadingCard(error: _controller.error)
      else ...[
        _DecisionCard(outlook: outlook, advice: advice),
        const SizedBox(height: 12),
        _ExitCard(advice: advice),
        const SizedBox(height: 12),
        _AgentsCard(views: outlook.views, call: outlook.call),
        const SizedBox(height: 12),
      ],
      _OtherRoundsCard(
        controller: _controller,
        current: _horizon,
        onPick: (value) => setState(() => _horizon = value),
      ),
      const SizedBox(height: 12),
      _ScoreCard(controller: _controller, horizon: _horizon),
      if (_showAlerts) ...[
        const SizedBox(height: 12),
        _AlertsCard(alerts: alerts),
      ],
      const SizedBox(height: 16),
      Text(
        'Nexora lee datos públicos de Binance y da una probabilidad, no una '
        'certeza. Ninguna ronda está garantizada.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }
}

Color _callColor(PredictionCall call) => switch (call) {
      PredictionCall.up => NexoraTheme.up,
      PredictionCall.down => NexoraTheme.down,
      PredictionCall.wait => NexoraTheme.warn,
    };

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) =>
      Card(child: Padding(padding: padding, child: child));
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.style, this.align = TextAlign.start});

  final String text;
  final TextStyle? style;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: style,
      );
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.horizon,
    required this.secondsLeft,
    required this.progress,
    required this.opensAt,
    required this.closesAt,
    required this.nextCloses,
    required this.synced,
  });

  final PredictionHorizon horizon;
  final int secondsLeft;
  final double progress;
  final DateTime opensAt;
  final DateTime closesAt;
  final List<DateTime> nextCloses;
  final bool synced;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Line(
                  horizon.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                synced ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                size: 16,
                color: synced ? NexoraTheme.up : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              _Line(
                synced ? 'Reloj de Binance' : 'Sin reloj',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              horizon == PredictionHorizon.h1
                  ? Simple.duration(secondsLeft)
                  : Simple.countdown(secondsLeft),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Line(
                  'Abre ${Simple.clock(opensAt)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              _Line(
                'Cierra ${Simple.clockSeconds(closesAt)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Line(
            'Próximos cierres ${nextCloses.map(Simple.clock).join(' · ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          _Line(
            'El contador arranca solo en cada ronda.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.outlook, required this.advice});

  final PredictionOutlook outlook;
  final ExitAdvice advice;

  @override
  Widget build(BuildContext context) {
    final color = _callColor(outlook.call);
    final closeClock = Simple.clock(outlook.window.end);
    final sentence = switch (outlook.call) {
      PredictionCall.up => 'El mercado cierra arriba a las $closeClock.',
      PredictionCall.down => 'El mercado cierra abajo a las $closeClock.',
      PredictionCall.wait => 'El equipo no ve ventaja para las $closeClock.',
    };
    return _Panel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                switch (outlook.call) {
                  PredictionCall.up => Icons.trending_up,
                  PredictionCall.down => Icons.trending_down,
                  PredictionCall.wait => Icons.pause_circle_outline,
                },
                color: color,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Line(
                  outlook.call.label,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.05,
                  ),
                ),
              ),
              _Line(
                Simple.percentPoints(outlook.confidence),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Line(sentence, style: Theme.of(context).textTheme.bodyMedium),
          if (advice.lockedAt != null) ...[
            const SizedBox(height: 4),
            _Line(
              'Decide a las ${Simple.clockSeconds(advice.lockedAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NexoraTag('Acuerdo ${Simple.percent(outlook.agreement)}'),
              NexoraTag(
                outlook.isCalm ? 'Mercado tranquilo' : 'Mercado movido',
                tone: outlook.isCalm ? NexoraTheme.up : NexoraTheme.warn,
              ),
              NexoraTag('Ronda ${Simple.signedPercent(outlook.distancePercent)}'),
              NexoraTag('Precio ${Simple.price(outlook.price)}'),
            ],
          ),
          if (outlook.secondOpinion case final note?) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.smart_toy_outlined, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


class _ExitCard extends StatelessWidget {
  const _ExitCard({required this.advice});

  final ExitAdvice advice;

  @override
  Widget build(BuildContext context) {
    final color = switch (advice.level) {
      ExitLevel.calm => NexoraTheme.up,
      ExitLevel.watch => NexoraTheme.warn,
      ExitLevel.exit => NexoraTheme.down,
    };
    final icon = switch (advice.level) {
      ExitLevel.calm => Icons.verified_outlined,
      ExitLevel.watch => Icons.visibility_outlined,
      ExitLevel.exit => Icons.logout,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(NexoraTheme.radius + 2),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(
                  advice.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  advice.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (advice.isOpen) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      NexoraTag(
                        'Ahora ${Simple.percent(advice.currentProbability)}',
                        tone: color,
                      ),
                      const SizedBox(width: 8),
                      NexoraTag('Mejor ${Simple.percent(advice.peakProbability)}'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentsCard extends StatelessWidget {
  const _AgentsCard({required this.views, required this.call});

  final List<AgentView> views;
  final PredictionCall call;

  @override
  Widget build(BuildContext context) {
    final ordered = [...views]..sort((a, b) => b.weight.compareTo(a.weight));
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _Line(
                  'El equipo',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              _Line(
                '${views.length} agentes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          _Line(
            'Cada uno mira una cosa y vota todo el tiempo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final view in ordered) _AgentRow(view: view),
        ],
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.view});

  final AgentView view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = view.saysUp ? NexoraTheme.up : NexoraTheme.down;
    final quiet = view.relevance < .06;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: quiet ? scheme.outlineVariant : color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: _Line(
                        view.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (view.warning != null) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: view.warning!,
                        child: const Icon(
                          Icons.info_outline,
                          size: 15,
                          color: NexoraTheme.warn,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                _Line(
                  quiet ? 'Sin opinión fuerte ahora.' : view.note,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: _Line(
              quiet ? '--' : Simple.percent(view.probabilityUp),
              align: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: quiet ? scheme.onSurfaceVariant : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtherRoundsCard extends StatelessWidget {
  const _OtherRoundsCard({
    required this.controller,
    required this.current,
    required this.onPick,
  });

  final PredictionController controller;
  final PredictionHorizon current;
  final ValueChanged<PredictionHorizon> onPick;

  @override
  Widget build(BuildContext context) {
    final others = PredictionHorizon.values
        .where((horizon) => horizon != current)
        .toList(growable: false);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Line(
            'Las otras rondas',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          for (final horizon in others) ...[
            _OtherRoundRow(
              horizon: horizon,
              outlook: controller.outlookFor(horizon),
              secondsLeft: controller.secondsLeftFor(horizon),
              closesAt: controller.windowFor(horizon).end,
              advice: controller.adviceFor(horizon),
              onTap: () => onPick(horizon),
            ),
            if (horizon != others.last) const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}

class _OtherRoundRow extends StatelessWidget {
  const _OtherRoundRow({
    required this.horizon,
    required this.outlook,
    required this.secondsLeft,
    required this.closesAt,
    required this.advice,
    required this.onTap,
  });

  final PredictionHorizon horizon;
  final PredictionOutlook? outlook;
  final int secondsLeft;
  final DateTime closesAt;
  final ExitAdvice advice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final call = outlook?.call ?? PredictionCall.wait;
    final color = _callColor(call);
    return InkWell(
      borderRadius: BorderRadius.circular(NexoraTheme.radius - 4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Line(
                    horizon.tag,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  _Line(
                    'Cierra ${Simple.clock(closesAt)} · faltan '
                    '${Simple.duration(secondsLeft)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (advice.level == ExitLevel.exit) ...[
              const Icon(Icons.logout, size: 16, color: NexoraTheme.down),
              const SizedBox(width: 6),
            ],
            _Line(
              outlook == null
                  ? '--'
                  : '${call.label} ${Simple.percentPoints(outlook!.confidence)}',
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.controller, required this.horizon});

  final PredictionController controller;
  final PredictionHorizon horizon;

  @override
  Widget build(BuildContext context) {
    final score = controller.journal.scoreFor(horizon);
    final samples = controller.scoreboard.samplesOf(horizon);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _Line(
                  'Cómo va el equipo',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              _Line(
                score.calls == 0
                    ? 'Sin cierres aún'
                    : Simple.outOf(score.hits, score.calls),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Line(
            score.calls == 0
                ? 'Los aciertos aparecen al cerrar la primera ronda.'
                : 'Aciertos de la ronda de ${horizon.tag} desde que abres la app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          _Line(
            'Los agentes ya revisan $samples votos cerrados.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.alerts});

  final List<PredictionAlert> alerts;

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Line(
              'Avisos',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (alerts.isEmpty)
              _Line(
                'Aquí llegan las señales y las salidas.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              for (final alert in alerts.take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        switch (alert.kind) {
                          PredictionAlertKind.open => Icons.bolt,
                          PredictionAlertKind.flip => Icons.swap_horiz,
                          PredictionAlertKind.exit => Icons.logout,
                          PredictionAlertKind.result => Icons.flag_outlined,
                        },
                        size: 17,
                        color: alert.isUrgent
                            ? NexoraTheme.down
                            : _callColor(alert.call),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Line(
                              alert.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              alert.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Line(
                        Simple.clock(alert.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
          ],
        ),
      );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) => _Panel(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
        child: Column(
          children: [
            if (error == null)
              const CircularProgressIndicator()
            else
              const Icon(Icons.cloud_off_outlined, size: 30),
            const SizedBox(height: 14),
            Text(
              error ?? 'El equipo lee el mercado.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
}
