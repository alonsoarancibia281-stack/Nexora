import 'dart:math' as math;

/// Branches of mathematics represented in the 50-mathematician council.
///
/// Each branch is staffed by five mathematicians. Every mathematician runs one
/// complex, self-contained mathematical operation over the live BTC series and
/// publishes a *theorem*: a normalized directional signal plus the confidence
/// its own derivation deserves. The 100 market analysts consume those theorems
/// (never the raw formulas) and vote afterwards.
enum MathBranch {
  stochasticCalculus,
  fractalGeometry,
  spectralAnalysis,
  informationTheory,
  bayesianInference,
  econometrics,
  chaosTheory,
  extremeValue,
  linearAlgebra,
  optimalControl,
}

extension MathBranchLabel on MathBranch {
  String get label {
    switch (this) {
      case MathBranch.stochasticCalculus:
        return 'Cálculo estocástico';
      case MathBranch.fractalGeometry:
        return 'Geometría fractal';
      case MathBranch.spectralAnalysis:
        return 'Análisis espectral';
      case MathBranch.informationTheory:
        return 'Teoría de la información';
      case MathBranch.bayesianInference:
        return 'Inferencia bayesiana';
      case MathBranch.econometrics:
        return 'Econometría';
      case MathBranch.chaosTheory:
        return 'Teoría del caos';
      case MathBranch.extremeValue:
        return 'Valores extremos';
      case MathBranch.linearAlgebra:
        return 'Álgebra lineal';
      case MathBranch.optimalControl:
        return 'Control óptimo';
    }
  }

  String get shortLabel {
    switch (this) {
      case MathBranch.stochasticCalculus:
        return 'Estocástico';
      case MathBranch.fractalGeometry:
        return 'Fractal';
      case MathBranch.spectralAnalysis:
        return 'Espectral';
      case MathBranch.informationTheory:
        return 'Información';
      case MathBranch.bayesianInference:
        return 'Bayes';
      case MathBranch.econometrics:
        return 'Econometría';
      case MathBranch.chaosTheory:
        return 'Caos';
      case MathBranch.extremeValue:
        return 'Extremos';
      case MathBranch.linearAlgebra:
        return 'Álgebra';
      case MathBranch.optimalControl:
        return 'Control';
    }
  }
}

/// Immutable market snapshot handed to the mathematicians.
class MathContext {
  MathContext({
    required List<double> closes,
    required List<double> highs,
    required List<double> lows,
    required List<double> volumes,
    required this.roundStartPrice,
    required this.secondsRemaining,
    required this.bookImbalance,
    required this.aggressorImbalance,
    required this.signedVolume,
    required this.spreadBps,
    required this.micropriceEdge,
    required this.instability,
  })  : closes = List<double>.unmodifiable(closes),
        highs = List<double>.unmodifiable(highs),
        lows = List<double>.unmodifiable(lows),
        volumes = List<double>.unmodifiable(volumes),
        logReturns = List<double>.unmodifiable(_logReturns(closes));

  final List<double> closes;
  final List<double> highs;
  final List<double> lows;
  final List<double> volumes;
  final List<double> logReturns;
  final double roundStartPrice;
  final int secondsRemaining;
  final double bookImbalance;
  final double aggressorImbalance;
  final double signedVolume;
  final double spreadBps;
  final double micropriceEdge;
  final double instability;

  bool get isReady => logReturns.length >= 32 && closes.length >= 33;

  double get price => closes.isEmpty ? 0 : closes.last;

  /// Remaining horizon expressed in one-minute units (never zero).
  late final double horizonMinutes =
      math.max(secondsRemaining.clamp(0, 300) / 60.0, .05);

  late final double sigma = math.max(_std(logReturns), 1e-9);

  late final double drift = _mean(logReturns);

  /// Signed log distance already travelled inside the current 5m round.
  late final double distanceLog = (roundStartPrice <= 0 || price <= 0)
      ? 0.0
      : math.log(price / roundStartPrice);

  late final double horizonSigma = sigma * math.sqrt(horizonMinutes);

  /// Normalized instability in [0,1].
  late final double turbulence = instability.clamp(0.0, 100.0) / 100.0;
}

/// One complex mathematical operation resolved by a single mathematician.
class MathTheorem {
  const MathTheorem({
    required this.id,
    required this.name,
    required this.branch,
    required this.formula,
    required this.value,
    required this.signal,
    required this.confidence,
  });

  /// 1..50
  final int id;
  final String name;
  final MathBranch branch;

  /// Human readable notation of the operation that produced [signal].
  final String formula;

  /// Raw magnitude produced by the operation (diagnostics only).
  final double value;

  /// Directional evidence in [-1,1]; positive means "market up".
  final double signal;

  /// Self-assessed reliability of the derivation in [0,1].
  final double confidence;

  double get weightedSignal => signal * confidence;
}

/// Aggregated output of the whole council, consumed by the 100 analysts.
class MathBriefing {
  MathBriefing({
    required this.theorems,
    required this.branchSignal,
    required this.branchConfidence,
    required this.consensusSignal,
    required this.dispersion,
    required this.probabilityUp,
    required this.isReady,
  });

  final List<MathTheorem> theorems;
  final Map<MathBranch, double> branchSignal;
  final Map<MathBranch, double> branchConfidence;

  /// Confidence-weighted mean of the 50 signals in [-1,1].
  final double consensusSignal;

  /// Standard deviation of the 50 signals in [0,1]; a proxy for how much the
  /// mathematicians contradict each other.
  final double dispersion;

  /// Probability of "up" implied by the council alone.
  final double probabilityUp;

  final bool isReady;

  static MathBriefing neutral() => MathBriefing(
        theorems: const <MathTheorem>[],
        branchSignal: {for (final b in MathBranch.values) b: 0.0},
        branchConfidence: {for (final b in MathBranch.values) b: 0.0},
        consensusSignal: 0,
        dispersion: 0,
        probabilityUp: .5,
        isReady: false,
      );

  double signalOf(MathBranch branch) => branchSignal[branch] ?? 0;

  double confidenceOf(MathBranch branch) => branchConfidence[branch] ?? 0;

  int get mathematicians => theorems.length;

  /// Fraction of the council pointing in the majority direction.
  double get internalAgreement {
    if (theorems.isEmpty) return 0;
    final up = theorems.where((t) => t.signal > 0).length;
    final down = theorems.where((t) => t.signal < 0).length;
    final decided = up + down;
    if (decided == 0) return 0;
    return math.max(up, down) / decided;
  }

  List<MathTheorem> theoremsOf(MathBranch branch) =>
      theorems.where((t) => t.branch == branch).toList(growable: false);

  /// Strongest operations by absolute weighted evidence.
  List<MathTheorem> topTheorems(int count) {
    final sorted = [...theorems]..sort((a, b) =>
        b.weightedSignal.abs().compareTo(a.weightedSignal.abs()));
    return sorted.take(count).toList(growable: false);
  }
}

/// Council of 50 mathematicians: ten branches, five specialists each.
class PulseMathCouncil {
  const PulseMathCouncil();

  static const int mathematicians = 50;

  MathBriefing deliberate(MathContext c) {
    if (!c.isReady) return MathBriefing.neutral();

    final builders = <MathTheorem Function(MathContext)>[
      _m01, _m02, _m03, _m04, _m05,
      _m06, _m07, _m08, _m09, _m10,
      _m11, _m12, _m13, _m14, _m15,
      _m16, _m17, _m18, _m19, _m20,
      _m21, _m22, _m23, _m24, _m25,
      _m26, _m27, _m28, _m29, _m30,
      _m31, _m32, _m33, _m34, _m35,
      _m36, _m37, _m38, _m39, _m40,
      _m41, _m42, _m43, _m44, _m45,
      _m46, _m47, _m48, _m49, _m50,
    ];

    final theorems = <MathTheorem>[];
    for (var i = 0; i < builders.length; i++) {
      MathTheorem theorem;
      try {
        theorem = builders[i](c);
      } catch (_) {
        theorem = _neutral(
          i + 1,
          'Operación ${i + 1}',
          MathBranch.values[i ~/ 5],
          'derivación no disponible',
        );
      }
      theorems.add(theorem);
    }

    final branchSignal = <MathBranch, double>{};
    final branchConfidence = <MathBranch, double>{};
    for (final branch in MathBranch.values) {
      final group = theorems.where((t) => t.branch == branch).toList();
      var weighted = 0.0;
      var weight = 0.0;
      var confidence = 0.0;
      for (final t in group) {
        final w = math.max(t.confidence, .05);
        weighted += t.signal * w;
        weight += w;
        confidence += t.confidence;
      }
      branchSignal[branch] = weight <= 0 ? 0.0 : _clamp1(weighted / weight);
      branchConfidence[branch] =
          group.isEmpty ? 0.0 : _unit(confidence / group.length);
    }

    var weighted = 0.0;
    var weight = 0.0;
    for (final t in theorems) {
      final w = math.max(t.confidence, .04);
      weighted += t.signal * w;
      weight += w;
    }
    final consensus = weight <= 0 ? 0.0 : _clamp1(weighted / weight);
    final dispersion = _unit(_std(theorems.map((t) => t.signal).toList()));

    // Log-odds conversion damped by internal contradiction: a council that
    // splits in half must not produce a confident probability.
    final coherence = (1 - dispersion * .75).clamp(.15, 1.0).toDouble();
    final p = _sigmoid(consensus * 2.35 * coherence);

    return MathBriefing(
      theorems: List<MathTheorem>.unmodifiable(theorems),
      branchSignal: Map<MathBranch, double>.unmodifiable(branchSignal),
      branchConfidence: Map<MathBranch, double>.unmodifiable(branchConfidence),
      consensusSignal: consensus,
      dispersion: dispersion,
      probabilityUp: p.clamp(.05, .95).toDouble(),
      isReady: true,
    );
  }

  // ===========================================================================
  // Branch 1 — Stochastic calculus
  // ===========================================================================

  MathTheorem _m01(MathContext c) {
    final lp = _logPrices(c.closes);
    if (lp.length < 14) {
      return _neutral(1, 'Reversión Ornstein-Uhlenbeck',
          MathBranch.stochasticCalculus, 'dX=θ(μ−X)dt+σdW');
    }
    final fit = _ols(lp.sublist(0, lp.length - 1), lp.sublist(1));
    final beta = fit.slope;
    final theta = (beta > 0 && beta < 1) ? -math.log(beta) : 0.0;
    final mu = (1 - beta).abs() < 1e-9
        ? _mean(lp)
        : fit.intercept / (1 - beta);
    final reach = 1 - math.exp(-theta * c.horizonMinutes);
    final gap = mu - lp.last;
    final signal = _clamp1(gap * reach / math.max(c.horizonSigma, 1e-9));
    final halfLife = theta <= 0 ? 0.0 : math.log(2) / theta;
    return _theorem(1, 'Reversión Ornstein-Uhlenbeck',
        MathBranch.stochasticCalculus, 'dX=θ(μ−X)dt+σdW · θ=−ln β₁',
        halfLife, signal, fit.r2 * (theta <= 0 ? .18 : 1.0));
  }

