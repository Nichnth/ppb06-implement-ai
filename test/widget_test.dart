import 'package:flutter_test/flutter_test.dart';
import 'package:colorcam/core/validators.dart';

void main() {
  group('InputValidators', () {
    test('validates email format', () {
      expect(InputValidators.email('not-an-email'), isNotNull);
      expect(InputValidators.email('user@example.com'), isNull);
    });

    test('validates password length', () {
      expect(InputValidators.password('1234567'), isNotNull);
      expect(InputValidators.password('12345678'), isNull);
    });

    test('validates password confirmation', () {
      expect(InputValidators.confirmPassword('', 'password123'), isNotNull);
      expect(InputValidators.confirmPassword('pass', 'password123'), isNotNull);
      expect(
        InputValidators.confirmPassword('password123', 'password123'),
        isNull,
      );
    });
  });
}
