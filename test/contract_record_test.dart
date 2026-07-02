import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/contract_record.dart';
import 'package:leu_consignor_app/src/models/sync_status.dart';

void main() {
  group('ContractRecord', () {
    test('deduplicates attachments when reading persisted payloads', () {
      final record = ContractRecord.fromJson({
        'id': 'contract-1',
        'consignorId': '100',
        'attachments': [
          {'path': '/tmp/passport.jpg', 'typeIndex': 0},
        ],
        'passportFiles': ['/tmp/passport.jpg'],
      });

      expect(record.attachments, hasLength(1));
      expect(record.attachments.single.type, UploadType.passport);
    });

    test('maps API file types to upload types', () {
      final passport = ContractAttachment.fromJson({
        'fileName': 'passport.png',
        'fileType': 1,
      });
      final product = ContractAttachment.fromJson({
        'fileName': 'coin.jpg',
        'fileType': 3,
      });
      final agreement = ContractAttachment.fromJson({
        'fileName': 'contract.pdf',
        'fileType': 2,
      });

      expect(passport.type, UploadType.passport);
      expect(product.type, UploadType.product);
      expect(agreement.type, UploadType.agreement);
    });

    test('preserves upload kind for split identity sections', () {
      final upload = ContractUpload.fromJson({
        'localId': 'rep-id',
        'fileName': 'representative.png',
        'fileType': 1,
        'kind': 'RepresentativeId',
      });

      expect(upload.kind, 'RepresentativeId');
      expect(upload.toJson()['kind'], 'RepresentativeId');
      expect(upload.toAttachment().kind, 'RepresentativeId');
    });

    test('parses finalized sync status from backend values', () {
      expect(
        RecordSyncStatusX.fromAny('Finalized', hasRemoteReference: true),
        RecordSyncStatus.finalized,
      );
    });

    test('treats remote Abacus contracts without auction ids as remote', () {
      final record = ContractRecord(
        id: 'COC-26-1',
        consignorId: '121097',
        auctionDisplayName: 'COC-26-1',
        pdfName: 'COC-26-1.pdf',
        remoteLastModifiedUtc: DateTime.utc(2026, 7, 2),
        syncStatus: RecordSyncStatus.synced,
      );

      expect(record.auctionId, isNull);
      expect(record.hasRemoteReference, isTrue);
      expect(record.hasLocalChanges, isFalse);
    });

    test('keeps local drafts editable but out of workspace sync', () {
      final draft = ContractRecord.empty('100', auctionId: 1).copyWith(
        uploads: [
          ContractUpload(
            localId: 'product-1',
            fileName: 'COC-26-1-Product-1.png',
            fileType: UploadType.product,
          ),
        ],
      );

      expect(draft.isEditableDraft, isTrue);
      expect(draft.hasLocalChanges, isTrue);
      expect(draft.shouldUploadDuringWorkspaceSync, isFalse);
    });

    test('allows pending local contracts to upload during workspace sync', () {
      final pending = ContractRecord.empty('100', auctionId: 1).copyWith(
        syncStatus: RecordSyncStatus.pendingSync,
        uploads: [
          ContractUpload(
            localId: 'contract-pdf',
            fileName: 'COC-26-1.pdf',
            fileType: UploadType.agreement,
          ),
        ],
      );

      expect(pending.isEditableDraft, isFalse);
      expect(pending.shouldUploadDuringWorkspaceSync, isTrue);
    });
  });
}
