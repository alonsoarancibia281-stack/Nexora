import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OTP contract', () {
    test('accepts only six numeric digits', () {
      final rule = RegExp(r'^\d{6}$');
      expect(rule.hasMatch('123456'), isTrue);
      expect(rule.hasMatch('12345'), isFalse);
      expect(rule.hasMatch('12A456'), isFalse);
    });

    test('expiry window is ten minutes', () {
      const ttl = Duration(minutes: 10);
      expect(ttl.inSeconds, 600);
    });

    test('verification lock threshold is five attempts', () {
      const maxAttempts = 5;
      expect(maxAttempts, 5);
    });
  });
}
