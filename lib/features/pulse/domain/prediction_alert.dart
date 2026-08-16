import 'exit_watch.dart';
import 'prediction_horizon.dart';
import 'prediction_outlook.dart';
import 'round_clock.dart';

/// Why the app pings you.
enum PredictionAlertKind { open, flip, exit, result }

extension PredictionAlertKindInfo on PredictionAlertKind {
  String get label => switch (this) {
        PredictionAlertKind.open => 'Señal',
        PredictionAlertKind.flip => 'Cambio',
        PredictionAlertKind.exit => 'Salida',
        PredictionAlertKind.result => 'Cierre',
      };
}

class PredictionAlert {
  const PredictionAlert({
    required this.id,
    required this.horizon,
    required this.kind,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.call,
  });

  final String id;
  final PredictionHorizon horizon;
  final PredictionAlertKind kind;

  /// One line, short enough for a button or a banner.
  final String title;
  final String message;
  final DateTime createdAt;
  final PredictionCall call;

  bool get isUrgent => kind == PredictionAlertKind.exit;
}

/// Builds alerts and keeps the last ones.
///
/// It only speaks when something changes: a new call, a change of side, a
/// warning to step out, and the result when the round closes.
class PredictionAlertCenter {
  PredictionAlertCenter({this.maxAlerts = 40});

  final int maxAlerts;
  final List<PredictionAlert> _alerts = <PredictionAlert>[];
  final Set<String> _sent = <String>{};

  /// Newest first.
  List<PredictionAlert> get alerts => List.unmodifiable(_alerts);

  List<PredictionAlert> forHorizon(PredictionHorizon horizon) =>
      _alerts.where((alert) => alert.horizon == horizon).toList(growable: false);

  void clear() {
    _alerts.clear();
    _sent.clear();
  }

  /// Reads one refresh and returns only the alerts born right now.
  List<PredictionAlert> ingest({
    required PredictionOutlook outlook,
    required ExitAdvice advice,
    required String closeClock,
  }) {
    final born = <PredictionAlert>[];
    final round = outlook.window.start.millisecondsSinceEpoch;
    final horizon = outlook.horizon;

    if (advice.isOpen) {
      final openKey = '${horizon.name}/$round/open/${advice.call.name}';
      if (_sent.add(openKey)) {
        born.add(
          PredictionAlert(
            id: openKey,
            horizon: horizon,
            kind: _sent.any((key) =>
                    key.startsWith('${horizon.name}/$round/open/') &&
                    key != openKey)
                ? PredictionAlertKind.flip
                : PredictionAlertKind.open,
            title: '${advice.call.sentence} · ${horizon.tag}',
            message:
                'Cierra a las $closeClock con ${(advice.currentProbability * 100).round()}% a favor.',
            createdAt: outlook.updatedAt,
            call: advice.call,
          ),
        );
      }
    }

    if (advice.level == ExitLevel.exit && advice.isOpen) {
      final exitKey = '${horizon.name}/$round/exit/${advice.call.name}';
      if (_sent.add(exitKey)) {
        born.add(
          PredictionAlert(
            id: exitKey,
            horizon: horizon,
            kind: PredictionAlertKind.exit,
            title: 'Sal ahora · ${horizon.tag}',
            message: advice.detail,
            createdAt: outlook.updatedAt,
            call: advice.call,
          ),
        );
      }
    }

    _store(born);
    return born;
  }

  /// Announces how the round ended.
  PredictionAlert? announceResult({
    required PredictionHorizon horizon,
    required RoundWindow window,
    required PredictionCall call,
    required bool closedUp,
    required double changePercent,
    required DateTime at,
    required String closeClock,
  }) {
    final key =
        '${horizon.name}/${window.start.millisecondsSinceEpoch}/result';
    if (!_sent.add(key)) return null;
    final moved = closedUp ? 'sube' : 'baja';
    final verdict = !call.isDirectional
        ? 'Sin apuesta abierta.'
        : (call == PredictionCall.up) == closedUp
            ? 'La predicción acierta.'
            : 'La predicción falla.';
    final alert = PredictionAlert(
      id: key,
      horizon: horizon,
      kind: PredictionAlertKind.result,
      title: 'Cierre $closeClock · ${horizon.tag}',
      message:
          'BTC $moved ${changePercent.abs().toStringAsFixed(2)}%. $verdict',
      createdAt: at,
      call: call,
    );
    _store([alert]);
    return alert;
  }

  void _store(List<PredictionAlert> born) {
    if (born.isEmpty) return;
    _alerts.insertAll(0, born);
    if (_alerts.length > maxAlerts) {
      _alerts.removeRange(maxAlerts, _alerts.length);
    }
  }
}
