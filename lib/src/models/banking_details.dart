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

  factory BankingDetails.fromJson(Map<String, dynamic> json) => BankingDetails(
        bankName: (json['bankName'] ?? json['BankName']) as String? ?? '',
        accountNumber:
            (json['accountNumber'] ?? json['AccountNumber']) as String? ?? '',
        isIban: (json['isIban'] ?? json['IsIban']) as bool? ?? true,
        clearingNumber:
            (json['clearingNumber'] ?? json['ClearingNumber']) as String? ?? '',
        routingNumber:
            (json['routingNumber'] ?? json['RoutingNumber']) as String? ?? '',
        bicSwift: (json['bicSwift'] ?? json['BicSwift']) as String? ?? '',
        bankCountryIso3: _countryIso(json['bankCountry'] ?? json['BankCountry']),
        bankCountryName:
            _countryName(json['bankCountry'] ?? json['BankCountry']),
        beneficiary: Person.fromJson(
          ((json['beneficiary'] ?? json['Beneficiary']) as Map?)
                  ?.cast<String, dynamic>() ??
              {},
        ),
        beneficiaryAddress: Address.fromJson(
          ((json['beneficiaryAddress'] ?? json['BeneficiaryAddress']) as Map?)
                  ?.cast<String, dynamic>() ??
              {},
        ),
        bankAddress: Address.fromJson(
          ((json['bankAddress'] ?? json['BankAddress']) as Map?)
                  ?.cast<String, dynamic>() ??
              {},
        ),
      );

  Map<String, dynamic> toJson() => {
        'bankName': bankName,
        'bankCountry': bankCountryIso3.trim().isEmpty && bankCountryName.trim().isEmpty
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