  MathTheorem _m02(MathContext c) {
    // Geometric Brownian motion: dS/S = μ dt + σ dW, evaluated on the
    // remaining horizon with the Itô convexity correction.
    final mu = c.drift;
    final tau = c.horizonMinutes;
    final expected = (mu - .5 * c.sigma * c.sigma) * tau;
    final z = (c.distanceLog + expected) / math.max(c.horizonSigma, 1e-12);
    final signal = _clamp1(z / 2.2);
    final n = c.logReturns.length;
    final tStat = (mu / (c.sigma / math.sqrt(n))).abs();
    return _theorem(2, 'Difusión geométrica browniana',
        MathBranch.stochasticCalculus, 'dS/S=μdt+σdW · Δ=(μ−σ²/2)τ',
        z, signal, _unit(tStat / 2.6));
  }

  MathTheorem _m03(MathContext c) {
    // Barndorff-Nielsen & Shephard jump test: realized variance versus
    // bipower variation isolates discontinuous moves.
    final r = _tail(c.logReturns, 48);
    if (r.length < 8) {
      return _neutral(3, 'Variación bipotencia', MathBranch.stochasticCalculus,
          'RV−BV');
    }
    var rv = 0.0;
    for (final v in r) {
      rv += v * v;
    }
    var bv = 0.0;
    for (var i = 1; i < r.length; i++) {
      bv += r[i].abs() * r[i - 1].abs();
    }
    bv *= math.pi / 2;
    final jumpShare = rv <= 0 ? 0.0 : ((rv - bv) / rv).clamp(0.0, 1.0);
    var signedJump = 0.0;
    var jumpMass = 0.0;
    final threshold = 2.8 * c.sigma;
    for (final v in r) {
      if (v.abs() > threshold) {
        signedJump += v;
        jumpMass += v.abs();
      }
    }
    final bias = jumpMass <= 0 ? 0.0 : signedJump / jumpMass;
    final signal = _clamp1(bias * jumpShare * 1.6);
    return _theorem(3, 'Variación bipotencia (saltos)',
        MathBranch.stochasticCalculus, 'RV−BV · BV=(π/2)Σ|rᵢ||rᵢ₋₁|',
        jumpShare, signal, _unit(jumpShare * .9 + .05));
  }

  MathTheorem _m04(MathContext c) {
    // Cox-Ingersoll-Ross style variance mean reversion on realized variance.
    final r = _tail(c.logReturns, 48);
    final variance = <double>[];
    for (var i = 4; i < r.length; i++) {
      final window = r.sublist(i - 4, i + 1);
      var s = 0.0;
      for (final v in window) {
        s += v * v;
      }
      variance.add(s / window.length);
    }
    if (variance.length < 8) {
      return _neutral(4, 'Reversión de varianza CIR',
          MathBranch.stochasticCalculus, 'dv=κ(θ−v)dt+ξ√v dW');
    }
    final fit = _ols(
      variance.sublist(0, variance.length - 1),
      variance.sublist(1),
    );
    final kappa = (fit.slope > 0 && fit.slope < 1) ? 1 - fit.slope : 0.0;
    final longRun = kappa <= 0 ? _mean(variance) : fit.intercept / kappa;
    final current = variance.last;
    final contraction = longRun <= 0
        ? 0.0
        : ((longRun - current) / longRun).clamp(-1.0, 1.0).toDouble();
    // Contracting volatility lets the prevailing drift dominate; expanding
    // volatility argues for reversion of the current excursion.
    final trend = _clamp1(c.drift / math.max(c.sigma, 1e-12) * 2.4);
    final signal = _clamp1(trend * contraction - c.distanceLog /
        math.max(c.horizonSigma, 1e-9) * .18 * (1 - contraction).abs());
    return _theorem(4, 'Reversión de varianza CIR',
        MathBranch.stochasticCalculus, 'dv=κ(θ−v)dt+ξ√v dW',
        kappa, signal, _unit(fit.r2 * .85 + .05));
  }

  MathTheorem _m05(MathContext c) {
    // Girsanov change of measure: order flow acts as the market price of risk
    // that tilts the drift under the trading measure.
    final lambda = (c.aggressorImbalance * .6 + c.bookImbalance * .4)
        .clamp(-1.0, 1.0);
    final adjustedDrift = c.drift + lambda * c.sigma * .35;
    final expected = adjustedDrift * c.horizonMinutes;
    final z = (c.distanceLog + expected) / math.max(c.horizonSigma, 1e-12);
    final spreadPenalty = (1 - (c.spreadBps.abs() / 6).clamp(0.0, .6));
    final signal = _clamp1(z / 2.0 * spreadPenalty);
    return _theorem(5, 'Cambio de medida de Girsanov',
        MathBranch.stochasticCalculus, 'dQ/dP=exp(−λW−½λ²t) · μᵠ=μ+λσ',
        lambda.toDouble(), signal, _unit(lambda.abs() * .7 + .15));
  }

  // ===========================================================================
  // Branch 2 — Fractal geometry
  // ===========================================================================

  MathTheorem _m06(MathContext c) {
    final r = _tail(c.logReturns, 64);
    final h = _hurstRs(r);
    final persistence = ((h - .5) * 2).clamp(-1.0, 1.0).toDouble();
    final trendZ = _clamp1(_mean(_tail(r, 12)) * math.sqrt(12) /
        math.max(c.sigma, 1e-12));
    // H>0.5 → persistent (follow), H<0.5 → antipersistent (fade).
    final signal = _clamp1(trendZ * persistence * 1.4);
    return _theorem(6, 'Exponente de Hurst (R/S)', MathBranch.fractalGeometry,
        'E[R/S]=c·nᴴ', h, signal, _unit(persistence.abs() * 1.2));
  }

  MathTheorem _m07(MathContext c) {
    final r = _tail(c.logReturns, 64);
    final alpha = _dfaExponent(r);
    final persistence = ((alpha - .5) * 2).clamp(-1.0, 1.0).toDouble();
    final trendZ = _clamp1(_mean(_tail(r, 16)) * 4 / math.max(c.sigma, 1e-12));
    final signal = _clamp1(trendZ * persistence * 1.3);
    return _theorem(7, 'Fluctuación sin tendencia (DFA)',
        MathBranch.fractalGeometry, 'F(n)∝n^α', alpha, signal,
        _unit(persistence.abs() * 1.1));
  }

  MathTheorem _m08(MathContext c) {
    final r = _tail(c.logReturns, 48);
    final d = _higuchiDimension(r);
    // D∈[1,2]; near 1 the curve is smooth/trending, near 2 it is noise.
    final smoothness = ((2 - d)).clamp(0.0, 1.0).toDouble();
    final trendZ = _clamp1(_mean(_tail(r, 10)) * math.sqrt(10) /
        math.max(c.sigma, 1e-12));
    final signal = _clamp1(trendZ * smoothness * 1.5);
    return _theorem(8, 'Dimensión fractal de Higuchi',
        MathBranch.fractalGeometry, 'L(k)∝k^(−D)', d, signal,
        _unit(smoothness));
  }

  MathTheorem _m09(MathContext c) {
    // Fractional differentiation keeps long memory while making the series
    // stationary (López de Prado weights).
    final lp = _logPrices(c.closes);
    if (lp.length < 24) {
      return _neutral(9, 'Diferenciación fraccionaria',
          MathBranch.fractalGeometry, '(1−B)^d X');
    }
    const d = .42;
    const width = 20;
    final weights = List<double>.filled(width, 0);
    weights[0] = 1;
    for (var k = 1; k < width; k++) {
      weights[k] = -weights[k - 1] * (d - k + 1) / k;
    }
    final series = <double>[];
    for (var i = width; i <= lp.length; i++) {
      var s = 0.0;
      for (var k = 0; k < width; k++) {
        s += weights[k] * lp[i - 1 - k];
      }
      series.add(s);
    }
    if (series.length < 6) {
      return _neutral(9, 'Diferenciación fraccionaria',
          MathBranch.fractalGeometry, '(1−B)^d X');
    }
    final mean = _mean(series);
    final sd = math.max(_std(series), 1e-12);
    final z = (series.last - mean) / sd;
    // Positive fractional excursions decay back toward the memory mean.
    final signal = _clamp1(-z / 2.4);
    return _theorem(9, 'Diferenciación fraccionaria',
        MathBranch.fractalGeometry, '(1−B)^d X · d=0.42', z, signal,
        _unit(z.abs() / 2.6));
  }

  MathTheorem _m10(MathContext c) {
    // Lo & MacKinlay variance ratio: VR>1 → trending self-similarity.
    final r = _tail(c.logReturns, 60);
    final vr = _varianceRatio(r, 5);
    final excess = (vr - 1).clamp(-1.0, 1.5).toDouble();
    final trendZ = _clamp1(_mean(_tail(r, 15)) * math.sqrt(15) /
        math.max(c.sigma, 1e-12));
    final signal = _clamp1(trendZ * excess * 1.2 -
        (excess < 0 ? trendZ * excess.abs() * .4 : 0));
    return _theorem(10, 'Cociente de varianzas Lo-MacKinlay',
        MathBranch.fractalGeometry, 'VR(q)=Var(rᵠ)/(q·Var(r))', vr, signal,
        _unit(excess.abs() * .9));
  }

  // ===========================================================================
  // Branch 3 — Spectral analysis
  // ===========================================================================

  MathTheorem _m11(MathContext c) {
    final r = _tail(c.logReturns, 48);
    final n = r.length;
    if (n < 16) {
      return _neutral(
          11, 'Ciclo dominante DFT', MathBranch.spectralAnalysis, 'X(k)=Σx e^{−2πikt/n}');
    }
    var bestPower = 0.0;
    var bestK = 0;
    var bestRe = 0.0;
    var bestIm = 0.0;
    var totalPower = 0.0;
    for (var k = 2; k <= n ~/ 2; k++) {
      var re = 0.0;
      var im = 0.0;
      for (var t = 0; t < n; t++) {
        final ang = 2 * math.pi * k * t / n;
        re += r[t] * math.cos(ang);
        im -= r[t] * math.sin(ang);
      }
      final power = re * re + im * im;
      totalPower += power;
      if (power > bestPower) {
        bestPower = power;
        bestK = k;
        bestRe = re;
        bestIm = im;
      }
    }
    if (bestK == 0 || totalPower <= 0) {
      return _neutral(
          11, 'Ciclo dominante DFT', MathBranch.spectralAnalysis, 'X(k)=Σx e^{−2πikt/n}');
    }
    final ang = 2 * math.pi * bestK * n / n;
    final next = (2 / n) * (bestRe * math.cos(ang) - bestIm * math.sin(ang));
    final strength = (bestPower / totalPower).clamp(0.0, 1.0).toDouble();
    final signal = _clamp1(next / math.max(c.sigma, 1e-12) * strength * 2.0);
    return _theorem(11, 'Ciclo dominante DFT', MathBranch.spectralAnalysis,
        'X(k)=Σxₜe^{−2πikt/n} · T=n/k', n / bestK, signal,
        _unit(strength * 2.2));
  }

