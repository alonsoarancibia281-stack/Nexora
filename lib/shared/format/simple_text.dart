/// Short, plain numbers.
///
/// Nexora shows one idea per number: no long decimals, no scientific notation
/// and no numbers the eye cannot read at a glance.
class Simple {
  const Simple._();

  /// 0.62 -> '62%'
  static String percent(double fraction) => '${(fraction * 100).round()}%';

  /// 62.4 -> '62%'
  static String percentPoints(double points) => '${points.round()}%';

  /// 0.1234 -> '+0.12%'
  static String signedPercent(double percentValue, {int decimals = 2}) {
    final sign = percentValue >= 0 ? '+' : '';
    return '$sign${percentValue.toStringAsFixed(decimals)}%';
  }

  /// 64918.42 -> '64.918'
  static String price(double value) {
    if (value <= 0) return '--';
    if (value >= 1000) return _thousands(value.round());
    if (value >= 1) return value.toStringAsFixed(2);
    return value.toStringAsFixed(5);
  }

  /// 64918 -> '64.918'
  static String _thousands(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Local clock, '14:35'.
  static String clock(DateTime time) {
    final local = time.toLocal();
    return '${_two(local.hour)}:${_two(local.minute)}';
  }

  /// Local clock with seconds, '14:35:00'.
  static String clockSeconds(DateTime time) {
    final local = time.toLocal();
    return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
  }

  /// 299 -> '04:59'
  static String countdown(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final minutes = safe ~/ 60;
    return '${_two(minutes)}:${_two(safe % 60)}';
  }

  /// 3725 -> '1h 02m'
  static String duration(int seconds) {
    if (seconds < 3600) return countdown(seconds);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${hours}h ${_two(minutes)}m';
  }

  /// '3 de 5'
  static String outOf(int hits, int total) => '$hits de $total';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
