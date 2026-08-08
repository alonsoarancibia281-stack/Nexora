import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/pulse_ai_consensus.dart';
import '../domain/pulse_signal.dart';

class PulseAiService {
  const PulseAiService({http.Client? client}) : _client = client;

  final http.Client? _client;
  static const _endpoint = String.fromEnvironment('NEXORA_AI_ENDPOINT');

  bool get isConfigured => _endpoint.trim().isNotEmpty;

  Future<PulseAiConsensus?> evaluate({
    required String symbol,
    required double startPrice,
    required double currentPrice,
    required int secondsRemaining,
    required PulseSignal quantitative,
  }) async {
    if (!isConfigured) return null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse(_endpoint),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'symbol': symbol,
              'startPrice': startPrice,
              'currentPrice': currentPrice,
              'secondsRemaining': secondsRemaining,
              'quantitative': {
                'direction': quantitative.direction.name,
                'score': quantitative.score,
                'confidence': quantitative.confidence,
                'momentumScore': quantitative.momentumScore,
                'trendScore': quantitative.trendScore,
                'orderBookImbalance': quantitative.orderBookImbalance,
                'volumeRatio': quantitative.volumeRatio,
                'bodyPressure': quantitative.bodyPressure,
              },
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final direction = switch ('${data['direction']}'.toLowerCase()) {
        'up' => PulseDirection.up,
        'down' => PulseDirection.down,
        _ => PulseDirection.noTrade,
      };
      final confidence = (data['confidence'] as num?)?.toDouble() ?? 50.0;
      return PulseAiConsensus(
        direction: direction,
        confidence: confidence.clamp(50.0, 90.0).toDouble(),
        explanation: '${data['explanation'] ?? 'Sin explicación adicional.'}',
        provider: '${data['provider'] ?? 'AI'}',
      );
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