  MathTheorem _m12(MathContext c) {
    // Hilbert transform quadrature (Ehlers FIR approximation).
    final r = _tail(c.logReturns, 24);
    if (r.length < 8) {
      return _neutral(12, 'Cuadratura de Hilbert',
          MathBranch.spectralAnalysis, 'H{x}(t)');
    }
    final n = r.length;
    final inPhase = r[n - 4];
    final quad = .0962 * r[n - 1] +
        .5769 * r[n - 3] -
        .5769 * r[n - 5] -
        .0962 * r[n - 7];
    final amplitude = math.sqrt(inPhase * inPhase + quad * quad);
    final phase = math.atan2(quad, inPhase);
    // A rising sine (phase in the ascending quadrant) projects upward.
    final projection = math.cos(phase);
    final signal = _clamp1(projection * (amplitude / math.max(c.sigma, 1e-12)));
    return _theorem(12, 'Cuadratura de Hilbert', MathBranch.spectralAnalysis,
        'φ=atan2(Q,I) · proj=cos φ', phase, signal,
        _unit(amplitude / math.max(c.sigma * 2.2, 1e-12)));
  }

  MathTheorem _m13(MathContext c) {
    final r = _tail(c.logReturns, 32);
    var approx = List<double>.from(r);
    var detailEnergy = 0.0;
    while (approx.length >= 2) {
      final nextApprox = <double>[];
      var levelEnergy = 0.0;
      for (var i = 0; i + 1 < approx.length; i += 2) {
        nextApprox.add((approx[i] + approx[i + 1]) / math.sqrt2);
        final d = (approx[i] - approx[i + 1]) / math.sqrt2;
        levelEnergy += d * d;
      }
      detailEnergy += levelEnergy;
      approx = nextApprox;
    }
    final approxEnergy =
        approx.fold<double>(0, (s, v) => s + v * v);
    final total = approxEnergy + detailEnergy;
    final trendRatio = total <= 0 ? 0.0 : approxEnergy / total;
    final z = approx.isEmpty ? 0.0 : approx.last / math.max(c.sigma, 1e-12);
    final signal = _clamp1(z / 2.0);
    return _theorem(13, 'Energía multirresolución de Haar',
        MathBranch.spectralAnalysis, 'W=Σ⟨x,ψ⟩ψ · E_a/(E_a+E_d)',
        trendRatio, signal, _unit(trendRatio * 1.5));
  }

  MathTheorem _m14(MathContext c) {
    final r = _tail(c.logReturns, 48);
    final powers = _periodogram(r);
    if (powers.isEmpty) {
      return _neutral(14, 'Planitud espectral de Wiener',
          MathBranch.spectralAnalysis, 'SFM=GM/AM');
    }
    var logSum = 0.0;
    var sum = 0.0;
    for (final p in powers) {
      logSum += math.log(math.max(p, 1e-18));
      sum += p;
    }
    final gm = math.exp(logSum / powers.length);
    final am = sum / powers.length;
    final flatness = am <= 0 ? 1.0 : (gm / am).clamp(0.0, 1.0).toDouble();
    final structure = 1 - flatness;
    final trendZ = _clamp1(c.drift * math.sqrt(r.length.toDouble()) /
        math.max(c.sigma, 1e-12));
    final signal = _clamp1(trendZ * structure * 1.8);
    return _theorem(14, 'Planitud espectral de Wiener',
        MathBranch.spectralAnalysis, 'SFM=GM(P)/AM(P)', flatness, signal,
        _unit(structure * 1.4));
  }

  MathTheorem _m15(MathContext c) {
    final p = _tail(c.closes, 16);
    if (p.length < 7) {
      return _neutral(15, 'Derivada Savitzky-Golay',
          MathBranch.spectralAnalysis, 'ĝ=Σcᵢyᵢ');
    }
    final w = p.sublist(p.length - 7);
    const first = <double>[-3, -2, -1, 0, 1, 2, 3];
    const second = <double>[5, 0, -3, -4, -3, 0, 5];
    var velocity = 0.0;
    var acceleration = 0.0;
    for (var i = 0; i < 7; i++) {
      velocity += first[i] * w[i];
      acceleration += second[i] * w[i];
    }
    velocity /= 28.0;
    acceleration /= 42.0;
    final scale = math.max(c.price * c.sigma, 1e-9);
    final signal = _clamp1((velocity * 1.0 + acceleration * 1.8) / scale);
    return _theorem(15, 'Derivada Savitzky-Golay',
        MathBranch.spectralAnalysis, "y'=Σcᵢyᵢ/28 · y''=Σdᵢyᵢ/42",
        velocity / scale, signal,
        _unit((velocity.abs() / scale) * .9));
  }

  // ===========================================================================
  // Branch 4 — Information theory
  // ===========================================================================

  MathTheorem _m16(MathContext c) {
    final r = _tail(c.logReturns, 60);
    final bins = _quantize(r, 7, c.sigma);
    final h = _entropy(bins, 7);
    final hMax = math.log(7);
    final predictability = hMax <= 0 ? 0.0 : (1 - h / hMax).clamp(0.0, 1.0);
    final z = _mean(_tail(r, 12)) * math.sqrt(12) / math.max(c.sigma, 1e-12);
    final signal = _clamp1(z / 2.0 * (.35 + predictability));
    return _theorem(16, 'Entropía de Shannon', MathBranch.informationTheory,
        'H=−Σp log p', h, signal, _unit(predictability * 1.6));
  }

  MathTheorem _m17(MathContext c) {
    final r = _tail(c.logReturns, 60);
    final pe = _permutationEntropy(r, 3);
    final order = (1 - pe).clamp(0.0, 1.0).toDouble();
    final z = _mean(_tail(r, 8)) * math.sqrt(8) / math.max(c.sigma, 1e-12);
    final signal = _clamp1(z / 1.9 * (.30 + order * 1.2));
    return _theorem(17, 'Entropía de permutación',
        MathBranch.informationTheory, 'PE=−Σp(π)log p(π)/log m!', pe, signal,
        _unit(order * 1.8));
  }

  MathTheorem _m18(MathContext c) {
    final r = _tail(c.logReturns, 48);
    final se = _sampleEntropy(r, 2, .22 * c.sigma);
    final regularity = (1 - se / 2.6).clamp(0.0, 1.0).toDouble();
    final z = _mean(_tail(r, 10)) * math.sqrt(10) / math.max(c.sigma, 1e-12);
    final signal = _clamp1(z / 2.1 * (.30 + regularity));
    return _theorem(18, 'Entropía muestral', MathBranch.informationTheory,
        'SampEn=−ln(A/B)', se, signal, _unit(regularity * 1.3));
  }

  MathTheorem _m19(MathContext c) {
    final r = _tail(c.logReturns, 60);
    if (r.length < 30) {
      return _neutral(19, 'Divergencia de Kullback-Leibler',
          MathBranch.informationTheory, 'D(P‖Q)=Σp log(p/q)');
    }
    final recent = r.sublist(r.length - 15);
    final baseline = r.sublist(0, r.length - 15);
    final pRecent = _histogram(_quantize(recent, 5, c.sigma), 5);
    final qBase = _histogram(_quantize(baseline, 5, c.sigma), 5);
    var kl = 0.0;
    for (var i = 0; i < 5; i++) {
      final p = (pRecent[i] + .5) / (recent.length + 2.5);
      final q = (qBase[i] + .5) / (baseline.length + 2.5);
      kl += p * math.log(p / q);
    }
    final shift = (_mean(recent) - _mean(baseline)) /
        math.max(c.sigma, 1e-12);
    final signal = _clamp1(shift * (kl.clamp(0.0, 1.2)) * 2.2);
    return _theorem(19, 'Divergencia de Kullback-Leibler',
        MathBranch.informationTheory, 'D(P‖Q)=Σp log(p/q)', kl, signal,
        _unit(kl / .55));
  }

  MathTheorem _m20(MathContext c) {
    final r = _tail(c.logReturns, 60);
    if (r.length < 12) {
      return _neutral(20, 'Información mutua de signos',
          MathBranch.informationTheory, 'I(X;Y)=ΣΣp log(p/pq)');
    }
    var nUpUp = 0, nUpDn = 0, nDnUp = 0, nDnDn = 0;
    for (var i = 1; i < r.length; i++) {
      final prev = r[i - 1] >= 0;
      final curr = r[i] >= 0;
      if (prev && curr) {
        nUpUp++;
      } else if (prev && !curr) {
        nUpDn++;
      } else if (!prev && curr) {
        nDnUp++;
      } else {
        nDnDn++;
      }
    }
    final total = (nUpUp + nUpDn + nDnUp + nDnDn).toDouble();
    if (total <= 0) {
      return _neutral(20, 'Información mutua de signos',
          MathBranch.informationTheory, 'I(X;Y)=ΣΣp log(p/pq)');
    }
    final joint = <double>[
      nUpUp / total,
      nUpDn / total,
      nDnUp / total,
      nDnDn / total,
    ];
    final px = <double>[(nUpUp + nUpDn) / total, (nDnUp + nDnDn) / total];
    final py = <double>[(nUpUp + nDnUp) / total, (nUpDn + nDnDn) / total];
    var mi = 0.0;
    final pairs = <List<int>>[
      [0, 0],
      [0, 1],
      [1, 0],
      [1, 1],
    ];
    for (var k = 0; k < 4; k++) {
      final p = joint[k];
      if (p <= 0) continue;
      final denom = px[pairs[k][0]] * py[pairs[k][1]];
      if (denom <= 0) continue;
      mi += p * math.log(p / denom);
    }
    final lastUp = r.last >= 0;
    final continuation = lastUp
        ? (nUpUp - nUpDn) / math.max(nUpUp + nUpDn, 1)
        : (nDnUp - nDnDn) / math.max(nDnUp + nDnDn, 1);
    final signal = _clamp1(continuation * (mi / .12).clamp(0.0, 1.0) * 1.5);
    return _theorem(20, 'Información mutua de signos',
        MathBranch.informationTheory, 'I(X;Y)=ΣΣp log(p/(p·q))', mi, signal,
        _unit(mi / .10));
  }

  // ===========================================================================
  // Branch 5 — Bayesian inference
  // ===========================================================================

  MathTheorem _m21(MathContext c) {
    final r = _tail(c.logReturns, 40);
    final k = r.where((v) => v > 0).length;
    final n = r.length;
    final alpha = k + .5;
    final beta = n - k + .5;
    final mean = alpha / (alpha + beta);
    final variance =
        alpha * beta / (math.pow(alpha + beta, 2) * (alpha + beta + 1));
    final sd = math.sqrt(math.max(variance, 1e-12));
    final z = (mean - .5) / math.max(sd, 1e-9);
    final signal = _clamp1(z / 2.4);
    return _theorem(21, 'Posterior Beta-Binomial',
        MathBranch.bayesianInference, 'p|k~Beta(k+½, n−k+½)', mean, signal,
        _unit(z.abs() / 2.6));
  }

