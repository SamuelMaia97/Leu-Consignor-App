import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/utils/phone_number_parser.dart';

void main() {
  group('PhoneNumberParser', () {
    test('splits full number into prefix and local number', () {
      final parsed = PhoneNumberParser.parse('+41 44 123 45 67');
      expect(parsed.prefix, '+41');
      expect(parsed.localNumber, '44 123 45 67');
    });

    test('combines prefix and local number', () {
      expect(
        PhoneNumberParser.combine(prefix: '+49', localNumber: '89 1234 5678'),
        '+49 89 1234 5678',
      );
    });

    test('does not duplicate an existing country prefix', () {
      expect(
        PhoneNumberParser.combine(
          prefix: '+41',
          localNumber: '+41 44 123 45 67',
        ),
        '+41 44 123 45 67',
      );
    });
  });
}
