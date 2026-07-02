import 'address.dart';
import 'person.dart';

class BankingDetails {
  BankingDetails({
    this.bankName = '',
    this.accountNumber = '',
    this.isIban = true,
    this.clearingNumber = '',
    this.routingNumber = '',
    this.bicSwift = '',
    this.bankCountryIso3 = '',
    this.bankCountryName = '',
    Person? beneficiary,
    Address? beneficiaryAddress,
    Address? bankAddress,
  })  : beneficiary = beneficiary ?? Person(),
        beneficiaryAddress = beneficiaryAddress ?? Address(),
        bankAddress = bankAddress ?? Address();

  String bankName;
  String accountNumber;
  bool isIban;
  String clearingNumber;
  String routingNumber;
  String bicSwift;
  String bankCountryIso3;
  String bankCountryName;
  Person beneficiary;
  Address beneficiaryAddress;
  Address bankAddress;

  factory BankingDetails.fromJson(Map<String, dynamic> json) {
    final accountNumber = _toString(
      _firstValue(json, const [
        'accountNumber',
        'AccountNumber',
        'iban',
        'IBAN',
        'Iban',
        'bankAccount',
        'BankAccount',
        'KONTO',
        'Konto',
      ]),
    );
    final bankCountry = _firstValue(json, const [
      'bankCountry',
      'BankCountry',
      'bankCountryIso3',
      'BankCountryIso3',
      'bankCountryCode',
      'BankCountryCode',
      'BG_Land',
      'BG_LAND',
    ]);
    final bankCountryIso = _countryIso(bankCountry);
    final inferredBankCountryIso = bankCountryIso.trim().isEmpty
        ? _ibanCountryIso3(accountNumber)
        : bankCountryIso;
    final bankCountryName = _countryName(bankCountry);
    final inferredBankCountryName = bankCountryName.trim().isEmpty
        ? _countryNameFromIso3(inferredBankCountryIso)
        : bankCountryName;
    final bankAddressJson = _mapFromKeys(
      json,
      const {
        'streetAddress': [
          'bankAddressStreet',
          'BankAddressStreet',
          'BG_Strasse',
          'BG_STRASSE',
          'BG_STREET',
        ],
        'postalCode': [
          'bankAddressPostalCode',
          'BankAddressPostalCode',
          'BG_PLZ',
        ],
        'city': [
          'bankAddressCity',
          'BankAddressCity',
          'BG_Ort',
          'BG_ORT',
        ],
        'adminRegion': [
          'bankAddressAdminRegion',
          'BankAddressAdminRegion',
        ],
      },
    );

    return BankingDetails(
      bankName: _toString(
        _firstValue(json, const [
          'bankName',
          'BankName',
          'bank',
          'Bank',
          'BG_NAME',
          'BG_Name',
        ]),
      ),
      accountNumber: accountNumber,
      isIban: _toBool(_firstValue(json, const ['isIban', 'IsIban'])) ??
          _looksLikeIban(accountNumber),
      clearingNumber: _toString(
        _firstValue(json, const [
          'clearingNumber',
          'ClearingNumber',
          'clearingNo',
          'ClearingNo',
          'BLZ',
        ]),
      ),
      routingNumber: _toString(
        _firstValue(json, const [
          'routingNumber',
          'RoutingNumber',
          'routingNo',
          'RoutingNo',
        ]),
      ),
      bicSwift: _toString(
        _firstValue(json, const [
          'bicSwift',
          'BicSwift',
          'bic',
          'BIC',
          'swift',
          'SWIFT',
        ]),
      ),
      bankCountryIso3: inferredBankCountryIso,
      bankCountryName: inferredBankCountryName,
      beneficiary: Person.fromJson(
        _firstMap(json, const ['beneficiary', 'Beneficiary']) ??
            const <String, dynamic>{},
      ),
      beneficiaryAddress: Address.fromJson(
        _firstMap(
              json,
              const ['beneficiaryAddress', 'BeneficiaryAddress'],
            ) ??
            const <String, dynamic>{},
      ),
      bankAddress: Address.fromJson(
        _firstMap(json, const ['bankAddress', 'BankAddress']) ??
            bankAddressJson,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'bankName': bankName,
        'bankCountry':
            bankCountryIso3.trim().isEmpty && bankCountryName.trim().isEmpty
                ? null
                : {
                    'isoCountryCode': bankCountryIso3,
                    'countryName': bankCountryName,
                  },
        'bankAddress': bankAddress.toJson(),
        'accountNumber': accountNumber,
        'isIban': isIban,
        'bicSwift': bicSwift,
        'clearingNumber': clearingNumber.isEmpty ? null : clearingNumber,
        'routingNumber': routingNumber.isEmpty ? null : routingNumber,
        'beneficiary': beneficiary.toJson(),
        'beneficiaryAddress': beneficiaryAddress.toJson(),
      };

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

  static bool? _toBool(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return null;
  }

  static Object? _firstValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      return value;
    }
    return null;
  }

  static Map<String, dynamic>? _firstMap(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value is Map) {
        return value.cast<String, dynamic>();
      }
    }
    return null;
  }

  static Map<String, dynamic> _mapFromKeys(
    Map<String, dynamic> json,
    Map<String, List<String>> keyAliases,
  ) {
    final mapped = <String, dynamic>{};
    for (final entry in keyAliases.entries) {
      final value = _firstValue(json, entry.value);
      if (value != null) {
        mapped[entry.key] = value;
      }
    }
    return mapped;
  }

  static bool _looksLikeIban(String value) {
    return RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{8,}$')
        .hasMatch(value.replaceAll(RegExp(r'\s+'), '').toUpperCase());
  }

  static String _ibanCountryIso3(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (!_looksLikeIban(normalized)) return '';
    return _iso2ToIso3(normalized.substring(0, 2));
  }

  static String _iso2ToIso3(String iso2) {
    switch (iso2.trim().toUpperCase()) {
      case 'AD':
        return 'AND';
      case 'AT':
        return 'AUT';
      case 'BE':
        return 'BEL';
      case 'CH':
        return 'CHE';
      case 'DE':
        return 'DEU';
      case 'ES':
        return 'ESP';
      case 'FR':
        return 'FRA';
      case 'GB':
        return 'GBR';
      case 'IT':
        return 'ITA';
      case 'LI':
        return 'LIE';
      case 'LU':
        return 'LUX';
      case 'MC':
        return 'MCO';
      case 'NL':
        return 'NLD';
      case 'PT':
        return 'PRT';
      default:
        return iso2.trim().toUpperCase();
    }
  }

  static String _countryNameFromIso3(String iso3) {
    switch (iso3.trim().toUpperCase()) {
      case 'AUT':
        return 'Austria';
      case 'CHE':
        return 'Switzerland';
      case 'DEU':
        return 'Germany';
      case 'FRA':
        return 'France';
      case 'GBR':
        return 'United Kingdom';
      case 'ITA':
        return 'Italy';
      case 'LIE':
        return 'Liechtenstein';
      default:
        return '';
    }
  }

  static bool _looksLikeCountryCode(String value) {
    return RegExp(r'^[A-Za-z]{2,3}$').hasMatch(value.trim());
  }
}