  MathTheorem _m22(MathContext c) {
    final r = _tail(c.logReturns, 60);
    const lags = 3;
    if (r.length < lags + 12) {
      return _neutral(22, 'Regresión ridge bayesiana',
          MathBranch.bayesianInference, 'w=(XᵀX+λI)⁻¹Xᵀy');
    }
    final rows = <List<double>>[];
    final targets = <double>[];
    for (var i = lags; i < r.length; i++) {
      rows.add([for (var j = 1; j <= lags; j++) r[i - j]]);
      targets.add(r[i]);
    }
    final lambda = math.max(c.sigma * c.sigma * rows.length * .12, 1e-14);
    final gram = List<List<double>>.generate(
        lags, (_) => List<double>.filled(lags, 0));
    final rhs = List<double>.filled(lags, 0);
    for (var i = 0; i < rows.length; i++) {
      for (var a = 0; a < lags; a++) {
        rhs[a] += rows[i][a] * targets[i];
        for (var b = 0; b < lags; b++) {
          gram[a][b] += rows[i][a] * rows[i][b];
        }
      }
    }
    for (var a = 0; a < lags; a++) {
      gram[a][a] += lambda;
    }
    final w = _solveLinear(gram, rhs);
    if (w == null) {
      return _neutral(22, 'Regresión ridge bayesiana',
          MathBranch.bayesianInference, 'w=(XᵀX+λI)⁻¹Xᵀy');
    }
    var prediction = 0.0;
    for (var j = 0; j < lags; j++) {
      prediction += w[j] * r[r.length - 1 - j];
    }
    var ssr = 0.0;
    for (var i = 0; i < rows.length; i++) {
      var fitted = 0.0;
      for (var a = 0; a < lags; a++) {
        fitted += w[a] * rows[i][a];
      }
      final e = targets[i] - fitted;
      ssr += e * e;
    }
    final residualSigma = math.sqrt(ssr / math.max(rows.length - lags, 1));
    final z = prediction / math.max(residualSigma, 1e-12);
    final horizonScale = math.sqrt(math.min(c.horizonMinutes, 3.0));
    final signal = _clamp1(z * horizonScale / 1.6);
    return _theorem(22, 'Regresión ridge bayesiana',
        MathBranch.bayesianInference, 'w=(XᵀX+λI)⁻¹Xᵀy', prediction, signal,
        _unit(z.abs() / 1.9));
  }

  MathTheorem _m23(MathContext c) {
    final r = _tail(c.logReturns, 60);
    final n = r.length;
    if (n < 20) {
      return _neutral(23, 'Factor de Bayes de deriva',
          MathBranch.bayesianInference, 'BF=exp(ΔBIC/2)');
    }
    final mu = _mean(r);
    var ss0 = 0.0;
    var ss1 = 0.0;
    for (final v in r) {
      ss0 += v * v;
      final d = v - mu;
      ss1 += d * d;
    }
    final s0 = math.max(ss0 / n, 1e-18);
    final s1 = math.max(ss1 / n, 1e-18);
    final deltaBic = n * math.log(s0 / s1) - math.log(n.toDouble());
    final bayesFactor = math.exp((deltaBic / 2).clamp(-25.0, 25.0));
    final posterior = bayesFactor / (1 + bayesFactor);
    final tStat = mu / math.max(math.sqrt(s1 / n), 1e-15);
    final signal = _clamp1(_tanh(tStat / 1.8) * posterior);
    return _theorem(23, 'Factor de Bayes de deriva',
        MathBranch.bayesianInference, 'BF=exp(ΔBIC/2) · ΔBIC=n·ln(s₀/s₁)−ln n',
        bayesFactor, signal, _unit(posterior));
  }

  MathTheorem _m24(MathContext c) {
    // Two-state Kalman filter: local level + local slope.
    final lp = _logPrices(_tail(c.closes, 60));
    if (lp.length < 12) {
      return _neutral(24, 'Filtro de Kalman nivel-tendencia',
          MathBranch.bayesianInference, 'x̂=Fx+K(z−HFx)');
    }
    var level = lp.first;
    var slope = 0.0;
    var p00 = 1e-4, p01 = 0.0, p10 = 0.0, p11 = 1e-4;
    final q = math.max(c.sigma * c.sigma * .04, 1e-16);
    final rObs = math.max(c.sigma * c.sigma, 1e-16);
    for (var i = 1; i < lp.length; i++) {
      // Predict: level += slope
      final pl = level + slope;
      final ps = slope;
      final a00 = p00 + p01 + p10 + p11 + q;
      final a01 = p01 + p11;
      final a10 = p10 + p11;
      final a11 = p11 + q;
      // Update with observation of the level.
      final s = a00 + rObs;
      final k0 = a00 / s;
      final k1 = a10 / s;
      final innovation = lp[i] - pl;
      level = pl + k0 * innovation;
      slope = ps + k1 * innovation;
      p00 = a00 - k0 * a00;
      p01 = a01 - k0 * a01;
      p10 = a10 - k1 * a00;
      p11 = a11 - k1 * a01;
    }
    final projected = slope * c.horizonMinutes;
    final z = (c.distanceLog + projected) / math.max(c.horizonSigma, 1e-12);
    final signal = _clamp1(z / 2.1);
    return _theorem(24, 'Filtro de Kalman nivel-tendencia',
        MathBranch.bayesianInference, 'x̂ₜ=Fx̂ₜ₋₁+K(zₜ−HFx̂ₜ₋₁)', slope, signal,
        _unit((slope.abs() / math.max(c.sigma, 1e-12)) * 1.4));
  }

  MathTheorem _m25(MathContext c) {
    // Dirichlet-multinomial posterior over a 3-state Markov chain.
    final r = _tail(c.logReturns, 60);
    final band = .25 * c.sigma;
    int state(double v) => v > band ? 0 : (v < -band ? 2 : 1);
    final counts = List<List<double>>.generate(3, (_) => List<double>.filled(3, 1.0));
    for (var i = 1; i < r.length; i++) {
      counts[state(r[i - 1])][state(r[i])] += 1;
    }
    final current = state(r.last);
    final row = counts[current];
    final total = row[0] + row[1] + row[2];
    final pUp = row[0] / total;
    final pDown = row[2] / total;
    final edge = pUp - pDown;
    final concentration = (total - 3) / math.max(total, 1);
    final signal = _clamp1(edge * 2.2 * concentration);
    return _theorem(25, 'Cadena de Markov Dirichlet',
        MathBranch.bayesianInference, 'θ|n~Dir(α+n)', edge, signal,
        _unit(edge.abs() * 3.0 * concentration));
  }

  // ===========================================================================
  // Branch 6 — Econometrics
  // ===========================================================================

  MathTheorem _m26(MathContext c) {
    final r = _tail(c.logReturns, 60);
    final rho1 = _autocorr(r, 1);
    final rho2 = _autocorr(r, 2);
    final den = 1 - rho1 * rho1;
    if (den.abs() < 1e-9 || r.length < 6) {
      return _neutral(26, 'AR(2) Yule-Walker', MathBranch.econometrics,
          'φ=Γ⁻¹γ');
    }
    final phi1 = rho1 * (1 - rho2) / den;
    final phi2 = (rho2 - rho1 * rho1) / den;
    final forecast = phi1 * r[r.length - 1] + phi2 * r[r.length - 2];
    final z = forecast / math.max(c.sigma, 1e-12);
    final signal = _clamp1(z * math.sqrt(math.min(c.horizonMinutes, 3.0)) / 1.5);
    final strength = (rho1.abs() + rho2.abs()).clamp(0.0, 1.0);
    return _theorem(26, 'AR(2) Yule-Walker', MathBranch.econometrics,
        'φ₁=ρ₁(1−ρ₂)/(1−ρ₁²)', forecast, signal, _unit(strength * 2.4));
  }

  MathTheorem _m27(MathContext c) {
    // GARCH(1,1) variance forecast aggregated over the remaining horizon.
    final r = _tail(c.logReturns, 90);
    const alpha = .085;
    const beta = .895;
    final unconditional = math.max(_variance(r), 1e-18);
    final omega = unconditional * (1 - alpha - beta);
    var variance = unconditional;
    for (final v in r) {
      variance = omega + alpha * v * v + beta * variance;
    }
    final steps = math.max(c.horizonMinutes.ceil(), 1);
    var aggregate = 0.0;
    var forward = variance;
    for (var i = 0; i < steps; i++) {
      aggregate += forward;
      forward = omega + (alpha + beta) * forward;
    }
    final horizonSigma = math.sqrt(math.max(aggregate, 1e-18));
    final expected = c.drift * c.horizonMinutes;
    final z = (c.distanceLog + expected) / math.max(horizonSigma, 1e-12);
    final signal = _clamp1(z / 2.2);
    final volRatio = unconditional <= 0 ? 1.0 : variance / unconditional;
    return _theorem(27, 'Varianza GARCH(1,1)', MathBranch.econometrics,
        'σ²ₜ=ω+αε²ₜ₋₁+βσ²ₜ₋₁', volRatio, signal,
        _unit(1 / (1 + (volRatio - 1).abs() * 1.4) * .9));
  }

  MathTheorem _m28(MathContext c) {
    final p = _tail(c.closes, 34);
    final n = p.length;
    if (n < 10) {
      return _neutral(28, 'Prueba de tendencia Mann-Kendall',
          MathBranch.econometrics, 'S=ΣΣ sgn(xⱼ−xᵢ)');
    }
    var s = 0;
    for (var i = 0; i < n - 1; i++) {
      for (var j = i + 1; j < n; j++) {
        if (p[j] > p[i]) {
          s++;
        } else if (p[j] < p[i]) {
          s--;
        }
      }
    }
    final varS = n * (n - 1) * (2 * n + 5) / 18.0;
    final z = s == 0
        ? 0.0
        : (s > 0 ? s - 1 : s + 1) / math.sqrt(math.max(varS, 1e-9));
    final signal = _clamp1(z / 2.8);
    return _theorem(28, 'Prueba de tendencia Mann-Kendall',
        MathBranch.econometrics, 'Z=(S∓1)/√Var(S)', z.toDouble(), signal,
        _unit(z.abs() / 2.4));
  }

  MathTheorem _m29(MathContext c) {
    // Hodrick-Prescott decomposition: trend slope plus cyclical gap.
    final lp = _logPrices(_tail(c.closes, 48));
    if (lp.length < 12) {
      return _neutral(29, 'Filtro Hodrick-Prescott',
          MathBranch.econometrics, 'min Σ(y−τ)²+λΣ(Δ²τ)²');
    }
    final trend = _hpFilter(lp, 240);
    final n = trend.length;
    final slope = trend[n - 1] - trend[n - 2];
    final gap = lp.last - trend[n - 1];
    final cycleSigma = math.max(
      _std([for (var i = 0; i < n; i++) lp[i] - trend[i]]),
      1e-12,
    );
    final trendTerm = slope * c.horizonMinutes / math.max(c.horizonSigma, 1e-12);
    final gapTerm = -gap / cycleSigma * .45;
    final signal = _clamp1((trendTerm + gapTerm) / 2.0);
    return _theorem(29, 'Filtro Hodrick-Prescott', MathBranch.econometrics,
        'min Σ(y−τ)²+λΣ(τₜ₊₁−2τₜ+τₜ₋₁)²', slope, signal,
        _unit((slope.abs() / math.max(c.sigma, 1e-12)) * 1.2 + .1));
  }

  MathTheorem _m30(MathContext c) {
    final r = _tail(c.logReturns, 60);
    final n = r.length;
    if (n < 12) {
      return _neutral(30, 'Estadístico Ljung-Box', MathBranch.econometrics,
          'Q=n(n+2)Σρ²ₖ/(n−k)');
    }
    var q = 0.0;
    var forecast = 0.0;
    for (var k = 1; k <= 5; k++) {
      final rho = _autocorr(r, k);
      q += rho * rho / math.max(n - k, 1);
      forecast += rho * r[n - k];
    }
    q *= n * (n + 2);
    final significance = (q / 11.07).clamp(0.0, 2.0);
    final z = forecast / math.max(c.sigma, 1e-12);
    final signal = _clamp1(z * math.min(significance, 1.0) / 1.4);
    return _theorem(30, 'Estadístico Ljung-Box', MathBranch.econometrics,
        'Q=n(n+2)Σρ²ₖ/(n−k)', q, signal, _unit(significance * .7));
  }

