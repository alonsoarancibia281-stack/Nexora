import 'dart:math' as math;

/// One normalized headline coming from any of the public Bitcoin feeds.
class NewsItem {
  const NewsItem({
    required this.title,
    required this.body,
    required this.source,
    required this.publishedAt,
    this.categories = '',
  });

  final String title;
  final String body;
  final String source;
  final DateTime publishedAt;
  final String categories;

  double ageMinutes(DateTime now) {
    final minutes = now.toUtc().difference(publishedAt.toUtc()).inSeconds / 60.0;
    return minutes.isFinite ? math.max(minutes, 0) : 0;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': title,
        'b': body.length > 600 ? body.substring(0, 600) : body,
        's': source,
        'p': publishedAt.toUtc().millisecondsSinceEpoch,
        'c': categories,
      };

  static NewsItem? fromJson(Map<String, dynamic> json) {
    try {
      return NewsItem(
        title: '${json['t']}',
        body: '${json['b'] ?? ''}',
        source: '${json['s'] ?? 'feed'}',
        publishedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['p'] as num).toInt(),
          isUtc: true,
        ),
        categories: '${json['c'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }
}

/// The ten beats covered by the 50 news analysts.
enum NewsDesk {
  macro,
  regulation,
  institutional,
  onchain,
  security,
  adoption,
  mining,
  derivatives,
  exchange,
  sentiment,
}

extension NewsDeskLabel on NewsDesk {
  String get label {
    switch (this) {
      case NewsDesk.macro:
        return 'Macroeconomía';
      case NewsDesk.regulation:
        return 'Regulación';
      case NewsDesk.institutional:
        return 'Institucional / ETF';
      case NewsDesk.onchain:
        return 'On-chain';
      case NewsDesk.security:
        return 'Seguridad';
      case NewsDesk.adoption:
        return 'Adopción';
      case NewsDesk.mining:
        return 'Minería';
      case NewsDesk.derivatives:
        return 'Derivados';
      case NewsDesk.exchange:
        return 'Exchanges';
      case NewsDesk.sentiment:
        return 'Sentimiento';
    }
  }

  String get shortLabel {
    switch (this) {
      case NewsDesk.macro:
        return 'Macro';
      case NewsDesk.regulation:
        return 'Regulación';
      case NewsDesk.institutional:
        return 'ETF';
      case NewsDesk.onchain:
        return 'On-chain';
      case NewsDesk.security:
        return 'Seguridad';
      case NewsDesk.adoption:
        return 'Adopción';
      case NewsDesk.mining:
        return 'Minería';
      case NewsDesk.derivatives:
        return 'Derivados';
      case NewsDesk.exchange:
        return 'Exchanges';
      case NewsDesk.sentiment:
        return 'Sentimiento';
    }
  }
}

/// A single news analyst's reading of the current feed.
class NewsAnalystOpinion {
  const NewsAnalystOpinion({
    required this.id,
    required this.desk,
    required this.signal,
    required this.confidence,
    required this.itemsRead,
    required this.contrarian,
  });

  /// 1..50
  final int id;
  final NewsDesk desk;

  /// Directional reading in [-1,1]; positive means bullish for BTC.
  final double signal;
  final double confidence;
  final int itemsRead;

  /// True when this analyst fades extreme coverage instead of following it.
  final bool contrarian;
}

/// Aggregated verdict of the whole news floor.
class NewsBriefing {
  NewsBriefing({
    required this.opinions,
    required this.deskSignal,
    required this.deskConfidence,
    required this.consensusSignal,
    required this.dispersion,
    required this.probabilityUp,
    required this.headlines,
    required this.itemsAnalyzed,
    required this.breakingCount,
    required this.freshestMinutes,
    required this.updatedAt,
    required this.isReady,
  });

  final List<NewsAnalystOpinion> opinions;
  final Map<NewsDesk, double> deskSignal;
  final Map<NewsDesk, double> deskConfidence;
  final double consensusSignal;
  final double dispersion;
  final double probabilityUp;

  /// Most relevant headlines, freshest first.
  final List<ScoredHeadline> headlines;

  final int itemsAnalyzed;

