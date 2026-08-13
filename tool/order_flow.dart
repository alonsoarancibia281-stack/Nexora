// Historical order-flow reconstruction from Binance public data dumps.
//
// The order book itself is not published historically — depth snapshots exist
// only live — but every executed trade is, at
// data.binance.vision/data/spot/daily/aggTrades. That covers the half of the
// microstructure the trade-flow desk actually reads: who crossed the spread,
// how hard, how persistently and in what size.
//
// Trades are streamed straight into fixed time buckets instead of being kept
// in memory: a single day of BTCUSDT is several million rows and the features
// only ever need aggregates.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Everything that happened in one slice of the tape.
class FlowBucket {
  double buyVolume = 0;
  double sellVolume = 0;
  int buyTrades = 0;
  int sellTrades = 0;
  double firstPrice = 0;
  double lastPrice = 0;

  /// Signed volume restricted to unusually large prints.
  double largeSigned = 0;
  double largeVolume = 0;

  double get volume => buyVolume + sellVolume;

  double get signed => buyVolume - sellVolume;

  int get trades => buyTrades + sellTrades;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'b': buyVolume,
        's': sellVolume,
        'bt': buyTrades,
        'st': sellTrades,
        'f': firstPrice,
        'l': lastPrice,
        'ls': largeSigned,
        'lv': largeVolume,
      };

  static FlowBucket fromJson(Map<String, dynamic> json) => FlowBucket()
    ..buyVolume = (json['b'] as num).toDouble()
    ..sellVolume = (json['s'] as num).toDouble()
    ..buyTrades = (json['bt'] as num).toInt()
    ..sellTrades = (json['st'] as num).toInt()
    ..firstPrice = (json['f'] as num).toDouble()
    ..lastPrice = (json['l'] as num).toDouble()
    ..largeSigned = (json['ls'] as num).toDouble()
    ..largeVolume = (json['lv'] as num).toDouble();
}

/// The microstructure the engine would have seen at one instant.
class FlowSnapshot {
  const FlowSnapshot({
    required this.aggressorImbalance,
    required this.signedVolume,
    required this.tradeAcceleration,
    required this.priceImpulseBps,
    required this.flowPersistence,
    required this.largeTradeBias,
    required this.trades,
  });

  final double aggressorImbalance;
  final double signedVolume;
  final double tradeAcceleration;
  final double priceImpulseBps;
  final double flowPersistence;
  final double largeTradeBias;
  final int trades;

  static const FlowSnapshot empty = FlowSnapshot(
    aggressorImbalance: 0,
    signedVolume: 0,
    tradeAcceleration: 0,
    priceImpulseBps: 0,
    flowPersistence: 0,
    largeTradeBias: 0,
    trades: 0,
  );
}

/// Bucketed tape for a range of days.
class FlowBook {
  FlowBook(this.buckets);

  /// Key is epoch second ÷ [bucketSeconds].
  final Map<int, FlowBucket> buckets;

  static const int bucketSeconds = 10;

  /// A print at or above this size counts as a large order. Fixed rather than
  /// percentile-based so the definition cannot drift between days.
  static const double largeTradeBtc = .5;

  bool get isEmpty => buckets.isEmpty;

  int get bucketCount => buckets.length;

  /// Reconstructs what the trade-flow desk would have read at [moment],
  /// looking back over [windowSeconds] and using only buckets that closed.
  FlowSnapshot at(DateTime moment, {int windowSeconds = 60}) {
    final end = moment.millisecondsSinceEpoch ~/ 1000 ~/ bucketSeconds;
    final span = windowSeconds ~/ bucketSeconds;
    if (span < 2) return FlowSnapshot.empty;

    var buy = 0.0, sell = 0.0, largeSigned = 0.0, largeVolume = 0.0;
    var trades = 0;
    var firstPrice = 0.0, lastPrice = 0.0;
    var aligned = 0, decided = 0;
    var priorVolume = 0.0, windowVolume = 0.0;

    for (var i = span; i >= 1; i--) {
      final bucket = buckets[end - i];
      if (bucket == null) continue;
      buy += bucket.buyVolume;
      sell += bucket.sellVolume;
      trades += bucket.trades;
      largeSigned += bucket.largeSigned;
      largeVolume += bucket.largeVolume;
      windowVolume += bucket.volume;
      if (firstPrice == 0 && bucket.firstPrice > 0) firstPrice = bucket.firstPrice;
      if (bucket.lastPrice > 0) lastPrice = bucket.lastPrice;
    }
    for (var i = span * 2; i > span; i--) {
      priorVolume += buckets[end - i]?.volume ?? 0;
    }

    if (trades == 0) return FlowSnapshot.empty;

    final total = buy + sell;
    final imbalance =
        total <= 0 ? 0.0 : ((buy - sell) / total).clamp(-1.0, 1.0).toDouble();

    // Persistence: how many ten-second slices leaned the same way as the
    // window as a whole. A cleaner measure than trade-by-trade runs and it
    // survives the bucketing.
    for (var i = span; i >= 1; i--) {
      final bucket = buckets[end - i];
      if (bucket == null || bucket.signed == 0) continue;
      decided++;
      if (bucket.signed.sign == imbalance.sign) aligned++;
    }
    final persistence = decided == 0
        ? 0.0
        : ((aligned / decided) * 2 - 1).clamp(-1.0, 1.0) * imbalance.sign;

    final acceleration = priorVolume <= 0
        ? 0.0
        : ((windowVolume / priorVolume) - 1).clamp(-1.0, 1.0).toDouble();

    final impulse = firstPrice <= 0
        ? 0.0
        : ((lastPrice - firstPrice) / firstPrice * 10000)
            .clamp(-20.0, 20.0)
            .toDouble();

    return FlowSnapshot(
      aggressorImbalance: imbalance,
      signedVolume: imbalance,
      tradeAcceleration: acceleration,
      priceImpulseBps: impulse,
      flowPersistence: persistence.toDouble(),
      largeTradeBias: largeVolume <= 0
          ? 0.0
          : (largeSigned / largeVolume).clamp(-1.0, 1.0).toDouble(),
      trades: trades,
    );
  }
}