  // ===========================================================================
  // Branch 7 — Chaos theory
  // ===========================================================================

  MathTheorem _m31(MathContext c) {
    final r = _tail(c.logReturns, 48);
    final lambda = _lyapunov(r, 3, 5);
    final predictability = math.exp(-lambda.abs() * c.horizonMinutes)
        .clamp(0.0, 1.0)
        .toDouble();
    final z = _mean(_tail(r, 10)) * math.sqrt(10) / math.max(c.sigma, 1e-12);
    final signal = _clamp1(z / 2.0 * predictability);
    return _theorem(31, 'Exponente de Lyapunov (Rosenstein)',
        MathBranch.chaosTheory, 'λ=lim (1/t)ln(d(t)/d₀)', lambda, signal,
        _unit(predictability * .95));
  }

  MathTheorem _m32(MathContext c) {
    final r = _tail(c.logReturns, 44);
    final det = _recurrenceDeterminism(r, 3, .30 * c.sigma);
    final lastSign = r.isEmpty ? 0.0 : (r.last >= 0 ? 1.0 : -1.0);
    final block = _mean(_tail(r, 4)) / math.max(c.sigma, 1e-12);
    final signal = _clamp1((block * .6 + lastSign * .4) * det * 1.6);
    return _theorem(32, 'Determinismo de recurrencia (RQA)',
        MathBranch.chaosTheory, 'DET=Σ l·P(l)/Σ R', det, signal,
        _unit(det * 1.3));
  }

  MathTheorem _m33(MathContext c) {
    final r = _tail(c.logReturns, 44);
    final d2 = _correlationDimension(r, 3, c.sigma);
    // High correlation dimension ⇒ stochastic ⇒ fade excursions.
    final stochasticity = (d2 / 3.0).clamp(0.0, 1.0).toDouble();
    final excursion = c.distanceLog / math.max(c.horizonSigma, 1e-12);
    final drift = c.drift * math.sqrt(r.length.toDouble()) /
        math.max(c.sigma, 1e-12);
    final signal = _clamp1(
        drift * (1 - stochasticity) * 1.4 - excursion * stochasticity * .35);
    return _theorem(33, 'Dimensión de correlación (Grassberger-Procaccia)',
        MathBranch.chaosTheory, 'C(r)∝r^{D₂}', d2, signal,
        _unit((1 - stochasticity) * .9 + .1));
  }

  MathTheorem _m34(MathContext c) {
    final r = _tail(c.logReturns, 48);
    final k = _zeroOneChaosTest(r);
    final regularity = (1 - k).clamp(0.0, 1.0).toDouble();
    final z = _mean(_tail(r, 12)) * math.sqrt(12) / math.max(c.sigma, 1e-12);
    final signal = _clamp1(z / 2.0 * (.25 + regularity));
    return _theorem(34, 'Prueba 0-1 de caos', MathBranch.chaosTheory,
        'K=corr(n, M(n))', k, signal, _unit(regularity * 1.1));
  }

  MathTheorem _m35(MathContext c) {
    // Nearest-neighbour analog forecast in reconstructed phase space.
    final r = _tail(c.logReturns, 60);
    const dim = 3;
    if (r.length < dim + 12) {
      return _neutral(35, 'Pronóstico por análogos',
          MathBranch.chaosTheory, 'x̂ₜ₊₁=Σwᵢxₙᵢ₊₁');
    }
    final target = r.sublist(r.length - dim);
    final neighbours = <List<double>>[];
    for (var i = 0; i + dim < r.length - 1; i++) {
      final window = r.sublist(i, i + dim);
      neighbours.add([_dist(window, target), r[i + dim]]);
    }
    neighbours.sort((a, b) => a[0].compareTo(b[0]));
    final k = math.min(5, neighbours.length);
    var weighted = 0.0;
    var weight = 0.0;
    for (var i = 0; i < k; i++) {
      final w = 1 / (neighbours[i][0] + 1e-9);
      weighted += neighbours[i][1] * w;
      weight += w;
    }
    final forecast = weight <= 0 ? 0.0 : weighted / weight;
    final z = forecast / math.max(c.sigma, 1e-12);
    final tightness = neighbours.isEmpty
        ? 0.0
        : (1 - (neighbours[0][0] / math.max(c.sigma * 2.5, 1e-12)))
            .clamp(0.0, 1.0)
            .toDouble();
    final signal = _clamp1(z * 1.3 * (.4 + tightness * .6));
    return _theorem(35, 'Pronóstico por análogos', MathBranch.chaosTheory,
        'x̂ₜ₊₁=Σwᵢxₙᵢ₊₁ · wᵢ=1/dᵢ', forecast, signal,
        _unit(tightness * .8 + z.abs() * .2));
  }

  // ===========================================================================
  // Branch 8 — Extreme value theory
  // ===========================================================================

  MathTheorem _m36(MathContext c) {
    final r = _tail(c.logReturns, 90);
    final ups = r.where((v) => v > 0).map((v) => v).toList()..sort();
    final downs = r.where((v) => v < 0).map((v) => -v).toList()..sort();
    final xiUp = _hillEstimator(ups);
    final xiDown = _hillEstimator(downs);
    final total = xiUp + xiDown;
    // A heavier upper tail means upside shocks dominate.
    final asymmetry = total <= 0 ? 0.0 : (xiUp - xiDown) / total;
    final signal = _clamp1(asymmetry * 1.8);
    return _theorem(36, 'Índice de cola de Hill', MathBranch.extremeValue,
        'ξ̂=(1/k)Σ ln(X₍ᵢ₎/X₍ₖ₎)', asymmetry, signal,
        _unit(asymmetry.abs() * 2.2));
  }

  MathTheorem _m37(MathContext c) {
    // Gumbel block maxima of absolute moves versus the distance still needed.
    final r = _tail(c.logReturns, 90);
    final maxima = <double>[];
    for (var i = 0; i + 5 <= r.length; i += 5) {
      var m = 0.0;
      for (var j = i; j < i + 5; j++) {
        m = math.max(m, r[j].abs());
      }
      maxima.add(m);
    }
    if (maxima.length < 4) {
      return _neutral(37, 'Máximos por bloques de Gumbel',
          MathBranch.extremeValue, 'F(x)=exp(−e^{−(x−μ)/β})');
    }
    final beta = math.max(_std(maxima) * math.sqrt(6) / math.pi, 1e-12);
    final mu = _mean(maxima) - .5772 * beta;
    final needed = c.distanceLog.abs();
    final scaled = needed / math.max(math.sqrt(c.horizonMinutes), .2);
    final pExceed =
        1 - math.exp(-math.exp(-((scaled - mu) / beta).clamp(-30.0, 30.0)));
    // If a reversal of the current excursion is unlikely, the excursion holds.
    final hold = (1 - pExceed).clamp(0.0, 1.0).toDouble();
    final direction = c.distanceLog >= 0 ? 1.0 : -1.0;
    final signal = _clamp1(direction * hold * 1.15);
    return _theorem(37, 'Máximos por bloques de Gumbel',
        MathBranch.extremeValue, 'F(x)=exp(−e^{−(x−μ)/β})', pExceed, signal,
        _unit(hold * .85));
  }

  MathTheorem _m38(MathContext c) {
    final r = _tail(c.logReturns, 90);
    final kurt = _excessKurtosis(r);
    final nu = kurt > .3 ? (4 + 6 / kurt).clamp(2.6, 30.0) : 30.0;
    final expected = c.drift * c.horizonMinutes;
    final x = (c.distanceLog + expected) / math.max(c.horizonSigma, 1e-12);
    final p = _studentTCdf(x, nu.toDouble());
    final signal = _clamp1((p - .5) * 2.2);
    return _theorem(38, 'Cola Student-t', MathBranch.extremeValue,
        'ν=4+6/κ · P(T<z)', nu.toDouble(), signal,
        _unit((p - .5).abs() * 2.4));
  }

  MathTheorem _m39(MathContext c) {
    final r = _tail(c.logReturns, 90);
    final sorted = [...r]..sort();
    final k = math.max(3, (sorted.length * .12).round());
    final worst = sorted.take(k).toList();
    final best = sorted.reversed.take(k).toList();
    final cvarDown = _mean(worst).abs();
    final cvarUp = _mean(best).abs();
    final total = cvarUp + cvarDown;
    final asymmetry = total <= 0 ? 0.0 : (cvarUp - cvarDown) / total;
    final flowTilt = c.aggressorImbalance * .35;
    final signal = _clamp1((asymmetry * 1.9 + flowTilt));
    return _theorem(39, 'Asimetría de déficit esperado (CVaR)',
        MathBranch.extremeValue, 'ES_α=E[X|X≤q_α]', asymmetry, signal,
        _unit(asymmetry.abs() * 2.4));
  }

  MathTheorem _m40(MathContext c) {
    final r = _tail(c.logReturns, 90);
    final skew = _skewness(r);
    final kurt = _excessKurtosis(r);
    final expected = c.drift * c.horizonMinutes;
    final z = (c.distanceLog + expected) / math.max(c.horizonSigma, 1e-12);
    final zc = z +
        (z * z - 1) * skew / 6 +
        (z * z * z - 3 * z) * kurt / 24 -
        (2 * z * z * z - 5 * z) * skew * skew / 36;
    final p = _normalCdf(zc.clamp(-6.0, 6.0));
    final signal = _clamp1((p - .5) * 2.2);
    return _theorem(40, 'Expansión de Cornish-Fisher',
        MathBranch.extremeValue,
        'z_cf=z+(z²−1)S/6+(z³−3z)K/24−(2z³−5z)S²/36', zc, signal,
        _unit((p - .5).abs() * 2.2));
  }

  // ===========================================================================
  // Branch 9 — Linear algebra
  // ===========================================================================

  MathTheorem _m41(MathContext c) {
    const dim = 5;
    final r = _tail(c.logReturns, 60);
    final vectors = _embed(r, dim);
    if (vectors.length < dim + 4) {
      return _neutral(41, 'Componente principal (PCA)',
          MathBranch.linearAlgebra, 'Σv=λv');
    }
    final cov = _covarianceMatrix(vectors);
    final v = _principalEigenvector(cov);
    var sum = 0.0;
    for (final x in v) {
      sum += x;
    }
    final oriented = sum < 0 ? v.map((x) => -x).toList() : v;
    var projection = 0.0;
    final last = vectors.last;
    for (var i = 0; i < dim; i++) {
      projection += oriented[i] * last[i];
    }
    var eigen = 0.0;
    for (var i = 0; i < dim; i++) {
      var s = 0.0;
      for (var j = 0; j < dim; j++) {
        s += cov[i][j] * oriented[j];
      }
      eigen += oriented[i] * s;
    }
    var trace = 0.0;
    for (var i = 0; i < dim; i++) {
      trace += cov[i][i];
    }
    final explained = trace <= 0 ? 0.0 : (eigen / trace).clamp(0.0, 1.0);
    final z = projection / math.max(c.sigma * math.sqrt(dim.toDouble()), 1e-12);
    final signal = _clamp1(z * explained * 1.7);
    return _theorem(41, 'Componente principal (PCA)',
        MathBranch.linearAlgebra, 'Σv=λv · proj=vᵀx', explained, signal,
        _unit(explained * 1.2));
  }

