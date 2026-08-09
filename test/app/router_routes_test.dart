import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexora_markets_ai/app/router.dart';

void main() {
  test('Predicciones y Futuros conservan rutas independientes', () {
    final paths = appRouter.configuration.routes
        .whereType<GoRoute>()
        .map((route) => route.path)
        .toSet();

    expect(paths, contains('/pulse'));
    expect(paths, contains('/futures'));
  });
}
