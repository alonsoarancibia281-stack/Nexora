import 'pulse_signal.dart';

class PulseAiConsensus {
  const PulseAiConsensus({
    required this.direction,
    required this.confidence,
    required this.explanation,
    required this.provider,
  });

  final PulseDirection direction;
  final double confidence;
  final String explanation;
  final String provider;
}