  MathTheorem _m42(MathContext c) {
    // Singular spectrum analysis: rank-1 reconstruction of the trend.
    const window = 8;
    final r = _tail(c.logReturns, 56);
    final vectors = _embed(r, window);
    if (vectors.length < window + 3) {
      return _neutral(42, 'Análisis espectral singular (SSA)',
          MathBranch.linearAlgebra, 'X=UΣVᵀ');
    }
    final cov = _covarianceMatrix(vectors);
    final u = _principalEigenvector(cov);
    final reconstructed = List<double>.filled(r.length, 0);
    final counts = List<double>.filled(r.length, 0);
    for (var i = 0; i < vectors.length; i++) {
      var score = 0.0;
      for (var j = 0; j < window; j++) {
        score += u[j] * vectors[i][j];
      }
      for (var j = 0; j < window; j++) {
        reconstructed[i + j] += score * u[j];
        counts[i + j] += 1;
      }
    }
    for (var i = 0; i < reconstructed.length; i++) {
      if (counts[i] > 0) reconstructed[i] /= counts[i];
    }
    final tailTrend = _tail(reconstructed, 6);
    final slope = _ols(
      [for (var i = 0; i < tailTrend.length; i++) i.toDouble()],
      tailTrend,
    );
    final projected = _mean(tailTrend) + slope.slope * c.horizonMinutes;
    final z = projected * math.sqrt(math.max(c.horizonMinutes, .1)) /
        math.max(c.sigma, 1e-12);
    final signal = _clamp1(z * 1.5);
    return _theorem(42, 'Análisis espectral singular (SSA)',
        MathBranch.linearAlgebra, 'X=UΣVᵀ · X̂₁=σ₁u₁v₁ᵀ', slope.slope, signal,
        _unit(slope.r2 * .9 + .05));
  }

  MathTheorem _m43(MathContext c) {
    final r = _tail(c.logReturns, 72);
    final coefficients = _levinsonDurbin(r, 4);
    if (coefficients.isEmpty) {
      return _neutral(43, 'AR(4) Levinson-Durbin', MathBranch.linearAlgebra,
          'Rφ=r · recursión de Levinson');
    }
    var forecast = 0.0;
    for (var i = 0; i < coefficients.length; i++) {
      final idx = r.length - 1 - i;
      if (idx < 0) break;
      forecast += coefficients[i] * r[idx];
    }
    final z = forecast / math.max(c.sigma, 1e-12);
    var energy = 0.0;
    for (final v in coefficients) {
      energy += v.abs();
    }
    final signal = _clamp1(z * math.sqrt(math.min(c.horizonMinutes, 3.0)) / 1.5);
    return _theorem(43, 'AR(4) Levinson-Durbin', MathBranch.linearAlgebra,
        'Rφ=r · φₖ recursivo', forecast, signal,
        _unit(energy.clamp(0.0, 1.0) * 1.6));
  }

  MathTheorem _m44(MathContext c) {
    // Companion-matrix spectral radius: is the fitted AR system stable?
    final r = _tail(c.logReturns, 72);
    final phi = _levinsonDurbin(r, 4);
    if (phi.isEmpty) {
      return _neutral(44, 'Radio espectral de la matriz compañera',
          MathBranch.linearAlgebra, 'ρ(A)=max|λᵢ|');
    }
    final p = phi.length;
    final companion =
        List<List<double>>.generate(p, (_) => List<double>.filled(p, 0));
    for (var j = 0; j < p; j++) {
      companion[0][j] = phi[j];
    }
    for (var i = 1; i < p; i++) {
      companion[i][i - 1] = 1;
    }
    var v = List<double>.filled(p, 1 / math.sqrt(p));
    var radius = 0.0;
    for (var it = 0; it < 40; it++) {
      final w = List<double>.filled(p, 0);
      for (var i = 0; i < p; i++) {
        var s = 0.0;
        for (var j = 0; j < p; j++) {
          s += companion[i][j] * v[j];
        }
        w[i] = s;
      }
      var norm = 0.0;
      for (final x in w) {
        norm += x * x;
      }
      norm = math.sqrt(norm);
      if (norm < 1e-15) break;
      radius = norm;
      for (var i = 0; i < p; i++) {
        v[i] = w[i] / norm;
      }
    }
    var forecast = 0.0;
    for (var i = 0; i < p; i++) {
      final idx = r.length - 1 - i;
      if (idx < 0) break;
      forecast += phi[i] * r[idx];
    }
    final stability = (1 - (radius - .55).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    final z = forecast / math.max(c.sigma, 1e-12);
    final signal = _clamp1(z * stability * 1.4);
    return _theorem(44, 'Radio espectral de la matriz compañera',
        MathBranch.linearAlgebra, 'ρ(A)=max|λᵢ| · A compañera de φ', radius,
        signal, _unit(stability * .85));
  }

  MathTheorem _m45(MathContext c) {
    final lp = _logPrices(_tail(c.closes, 14));
    if (lp.length < 8) {
      return _neutral(45, 'Extrapolación cuadrática',
          MathBranch.linearAlgebra, 'y=a+bt+ct²');
    }
    final n = lp.length;
    final x = [for (var i = 0; i < n; i++) i.toDouble()];
    final gram = List<List<double>>.generate(3, (_) => List<double>.filled(3, 0));
    final rhs = List<double>.filled(3, 0);
    for (var i = 0; i < n; i++) {
      final basis = <double>[1, x[i], x[i] * x[i]];
      for (var a = 0; a < 3; a++) {
        rhs[a] += basis[a] * lp[i];
        for (var b = 0; b < 3; b++) {
          gram[a][b] += basis[a] * basis[b];
        }
      }
    }
    final w = _solveLinear(gram, rhs);
    if (w == null) {
      return _neutral(45, 'Extrapolación cuadrática',
          MathBranch.linearAlgebra, 'y=a+bt+ct²');
    }
    final future = (n - 1) + c.horizonMinutes;
    final projected = w[0] + w[1] * future + w[2] * future * future;
    var ssTot = 0.0;
    var ssRes = 0.0;
    final mean = _mean(lp);
    for (var i = 0; i < n; i++) {
      final fitted = w[0] + w[1] * x[i] + w[2] * x[i] * x[i];
      ssRes += math.pow(lp[i] - fitted, 2).toDouble();
      ssTot += math.pow(lp[i] - mean, 2).toDouble();
    }
    final r2 = ssTot <= 0 ? 0.0 : (1 - ssRes / ssTot).clamp(0.0, 1.0);
    final z = (projected - lp.last) / math.max(c.horizonSigma, 1e-12);
    final signal = _clamp1(z / 2.0 * r2);
    return _theorem(45, 'Extrapolación cuadrática',
        MathBranch.linearAlgebra, 'y=a+bt+ct² · mínimos cuadrados', w[2],
        signal, _unit(r2 * .95));
  }

  // ===========================================================================
  // Branch 10 — Optimal control & decision theory
  // ===========================================================================

  MathTheorem _m46(MathContext c) {
    final expected = c.drift * c.horizonMinutes;
    final z = (c.distanceLog + expected) / math.max(c.horizonSigma, 1e-12);
    final p = _normalCdf(z.clamp(-6.0, 6.0));
    final kelly = (2 * p - 1).clamp(-1.0, 1.0).toDouble();
    // Fractional Kelly (half) is the standard robustness discount.
    final signal = _clamp1(kelly * .5 * (1 - c.turbulence * .5) * 2.0);
    return _theorem(46, 'Criterio de Kelly', MathBranch.optimalControl,
        'f*=p−q=2p−1', kelly, signal, _unit(kelly.abs() * 1.3));
  }

  MathTheorem _m47(MathContext c) {
    // Almgren-Chriss style: drift versus risk aversion and impact costs.
    final alpha = c.drift * c.horizonMinutes +
        (c.bookImbalance * .5 + c.micropriceEdge / 10) * c.sigma * .4;
    final riskAversion = .8 + c.turbulence * 1.8;
    final impact = 1 + (c.spreadBps.abs() / 4).clamp(0.0, 1.5);
    final trajectory =
        alpha / (riskAversion * math.max(c.horizonSigma, 1e-12) * impact);
    final signal = _clamp1(trajectory * 1.6);
    return _theorem(47, 'Trayectoria óptima Almgren-Chriss',
        MathBranch.optimalControl, 'x*=argmin E[C]+λVar[C]', trajectory,
        signal, _unit((1 / impact) * (1 - c.turbulence * .4)));
  }

  MathTheorem _m48(MathContext c) {
    // Exact binomial dynamic program over the remaining one-minute steps.
    final steps = math.max(c.horizonMinutes.ceil(), 1).clamp(1, 6).toInt();
    final q = _normalCdf((c.drift / math.max(c.sigma, 1e-12)).clamp(-4.0, 4.0));
    final d = c.distanceLog;
    var probabilityUp = 0.0;
    for (var k = 0; k <= steps; k++) {
      final ending = d + (2 * k - steps) * c.sigma;
      if (ending > 0) {
        probabilityUp += _binomial(steps, k) *
            math.pow(q, k).toDouble() *
            math.pow(1 - q, steps - k).toDouble();
      }
    }
    final signal = _clamp1((probabilityUp - .5) * 2.2);
    return _theorem(48, 'Programación dinámica de Bellman',
        MathBranch.optimalControl, 'V(s)=maxₐ E[r+γV(s′)]', probabilityUp,
        signal, _unit((probabilityUp - .5).abs() * 2.4));
  }

  MathTheorem _m49(MathContext c) {
    // Reflection principle: probability of touching the round-open level again
    // before expiry.
    final d = c.distanceLog;
    final mu = c.drift;
    final sigma = math.max(c.sigma, 1e-12);
    final tau = c.horizonMinutes;
    final s = sigma * math.sqrt(tau);
    if (d.abs() < 1e-12 || s <= 1e-12) {
      return _theorem(49, 'Principio de reflexión (barrera)',
          MathBranch.optimalControl, 'P(τ_b≤T)=Φ(·)+e^{−2μb/σ²}Φ(·)', 0, 0,
          .05);
    }
    final directedMu = d > 0 ? mu : -mu;
    final b = d.abs();
    final term1 = _normalCdf((-b - directedMu * tau) / s);
    final exponent = (-2 * directedMu * b / (sigma * sigma)).clamp(-30.0, 30.0);
    final term2 = math.exp(exponent) * _normalCdf((-b + directedMu * tau) / s);
    final touch = (term1 + term2).clamp(0.0, 1.0).toDouble();
    final direction = d > 0 ? 1.0 : -1.0;
    final signal = _clamp1(direction * (1 - touch) * 1.4);
    return _theorem(49, 'Principio de reflexión (barrera)',
        MathBranch.optimalControl, 'P(τ_b≤T)=Φ(·)+e^{−2μb/σ²}Φ(·)', touch,
        signal, _unit((1 - touch) * .9));
  }

  MathTheorem _m50(MathContext c) {
    // Entropy-regularized softmax policy over the binary up/down decision.
    final expected = c.drift * c.horizonMinutes;
    final utilityUp =
        (c.distanceLog + expected) / math.max(c.horizonSigma, 1e-12);
    final temperature = .55 + c.turbulence * 1.35;
    final a = (utilityUp / temperature).clamp(-25.0, 25.0);
    final b = (-utilityUp / temperature).clamp(-25.0, 25.0);
    final expA = math.exp(a);
    final expB = math.exp(b);
    final policyUp = expA / (expA + expB);
    final value = temperature * math.log(expA + expB);
    final signal = _clamp1((policyUp - .5) * 2.1);
    return _theorem(50, 'Política softmax con entropía',
        MathBranch.optimalControl, 'π(a)∝e^{Q(a)/τ} · V=τ·logΣe^{Q/τ}', value,
        signal, _unit((policyUp - .5).abs() * 2.3));
  }

  // ===========================================================================

  MathTheorem _theorem(
    int id,
    String name,
    MathBranch branch,
    String formula,
    double value,
    double signal,
    double confidence,
  ) =>
      MathTheorem(
        id: id,
        name: name,
        branch: branch,
        formula: formula,
        value: _finite(value),
        signal: _clamp1(signal),
        confidence: _unit(confidence),
      );

  MathTheorem _neutral(
    int id,
    String name,
    MathBranch branch,
    String formula,
  ) =>
      MathTheorem(
        id: id,
        name: name,
        branch: branch,
        formula: formula,
        value: 0,
        signal: 0,
        confidence: 0,
      );
}

// =============================================================================
// Numerical helpers
// =============================================================================

double _finite(double v, [double fallback = 0]) => v.isFinite ? v : fallback;

double _clamp1(double v) => v.isFinite ? v.clamp(-1.0, 1.0).toDouble() : 0.0;

double _unit(double v) => v.isFinite ? v.clamp(0.0, 1.0).toDouble() : 0.0;

double _sigmoid(double x) => 1 / (1 + math.exp(-x.clamp(-30.0, 30.0)));

double _tanh(double x) {
  final e = math.exp((2 * x).clamp(-30.0, 30.0));
  return (e - 1) / (e + 1);
}

List<double> _logReturns(List<double> closes) {
  final out = <double>[];
  for (var i = 1; i < closes.length; i++) {
    final a = closes[i - 1];
    final b = closes[i];
    if (a > 0 && b > 0) out.add(math.log(b / a));
  }
  return out;
}

List<double> _logPrices(List<double> closes) {
  final out = <double>[];
  for (final v in closes) {
    if (v > 0) out.add(math.log(v));
  }
  return out;
}

List<double> _tail(List<double> x, int n) =>
    x.length <= n ? List<double>.from(x) : x.sublist(x.length - n);

double _mean(List<double> x) {
  if (x.isEmpty) return 0;
  var s = 0.0;
  for (final v in x) {
    s += v;
  }
  return _finite(s / x.length);
}

double _variance(List<double> x) {
  if (x.length < 2) return 0;
  final m = _mean(x);
  var s = 0.0;
  for (final v in x) {
    final d = v - m;
    s += d * d;
  }
  return _finite(s / (x.length - 1));
}

double _std(List<double> x) => math.sqrt(math.max(_variance(x), 0));

double _skewness(List<double> x) {
  if (x.length < 3) return 0;
  final m = _mean(x);
  final sd = _std(x);
  if (sd <= 1e-15) return 0;
  var s = 0.0;
  for (final v in x) {
    s += math.pow((v - m) / sd, 3).toDouble();
  }
  return _finite(s / x.length);
}

double _excessKurtosis(List<double> x) {
  if (x.length < 4) return 0;
  final m = _mean(x);
  final sd = _std(x);
  if (sd <= 1e-15) return 0;
  var s = 0.0;
  for (final v in x) {
    s += math.pow((v - m) / sd, 4).toDouble();
  }
  return _finite(s / x.length - 3);
}

double _autocorr(List<double> x, int lag) {
  if (x.length <= lag + 2) return 0;
  final m = _mean(x);
  var num = 0.0;
  var den = 0.0;
  for (var i = 0; i < x.length; i++) {
    final d = x[i] - m;
    den += d * d;
    if (i >= lag) num += d * (x[i - lag] - m);
  }
  if (den <= 1e-18) return 0;
  return _finite(num / den).clamp(-1.0, 1.0).toDouble();
}

class _Fit {
  const _Fit(this.slope, this.intercept, this.r2);
  final double slope;
  final double intercept;
  final double r2;
}

_Fit _ols(List<double> x, List<double> y) {
  final n = math.min(x.length, y.length);
  if (n < 3) return const _Fit(0, 0, 0);
  var sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sx += x[i];
    sy += y[i];
    sxy += x[i] * y[i];
    sxx += x[i] * x[i];
    syy += y[i] * y[i];
  }
  final den = n * sxx - sx * sx;
  if (den.abs() < 1e-18) return const _Fit(0, 0, 0);
  final slope = (n * sxy - sx * sy) / den;
  final intercept = (sy - slope * sx) / n;
  final varY = n * syy - sy * sy;
  final r = varY.abs() < 1e-18
      ? 0.0
      : (n * sxy - sx * sy) / math.sqrt(den * varY.abs());
  return _Fit(_finite(slope), _finite(intercept), _unit(r * r));
}

