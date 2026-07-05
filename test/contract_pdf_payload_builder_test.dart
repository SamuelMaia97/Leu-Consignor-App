import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/domain/consignor_type.dart';
import 'package:leu_consignor_app/src/models/consignor.dart';
import 'package:leu_consignor_app/src/models/contract_record.dart';
import 'package:leu_consignor_app/src/models/payment_option.dart';
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

    test('localizes country names and web auction text for German contracts',
        () async {
      final consignor = _consignor(ConsignorType.naturalPerson)
        ..correspondence = 'de';
      final record = ContractRecord.empty('100', auctionId: 1).copyWith(
        auctionDisplayName: 'Web Auction 12',
      );

      final payload = await builder.build(
        consignor: consignor,
        record: record,
      );

      expect(payload['auction_name'], 'Webauktion 12');
      expect(payload['consignor_nationality'], 'Schweiz');
      expect(payload['consignor_address_2'], '8400 Winterthur, Schweiz');
      expect(payload['consignmentCountry'], 'Schweiz');
      expect(payload['originCountry'], 'Schweiz');
    });

    test('includes selected academic title in contract person names', () async {
      final consignor = _consignor(ConsignorType.naturalPerson);
      consignor.consignorInfo.title = 1;

      final payload = await builder.build(
        consignor: consignor,
        record: ContractRecord.empty('100', auctionId: 1),
      );

      expect(payload['consignor_full_name'], 'Dr. Anna Muster');
      expect(payload['consignor_signature_name'], 'Dr. Anna Muster');
    });

    test('uses authorized representative name for signer placeholders',
        () async {
      final representative = _consignor(ConsignorType.naturalPerson)
        ..id = '200';
      representative.consignorInfo
        ..firstName = 'Marco'
        ..lastName = 'Signer';

      final payload = await builder.build(
        consignor: _consignor(ConsignorType.naturalPerson),
        authorizedRepresentative: representative,
        record: ContractRecord.empty('100', auctionId: 1),
      );

      expect(payload['consignor_full_name'], 'Anna Muster');
      expect(payload['representative_name'], 'Marco Signer');
      expect(payload['representativeName'], 'Marco Signer');
      expect(payload['ownerFullName'], 'Marco Signer');
      expect(payload['consignor_signature_name'], 'Marco Signer');
      expect(payload['annex_a_signature_name'], 'Marco Signer');
      expect(payload['annex_c_signature_name'], 'Marco Signer');
    });

    test('formats visible template dates day first', () async {
      final payload = await builder.build(
        consignor: _consignor(ConsignorType.naturalPerson),
        record: ContractRecord.empty('100', auctionId: 1).copyWith(
          signedAt: DateTime.utc(2026, 9, 15),
        ),
      );

      expect(payload['consignor_dob'], '02-01-1980');
      expect(payload['auction_date'], '15-09-2026');
    });

    test('sends effective auction date to backend when no explicit date exists',
        () async {
      final payload = await builder.build(
        consignor: _consignor(ConsignorType.naturalPerson),
        record: ContractRecord.empty('100', auctionId: 1).copyWith(
          signedAt: DateTime.utc(2026, 9, 15),
        ),
      );

      final record = payload['record'] as Map<String, dynamic>;

      expect(payload['auctionDate'], '2026-09-15T00:00:00.000Z');
      expect(record['auctionDate'], '2026-09-15T00:00:00.000Z');
      expect(payload['auction_date'], '15-09-2026');
    });

    test('emits PDF name, title, page numbers, and provisional flags',
        () async {
      final payload = await builder.build(
        consignor: _consignor(ConsignorType.naturalPerson),
        record: ContractRecord.empty('100', auctionId: 1).copyWith(
          pdfName: 'COA-100_1-202606091435.pdf',
        ),
      );

      expect(payload['pdfName'], 'COA-100_1-202606091435.pdf');
      expect(payload['pdfTitle'], 'COA-100_1-202606091435');
      expect(payload['documentTitle'], 'COA-100_1-202606091435');
      expect(payload['includePageNumbers'], isTrue);
      expect(payload['isProvisional'], isTrue);
      expect(payload['watermarkText'], 'PROVISIONAL');
      expect(payload['watermark_text'], 'PROVISIONAL');
      expect(payload['pageWatermarkText'], 'PROVISIONAL');
      expect(payload['watermark'], {'text': 'PROVISIONAL'});
      expect(payload['pageWatermark'], {'text': 'PROVISIONAL'});
      expect(payload['place_of_signature'], 'Winterthur');
      expect(payload['consignor_place_date'], 'Winterthur');
      expect(payload['contract_place_date'], 'Winterthur');
      expect(payload['contractPlaceDate'], 'Winterthur');
      expect(payload['leu_place_date'], 'Winterthur');
      expect(payload['leuPlaceDate'], 'Winterthur');
      expect(payload['annex_a_place_date'], 'Winterthur');
      expect(payload['annexAPlaceDate'], 'Winterthur');
      expect(payload['annex_place_date'], 'Winterthur');
      expect(payload['annexPlaceDate'], 'Winterthur');
      expect(payload['annex_c_place_date'], 'Winterthur');
      expect(payload['annexCPlaceDate'], 'Winterthur');
    });

    test('emits editable signature place and date suffix for templates',
        () async {
      final payload = await builder.build(
        consignor: _consignor(ConsignorType.naturalPerson),
        record: ContractRecord.empty('100', auctionId: 1).copyWith(
          signedAt: DateTime.utc(2026, 6, 9),
          placeOfSignature: 'Zurich',
        ),
        signatureData: ContractSignatureData(
          leuRepresentativeName: 'Yves Gunzenreiner',
          leuRepresentativeSignatureAsset: '',
          contractSignaturePng: Uint8List.fromList([1]),
          annexASignaturePng: Uint8List.fromList([2]),
          annexCSignaturePng: Uint8List.fromList([3]),
        ),
      );

      expect(payload['place_of_signature'], 'Zurich');
      expect(payload['consignor_place_date'], 'Zurich, 09-06-2026');
      expect(payload['contractPlaceDate'], 'Zurich, 09-06-2026');
      expect(payload['leu_place_date'], 'Winterthur, 09-06-2026');
      expect(payload['annex_a_place_date'], 'Zurich, 09-06-2026');
      expect(payload['annexAPlaceDate'], 'Zurich, 09-06-2026');
      expect(payload['annex_c_place_date'], 'Zurich, 09-06-2026');
      expect(payload['annexCPlaceDate'], 'Zurich, 09-06-2026');
    });

    test('emits selected Leu representative function for templates', () async {
      final payload = await builder.build(
        consignor: _consignor(ConsignorType.naturalPerson),
        record: ContractRecord.empty('100', auctionId: 1),
        signatureData: ContractSignatureData(
          leuRepresentativeName: 'Lars Rutten',
          leuRepresentativeFunction: 'DCEO',
          leuRepresentativeSignatureAsset: '',
          contractSignaturePng: Uint8List.fromList([1]),
          annexASignaturePng: Uint8List.fromList([2]),
          annexCSignaturePng: Uint8List.fromList([3]),
        ),
      );

      final signatureData = payload['signatureData'] as Map<String, dynamic>;

      expect(payload['leuRepresentativeName'], 'Lars Rutten');
      expect(payload['leuRepresentativeFunction'], 'DCEO');
      expect(payload['leu_representative_function'], 'DCEO');
      expect(
        payload['leu_representative_name_function'],
        'Leu Numismatik AG / Lars Rutten, DCEO',
      );
      expect(signatureData['leuRepresentativeFunction'], 'DCEO');
    });

    test('emits desired payment method and country-specific address lines',
        () async {
      final consignor = _consignor(ConsignorType.naturalPerson)
        ..paymentOption = PaymentOption.wise;

      consignor.consignorAddress
        ..streetAddress = 'Main Street'
        ..streetNumber = '12'
        ..postalCode = '10001'
        ..city = 'New York'
        ..adminRegion = 'NY'
        ..countryIso3 = 'USA'
        ..countryName = 'United States';

      final payload = await builder.build(
        consignor: consignor,
        record: ContractRecord.empty('100', auctionId: 1),
      );

      expect(payload['payment_method'], 'Wise');
      expect(payload['payment_method_text'], 'WISE');
      expect(payload['check_payment_wise'], '☑');
      expect(payload['consignor_address_1'], '12 Main Street');
      expect(
          payload['consignor_address_2'], 'New York, NY 10001, United States');
      expect(payload['consignor_address_3'], '');
    });

    test('emits commercial register block aliases and attachment kind',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('commercial_register_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final registerFile = File('${tempDir.path}/register.pdf');
      await registerFile.writeAsBytes([1, 2, 3], flush: true);

      final payload = await builder.build(
        consignor: _consignor(ConsignorType.legalEntity),
        record: ContractRecord.empty('100', auctionId: 1).copyWith(
          uploads: [
            ContractUpload(
              localId: 'register',
              fileName: 'register.pdf',
              fileType: UploadType.agreement,
              path: registerFile.path,
            ),
          ],
        ),
      );

      final attachments = payload['attachments'] as List<dynamic>;

      expect(payload['block_attach_commercial_register'], isTrue);
      expect(payload['show_block_attach_commercial_register'], isTrue);
      expect(
        payload['templateFlags'],
        containsPair('blockAttachCommercialRegister', true),
      );
      expect(attachments.single, containsPair('kind', 'CommercialRegister'));
    });

    test('excludes validation report files from COA render attachments',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('penta_payload_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final passportFile = File('${tempDir.path}/passport.jpg');
      await passportFile.writeAsBytes([0xFF, 0xD8, 0xFF], flush: true);
      final reportFile = File('${tempDir.path}/validation_report.json');
      await reportFile.writeAsString('{"validUntil":"2026-07-03"}',
          flush: true);

      final payload = await builder.build(
        consignor: _consignor(ConsignorType.naturalPerson),
        record: ContractRecord.empty('100', auctionId: 1).copyWith(
          uploads: [
            ContractUpload(
              localId: 'passport',
              fileName: 'passport.jpg',
              fileType: UploadType.passport,
              kind: 'NaturalPersonId',
              path: passportFile.path,
            ),
            ContractUpload(
              localId: 'validation-report',
              fileName: 'validation_report.json',
              fileType: UploadType.passport,
              kind: 'NaturalPersonIdValidationReport',
              path: reportFile.path,
            ),
          ],
        ),
      );

      final attachments = payload['attachments'] as List<dynamic>;

      expect(attachments, hasLength(1));
      expect(attachments.single, containsPair('fileName', 'passport.jpg'));
    });

    test('shows both commercial register blocks for legal through legal',
        () async {
      final payload = await builder.build(
        consignor: _consignor(ConsignorType.legalEntity),
        authorizedRepresentative: _consignor(ConsignorType.legalEntity)
          ..tradingName = 'Representative AG',
        record: ContractRecord.empty('100', auctionId: 1),
      );

      expect(payload['representative_company'], 'Representative AG');
      expect(payload['block_attach_commercial_register'], isTrue);
      expect(payload['block_attach_register_legal'], isTrue);
      expect(
        payload['templateFlags'],
        containsPair('blockAttachCommercialRegister', true),
      );
      expect(
        payload['templateFlags'],
        containsPair('blockAttachRegisterLegal', true),
      );
    });

    test('emits agreement, Annex A, and Annex C signatures in order', () async {
      final contractSignature = Uint8List.fromList([1, 2, 3]);
      final annexASignature = Uint8List.fromList([4, 5, 6]);
      final annexCSignature = Uint8List.fromList([7, 8, 9]);
      final payload = await builder.build(
        consignor: _consignor(ConsignorType.naturalPerson),
        record: ContractRecord.empty('100', auctionId: 1).copyWith(
          signedAt: DateTime.utc(2026, 6, 9),
        ),
        signatureData: ContractSignatureData(
          leuRepresentativeName: 'Yves Gunzenreiner',
          leuRepresentativeSignatureAsset: '',
          contractSignaturePng: contractSignature,
          annexASignaturePng: annexASignature,
          annexCSignaturePng: annexCSignature,
        ),
      );

      final contractSignatureBase64 = base64Encode(contractSignature);
      final annexASignatureBase64 = base64Encode(annexASignature);
      final annexCSignatureBase64 = base64Encode(annexCSignature);
      final signatureData = payload['signatureData'] as Map<String, dynamic>;

      expect(payload['isProvisional'], isFalse);
      expect(payload['watermarkText'], '');
      expect(payload['watermark_text'], '');
      expect(payload['pageWatermarkText'], '');
      expect(payload['watermark'], {'text': ''});
      expect(payload['pageWatermark'], {'text': ''});
      expect(payload['consignor_signature_image'], contractSignatureBase64);
      expect(payload['annex_a_signature_image'], annexASignatureBase64);
      expect(payload['annex_c_signature_image'], annexCSignatureBase64);
      expect(
        signatureData['customerSignaturePngBase64'],
        contractSignatureBase64,
      );
      expect(
        signatureData['contractSignaturePngBase64'],
        contractSignatureBase64,
      );
      expect(
        signatureData['annexASignaturePngBase64'],
        annexASignatureBase64,
      );
      expect(
        signatureData['annexCSignaturePngBase64'],
        annexCSignatureBase64,
      );
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