  /// Headlines published in the last ten minutes.
  final int breakingCount;

  final double freshestMinutes;
  final DateTime updatedAt;
  final bool isReady;

  static NewsBriefing empty() => NewsBriefing(
        opinions: const <NewsAnalystOpinion>[],
        deskSignal: {for (final d in NewsDesk.values) d: 0.0},
        deskConfidence: {for (final d in NewsDesk.values) d: 0.0},
        consensusSignal: 0,
        dispersion: 0,
        probabilityUp: .5,
        headlines: const <ScoredHeadline>[],
        itemsAnalyzed: 0,
        breakingCount: 0,
        freshestMinutes: double.infinity,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        isReady: false,
      );

  double signalOf(NewsDesk desk) => deskSignal[desk] ?? 0;

  double confidenceOf(NewsDesk desk) => deskConfidence[desk] ?? 0;

  int get analysts => opinions.length;

  double get internalAgreement {
    if (opinions.isEmpty) return 0;
    final up = opinions.where((o) => o.signal > .02).length;
    final down = opinions.where((o) => o.signal < -.02).length;
    final decided = up + down;
    if (decided == 0) return 0;
    return math.max(up, down) / decided;
  }

  int get bullishAnalysts => opinions.where((o) => o.signal > .02).length;

  int get bearishAnalysts => opinions.where((o) => o.signal < -.02).length;
}

/// A headline with the score the floor assigned to it.
class ScoredHeadline {
  const ScoredHeadline({
    required this.item,
    required this.score,
    required this.desk,
    required this.ageMinutes,
  });

  final NewsItem item;

  /// Sentiment in [-1,1].
  final double score;
  final NewsDesk desk;
  final double ageMinutes;
}

/// Fifty news analysts reading the Bitcoin feed around the clock.
///
/// Ten beats, five analysts each. Every analyst uses its own recency half-life,
/// its own conviction threshold, its own trust profile for the sources and —
/// for one out of five — a contrarian stance that fades saturated coverage,
/// which is why the floor produces a spread of opinions instead of one number
/// repeated fifty times.
class PulseNewsDesk {
  const PulseNewsDesk();

  static const int analysts = 50;

  NewsBriefing analyze(List<NewsItem> items, {DateTime? now}) {
    final clock = (now ?? DateTime.now()).toUtc();
    if (items.isEmpty) return NewsBriefing.empty();

    final scored = <ScoredHeadline>[];
    for (final item in items) {
      final desk = _classify(item);
      final score = _sentiment(item, desk);
      scored.add(ScoredHeadline(
        item: item,
        score: score,
        desk: desk,
        ageMinutes: item.ageMinutes(clock),
      ));
    }
    scored.sort((a, b) => a.ageMinutes.compareTo(b.ageMinutes));

    final opinions = <NewsAnalystOpinion>[];
    var id = 1;
    for (final desk in NewsDesk.values) {
      for (var variant = 0; variant < 5; variant++) {
        opinions.add(_runAnalyst(id++, desk, variant, scored, clock));
      }
    }

    final deskSignal = <NewsDesk, double>{};
    final deskConfidence = <NewsDesk, double>{};
    for (final desk in NewsDesk.values) {
      final group = opinions.where((o) => o.desk == desk).toList();
      var weighted = 0.0;
      var weight = 0.0;
      var confidence = 0.0;
      for (final o in group) {
        final w = math.max(o.confidence, .05);
        weighted += o.signal * w;
        weight += w;
        confidence += o.confidence;
      }
      deskSignal[desk] = weight <= 0 ? 0.0 : _clamp1(weighted / weight);
      deskConfidence[desk] =
          group.isEmpty ? 0.0 : _unit(confidence / group.length);
    }

    var weighted = 0.0;
    var weight = 0.0;
    for (final o in opinions) {
      final w = math.max(o.confidence, .04);
      weighted += o.signal * w;
      weight += w;
    }
    final consensus = weight <= 0 ? 0.0 : _clamp1(weighted / weight);
    final dispersion = _unit(_std([for (final o in opinions) o.signal]));
    final coherence = (1 - dispersion * .7).clamp(.15, 1.0).toDouble();

    final freshest = scored.isEmpty ? double.infinity : scored.first.ageMinutes;
    final breaking = scored.where((s) => s.ageMinutes <= 10).length;

    // News moves a 5-minute BTC round far less than microstructure does, so the
    // implied probability is deliberately compressed.
    final probability =
        _sigmoid(consensus * 1.35 * coherence).clamp(.20, .80).toDouble();

    final relevant = [...scored]
      ..sort((a, b) {
        final byScore = b.score.abs().compareTo(a.score.abs());
        if (byScore != 0 && (a.ageMinutes - b.ageMinutes).abs() < 90) {
          return byScore;
        }
        return a.ageMinutes.compareTo(b.ageMinutes);
      });

    return NewsBriefing(
      opinions: List<NewsAnalystOpinion>.unmodifiable(opinions),
      deskSignal: Map<NewsDesk, double>.unmodifiable(deskSignal),
      deskConfidence: Map<NewsDesk, double>.unmodifiable(deskConfidence),
      consensusSignal: consensus,
      dispersion: dispersion,
      probabilityUp: probability,
      headlines: List<ScoredHeadline>.unmodifiable(relevant.take(14)),
      itemsAnalyzed: scored.length,
      breakingCount: breaking,
      freshestMinutes: freshest,
      updatedAt: clock,
      isReady: true,
    );
  }