/// Downloads, unzips and buckets the daily aggTrades dumps.
class OrderFlowLoader {
  const OrderFlowLoader({this.cacheDir = '.backtest-cache/flow'});

  final String cacheDir;

  static const _base = 'https://data.binance.vision/data/spot/daily/aggTrades';

  /// Loads the [days] most recent days that are actually published, ending at
  /// [endingBefore] (defaults to yesterday, since today is still open).
  Future<FlowBook> load(
    String symbol,
    int days, {
    DateTime? endingBefore,
  }) async {
    final buckets = <int, FlowBucket>{};
    final anchor = (endingBefore ?? DateTime.now().toUtc())
        .subtract(const Duration(days: 1));
    var loaded = 0;
    for (var back = 0; back < days + 4 && loaded < days; back++) {
      final day = DateTime.utc(anchor.year, anchor.month, anchor.day)
          .subtract(Duration(days: back));
      final ok = await _loadDay(symbol, day, buckets);
      if (ok) loaded++;
    }
    stdout.writeln('  flujo: $loaded días · ${buckets.length} tramos de '
        '${FlowBook.bucketSeconds}s');
    return FlowBook(buckets);
  }

  Future<bool> _loadDay(
    String symbol,
    DateTime day,
    Map<int, FlowBucket> into,
  ) async {
    final stamp = '${day.year}-${_two(day.month)}-${_two(day.day)}';
    final cache = File('$cacheDir/${symbol}_$stamp.json');
    if (cache.existsSync()) {
      try {
        final rows = jsonDecode(cache.readAsStringSync()) as Map<String, dynamic>;
        rows.forEach((key, value) {
          into[int.parse(key)] =
              FlowBucket.fromJson(value as Map<String, dynamic>);
        });
        stdout.writeln('  flujo $stamp: desde caché');
        return true;
      } catch (_) {
        // Fall through and re-download.
      }
    }

    final url = '$_base/$symbol/$symbol-aggTrades-$stamp.zip';
    final tempDir = Directory.systemTemp.createTempSync('flow');
    final zip = File('${tempDir.path}/$stamp.zip');
    try {
      stdout.write('  flujo $stamp: descargando…');
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) {
        stdout.writeln(' no disponible (${response.statusCode})');
        return false;
      }
      zip.writeAsBytesSync(response.bodyBytes);
      final unzip = await Process.run(
        'unzip',
        ['-o', '-q', zip.path, '-d', tempDir.path],
      );
      if (unzip.exitCode != 0) {
        stdout.writeln(' unzip falló: ${unzip.stderr}');
        return false;
      }

      final csv = tempDir
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.csv'));
      final dayBuckets = <int, FlowBucket>{};
      var rows = 0;
      final lines = csv
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.isEmpty) continue;
        final parts = line.split(',');
        if (parts.length < 7) continue;
        final price = double.tryParse(parts[1]);
        final qty = double.tryParse(parts[2]);
        var timestamp = int.tryParse(parts[5]);
        if (price == null || qty == null || timestamp == null) {
          continue; // header row
        }
        // Some dumps switched to microsecond timestamps.
        if (timestamp > 100000000000000) timestamp = timestamp ~/ 1000;
        final buyerMaker = parts[6].trim().toLowerCase() == 'true';

        final key = timestamp ~/ 1000 ~/ FlowBook.bucketSeconds;
        final bucket = dayBuckets.putIfAbsent(key, FlowBucket.new);
        if (bucket.firstPrice == 0) bucket.firstPrice = price;
        bucket.lastPrice = price;
        // buyerMaker true means the aggressor sold into the bid.
        if (buyerMaker) {
          bucket.sellVolume += qty;
          bucket.sellTrades++;
          if (qty >= FlowBook.largeTradeBtc) {
            bucket.largeSigned -= qty;
            bucket.largeVolume += qty;
          }
        } else {
          bucket.buyVolume += qty;
          bucket.buyTrades++;
          if (qty >= FlowBook.largeTradeBtc) {
            bucket.largeSigned += qty;
            bucket.largeVolume += qty;
          }
        }
        rows++;
      }

      into.addAll(dayBuckets);
      Directory(cacheDir).createSync(recursive: true);
      cache.writeAsStringSync(jsonEncode(<String, dynamic>{
        for (final entry in dayBuckets.entries)
          '${entry.key}': entry.value.toJson(),
      }));
      stdout.writeln(' $rows trades → ${dayBuckets.length} tramos');
      return true;
    } catch (error) {
      stdout.writeln(' error: $error');
      return false;
    } finally {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Best effort.
      }
    }
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

/// Earliest and latest instant the book has data for.
({DateTime from, DateTime to})? flowRange(FlowBook book) {
  if (book.isEmpty) return null;
  var lo = 1 << 62;
  var hi = 0;
  for (final key in book.buckets.keys) {
    lo = math.min(lo, key);
    hi = math.max(hi, key);
  }
  return (
    from: DateTime.fromMillisecondsSinceEpoch(
      lo * FlowBook.bucketSeconds * 1000,
      isUtc: true,
    ),
    to: DateTime.fromMillisecondsSinceEpoch(
      hi * FlowBook.bucketSeconds * 1000,
      isUtc: true,
    ),
  );
}
