import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/utils/form_validators.dart';

void main() {
  group('FormValidators', () {
    test('requires email', () {
      expect(FormValidators.email(''), isNotNull);
      expect(FormValidators.email('john@example.com'), isNull);
    });

    test('requires valid phone prefix and local number', () {
      expect(FormValidators.phonePrefix('+41'), isNull);
      expect(FormValidators.phonePrefix('41'), isNotNull);
      expect(FormValidators.phoneLocalNumber('44 123 45 67'), isNull);
      expect(FormValidators.phoneLocalNumber('abc'), isNotNull);
    });

    test('requires valid iban', () {
      expect(FormValidators.iban('CH93 0076 2011 6238 5295 7'), isNull);
      expect(FormValidators.iban('123'), isNotNull);
    });
  });
}