  NewsAnalystOpinion _runAnalyst(
    int id,
    NewsDesk desk,
    int variant,
    List<ScoredHeadline> scored,
    DateTime now,
  ) {
    // Personal parameters: half-life between 25 and 205 minutes, rising
    // thresholds, and one contrarian per beat.
    final halfLife = 25.0 + variant * 45.0;
    final threshold = .05 + variant * .035;
    final crossBeatWeight = .18 + variant * .06;
    final contrarian = variant == 4;

    var weighted = 0.0;
    var weight = 0.0;
    var read = 0;
    var saturation = 0.0;

    for (final headline in scored) {
      final onBeat = headline.desk == desk;
      final relevance = onBeat ? 1.0 : crossBeatWeight;
      if (relevance <= 0) continue;
      if (headline.score.abs() < threshold) continue;

      final decay = math.pow(.5, headline.ageMinutes / halfLife).toDouble();
      if (decay < .02) continue;
      final credibility = _sourceTrust(headline.item.source, variant);
      final w = decay * relevance * credibility;
      weighted += headline.score * w;
      weight += w;
      saturation += w;
      read++;
    }

    if (weight <= 0) {
      return NewsAnalystOpinion(
        id: id,
        desk: desk,
        signal: 0,
        confidence: 0,
        itemsRead: 0,
        contrarian: contrarian,
      );
    }

    var signal = weighted / weight;

    // A contrarian fades coverage once the beat is saturated and one-sided.
    if (contrarian && saturation > 3.5 && signal.abs() > .35) {
      signal = -signal * .55;
    }

    final coverage = (read / 12).clamp(0.0, 1.0).toDouble();
    final conviction = signal.abs();
    final confidence = _unit(conviction * .65 + coverage * .35);

    return NewsAnalystOpinion(
      id: id,
      desk: desk,
      signal: _clamp1(signal),
      confidence: confidence,
      itemsRead: read,
      contrarian: contrarian,
    );
  }

  NewsDesk _classify(NewsItem item) {
    final text = '${item.title} ${item.categories} ${item.body}'.toLowerCase();
    var best = NewsDesk.sentiment;
    var bestHits = 0;
    for (final entry in _deskKeywords.entries) {
      var hits = 0;
      for (final keyword in entry.value) {
        if (text.contains(keyword)) hits++;
      }
      if (hits > bestHits) {
        bestHits = hits;
        best = entry.key;
      }
    }
    return best;
  }

