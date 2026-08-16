import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/scan_candidate.dart';
import '../domain/setup_strategy.dart';

/// What Claude reads back from the numbers.
class ResearchNote {
  const ResearchNote({
    required this.why,
    required this.money,
    required this.watch,
    required this.risk,
    required this.grade,
    required this.provider,
  });

  /// Why the price is moving.
  final String why;

  /// What the money is doing.
  final String money;

  /// What to watch next.
  final String watch;

  /// The main risk.
  final String risk;

  /// 'fuerte', 'normal' or 'flojo'.
  final String grade;

  final String provider;

  bool get isStrong => grade == 'fuerte';
}

/// Step 02: the research call.
///
/// The model only ever sees the numbers below. It has no news feed, so the
/// note explains the move from price, volume and liquidity — never from
/// events it cannot know about.
class ResearchService {
  const ResearchService({http.Client? client}) : _client = client;

  final http.Client? _client;
  static const _endpoint = String.fromEnvironment('NEXORA_RESEARCH_ENDPOINT');
  static const _anonKey = String.fromEnvironment('NEXORA_SUPABASE_ANON_KEY');

  bool get isConfigured =>
      _endpoint.trim().isNotEmpty && _anonKey.trim().isNotEmpty;

  Future<ResearchNote?> review({
    required ScanCandidate candidate,
    StrategyReport? play,
  }) async {
    if (!isConfigured) return null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'apikey': _anonKey,
              'authorization': 'Bearer $_anonKey',
            },
            body: jsonEncode({
              'symbol': candidate.symbol,
              'price': candidate.price,
              'changePercent24h': candidate.changePercent24h,
              'weekChangePercent': candidate.weekChangePercent,
              'monthChangePercent': candidate.monthChangePercent,
              'quoteVolume24h': candidate.quoteVolume24h,
              'volumeSurge': candidate.volumeSurge,
              'distanceFromMonthHighPercent':
                  candidate.distanceFromMonthHighPercent,
              'upDayRatio': candidate.upDayRatio,
              'atrPercent': candidate.atrPercent,
              'strength': candidate.strength,
              'strategy': play?.strategy.name,
              'hitRate': play?.record.hitRate,
              'trades': play?.record.trades,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ResearchNote(
        why: '${data['why'] ?? ''}',
        money: '${data['money'] ?? ''}',
        watch: '${data['watch'] ?? ''}',
        risk: '${data['risk'] ?? ''}',
        grade: '${data['grade'] ?? 'normal'}',
        provider: '${data['provider'] ?? 'Claude'}',
      );
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
