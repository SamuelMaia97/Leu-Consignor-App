import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/country.dart';

void main() {
  group('Country', () {
    test('matches iso3 and iso2 codes', () {
      const country = Country(name: 'Switzerland', iso3: 'CHE', iso2: 'CH');

      expect(country.matchesCode('CHE'), isTrue);
      expect(country.matchesCode('CH'), isTrue);
      expect(country.matchesCode('DE'), isFalse);
    });
  });
}
