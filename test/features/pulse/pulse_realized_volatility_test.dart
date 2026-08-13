import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/market/domain/candle.dart';
import 'package:nexora_markets_ai/features/pulse/domain/pulse_realized_volatility.dart';

void main() {
  const volatility = PulseRealizedVolatility();
  final start = DateTime.utc(2026, 8, 13, 12);

  List<Candle> series(List<double> closes) => <Candle>[
        for (var i = 0; i < closes.length; i++)
          Candle(
            openTime: start.add(Duration(minutes: i)),
            open: closes[i],
            high: closes[i],
            low: closes[i],
            close: closes[i],
            volume: 10,
          ),
      ];

  /// Deterministic zig-zag of a given amplitude in percent.
  List<double> wave(double amplitudePct, int length, {int seed = 7}) {
    final random = math.Random(seed);
    var price = 45000.0;
    return <double>[
      for (var i = 0; i < length; i++)
        price *= 1 + (random.nextBool() ? 1 : -1) * amplitudePct / 100,
    ];
  }

  group('realized volatility', () {
    test('a frozen price reports the floor, not zero', () {
      final sigma = volatility.ewmaPerMinutePct(
        series(List<double>.filled(90, 45000)),
      );

      expect(sigma, PulseRealizedVolatility.floorPct);
    });

    test('it recovers the amplitude it was given', () {
      final sigma = volatility.ewmaPerMinutePct(series(wave(.05, 120)));

      // Every step is exactly ±0.05%, so the standard deviation of the
      // returns is 0.05% up to the log approximation.
      expect(sigma, closeTo(.05, .004));
    });

    test('a louder market reports a wider sigma', () {
      final quiet = volatility.ewmaPerMinutePct(series(wave(.02, 120)));
      final loud = volatility.ewmaPerMinutePct(series(wave(.10, 120)));

      expect(loud, greaterThan(quiet * 3));
    });

    test('a jump moves bipower far less than it moves the plain estimate', () {
      final clean = wave(.03, 120);
      // A single violent print that does not come back: exactly one large
      // return, which is what bipower is built to survive. Two adjacent large
      // returns would defeat it by construction, and honestly so.
      final jumped = <double>[
        for (var i = 0; i < clean.length; i++)
          i < 90 ? clean[i] : clean[i] * 1.02,
      ];

      final plainRise = volatility.realizedPerMinutePct(series(jumped)) -
          volatility.realizedPerMinutePct(series(clean));
      final robustRise = volatility.bipowerPerMinutePct(series(jumped)) -
          volatility.bipowerPerMinutePct(series(clean));

      expect(plainRise, greaterThan(0));
      expect(robustRise, lessThan(plainRise / 2));
    });

    test('the plain estimate also recovers the amplitude', () {
      expect(
        volatility.realizedPerMinutePct(series(wave(.05, 120))),
        closeTo(.05, .006),
      );
    });

    test('sigma grows with the square root of the time left', () {
      final oneMinute = volatility.scale(.05, 60);
      final fourMinutes = volatility.scale(.05, 240);

      expect(fourMinutes / oneMinute, closeTo(2, 1e-9));
    });

    test('the horizon never collapses to zero', () {
      expect(
        volatility.scale(.05, 0),
        greaterThanOrEqualTo(PulseRealizedVolatility.floorPct),
      );
    });
  });
}
