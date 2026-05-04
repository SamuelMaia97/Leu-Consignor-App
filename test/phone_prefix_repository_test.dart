import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/phone_prefix.dart';
import 'package:leu_consignor_app/src/repositories/phone_prefix_repository.dart';

void main() {
  group('PhonePrefixRepository', () {
    test('keeps shared dial codes when origin ids differ', () {
      final repository = PhonePrefixRepository();
      final values = repository.normalize([
        const PhonePrefix(
          label: 'United States (+1)',
          dialCode: '+1',
          originId: 223,
        ),
        const PhonePrefix(
          label: 'Canada (+1)',
          dialCode: '+1',
          originId: 38,
        ),
      ]);

      expect(values, hasLength(2));
    });

    test('deduplicates the same origin id', () {
      final repository = PhonePrefixRepository();
      final values = repository.normalize([
        const PhonePrefix(
          label: 'Switzerland (+41)',
          dialCode: '+41',
          originId: 204,
        ),
        const PhonePrefix(
          label: 'Schweiz (+41)',
          dialCode: '+41',
          originId: 204,
        ),
      ]);

      expect(values, hasLength(1));
    });
  });
}
