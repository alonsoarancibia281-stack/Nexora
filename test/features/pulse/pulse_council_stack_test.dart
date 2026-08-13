import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_analyst_evolution.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_audit_board.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_chief_analyst.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_consensus_engine.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_ensemble_100.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_flow_edge.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_math_council.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_news_desk.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_pattern_archive.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_round_plan.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_signal.dart';

PulseSignal signal({
  double score = 30,
  double instability = 25,
  MarketStability stability = MarketStability.stable,
}) =>
    PulseSignal(
      direction: score >= 0 ? PulseDirection.up : PulseDirection.down,
      score: score,
      confidence: 68,
      momentumScore: score,
      trendScore: score * .8,
      orderBookImbalance: score * .5,
      volumeRatio: 1.15,
      bodyPressure: score * .4,
      instabilityScore: instability,
      stability: stability,
      agreementRatio: .72,
      roundDistancePct: .02,
      expectedRemainingMovePct: .12,
      reasons: const <String>[],
    );

AnalystInput input(double bias) => AnalystInput(
      features: <String, double>{
        'momentum': bias,
        'trend': bias * .8,
        'shortReturn': bias * .6,
        'bookImbalance': bias * .5,
        'aggressorImbalance': bias * .5,
        'bodyPressure': bias * .4,
        'regimeTrend': bias * .7,
        'roundEdge': bias * .3,
        'zPrice': bias * .4,
        'volumeZ': bias * .3,
      },
      instability: 25,
      secondsRemaining: 240,
    );

List<Candle> series(int count, double drift, {int seed = 3}) {
  final random = math.Random(seed);
  final candles = <Candle>[];
  var price = 45000.0;
  for (var i = 0; i < count; i++) {
    final open = price;
    price *= 1 + drift + (random.nextDouble() - .5) * .0018;
    candles.add(Candle(
      openTime: DateTime.fromMillisecondsSinceEpoch(i * 300000, isUtc: true),
      open: open,
      high: math.max(open, price) * 1.0006,
      low: math.min(open, price) * .9994,
      close: price,
      volume: 90 + random.nextDouble() * 60,
    ));
  }
  return candles;
}

NewsItem headline(String title, {int minutesAgo = 5, String source = 'CoinDesk'}) =>
    NewsItem(
      title: title,
      body: title,
      source: source,
      publishedAt:
          DateTime.utc(2026, 8, 13, 12).subtract(Duration(minutes: minutesAgo)),
    );

