import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/pulse/domain/btc_5m_logistic_model.dart';

void main() {
  const model = Btc5mLogisticModel();

  test('matches spreadsheet probability for reference row', () {
    const rows = <List<double>>[
      [63203.31, 63220.25, 63200.15, 63200.16, 2.14372693],
      [63200.16, 63229.63, 63197.07, 63228.36, 4.32240456],
      [63228.37, 63228.37, 63152.37, 63177.57, 7.16206998],
      [63177.57, 63211.59, 63167.25, 63195.46, 4.69621948],
      [63195.46, 63222.34, 63176.39, 63222.33, 3.64412427],
      [63222.33, 63239.65, 63198.45, 63223.69, 6.08566724],
      [63223.69, 63277.60, 63178.01, 63240.23, 16.25441594],
      [63242.76, 63295.03, 63198.94, 63235.24, 13.54029197],
      [63235.24, 63235.24, 63198.94, 63198.94, 7.685772],
      [63198.94, 63330.02, 63198.94, 63297.34, 27.16303405],
      [63297.34, 63319.46, 63278.81, 63319.46, 4.85408574],
      [63319.45, 63321.30, 63283.52, 63293.51, 3.62210826],
      [63293.51, 63310.72, 63242.64, 63242.64, 7.4259954],
    ];

    final start = DateTime.utc(2026, 7, 9);
    final candles = <Candle>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      candles.add(Candle(
        openTime: start.add(Duration(minutes: i * 5)),
        open: r[0],
        high: r[1],
        low: r[2],
        close: r[3],
        volume: r[4],
      ));
    }

    final result = model.analyze(candles);
    expect(result.isReady, isTrue);
    expect(result.probabilityUp, closeTo(0.5007145341271017, 1e-12));
  });

  test('returns neutral probability when history is insufficient', () {
    final result = model.analyze(const <Candle>[]);
    expect(result.isReady, isFalse);
    expect(result.probabilityUp, .5);
  });
}
