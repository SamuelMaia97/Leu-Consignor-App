import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/consignor.dart';
import 'package:leu_consignor_app/src/models/contract_record.dart';
import 'package:leu_consignor_app/src/models/sync_status.dart';
import 'package:leu_consignor_app/src/utils/workflow_status.dart';

void main() {
  group('WorkflowStatus', () {
    test('detects duplicate contract numbers', () {
      final contracts = [
        ContractRecord.empty('100', auctionId: 1).copyWith(
          id: 'local-a',
          pdfName: 'COC-26-1.pdf',
        ),
        ContractRecord.empty('101', auctionId: 2).copyWith(
          id: 'local-b',
          pdfName: 'COC-26-1.pdf',
        ),
      ];

      final conflicts = WorkflowStatus.findContractConflicts(contracts);

      expect(conflicts, hasLength(1));
      expect(conflicts.single.contractNumber, 'COC-26-1');
      expect(conflicts.single.contracts, hasLength(2));
    });

    test('marks expired and valid passports correctly', () {
      final upload = ContractUpload(
        localId: 'passport',
        fileName: 'Passport.png',
        fileType: UploadType.passport,
      );

      final expired = WorkflowStatus.passportStatus(
        validUntil: DateTime(2024, 1, 1),
        uploads: [upload],
        now: DateTime(2026, 7, 2),
      );
      final valid = WorkflowStatus.passportStatus(
        validUntil: DateTime(2028, 1, 1),
        uploads: [upload],
        now: DateTime(2026, 7, 2),
      );

      expect(expired.kind, PassportStatusKind.expired);
      expect(valid.kind, PassportStatusKind.valid);
    });

    test('treats server metadata as Abacus source', () {
      final upload = ContractUpload(
        localId: 'dossier-document',
        fileName: 'Passport.png',
        fileType: UploadType.passport,
        serverLastModifiedUtc: DateTime(2026, 7, 2),
      );

      final status = WorkflowStatus.attachmentStatus(upload);

      expect(status.source, AttachmentSourceStatus.fromAbacus);
      expect(status.sync, AttachmentSyncStatus.synced);
    });

    test('builds local sync preview counts for pending contracts', () {
      final consignor = Consignor.empty();
      final contract =
          ContractRecord.empty(consignor.id, auctionId: 1).copyWith(
        pdfName: 'COC-26-2.pdf',
        syncStatus: RecordSyncStatus.pendingSync,
        uploads: [
          ContractUpload(
            localId: 'product-1',
            fileName: 'COC-26-2-Product-1.png',
            fileType: UploadType.product,
          ),
        ],
      );

      final preview = WorkflowStatus.buildSyncPreview(
        consignors: [consignor],
        contracts: [contract],
      );

      expect(preview.changedConsignorCount, 1);
      expect(preview.pendingContractCount, 1);
      expect(preview.pendingUploadCount, 1);
      expect(preview.knownContractCount, 1);
    });

    test('ignores local draft contracts in sync preview upload counts', () {
      final consignor = Consignor.empty();
      final contract =
          ContractRecord.empty(consignor.id, auctionId: 1).copyWith(
        pdfName: 'COC-26-3.pdf',
        uploads: [
          ContractUpload(
            localId: 'product-1',
            fileName: 'COC-26-3-Product-1.png',
            fileType: UploadType.product,
          ),
        ],
      );

      final preview = WorkflowStatus.buildSyncPreview(
        consignors: [consignor],
        contracts: [contract],
      );

      expect(preview.pendingContractCount, 0);
      expect(preview.pendingUploadCount, 0);
      expect(preview.knownContractCount, 1);
    });
  });
}