  double _sentiment(NewsItem item, NewsDesk desk) {
    final title = item.title.toLowerCase();
    final body = item.body.toLowerCase();
    var score = 0.0;
    var hits = 0.0;

    void scan(String text, double weight) {
      if (text.isEmpty) return;
      for (final entry in _bullishLexicon.entries) {
        if (!text.contains(entry.key)) continue;
        final negated = _isNegated(text, entry.key);
        score += (negated ? -entry.value : entry.value) * weight;
        hits += weight;
      }
      for (final entry in _bearishLexicon.entries) {
        if (!text.contains(entry.key)) continue;
        final negated = _isNegated(text, entry.key);
        score -= (negated ? -entry.value : entry.value) * weight;
        hits += weight;
      }
    }

    scan(title, 1.6);
    scan(body.length > 900 ? body.substring(0, 900) : body, .7);

    if (hits <= 0) return 0;
    var normalized = score / math.max(hits, 1.0);

    // Security incidents are asymmetric: they hurt far more than they help.
    if (desk == NewsDesk.security && normalized < 0) normalized *= 1.35;
    return _clamp1(normalized);
  }

  bool _isNegated(String text, String keyword) {
    final index = text.indexOf(keyword);
    if (index <= 0) return false;
    final start = math.max(0, index - 28);
    final window = text.substring(start, index);
    for (final negation in _negations) {
      if (window.contains(negation)) return true;
    }
    return false;
  }

