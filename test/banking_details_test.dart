import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/banking_details.dart';
import 'package:leu_consignor_app/src/models/consignor.dart';

void main() {
  group('Banking field cleanup', () {
    test('consignor payload keeps the normalized account number fields', () {
      final consignor = Consignor.empty()
        ..bankingDetails.accountNumber = 'CH9300762011623852957'
        ..bankingDetails.isIban = true
        ..bankingDetails.clearingNumber = ''
        ..bankingDetails.bicSwift = '';

      final banking =
          consignor.toJson()['bankingDetails'] as Map<String, dynamic>;

      expect(banking['accountNumber'], 'CH9300762011623852957');
      expect(banking['isIban'], isTrue);
      expect(banking['clearingNumber'], isNull);
      expect(banking['bicSwift'], '');
    });

    test('bank country is inferred from a Swiss IBAN when missing', () {
      final banking = BankingDetails.fromJson(const {
        'accountNumber': 'CH9300762011623852957',
        'isIban': true,
      });

      expect(banking.bankCountryIso3, 'CHE');
      expect(banking.bankCountryName, 'Switzerland');
    });

    test('bank country normalizes Swiss ISO2 code to ISO3', () {
      final banking = BankingDetails.fromJson(const {
        'accountNumber': 'CH9300762011623852957',
        'BG_LAND': 'CH',
      });

      expect(banking.bankCountryIso3, 'CHE');
      expect(banking.bankCountryName, 'Switzerland');
    });

    test('numeric bank country identifiers are not treated as country names',
        () {
      final banking = BankingDetails.fromJson(const {
        'accountNumber': 'CH9300762011623852957',
        'BG_LAND': '1',
      });

      expect(banking.bankCountryIso3, 'CHE');
      expect(banking.bankCountryName, 'Switzerland');
    });
  });
}
