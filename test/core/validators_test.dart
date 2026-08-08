import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/core/validators.dart';
void main(){group('Validators',(){test('accepts strong password',()=>expect(Validators.password('Nexora#2026'),isNull));test('rejects weak password',()=>expect(Validators.password('password'),isNotNull));test('validates email',(){expect(Validators.email('user@example.com'),isNull);expect(Validators.email('bad-email'),isNotNull);});});}