void main() {
  const ensemble = PulseEnsemble100();
  const council = PulseMathCouncil();
  const desk = PulseNewsDesk();
  const archive = PulsePatternArchive();
  const fusion = PulseConsensusEngine();
  const board = PulseAuditBoard();
  const chief = PulseChiefAnalyst();

  group('ensemble of 100 analysts', () {
    test('every analyst votes and the teams cover all ten families', () {
      final result = ensemble.analyze(
        input(.5),
        evolution: PulseEvolutionState.bootstrap(),
      );

      expect(result.opinions, hasLength(100));
      expect(result.votes, hasLength(100));
      expect(result.teamOpinions, hasLength(AnalystFamily.values.length));
      expect(result.probabilityUp, inInclusiveRange(.04, .96));
      expect(result.dispersion, inInclusiveRange(0, 1));
    });

    test('bullish features produce a higher probability than bearish ones', () {
      final state = PulseEvolutionState.bootstrap();
      final bullish = ensemble.analyze(input(.6), evolution: state);
      final bearish = ensemble.analyze(input(-.6), evolution: state);

      expect(bullish.probabilityUp, greaterThan(bearish.probabilityUp));
      expect(bullish.upVotes, greaterThan(bullish.downVotes));
      expect(bearish.downVotes, greaterThan(bearish.upVotes));
    });

    test('the mathematicians shift the vote when the analysts are neutral', () {
      final state = PulseEvolutionState.bootstrap();
      final withoutCouncil = ensemble.analyze(input(0), evolution: state);
      final bullishCouncil = MathBriefing(
        theorems: const <MathTheorem>[],
        branchSignal: {for (final b in MathBranch.values) b: .9},
        branchConfidence: {for (final b in MathBranch.values) b: .9},
        consensusSignal: .9,
        dispersion: .1,
        probabilityUp: .8,
        isReady: true,
      );
      final withCouncil = ensemble.analyze(
        input(0),
        briefing: bullishCouncil,
        evolution: state,
      );

      expect(withCouncil.probabilityUp, greaterThan(withoutCouncil.probabilityUp));
    });
  });

  group('news desk of 50 analysts', () {
    test('fifty analysts read the feed across ten desks', () {
      final briefing = desk.analyze(
        [
          headline('Bitcoin ETF inflows surge to a record high'),
          headline('Institutional demand climbs as BTC rallies'),
          headline('Fed signals a rate cut, risk assets gain'),
        ],
        now: DateTime.utc(2026, 8, 13, 12),
      );

      expect(briefing.isReady, isTrue);
      expect(briefing.opinions, hasLength(PulseNewsDesk.analysts));
      for (final d in NewsDesk.values) {
        expect(briefing.opinions.where((o) => o.desk == d), hasLength(5));
      }
      expect(briefing.probabilityUp, greaterThan(.5));
    });

    test('bearish coverage pushes the floor below a coin flip', () {
      final briefing = desk.analyze(
        [
          headline('Major exchange hacked, bitcoin plunges'),
          headline('Regulators announce crackdown and ban on trading'),
          headline('Liquidations cascade as BTC crashes'),
        ],
        now: DateTime.utc(2026, 8, 13, 12),
      );

      expect(briefing.probabilityUp, lessThan(.5));
      expect(briefing.bearishAnalysts, greaterThan(briefing.bullishAnalysts));
    });

    test('an empty feed stays neutral', () {
      final briefing = desk.analyze(const <NewsItem>[]);

      expect(briefing.isReady, isFalse);
      expect(briefing.probabilityUp, .5);
    });

    test('negation flips the reading of a headline', () {
      final positive = desk.analyze(
        [headline('Regulator approves spot bitcoin ETF')],
        now: DateTime.utc(2026, 8, 13, 12),
      );
      final negated = desk.analyze(
        [headline('Regulator rejects spot bitcoin ETF application')],
        now: DateTime.utc(2026, 8, 13, 12),
      );

      expect(positive.consensusSignal, greaterThan(negated.consensusSignal));
    });
  });

  group('historical archive of 100 analysts', () {
    test('one hundred analysts study the multi-timeframe history', () {
      final history = PatternHistory(series: <String, List<Candle>>{
        '5m': series(400, .0002),
        '1h': series(300, .0004, seed: 11),
        '4h': series(200, .0006, seed: 12),
        '1d': series(200, .0009, seed: 13),
      });

      final briefing = archive.study(history);

      expect(briefing.isReady, isTrue);
      expect(briefing.verdicts, hasLength(PulsePatternArchive.analysts));
      for (final lens in PatternLens.values) {
        expect(briefing.verdicts.where((v) => v.lens == lens), hasLength(10));
      }
      expect(briefing.probabilityUp, inInclusiveRange(.10, .90));
      expect(briefing.candlesStudied, greaterThan(1000));
      for (final verdict in briefing.verdicts) {
        expect(verdict.signal, inInclusiveRange(-1, 1));
        expect(verdict.confidence, inInclusiveRange(0, 1));
      }
    });

    test('a short history is reported as not ready instead of guessing', () {
      final briefing = archive.study(
        PatternHistory(series: <String, List<Candle>>{'5m': series(40, .0002)}),
      );

      expect(briefing.isReady, isFalse);
      expect(briefing.probabilityUp, .5);
    });
  });

  group('audit board and chief analyst', () {
    PulseConsensus buildConsensus({double bias = .6, double instability = 25}) {
      final state = PulseEvolutionState.bootstrap();
      final quantitative = signal(score: bias * 60, instability: instability);
      return fusion.fuse(
        signal: quantitative,
        ensemble: ensemble.analyze(input(bias), evolution: state),
        briefing: council.deliberate(MathContext(
          closes: [for (final c in series(90, .0004)) c.close],
          highs: [for (final c in series(90, .0004)) c.high],
          lows: [for (final c in series(90, .0004)) c.low],
          volumes: [for (final c in series(90, .0004)) c.volume],
          roundStartPrice: 45000,
          secondsRemaining: 240,
          bookImbalance: bias,
          aggressorImbalance: bias,
          signedVolume: bias,
          spreadBps: .9,
          micropriceEdge: 0,
          instability: instability,
        )),
        news: NewsBriefing.empty(),
        patterns: PatternBriefing.empty(),
        evolution: state,
      );
    }

    test('one hundred auditors run the final test over ten domains', () {
      final report = board.audit(
        consensus: buildConsensus(),
        signal: signal(),
        evolution: PulseEvolutionState.bootstrap(),
        secondsRemaining: 240,
      );

      expect(report.opinions, hasLength(PulseAuditBoard.auditors));
      for (final domain in AuditDomain.values) {
        expect(report.opinions.where((o) => o.domain == domain), hasLength(10));
      }
      expect(report.shrinkFactor, inInclusiveRange(.25, 1.0));
      expect(report.probabilityUp, inInclusiveRange(.05, .95));
      expect(report.qualityScore, inInclusiveRange(0, 1));
    });

    test('the audit never pushes the probability past the raw call', () {
      final consensus = buildConsensus();
      final report = board.audit(
        consensus: consensus,
        signal: signal(),
        evolution: PulseEvolutionState.bootstrap(),
        secondsRemaining: 240,
      );

      final rawEdge = (consensus.probabilityUp - .5).abs();
      final auditedEdge = (report.probabilityUp - .5).abs();
      expect(auditedEdge, lessThanOrEqualTo(rawEdge + 1e-9));
      expect(
        report.probabilityUp >= .5,
        consensus.probabilityUp >= .5,
        reason: 'the audit may shrink the edge but never flip it',
      );
    });

    test('a very unstable market is flagged by the regime auditors', () {
      final report = board.audit(
        consensus: buildConsensus(instability: 92),
        signal: signal(
          instability: 92,
          stability: MarketStability.veryUnstable,
        ),
        evolution: PulseEvolutionState.bootstrap(),
        secondsRemaining: 240,
      );

      expect(report.severityOf(AuditDomain.regimeValidity), greaterThan(.5));
      expect(report.shrinkFactor, lessThan(1));
      expect(report.verdict, isNot(AuditVerdict.approved));
    });

    test('the chief locks one call from the deliberation window', () {
      final consensus = buildConsensus();
      final audit = board.audit(
        consensus: consensus,
        signal: signal(),
        evolution: PulseEvolutionState.bootstrap(),
        secondsRemaining: 240,
      );
      final decidedAt = DateTime.utc(2026, 8, 13, 12, 1);
      final samples = <ChiefSample>[
        for (var i = 0; i < 12; i++)
          ChiefSample(
            takenAt: decidedAt.subtract(Duration(seconds: 60 - i * 5)),
            secondsRemaining: 300 - i * 5,
            probabilityUp: audit.probabilityUp,
            price: 45000,
            instability: 25,
            ensembleProbability: consensus.ensemble.probabilityUp,
            mathProbability: consensus.briefing.probabilityUp,
            patternProbability: .5,
            newsProbability: .5,
          ),
      ];

      final verdict = chief.decide(
        samples: samples,
        consensus: consensus,
        audit: audit,
        signal: signal(),
        entryPrice: 45000,
        decidedAt: decidedAt,
        secondsRemaining: chief.lockAtSecondsRemaining,
      );

      expect(verdict.samplesUsed, 12);
      expect(verdict.confidence, inInclusiveRange(50, 95));
      expect(verdict.probabilityUp, inInclusiveRange(.05, .95));
      expect(verdict.councilVotes, isNotEmpty);
      expect(verdict.rationale, isNotEmpty);
      expect(verdict.stability, inInclusiveRange(0, 1));
      expect(verdict.decidedAtSecondsRemaining, 240);
      expect(verdict.headline, contains('5 minutos'));
    });

    test('an incomplete decision window is flagged and cut back', () {
      final consensus = buildConsensus();
      final audit = board.audit(
        consensus: consensus,
        signal: signal(),
        evolution: PulseEvolutionState.bootstrap(),
        secondsRemaining: 240,
      );
      final decidedAt = DateTime.utc(2026, 8, 13, 12, 1);

      ChiefVerdict decide(int sampleCount, int secondsRemaining) => chief.decide(
            samples: [
              for (var i = 0; i < sampleCount; i++)
                ChiefSample(
                  takenAt: decidedAt,
                  secondsRemaining: secondsRemaining + i,
                  probabilityUp: .70,
                  price: 45000,
                  instability: 25,
                  ensembleProbability: .70,
                  mathProbability: .68,
                  patternProbability: .5,
                  newsProbability: .5,
                ),
            ],
            consensus: consensus,
            audit: audit,
            signal: signal(),
            entryPrice: 45000,
            decidedAt: decidedAt,
            secondsRemaining: secondsRemaining,
          );

      final complete = decide(12, chief.lockAtSecondsRemaining);
      expect(complete.fullDeliberation, isTrue);

      // Joined the round with two minutes left: one glance, not a window.
      final late = decide(1, 120);
      expect(late.fullDeliberation, isFalse);
      expect(late.confidence, lessThan(complete.confidence));
      expect(
        late.rationale.any((line) => line.contains('incompleta')),
        isTrue,
      );

      // Too few readings even at the right moment still counts as incomplete.
      final thin = decide(2, chief.lockAtSecondsRemaining);
      expect(thin.fullDeliberation, isFalse);
    });

    test('the chief abstains when the edge sits inside the noise band', () {
      final consensus = buildConsensus();
      final audit = board.audit(
        consensus: consensus,
        signal: signal(),
        evolution: PulseEvolutionState.bootstrap(),
        secondsRemaining: 240,
      );
      final decidedAt = DateTime.utc(2026, 8, 13, 12, 1);

      ChiefVerdict decide(double probability) => chief.decide(
            samples: [
              for (var i = 0; i < 8; i++)
                ChiefSample(
                  takenAt: decidedAt,
                  secondsRemaining: 300 - i * 5,
                  probabilityUp: probability,
                  price: 45000,
                  instability: 25,
                  ensembleProbability: probability,
                  mathProbability: probability,
                  patternProbability: .5,
                  newsProbability: .5,
                ),
            ],
            consensus: consensus,
            audit: audit,
            signal: signal(),
            entryPrice: 45000,
            decidedAt: decidedAt,
            secondsRemaining: chief.lockAtSecondsRemaining,
          );

      final coinFlip = decide(.505);
      expect(coinFlip.hasReading, isFalse);
      expect(coinFlip.headline, contains('sin lectura'));
      expect(
        coinFlip.rationale.any((line) => line.contains('no es legible')),
        isTrue,
      );

      final decisive = decide(.93);
      expect((decisive.probabilityUp - .5).abs(),
          greaterThanOrEqualTo(PulseChiefAnalyst.readingGate));
      expect(decisive.hasReading, isTrue);
      expect(decisive.headline, contains('5 minutos'));
    });

    test('unstable deliberation lowers the chief conviction', () {
      final consensus = buildConsensus();
      final audit = board.audit(
        consensus: consensus,
        signal: signal(),
        evolution: PulseEvolutionState.bootstrap(),
        secondsRemaining: 240,
      );
      final decidedAt = DateTime.utc(2026, 8, 13, 12, 1);

      ChiefVerdict decide(List<double> probabilities) => chief.decide(
            samples: [
              for (var i = 0; i < probabilities.length; i++)
                ChiefSample(
                  takenAt: decidedAt,
                  secondsRemaining: 300 - i * 5,
                  probabilityUp: probabilities[i],
                  price: 45000,
                  instability: 25,
                  ensembleProbability: .6,
                  mathProbability: .6,
                  patternProbability: .5,
                  newsProbability: .5,
                ),
            ],
            consensus: consensus,
            audit: audit,
            signal: signal(),
            entryPrice: 45000,
            decidedAt: decidedAt,
            secondsRemaining: 240,
          );

      final steady = decide(const [.70, .70, .70, .70, .70, .70]);
      final erratic = decide(const [.15, .85, .20, .90, .25, .70]);

      expect(steady.stability, greaterThan(erratic.stability));
      expect(steady.confidence, greaterThan(erratic.confidence));
    });
  });

  group('diffusion anchor', () {
    PulseConsensus fuseWith(PulseSignal quantitative, double bias) {
      final state = PulseEvolutionState.bootstrap();
      return fusion.fuse(
        signal: quantitative,
        ensemble: ensemble.analyze(input(bias), evolution: state),
        briefing: MathBriefing.neutral(),
        news: NewsBriefing.empty(),
        patterns: PatternBriefing.empty(),
        evolution: state,
      );
    }

    PulseSignal travelled(double distancePct) => PulseSignal(
          direction: PulseDirection.up,
          score: 10,
          confidence: 60,
          momentumScore: 10,
          trendScore: 8,
          orderBookImbalance: 0,
          volumeRatio: 1.1,
          bodyPressure: 5,
          instabilityScore: 25,
          stability: MarketStability.stable,
          agreementRatio: .6,
          roundDistancePct: distancePct,
          expectedRemainingMovePct: .12,
          reasons: const <String>[],
        );

    test('the realised move sets the anchor', () {
      final up = fuseWith(travelled(.20), 0);
      final down = fuseWith(travelled(-.20), 0);
      final flat = fuseWith(travelled(0), 0);

      expect(up.anchorProbabilityUp, greaterThan(.85));
      expect(down.anchorProbabilityUp, lessThan(.15));
      expect(flat.anchorProbabilityUp, closeTo(.5, 1e-9));
      expect(up.probabilityUp, greaterThan(down.probabilityUp));
    });

    test('councils cannot reverse a strong anchor', () {
      // Price is far above the open; the analysts are told to read bearish.
      final consensus = fuseWith(travelled(.30), -.9);

      expect(consensus.anchorProbabilityUp, greaterThan(.9));
      expect(consensus.direction, PulseDirection.up);
      expect(consensus.overridesAnchor, isFalse);
      expect(
        consensus.councilAdjustment.abs(),
        lessThanOrEqualTo(const PulseConsensusEngine().councilAuthority + 1e-9),
      );
    });

    test('councils still decide when the anchor is flat', () {
      final bullish = fuseWith(travelled(0), .8);
      final bearish = fuseWith(travelled(0), -.8);

      expect(bullish.probabilityUp, greaterThan(.5));
      expect(bearish.probabilityUp, lessThan(.5));
    });

    test('the councils always keep a say', () {
      final withBull = fuseWith(travelled(.06), .8);
      final withBear = fuseWith(travelled(.06), -.8);

      expect(withBull.probabilityUp, greaterThan(withBear.probabilityUp));
    });
  });

  group('trade tape', () {
    PulseSignal flat() => PulseSignal(
          direction: PulseDirection.up,
          score: 4,
          confidence: 55,
          momentumScore: 4,
          trendScore: 3,
          orderBookImbalance: 0,
          volumeRatio: 1,
          bodyPressure: 2,
          instabilityScore: 20,
          stability: MarketStability.stable,
          agreementRatio: .5,
          roundDistancePct: 0,
          expectedRemainingMovePct: .12,
          reasons: const <String>[],
        );

    PulseConsensus fuseWithFlow(PulseFlowEdge flow) {
      final state = PulseEvolutionState.bootstrap();
      return fusion.fuse(
        signal: flat(),
        ensemble: ensemble.analyze(input(0), evolution: state),
        briefing: MathBriefing.neutral(),
        news: NewsBriefing.empty(),
        patterns: PatternBriefing.empty(),
        evolution: state,
        flow: flow,
      );
    }

    test('an empty tape changes nothing', () {
      expect(fuseWithFlow(PulseFlowEdge.empty).flowAdjustment, 0);
    });

    test('a one-sided tape pushes the verdict its way', () {
      const buying = PulseFlowEdge(
        aggressorImbalance: .6,
        priceImpulseBps: 9,
        flowPersistence: .5,
        trades: 800,
      );
      const selling = PulseFlowEdge(
        aggressorImbalance: -.6,
        priceImpulseBps: -9,
        flowPersistence: -.5,
        trades: 800,
      );

      expect(buying.logOdds, greaterThan(0));
      expect(selling.logOdds, lessThan(0));
      expect(
        fuseWithFlow(buying).probabilityUp,
        greaterThan(fuseWithFlow(selling).probabilityUp),
      );
    });

    test('the tape contribution stays bounded', () {
      const extreme = PulseFlowEdge(
        aggressorImbalance: 12,
        priceImpulseBps: 900,
        flowPersistence: 12,
        trades: 5000,
      );

      expect(extreme.logOdds, lessThanOrEqualTo(PulseFlowEdge.bound + 1e-9));
    });
  });

  group('round plan', () {
    test('locks a thesis with target and invalidation at the open', () {
      final state = PulseEvolutionState.bootstrap();
      final consensus = fusion.fuse(
        signal: signal(),
        ensemble: ensemble.analyze(input(.6), evolution: state),
        briefing: MathBriefing.neutral(),
        news: NewsBriefing.empty(),
        patterns: PatternBriefing.empty(),
        evolution: state,
      );
      final start = DateTime.utc(2026, 8, 13, 12);
      final plan = PulseRoundPlan.build(
        roundStart: start,
        roundEnd: start.add(const Duration(minutes: 5)),
        entryPrice: 45000,
        secondsRemaining: 300,
        consensus: consensus,
        signal: signal(),
      );

      expect(plan.expectedMovePct, greaterThan(0));
      expect(plan.strategy, contains('5 minutos'));
      expect(plan.drivers, isNotEmpty);
      if (plan.isUp) {
        expect(plan.targetPrice, greaterThan(plan.entryPrice));
        expect(plan.invalidationPrice, lessThan(plan.entryPrice));
      } else {
        expect(plan.targetPrice, lessThan(plan.entryPrice));
        expect(plan.invalidationPrice, greaterThan(plan.entryPrice));
      }
    });

    test('tracks the thesis from on-track to settled', () {
      final start = DateTime.utc(2026, 8, 13, 12);
      final plan = PulseRoundPlan(
        roundStart: start,
        roundEnd: start.add(const Duration(minutes: 5)),
        entryPrice: 45000,
        direction: PulseDirection.up,
        probabilityUp: .68,
        expectedMovePct: .12,
        targetPrice: 45054,
        invalidationPrice: 44954,
        drivers: const <String>[],
        strategy: '',
        lockedAtSecondsRemaining: 240,
        analystAgreement: .7,
        councilAgreement: .7,
      );

      final onTrack = PulseRoundTracking.evaluate(
        plan: plan,
        currentPrice: 45030,
        secondsRemaining: 120,
        liveProbabilityUp: .70,
      );
      expect(onTrack.status, RoundPlanStatus.onTrack);
      expect(onTrack.movePct, greaterThan(0));
      expect(onTrack.progressToTarget, greaterThan(0));

      final atRisk = PulseRoundTracking.evaluate(
        plan: plan,
        currentPrice: 44985,
        secondsRemaining: 90,
        liveProbabilityUp: .55,
      );
      expect(atRisk.status, RoundPlanStatus.atRisk);
      expect(atRisk.needsPct, greaterThan(0));

      final invalidated = PulseRoundTracking.evaluate(
        plan: plan,
        currentPrice: 44900,
        secondsRemaining: 40,
        liveProbabilityUp: .40,
      );
      expect(invalidated.status, RoundPlanStatus.invalidated);

      final settled = PulseRoundTracking.evaluate(
        plan: plan,
        currentPrice: 45060,
        secondsRemaining: 0,
        liveProbabilityUp: .68,
        closed: true,
      );
      expect(settled.status, RoundPlanStatus.settledWin);
      expect(settled.settled, isTrue);
    });
  });
}
