import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/consignor.dart';

void main() {
  group('Banking field cleanup', () {
    test('consignor payload only requires IBAN from the banking form', () {
      final consignor = Consignor.empty()
        ..bankingDetails.accountNumber = 'CH9300762011623852957'
        ..bankingDetails.isIban = true
        ..bankingDetails.clearingNumber = ''
        ..bankingDetails.bicSwift = '';

      final banking = consignor.toJson()['bankingDetails'] as Map<String, dynamic>;

      expect(banking['accountNumber'], 'CH9300762011623852957');
      expect(banking['isIban'], isTrue);
      expect(banking['clearingNumber'], isNull);
      expect(banking['bicSwift'], '');
    });
  });
}
