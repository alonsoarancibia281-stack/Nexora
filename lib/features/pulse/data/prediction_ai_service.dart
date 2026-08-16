import 'dart:convert';

import 'package:http/http.dart' as http;

/// Short second opinion from the Nexora model endpoint.
class AiSecondOpinion {
  const AiSecondOpinion({
    required this.direction,
    required this.confidence,
    required this.explanation,
    required this.provider,
  });

  /// 'up', 'down' or 'noTrade'.
  final String direction;
  final double confidence;
  final String explanation;
  final String provider;
}

/// Asks the hosted model to review what the desk already decided.
///
/// It is optional: without an endpoint the app works exactly the same, and the
/// answer never outweighs the local agents.
class PredictionAiService {
  const PredictionAiService({http.Client? client}) : _client = client;

  final http.Client? _client;
  static const _endpoint = String.fromEnvironment('NEXORA_AI_ENDPOINT');
  static const _anonKey = String.fromEnvironment('NEXORA_SUPABASE_ANON_KEY');

  bool get isConfigured =>
      _endpoint.trim().isNotEmpty && _anonKey.trim().isNotEmpty;

  Future<AiSecondOpinion?> review({
    required String symbol,
    required String horizon,
    required double startPrice,
    required double currentPrice,
    required int secondsRemaining,
    required Map<String, dynamic> desk,
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
              'symbol': symbol,
              'horizon': horizon,
              'startPrice': startPrice,
              'currentPrice': currentPrice,
              'secondsRemaining': secondsRemaining,
              'quantitative': desk,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final direction = switch ('${data['direction']}'.toLowerCase()) {
        'up' => 'up',
        'down' => 'down',
        _ => 'noTrade',
      };
      return AiSecondOpinion(
        direction: direction,
        confidence: ((data['confidence'] as num?)?.toDouble() ?? 50)
            .clamp(50.0, 90.0)
            .toDouble(),
        explanation: '${data['explanation'] ?? 'Sin nota adicional.'}',
        provider: '${data['provider'] ?? 'IA'}',
      );
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
