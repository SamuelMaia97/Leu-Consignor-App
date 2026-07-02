import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/domain/consignor_type.dart';
import 'package:leu_consignor_app/src/models/abacus_sync.dart';
import 'package:leu_consignor_app/src/models/consignor.dart';
import 'package:leu_consignor_app/src/models/contract_record.dart';

void main() {
  group('AbacusFileSyncMetadata', () {
    test('labels signed contract PDFs for the vendor dossier', () {
      final metadata = AbacusFileSyncMetadata.forUpload(
        upload: ContractUpload(
          localId: 'contract',
          fileName: 'COR-consignor_contract_12345.pdf',
          fileType: UploadType.agreement,
        ),
        consignorSubjectId: 120149,
        contractNumber: '12345',
        eventUtc: DateTime.utc(2026, 6, 9),
        trigger: AbacusContractSyncEvent.contractSigned,
      );

      final json = metadata!.toJson();

      expect(json['documentKind'], 'ConsignmentContract');
      expect(json['label'], 'Consignment_Contract_12345');
      expect(json['documentName'], 'Consignment_Contract_12345.pdf');
      expect(json['verifyReceipt'], isTrue);
      expect((json['storage'] as Map)['lookupText'], 'Vertrag Einlieferung');
    });

    test('targets passport uploads to the Passport dossier', () {
      final metadata = AbacusFileSyncMetadata.forUpload(
        upload: ContractUpload(
          localId: 'passport',
          fileName: 'scan.jpg',
          fileType: UploadType.passport,
        ),
        consignorSubjectId: 120149,
        contractNumber: '12345',
        eventUtc: DateTime.utc(2026, 6, 9),
        trigger: AbacusContractSyncEvent.manualSync,
      );

      final json = metadata!.toJson();

      expect(json['documentKind'], 'Passport');
      expect(json['label'], 'Passport_120149_20260609');
      expect(json['documentName'], 'Passport_120149_20260609.jpg');
      expect((json['storage'] as Map)['storageId'],
          '39c1d257-327c-bb79-0408-9be8b5a1dcca');
    });

    test('targets representative passport uploads to the Passport dossier', () {
      final metadata = AbacusFileSyncMetadata.forUpload(
        upload: ContractUpload(
          localId: 'representative-passport',
          fileName: 'representative.jpg',
          fileType: UploadType.passport,
          kind: 'RepresentativeId',
        ),
        consignorSubjectId: 120149,
        contractNumber: '12345',
        eventUtc: DateTime.utc(2026, 6, 9),
        trigger: AbacusContractSyncEvent.manualSync,
      );

      final json = metadata!.toJson();

      expect(json['documentKind'], 'RepresentativePassport');
      expect(json['label'], 'Representative_Passport_120149_20260609');
      expect(
          json['documentName'], 'Representative_Passport_120149_20260609.jpg');
      expect((json['storage'] as Map)['lookupText'], 'Passport');
    });

    test('targets Desko validation reports to the Passport dossier', () {
      final metadata = AbacusFileSyncMetadata.forUpload(
        upload: ContractUpload(
          localId: 'report',
          fileName: 'validation-report.pdf',
          fileType: UploadType.passport,
          kind: 'RepresentativeIdValidationReport',
        ),
        consignorSubjectId: 120149,
        contractNumber: '12345',
        eventUtc: DateTime.utc(2026, 6, 9),
        trigger: AbacusContractSyncEvent.manualSync,
      );

      final json = metadata!.toJson();

      expect(json['documentKind'], 'RepresentativeIdValidationReport');
      expect(
          json['label'], 'Representative_Id_Validation_Report_120149_20260609');
      expect(json['documentName'],
          'Representative_Id_Validation_Report_120149_20260609.pdf');
      expect(json['verifyReceipt'], isTrue);
      expect((json['storage'] as Map)['lookupText'], 'Passport');
    });

    test('targets coin images to the consignment photos dossier', () {
      final metadata = AbacusFileSyncMetadata.forUpload(
        upload: ContractUpload(
          localId: 'temp coin 1',
          fileName: 'coin.png',
          fileType: UploadType.product,
        ),
        consignorSubjectId: 120149,
        contractNumber: '12345',
        eventUtc: DateTime.utc(2026, 6, 9),
        trigger: AbacusContractSyncEvent.manualSync,
      );

      final json = metadata!.toJson();

      expect(json['documentKind'], 'CoinImage');
      expect(json['label'], 'Coin_temp_coin_1_20260609');
      expect(json['documentName'], 'Coin_temp_coin_1_20260609.png');
      expect(json['contentType'], 'image/png');
      expect((json['storage'] as Map)['abbreviation'], 'EINL');
    });
  });

  group('AbacusRepresentativeLinkMetadata', () {
    test('serializes representative link relation ids', () {
      final representative = Consignor.empty()
        ..id = 'rep-local'
        ..existingCustomerId = 120163
        ..existingCustomerLabel = 'Anna Representative'
        ..consignorType = ConsignorType.naturalPerson;

      representative.consignorInfo
        ..firstName = 'Anna'
        ..lastName = 'Representative';

      final json = AbacusRepresentativeLinkMetadata(
        representative: representative,
        trigger: 'ConsignorSync',
      ).toJson();

      expect(json['target'], 'LinkedAddress');
      expect(json['relation'], 'Representative');
      expect(json['targetExistingCustomerId'], 120163);
      expect((json['linkTypeIds'] as Map)['test'],
          '899a75fc-a264-2e72-cab2-098101eb9bf0');
      expect((json['linkTypeIds'] as Map)['production'],
          'e174dc18-df58-ff73-edec-742a9302ec72');
    });
  });
}