List<double>? _solveLinear(List<List<double>> a, List<double> b) {
  final n = b.length;
  if (n == 0 || a.length != n) return null;
  final m = List<List<double>>.generate(
    n,
    (i) => <double>[...a[i], b[i]],
  );
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
    }
    if (m[pivot][col].abs() < 1e-14) return null;
    final tmp = m[col];
    m[col] = m[pivot];
    m[pivot] = tmp;
    final pv = m[col][col];
    for (var j = col; j <= n; j++) {
      m[col][j] /= pv;
    }
    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      final f = m[r][col];
      if (f == 0) continue;
      for (var j = col; j <= n; j++) {
        m[r][j] -= f * m[col][j];
      }
    }
  }
  return [for (var i = 0; i < n; i++) _finite(m[i][n])];
}

List<double> _hpFilter(List<double> y, double lambda) {
  final n = y.length;
  if (n < 5) return List<double>.from(y);
  final a = List<List<double>>.generate(n, (_) => List<double>.filled(n, 0));
  for (var i = 0; i < n; i++) {
    a[i][i] = 1;
  }
  const coef = <double>[1, -2, 1];
  for (var i = 0; i + 2 < n; i++) {
    for (var p = 0; p < 3; p++) {
      for (var q = 0; q < 3; q++) {
        a[i + p][i + q] += lambda * coef[p] * coef[q];
      }
    }
  }
  return _solveLinear(a, y) ?? List<double>.from(y);
}

List<double> _periodogram(List<double> x) {
  final n = x.length;
  if (n < 8) return const <double>[];
  final out = <double>[];
  for (var k = 1; k <= n ~/ 2; k++) {
    var re = 0.0;
    var im = 0.0;
    for (var t = 0; t < n; t++) {
      final ang = 2 * math.pi * k * t / n;
      re += x[t] * math.cos(ang);
      im -= x[t] * math.sin(ang);
    }
    out.add((re * re + im * im) / n);
  }
  return out;
}

List<List<double>> _embed(List<double> x, int dim) {
  final out = <List<double>>[];
  for (var i = 0; i + dim <= x.length; i++) {
    out.add(x.sublist(i, i + dim));
  }
  return out;
}

double _dist(List<double> a, List<double> b) {
  var s = 0.0;
  final n = math.min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    final d = a[i] - b[i];
    s += d * d;
  }
  return math.sqrt(s);
}

List<List<double>> _covarianceMatrix(List<List<double>> vectors) {
  final dim = vectors.first.length;
  final means = List<double>.filled(dim, 0);
  for (final v in vectors) {
    for (var i = 0; i < dim; i++) {
      means[i] += v[i];
    }
  }
  for (var i = 0; i < dim; i++) {
    means[i] /= vectors.length;
  }
  final cov = List<List<double>>.generate(dim, (_) => List<double>.filled(dim, 0));
  for (final v in vectors) {
    for (var i = 0; i < dim; i++) {
      for (var j = 0; j < dim; j++) {
        cov[i][j] += (v[i] - means[i]) * (v[j] - means[j]);
      }
    }
  }
  final denominator = math.max(vectors.length - 1, 1);
  for (var i = 0; i < dim; i++) {
    for (var j = 0; j < dim; j++) {
      cov[i][j] = _finite(cov[i][j] / denominator);
    }
  }
  return cov;
}

List<double> _principalEigenvector(List<List<double>> matrix,
    {int iterations = 60}) {
  final n = matrix.length;
  var v = List<double>.filled(n, 1 / math.sqrt(n));
  for (var it = 0; it < iterations; it++) {
    final w = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      for (var j = 0; j < n; j++) {
        s += matrix[i][j] * v[j];
      }
      w[i] = s;
    }
    var norm = 0.0;
    for (final x in w) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    if (norm < 1e-18) return v;
    v = [for (var i = 0; i < n; i++) w[i] / norm];
  }
  return v;
}

List<double> _levinsonDurbin(List<double> x, int order) {
  if (x.length < order * 3) return const <double>[];
  final r = <double>[for (var k = 0; k <= order; k++) _autocorr(x, k)];
  if (r[0].abs() < 1e-12) return const <double>[];
  var a = List<double>.filled(order, 0);
  var e = 1.0;
  for (var i = 0; i < order; i++) {
    var acc = r[i + 1];
    for (var j = 0; j < i; j++) {
      acc -= a[j] * r[i - j];
    }
    if (e.abs() < 1e-15) break;
    final k = acc / e;
    final updated = List<double>.from(a);
    updated[i] = k;
    for (var j = 0; j < i; j++) {
      updated[j] = a[j] - k * a[i - 1 - j];
    }
    a = updated;
    e *= (1 - k * k);
    if (e <= 0) break;
  }
  return [for (final v in a) _finite(v).clamp(-2.0, 2.0).toDouble()];
}

double _hurstRs(List<double> x) {
  if (x.length < 16) return .5;
  final scales = <int>[8, 16, 32];
  final points = <List<double>>[];
  for (final n in scales) {
    if (x.length < n * 2) continue;
    final chunks = x.length ~/ n;
    var total = 0.0;
    var used = 0;
    for (var chunk = 0; chunk < chunks; chunk++) {
      final segment = x.sublist(chunk * n, chunk * n + n);
      final mean = _mean(segment);
      var cumulative = 0.0;
      var maxDev = -double.infinity;
      var minDev = double.infinity;
      for (final v in segment) {
        cumulative += v - mean;
        maxDev = math.max(maxDev, cumulative);
        minDev = math.min(minDev, cumulative);
      }
      final range = maxDev - minDev;
      final sd = _std(segment);
      if (sd > 1e-15 && range > 0) {
        total += range / sd;
        used++;
      }
    }
    if (used > 0) {
      points.add([math.log(n.toDouble()), math.log(total / used)]);
    }
  }
  if (points.length < 2) return .5;
  final fit = _ols(
    [for (final p in points) p[0]],
    [for (final p in points) p[1]],
  );
  return fit.slope.clamp(.05, .95).toDouble();
}

