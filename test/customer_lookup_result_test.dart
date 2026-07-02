import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/domain/consignor_type.dart';
import 'package:leu_consignor_app/src/models/customer_lookup_result.dart';

void main() {
  group('CustomerLookupResult', () {
    test('prefills company rows from their contact person', () {
      final result = CustomerLookupResult.fromJson({
        'customerId': 115015,
        'displayLabel': 'Samuel Maia, Leu Numismatik AG',
        'prefill': {
          'id': 115015,
          'NAME': 'Leu Numismatik AG',
          'emailAddress': 'info@leunumismatik.com',
          'contactPerson': {
            'id': 119402,
            'firstName': 'Samuel',
            'lastName': 'Maia',
            'emailAddress': 'samuel.maia@example.test',
            'phoneNumber': '+41 44 123 45 67',
          },
        },
      });

      expect(result.customerId, 115015);
      expect(result.prefill.existingCustomerId, 115015);
      expect(result.prefill.systemReferenceCustomer, 115015);
      expect(result.prefill.consignorType, ConsignorType.legalEntity);
      expect(result.prefill.tradingName, 'Leu Numismatik AG');
      expect(result.prefill.consignorInfo.firstName, 'Samuel');
      expect(result.prefill.consignorInfo.lastName, 'Maia');
      expect(result.prefill.emailAddress, 'samuel.maia@example.test');
      expect(result.prefill.phonePrefix, '+41');
      expect(result.prefill.phoneNumber, '44 123 45 67');
    });

    test('uses contact person data beside the prefill object', () {
      final result = CustomerLookupResult.fromJson({
        'customerId': 115015,
        'displayLabel': 'Samuel Maia, Leu Numismatik AG',
        'ContactPerson': {
          'FirstName': 'Samuel',
          'LastName': 'Maia',
          'EmailAddress': 'samuel.maia@example.test',
        },
        'prefill': {
          'Id': 115015,
          'TradingName': 'Leu Numismatik AG',
          'EmailAddress': 'company@example.test',
        },
      });

      expect(result.prefill.consignorType, ConsignorType.legalEntity);
      expect(result.prefill.tradingName, 'Leu Numismatik AG');
      expect(result.prefill.consignorInfo.firstName, 'Samuel');
      expect(result.prefill.consignorInfo.lastName, 'Maia');
      expect(result.prefill.emailAddress, 'samuel.maia@example.test');
    });

    test('prefills Abacus-style flat banking fields', () {
      final result = CustomerLookupResult.fromJson({
        'customerId': 116505,
        'displayLabel': 'Bank Customer',
        'prefill': {
          'customerId': 116505,
          'VORNAME': 'Anna',
          'NAME': 'Bank',
          'EMAIL': 'anna.bank@example.test',
          'TEL': '+41 44 555 66 77',
          'STREET': 'Bankstrasse 1',
          'PLZ': '8000',
          'ORT': 'Zurich',
          'LAND': 'CHE',
          'BG_NAME': 'Abacus Maintained Bank',
          'KONTO': 'CH9300762011623852957',
          'BIC': 'POFICHBEXXX',
          'BG_LAND': 'CHE',
        },
      });

      expect(result.prefill.consignorInfo.firstName, 'Anna');
      expect(result.prefill.consignorInfo.lastName, 'Bank');
      expect(result.prefill.emailAddress, 'anna.bank@example.test');
      expect(result.prefill.consignorAddress.streetAddress, 'Bankstrasse 1');
      expect(result.prefill.consignorAddress.postalCode, '8000');
      expect(result.prefill.consignorAddress.city, 'Zurich');
      expect(result.prefill.consignorAddress.countryIso3, 'CHE');
      expect(result.prefill.bankingDetails.bankName, 'Abacus Maintained Bank');
      expect(
          result.prefill.bankingDetails.accountNumber, 'CH9300762011623852957');
      expect(result.prefill.bankingDetails.isIban, isTrue);
      expect(result.prefill.bankingDetails.bicSwift, 'POFICHBEXXX');
      expect(result.prefill.bankingDetails.bankCountryIso3, 'CHE');
    });
  });
}
