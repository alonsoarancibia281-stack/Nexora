import 'dart:math' as math;

import '../../market/domain/candle.dart';

/// Exact 7-feature logistic model transcribed from
/// Modelo_probabilidad_BTC_5min.xlsx.
///
/// The spreadsheet was trained on 5-minute BTC-USD candles. Nexora applies
/// the same feature definitions and standardized coefficients to completed
/// Binance BTCUSDT 5-minute candles. It is deliberately treated as one model
/// inside the ensemble because the workbook's held-out accuracy (50.90%) did
/// not beat its base-rate benchmark (52.18%).
class Btc5mLogisticModel {
  const Btc5mLogisticModel();

  static const double validationAccuracy = 0.5089959373186302;
  static const double validationBaseRateAccuracy = 0.5217643644805572;
  static const double validationBrier = 0.2496907810092144;

  Btc5mLogisticResult analyze(List<Candle> completed5mCandles) {
    if (completed5mCandles.length < 13) {
      return const Btc5mLogisticResult(
        probabilityUp: .5,
        logit: 0,
        isReady: false,
      );
    }

    final c = completed5mCandles;
    final n = c.length;
    final last = c[n - 1];
    final close = last.close;
    if (close <= 0 || c[n - 2].close <= 0 || c[n - 4].close <= 0 || c[n - 13].close <= 0) {
      return const Btc5mLogisticResult(probabilityUp: .5, logit: 0, isReady: false);
    }

    // Excel definitions:
    // ret1    = LN(close_t / close_t-1)
    // mom3    = LN(close_t / close_t-3)
    // mom12   = LN(close_t / close_t-12)
    // vol12   = STDEV.S(last 12 one-bar log returns)
    // volumeZ = (volume_t - mean(last 12 volumes)) / STDEV.S(last 12 volumes)
    // smaGap  = close_t / mean(last 12 closes) - 1
    // range   = (high_t - low_t) / close_t
    final ret1 = math.log(close / c[n - 2].close);
    final mom3 = math.log(close / c[n - 4].close);
    final mom12 = math.log(close / c[n - 13].close);

    final returns = <double>[];
    for (var i = n - 12; i < n; i++) {
      final prev = c[i - 1].close;
      final curr = c[i].close;
      if (prev <= 0 || curr <= 0) {
        return const Btc5mLogisticResult(probabilityUp: .5, logit: 0, isReady: false);
      }
      returns.add(math.log(curr / prev));
    }
    final vol12 = _sampleStd(returns);

    final last12 = c.sublist(n - 12);
    final volumes = last12.map((e) => e.volume).toList(growable: false);
    final volumeMean = _mean(volumes);
    final volumeStd = _sampleStd(volumes);
    final volumeZ = volumeStd <= 1e-12 ? 0.0 : (last.volume - volumeMean) / volumeStd;

    final closeMean = _mean(last12.map((e) => e.close).toList(growable: false));
    final smaGap = closeMean <= 0 ? 0.0 : close / closeMean - 1;
    final rangePct = (last.high - last.low) / close;

    final zRet = _z(ret1, 0.000003235557736987414, 0.0008817228416739969);
    final zMom3 = _z(mom3, 0.000008761199500714791, 0.001534927655365261);
    final zMom12 = _z(mom12, 0.00003795588700640758, 0.0030458431513786487);
    final zVol12 = _z(vol12, 0.0007640378186730847, 0.00044061844661711155);
    final zVolume = _z(volumeZ, -0.0004833667806042245, 1.0136813284785304);
    final zGap = _z(smaGap, 0.000017528498783244446, 0.0016541167995107928);
    final zRange = _z(rangePct, 0.0011394677686341235, 0.0008680542225013735);

    final logit = -0.027902451819610614 +
        zRet * -0.05087707963218398 +
        zMom3 * 0.03680428230712576 +
        zMom12 * -0.034354661465580756 +
        zVol12 * -0.06179132351404997 +
        zVolume * -0.01243638853409333 +
        zGap * -0.01946706615596481 +
        zRange * 0.05683303281512366;

    final probabilityUp = 1.0 / (1.0 + math.exp(-logit.clamp(-20.0, 20.0)));
    return Btc5mLogisticResult(
      probabilityUp: probabilityUp.clamp(.01, .99).toDouble(),
      logit: logit,
      isReady: true,
    );
  }

  double _z(double value, double mean, double std) =>
      std <= 0 ? 0.0 : (value - mean) / std;

  double _mean(List<double> values) =>
      values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;

  double _sampleStd(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = _mean(values);
    var sum = 0.0;
    for (final value in values) {
      final d = value - mean;
      sum += d * d;
    }
    return math.sqrt(sum / (values.length - 1));
  }
}

class Btc5mLogisticResult {
  const Btc5mLogisticResult({
    required this.probabilityUp,
    required this.logit,
    required this.isReady,
  });

  final double probabilityUp;
  final double logit;
  final bool isReady;

  double get confidence => math.max(probabilityUp, 1 - probabilityUp) * 100;
}