double _dfaExponent(List<double> x) {
  if (x.length < 24) return .5;
  final mean = _mean(x);
  final profile = <double>[];
  var cumulative = 0.0;
  for (final v in x) {
    cumulative += v - mean;
    profile.add(cumulative);
  }
  final scales = <int>[6, 12, 24];
  final points = <List<double>>[];
  for (final n in scales) {
    if (profile.length < n * 2) continue;
    final segments = profile.length ~/ n;
    var total = 0.0;
    for (var s = 0; s < segments; s++) {
      final segment = profile.sublist(s * n, s * n + n);
      final idx = [for (var i = 0; i < n; i++) i.toDouble()];
      final fit = _ols(idx, segment);
      var ss = 0.0;
      for (var i = 0; i < n; i++) {
        final fitted = fit.intercept + fit.slope * idx[i];
        ss += math.pow(segment[i] - fitted, 2).toDouble();
      }
      total += ss / n;
    }
    final f = math.sqrt(total / segments);
    if (f > 1e-18) points.add([math.log(n.toDouble()), math.log(f)]);
  }
  if (points.length < 2) return .5;
  final fit = _ols(
    [for (final p in points) p[0]],
    [for (final p in points) p[1]],
  );
  return fit.slope.clamp(.05, 1.6).toDouble();
}

double _higuchiDimension(List<double> x) {
  if (x.length < 16) return 1.5;
  final n = x.length;
  final points = <List<double>>[];
  for (final k in <int>[1, 2, 3, 4, 6]) {
    var lengthSum = 0.0;
    var count = 0;
    for (var m = 0; m < k; m++) {
      var sum = 0.0;
      var steps = 0;
      for (var i = 1; m + i * k < n; i++) {
        sum += (x[m + i * k] - x[m + (i - 1) * k]).abs();
        steps++;
      }
      if (steps > 0) {
        lengthSum += sum * (n - 1) / (steps * k * k);
        count++;
      }
    }
    if (count > 0) {
      final l = lengthSum / count;
      if (l > 1e-18) {
        points.add([math.log(1 / k), math.log(l)]);
      }
    }
  }
  if (points.length < 2) return 1.5;
  final fit = _ols(
    [for (final p in points) p[0]],
    [for (final p in points) p[1]],
  );
  return fit.slope.clamp(1.0, 2.0).toDouble();
}

double _varianceRatio(List<double> x, int q) {
  if (x.length < q * 4) return 1;
  final var1 = _variance(x);
  if (var1 <= 1e-18) return 1;
  final aggregated = <double>[];
  for (var i = 0; i + q <= x.length; i += q) {
    var s = 0.0;
    for (var j = i; j < i + q; j++) {
      s += x[j];
    }
    aggregated.add(s);
  }
  final varQ = _variance(aggregated);
  return _finite(varQ / (q * var1), 1).clamp(0.0, 4.0).toDouble();
}

List<int> _quantize(List<double> x, int bins, double sigma) {
  if (x.isEmpty) return const <int>[];
  final scale = math.max(sigma, 1e-12);
  final half = bins ~/ 2;
  return [
    for (final v in x)
      ((v / (scale * .8)).round() + half).clamp(0, bins - 1).toInt(),
  ];
}

List<int> _histogram(List<int> values, int bins) {
  final counts = List<int>.filled(bins, 0);
  for (final v in values) {
    if (v >= 0 && v < bins) counts[v]++;
  }
  return counts;
}

double _entropy(List<int> values, int bins) {
  if (values.isEmpty) return 0;
  final counts = _histogram(values, bins);
  var h = 0.0;
  for (final count in counts) {
    if (count <= 0) continue;
    final p = count / values.length;
    h -= p * math.log(p);
  }
  return _finite(h);
}

double _permutationEntropy(List<double> x, int order) {
  if (x.length < order + 6) return 1;
  final patterns = <String, int>{};
  var total = 0;
  for (var i = 0; i + order <= x.length; i++) {
    final window = x.sublist(i, i + order);
    final indices = [for (var j = 0; j < order; j++) j]
      ..sort((a, b) => window[a].compareTo(window[b]));
    patterns[indices.join()] = (patterns[indices.join()] ?? 0) + 1;
    total++;
  }
  if (total == 0) return 1;
  var h = 0.0;
  for (final count in patterns.values) {
    final p = count / total;
    h -= p * math.log(p);
  }
  var factorial = 1.0;
  for (var i = 2; i <= order; i++) {
    factorial *= i;
  }
  final hMax = math.log(factorial);
  if (hMax <= 0) return 1;
  return _unit(h / hMax);
}

double _sampleEntropy(List<double> x, int m, double r) {
  if (x.length < m + 8 || r <= 0) return 2.5;
  int count(int dim) {
    var matches = 0;
    final vectors = _embed(x, dim);
    for (var i = 0; i < vectors.length; i++) {
      for (var j = i + 1; j < vectors.length; j++) {
        var maxDiff = 0.0;
        for (var k = 0; k < dim; k++) {
          maxDiff = math.max(maxDiff, (vectors[i][k] - vectors[j][k]).abs());
        }
        if (maxDiff <= r) matches++;
      }
    }
    return matches;
  }

  final b = count(m);
  final a = count(m + 1);
  if (b <= 0 || a <= 0) return 2.5;
  return _finite(-math.log(a / b), 2.5).clamp(0.0, 4.0).toDouble();
}

double _lyapunov(List<double> x, int dim, int steps) {
  final vectors = _embed(x, dim);
  if (vectors.length < steps + 6) return 0;
  final divergences = List<double>.filled(steps, 0);
  final counts = List<int>.filled(steps, 0);
  for (var i = 0; i < vectors.length - steps; i++) {
    var bestDistance = double.infinity;
    var bestIndex = -1;
    for (var j = 0; j < vectors.length - steps; j++) {
      if ((i - j).abs() < dim) continue;
      final d = _dist(vectors[i], vectors[j]);
      if (d < bestDistance && d > 1e-15) {
        bestDistance = d;
        bestIndex = j;
      }
    }
    if (bestIndex < 0) continue;
    for (var s = 1; s <= steps; s++) {
      final d = _dist(vectors[i + s], vectors[bestIndex + s]);
      if (d > 1e-15) {
        divergences[s - 1] += math.log(d / bestDistance);
        counts[s - 1]++;
      }
    }
  }
  final xs = <double>[];
  final ys = <double>[];
  for (var s = 0; s < steps; s++) {
    if (counts[s] > 0) {
      xs.add((s + 1).toDouble());
      ys.add(divergences[s] / counts[s]);
    }
  }
  if (xs.length < 2) return 0;
  return _finite(_ols(xs, ys).slope).clamp(-2.0, 2.0).toDouble();
}

double _recurrenceDeterminism(List<double> x, int dim, double threshold) {
  final vectors = _embed(x, dim);
  final n = vectors.length;
  if (n < 8 || threshold <= 0) return 0;
  final matrix = List<List<bool>>.generate(
    n,
    (i) => List<bool>.filled(n, false),
  );
  var recurrent = 0;
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (i == j) continue;
      if (_dist(vectors[i], vectors[j]) <= threshold) {
        matrix[i][j] = true;
        recurrent++;
      }
    }
  }
  if (recurrent == 0) return 0;
  var diagonal = 0;
  for (var i = 0; i < n - 1; i++) {
    for (var j = 0; j < n - 1; j++) {
      if (matrix[i][j] && matrix[i + 1][j + 1]) diagonal += 1;
    }
  }
  return _unit(diagonal / recurrent);
}

double _correlationDimension(List<double> x, int dim, double sigma) {
  final vectors = _embed(x, dim);
  final n = vectors.length;
  if (n < 10 || sigma <= 0) return 1.5;
  final r1 = sigma * .8;
  final r2 = sigma * 2.0;
  var c1 = 0, c2 = 0, pairs = 0;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final d = _dist(vectors[i], vectors[j]);
      pairs++;
      if (d < r1) c1++;
      if (d < r2) c2++;
    }
  }
  if (pairs == 0 || c1 == 0 || c2 == 0) return 1.5;
  final value = (math.log(c2 / pairs) - math.log(c1 / pairs)) /
      (math.log(r2) - math.log(r1));
  return _finite(value, 1.5).clamp(0.2, 4.0).toDouble();
}

double _zeroOneChaosTest(List<double> x) {
  if (x.length < 20) return .5;
  const cConstant = 1.1;
  final n = x.length;
  final p = List<double>.filled(n, 0);
  final q = List<double>.filled(n, 0);
  var accP = 0.0;
  var accQ = 0.0;
  for (var j = 0; j < n; j++) {
    accP += x[j] * math.cos((j + 1) * cConstant);
    accQ += x[j] * math.sin((j + 1) * cConstant);
    p[j] = accP;
    q[j] = accQ;
  }
  final limit = n ~/ 4;
  if (limit < 4) return .5;
  final ns = <double>[];
  final ms = <double>[];
  for (var lag = 1; lag <= limit; lag++) {
    var sum = 0.0;
    var count = 0;
    for (var j = 0; j + lag < n; j++) {
      final dp = p[j + lag] - p[j];
      final dq = q[j + lag] - q[j];
      sum += dp * dp + dq * dq;
      count++;
    }
    if (count > 0) {
      ns.add(lag.toDouble());
      ms.add(sum / count);
    }
  }
  if (ns.length < 3) return .5;
  final meanN = _mean(ns);
  final meanM = _mean(ms);
  var cov = 0.0, vn = 0.0, vm = 0.0;
  for (var i = 0; i < ns.length; i++) {
    final dn = ns[i] - meanN;
    final dm = ms[i] - meanM;
    cov += dn * dm;
    vn += dn * dn;
    vm += dm * dm;
  }
  final den = math.sqrt(vn * vm);
  if (den <= 1e-18) return .5;
  return _unit((cov / den).abs());
}

double _hillEstimator(List<double> sortedPositive) {
  final n = sortedPositive.length;
  if (n < 6) return 0;
  final k = math.max(3, (n * .25).round());
  final tail = sortedPositive.sublist(n - k);
  final anchor = tail.first;
  if (anchor <= 1e-15) return 0;
  var s = 0.0;
  for (final v in tail) {
    s += math.log(math.max(v, 1e-18) / anchor);
  }
  final xi = s / k;
  return _finite(xi).clamp(0.0, 5.0).toDouble();
}

double _binomial(int n, int k) {
  if (k < 0 || k > n) return 0;
  var result = 1.0;
  for (var i = 1; i <= k; i++) {
    result = result * (n - k + i) / i;
  }
  return result;
}

double _normalCdf(double x) {
  final sign = x < 0 ? -1.0 : 1.0;
  final a = x.abs() / math.sqrt(2.0);
  final t = 1.0 / (1.0 + .3275911 * a);
  final erf = 1.0 -
      (((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - .284496736) *
                  t +
              .254829592) *
          t *
          math.exp(-a * a));
  return (.5 * (1 + sign * erf)).clamp(0.0, 1.0).toDouble();
}

/// Wallace-style approximation of the Student-t CDF; accurate enough for a
/// real-time directional decision.
double _studentTCdf(double x, double nu) {
  if (nu >= 60) return _normalCdf(x);
  final z = x * (1 - 1 / (4 * nu)) / math.sqrt(1 + x * x / (2 * nu));
  return _normalCdf(z);
}