  double _sourceTrust(String source, int variant) {
    final key = source.toLowerCase();
    var base = .72;
    if (key.contains('coindesk') || key.contains('bloomberg') ||
        key.contains('reuters')) {
      base = 1.0;
    } else if (key.contains('cointelegraph') || key.contains('bitcoin magazine') ||
        key.contains('the block') || key.contains('decrypt')) {
      base = .88;
    } else if (key.contains('reddit') || key.contains('blog')) {
      base = .55;
    }
    // Each analyst trusts the mainstream press a little differently.
    final skew = 1 + (variant - 2) * .06;
    return (base * skew).clamp(.35, 1.15).toDouble();
  }
}

const _negations = <String>[
  'no ',
  'not ',
  'never',
  'denies',
  'denied',
  'rejects',
  'rejected',
  'without',
  'fails to',
  'unlikely',
];

const _bullishLexicon = <String, double>{
  'surge': .9, 'surges': .9, 'rally': .85, 'rallies': .85, 'soar': .95,
  'soars': .95, 'jump': .7, 'jumps': .7, 'gain': .55, 'gains': .55,
  'rise': .6, 'rises': .6, 'climb': .6, 'climbs': .6, 'record high': 1.0,
  'all-time high': 1.0, 'ath': .85, 'breakout': .8, 'bullish': .95,
  'bull run': .95, 'accumulation': .6, 'accumulate': .55, 'inflow': .8,
  'inflows': .8, 'buys': .6, 'buying': .6, 'adoption': .6, 'approved': .85,
  'approves': .85, 'approval': .85, 'greenlights': .8, 'greenlight': .8, 'partnership': .5, 'upgrade': .5,
  'institutional demand': .9, 'etf inflow': 1.0, 'legal tender': .8,
  'halving': .5, 'supply shock': .85, 'short squeeze': .8, 'reserve': .5,
  'treasury': .55, 'demand': .5, 'optimism': .6, 'momentum': .5,
  'outperform': .7, 'recovery': .6, 'rebound': .7, 'green': .35,
  'strategic reserve': .95, 'rate cut': .75, 'dovish': .7, 'stimulus': .65,
  'hashrate high': .5, 'whale accumulation': .85, 'scarcity': .6,
};

const _bearishLexicon = <String, double>{
  'crash': 1.0, 'crashes': 1.0, 'plunge': .95, 'plunges': .95, 'slump': .8,
  'tumble': .85, 'tumbles': .85, 'drop': .6, 'drops': .6, 'fall': .6,
  'falls': .6, 'decline': .6, 'declines': .6, 'selloff': .9, 'sell-off': .9,
  'bearish': .95, 'bear market': .9, 'liquidation': .8, 'liquidations': .85,
  'outflow': .8, 'outflows': .8, 'hack': 1.0, 'hacked': 1.0, 'exploit': .95,
  'breach': .85, 'stolen': .9, 'scam': .7, 'fraud': .85, 'lawsuit': .7,
  'sues': .7, 'sued': .7, 'rejects': .8, 'halts': .6, 'ban': .95, 'bans': .95, 'banned': .95,
  'crackdown': .9, 'investigation': .6, 'subpoena': .65, 'delisting': .8,
  'bankruptcy': 1.0, 'insolvent': 1.0, 'insolvency': 1.0, 'default': .85,
  'halt': .6, 'outage': .6, 'downtime': .5, 'rejected': .8, 'denial': .7,
  'fear': .6, 'panic': .85, 'capitulation': .9, 'correction': .55,
  'rate hike': .75, 'hawkish': .7, 'inflation surge': .6, 'recession': .7,
  'miner capitulation': .85, 'whale dump': .9, 'dump': .8, 'dumps': .8,
  'warning': .5, 'risk': .35, 'pressure': .4, 'weak': .5, 'red': .35,
};

const _deskKeywords = <NewsDesk, List<String>>{
  NewsDesk.macro: [
    'fed', 'federal reserve', 'inflation', 'cpi', 'interest rate', 'rate cut',
    'rate hike', 'recession', 'dollar', 'treasury yield', 'jobs report',
    'powell', 'macro', 'gdp', 'stimulus', 'tariff',
  ],
  NewsDesk.regulation: [
    'sec', 'cftc', 'regulator', 'regulation', 'lawsuit', 'court', 'ban',
    'legislation', 'congress', 'senate', 'compliance', 'license', 'mica',
    'crackdown', 'subpoena', 'legal',
  ],
  NewsDesk.institutional: [
    'etf', 'blackrock', 'fidelity', 'grayscale', 'institutional', 'inflow',
    'outflow', 'microstrategy', 'strategy', 'corporate treasury', 'pension',
    'hedge fund', 'asset manager', 'custody', 'wall street',
  ],
  NewsDesk.onchain: [
    'on-chain', 'onchain', 'whale', 'wallet', 'supply', 'exchange reserve',
    'hodl', 'utxo', 'dormant', 'realized cap', 'mvrv', 'address', 'halving',
    'transfer', 'blockchain data',
  ],
  NewsDesk.security: [
    'hack', 'exploit', 'breach', 'stolen', 'phishing', 'ransom', 'malware',
    'vulnerability', 'bankruptcy', 'insolvency', 'fraud', 'scam', 'rug pull',
    'security incident',
  ],
  NewsDesk.adoption: [
    'adoption', 'payment', 'merchant', 'legal tender', 'remittance',
    'partnership', 'integration', 'users', 'country', 'city', 'bank offers',
    'retail', 'mainstream',
  ],
  NewsDesk.mining: [
    'mining', 'miner', 'miners', 'hashrate', 'hash rate', 'difficulty',
    'energy', 'asic', 'mining pool', 'electricity', 'rig',
  ],
  NewsDesk.derivatives: [
    'futures', 'options', 'funding rate', 'open interest', 'leverage',
    'liquidation', 'perpetual', 'basis', 'cme', 'derivatives', 'short squeeze',
    'long squeeze',
  ],
  NewsDesk.exchange: [
    'binance', 'coinbase', 'kraken', 'okx', 'bybit', 'exchange', 'listing',
    'delisting', 'order book', 'liquidity', 'trading volume', 'outage',
    'withdrawal',
  ],
  NewsDesk.sentiment: [
    'fear and greed', 'sentiment', 'analyst', 'prediction', 'forecast',
    'traders', 'market mood', 'social', 'survey', 'poll', 'outlook',
  ],
};

double _clamp1(double v) => v.isFinite ? v.clamp(-1.0, 1.0).toDouble() : 0.0;

double _unit(double v) => v.isFinite ? v.clamp(0.0, 1.0).toDouble() : 0.0;

double _sigmoid(double x) => 1 / (1 + math.exp(-x.clamp(-30.0, 30.0)));

double _std(List<double> x) {
  if (x.length < 2) return 0;
  var mean = 0.0;
  for (final v in x) {
    mean += v;
  }
  mean /= x.length;
  var acc = 0.0;
  for (final v in x) {
    final d = v - mean;
    acc += d * d;
  }
  final variance = acc / (x.length - 1);
  return variance <= 0 ? 0 : math.sqrt(variance);
}
