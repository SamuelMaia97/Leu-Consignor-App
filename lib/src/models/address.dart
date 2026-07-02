class Address {
  Address({
    this.streetAddress = '',
    this.streetNumber = '',
    this.streetAddressOptional = '',
    this.postalCode = '',
    this.city = '',
    this.adminRegion = '',
    this.countryIso3 = '',
    this.countryName = '',
  });

  String streetAddress;
  String streetNumber;
  String streetAddressOptional;
  String postalCode;
  String city;
  String adminRegion;
  String countryIso3;
  String countryName;

  factory Address.fromJson(Map<String, dynamic> json) {
    final country = _firstValue(json, const [
      'country',
      'Country',
      'countryCode',
      'CountryCode',
      'isoCountryCode',
      'IsoCountryCode',
      'LAND',
      'Land',
    ]);

    return Address(
      streetAddress: _toString(
        _firstValue(json, const [
          'streetAddress',
          'StreetAddress',
          'street',
          'Street',
          'addressLine1',
          'AddressLine1',
          'STRASSE',
          'Strasse',
          'STREET',
        ]),
      ),
      streetNumber: _toString(
        _firstValue(json, const [
          'streetNumber',
          'StreetNumber',
          'houseNumber',
          'HouseNumber',
        ]),
      ),
      streetAddressOptional: _toString(
        _firstValue(json, const [
          'streetAddressOptional',
          'StreetAddressOptional',
          'addressLine2',
          'AddressLine2',
        ]),
      ),
      postalCode: _toString(
        _firstValue(json, const [
          'postalCode',
          'PostalCode',
          'zip',
          'Zip',
          'zipCode',
          'ZipCode',
          'PLZ',
        ]),
      ),
      city: _toString(
        _firstValue(json, const [
          'city',
          'City',
          'ORT',
          'Ort',
        ]),
      ),
      adminRegion: _toString(
        _firstValue(json, const [
          'adminregion',
          'adminRegion',
          'Adminregion',
          'AdminRegion',
          'state',
          'State',
          'region',
          'Region',
        ]),
      ),
      countryIso3: _countryIso(country),
      countryName: _countryName(country),
    );
  }

  Map<String, dynamic> toJson() => {
        'streetAddress': streetAddress,
        'streetAddressOptional': streetAddressOptional,
        'houseNumber': streetNumber,
        'postalCode': postalCode,
        'adminregion': adminRegion,
        'country': countryIso3.trim().isEmpty && countryName.trim().isEmpty
            ? null
            : {
                'isoCountryCode': countryIso3,
                'countryName': countryName,
              },
        'city': city,
      };

  String toSingleLine() {
    final parts = [
      [streetAddress, streetNumber].where((e) => e.trim().isNotEmpty).join(' '),
      streetAddressOptional,
      [postalCode, city].where((e) => e.trim().isNotEmpty).join(' '),
      adminRegion,
      countryName,
    ];
    return parts.where((e) => e.trim().isNotEmpty).join(', ');
  }

  static String _countryIso(Object? value) {
    if (value is Map) {
      return (value['isoCountryCode'] ??
                  value['IsoCountryCode'] ??
                  value['countryCode'] ??
                  value['CountryCode'])
              ?.toString() ??
          '';
    }
    if (value is String && _looksLikeCountryCode(value)) {
      return value.trim().toUpperCase();
    }
    return '';
  }

  static String _countryName(Object? value) {
    if (value is Map) {
      return (value['countryName'] ?? value['CountryName'])?.toString() ?? '';
    }
    if (value is String && !_looksLikeCountryCode(value)) {
      return value.trim();
    }
    return '';
  }

  static String _toString(Object? value) => value?.toString() ?? '';

  static Object? _firstValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      return value;
    }
    return null;
  }

  static bool _looksLikeCountryCode(String value) {
    final normalized = value.trim();
    return RegExp(r'^[A-Za-z]{2,3}$').hasMatch(normalized);
  }
}
