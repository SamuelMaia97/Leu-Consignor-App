import '../models/address.dart';

class AddressFormatter {
  const AddressFormatter._();

  static List<String> contractLines(Address address) {
    final line1 = streetLine(address);
    final line2 = address.streetAddressOptional.trim();
    final line3 = localityLine(address);

    return [line1, line2, line3]
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
  }

  static String contractLine(Address address, int index) {
    final lines = contractLines(address);
    return index < lines.length ? lines[index] : '';
  }

  static String streetLine(Address address) {
    final street = address.streetAddress.trim();
    final number = address.streetNumber.trim();
    if (street.isEmpty) return number;
    if (number.isEmpty) return street;

    if (_usesStreetNumberFirst(address)) {
      return '$number $street';
    }
    return '$street $number';
  }

  static String localityLine(Address address) {
    final countryIso = address.countryIso3.trim().toUpperCase();
    final countryName = address.countryName.trim();
    final city = address.city.trim();
    final region = address.adminRegion.trim();
    final postalCode = address.postalCode.trim();

    final locality = switch (countryIso) {
      'USA' || 'CAN' || 'AUS' || 'NZL' => _joinNonEmpty([
          city,
          _joinNonEmpty([region, postalCode], separator: ' '),
        ], separator: ', '),
      'GBR' || 'IRL' => _joinNonEmpty([city, postalCode], separator: ' '),
      _ => _joinNonEmpty([
          _joinNonEmpty([postalCode, city], separator: ' '),
          region,
        ], separator: ', '),
    };

    return _joinNonEmpty([locality, countryName], separator: ', ');
  }

  static bool _usesStreetNumberFirst(Address address) {
    final countryIso = address.countryIso3.trim().toUpperCase();
    if (const {'USA', 'CAN', 'GBR', 'IRL', 'AUS', 'NZL'}.contains(countryIso)) {
      return true;
    }

    final countryName = address.countryName.trim().toLowerCase();
    return const {
      'united states',
      'usa',
      'canada',
      'united kingdom',
      'great britain',
      'ireland',
      'australia',
      'new zealand',
    }.contains(countryName);
  }

  static String _joinNonEmpty(
    Iterable<String> values, {
    required String separator,
  }) {
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(separator);
  }
}
