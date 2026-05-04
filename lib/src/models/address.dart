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
    this.addressInfo = '',
  });

  String streetAddress;
  String streetNumber;
  String streetAddressOptional;
  String postalCode;
  String city;
  String adminRegion;
  String countryIso3;
  String countryName;
  String addressInfo;

  factory Address.fromJson(Map<String, dynamic> json) => Address(
        streetAddress:
            (json['streetAddress'] ?? json['StreetAddress']) as String? ?? '',
        streetNumber: (json['streetNumber'] ??
                json['houseNumber'] ??
                json['HouseNumber']) as String? ??
            '',
        streetAddressOptional: (json['streetAddressOptional'] ??
                json['StreetAddressOptional']) as String? ??
            '',
        postalCode: (json['postalCode'] ?? json['PostalCode']) as String? ?? '',
        city: (json['city'] ?? json['City']) as String? ?? '',
        adminRegion: (json['adminregion'] ??
                json['adminRegion'] ??
                json['Adminregion'] ??
                json['AdminRegion']) as String? ??
            '',
        countryIso3: _countryIso(json['country'] ?? json['Country']),
        countryName: _countryName(json['country'] ?? json['Country']),
        addressInfo:
            (json['addressinfo'] ?? json['addressInfo'] ?? json['Addressinfo']) as String? ?? '',
      );

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
        'addressinfo': addressInfo,
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
      return (value['isoCountryCode'] ?? value['IsoCountryCode'])?.toString() ?? '';
    }
    return '';
  }

  static String _countryName(Object? value) {
    if (value is Map) {
      return (value['countryName'] ?? value['CountryName'])?.toString() ?? '';
    }
    return '';
  }
}