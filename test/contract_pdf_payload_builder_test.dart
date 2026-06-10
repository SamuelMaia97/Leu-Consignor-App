import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/domain/consignor_type.dart';
import 'package:leu_consignor_app/src/models/consignor.dart';
import 'package:leu_consignor_app/src/models/contract_record.dart';
import 'package:leu_consignor_app/src/services/contract_pdf_service.dart';

void main() {
  group('ContractPdfPayloadBuilder paragraph mapping', () {
    const builder = ContractPdfPayloadBuilder();

    final cases = <_ScenarioCase>[
      _ScenarioCase(
        name: 'Privatperson durch sich',
        consignorType: ConsignorType.naturalPerson,
        scenario: 'NaturalPersonSelf',
        expectedVisible: {4, 9, 13, 17, 22},
      ),
      _ScenarioCase(
        name: 'Privatperson durch bevollmaechtigte Person',
        consignorType: ConsignorType.naturalPerson,
        representativeType: ConsignorType.naturalPerson,
        scenario: 'NaturalPersonThroughNaturalRepresentative',
        expectedVisible: {4, 7, 10, 13, 15, 18, 23},
      ),
      _ScenarioCase(
        name: 'Privatperson durch bevollmaechtigte jur. Person',
        consignorType: ConsignorType.naturalPerson,
        representativeType: ConsignorType.legalEntity,
        scenario: 'NaturalPersonThroughLegalRepresentative',
        expectedVisible: {4, 7, 8, 11, 13, 15, 16, 20, 23},
      ),
      _ScenarioCase(
        name: 'jur. Person durch bevollmaechtigte Person',
        consignorType: ConsignorType.legalEntity,
        representativeType: ConsignorType.naturalPerson,
        scenario: 'LegalEntityThroughNaturalRepresentative',
        expectedVisible: {5, 6, 7, 11, 13, 14, 15, 21, 23},
      ),
      _ScenarioCase(
        name: 'jur. Person durch bevollmaechtigte jur. Person',
        consignorType: ConsignorType.legalEntity,
        representativeType: ConsignorType.legalEntity,
        scenario: 'LegalEntityThroughLegalRepresentative',
        expectedVisible: {5, 6, 7, 8, 12, 13, 14, 15, 16, 19, 21, 23},
      ),
      _ScenarioCase(
        name: 'Einzelfirma durch sich',
        consignorType: ConsignorType.soleProprietor,
        scenario: 'SoleProprietorSelf',
        expectedVisible: {2, 3, 4, 11, 13, 14, 17, 21, 22},
      ),
      _ScenarioCase(
        name: 'Einzelfirma durch bevollmaechtigte Person',
        consignorType: ConsignorType.soleProprietor,
        representativeType: ConsignorType.naturalPerson,
        scenario: 'SoleProprietorThroughNaturalRepresentative',
        expectedVisible: {2, 3, 4, 7, 10, 13, 14, 15, 18, 21, 23},
      ),
      _ScenarioCase(
        name: 'Einzelfirma durch bevollmaechtigte jur. Person',
        consignorType: ConsignorType.soleProprietor,
        representativeType: ConsignorType.legalEntity,
        scenario: 'SoleProprietorThroughLegalRepresentative',
        expectedVisible: {2, 3, 4, 7, 12, 13, 14, 15, 16, 19, 21, 23},
      ),
    ];

    for (final item in cases) {
      test(item.name, () async {
        final payload = await builder.build(
          consignor: _consignor(item.consignorType),
          authorizedRepresentative: item.representativeType == null
              ? null
              : _consignor(item.representativeType!),
          record: ContractRecord.empty('100', auctionId: 1),
        );

        expect(payload['contractScenario'], item.scenario);
        expect(
          payload['paragraphVisibility'],
          _expectedVisibility(item.expectedVisible),
        );
      });
    }

    test('emits exact template checkbox values for consignor type', () async {
      final payload = await builder.build(
        consignor: _consignor(ConsignorType.soleProprietor),
        record: ContractRecord.empty('100', auctionId: 1),
      );

      expect(payload['check_natural_person'], '☐');
      expect(payload['check_sole_proprietor'], '☑');
      expect(payload['check_legal_entity'], '☐');
    });
    test('emits consignment country placeholder aliases', () async {
      final payload = await builder.build(
        consignor: _consignor(ConsignorType.naturalPerson),
        record: ContractRecord.empty('100', auctionId: 1),
        consignmentCountry: 'France',
        consignmentCountryIso3: 'FRA',
      );

      expect(payload['consignmentCountry'], 'France');
      expect(payload['consignmentCountryIsoCountryCode'], 'FRA');
      expect(payload['consignment_country'], 'France');
      expect(payload['CountryOfConsignment'], 'France');
    });
  });
}

Map<String, bool> _expectedVisibility(Set<int> visibleParagraphs) {
  return {
    for (var i = 1; i <= 23; i++) 'Paragraf$i': visibleParagraphs.contains(i),
  };
}

Consignor _consignor(ConsignorType type) {
  final consignor = Consignor.empty()
    ..id = '100'
    ..consignorType = type
    ..tradingName = type == ConsignorType.naturalPerson ? '' : 'Leu Test AG'
    ..phonePrefix = '+41'
    ..phoneNumber = '52 214 11 10'
    ..emailAddress = 'test@example.com';

  consignor.consignorInfo
    ..firstName = 'Anna'
    ..lastName = 'Muster'
    ..nationalityName = 'Switzerland'
    ..dateOfBirth = DateTime.utc(1980, 1, 2);

  consignor.consignorAddress
    ..streetAddress = 'Stadthausstrasse'
    ..streetNumber = '143'
    ..postalCode = '8400'
    ..city = 'Winterthur'
    ..countryName = 'Switzerland';

  consignor.bankingDetails
    ..bankName = 'Test Bank'
    ..accountNumber = 'CH9300762011623852957'
    ..bicSwift = 'TESTCHZZ';

  return consignor;
}

class _ScenarioCase {
  const _ScenarioCase({
    required this.name,
    required this.consignorType,
    required this.scenario,
    required this.expectedVisible,
    this.representativeType,
  });

  final String name;
  final ConsignorType consignorType;
  final ConsignorType? representativeType;
  final String scenario;
  final Set<int> expectedVisible;
}
