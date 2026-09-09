import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/consignor.dart';
import 'package:leu_consignor_app/src/models/sync_status.dart';
import 'package:leu_consignor_app/src/services/consignor_sync_policy.dart';

void main() {
  final baseline = DateTime.utc(2026, 9, 9, 10);

  Consignor local({
    RecordSyncStatus status = RecordSyncStatus.synced,
    DateTime? modified,
    DateTime? remoteBaseline,
    String id = '42',
    int? abacusSubjectId = 7001,
  }) {
    return Consignor(
      id: id,
      systemReferenceConsignor: 84,
      systemReferenceCustomer: 42,
      abacusSubjectId: abacusSubjectId,
      lastModifiedUtc: modified ?? baseline,
      remoteLastModifiedUtc: remoteBaseline ?? baseline,
      syncStatus: status,
    );
  }

  group('ConsignorSyncPolicy', () {
    test('draft is skipped even when the report is newer', () {
      final result = ConsignorSyncPolicy.decide(
        local: local(status: RecordSyncStatus.draft),
        remoteExists: true,
        remoteLastModifiedUtc: baseline.add(const Duration(hours: 2)),
      );

      expect(result, ConsignorSyncAction.skipDraft);
    });

    test('remote-only change is pulled', () {
      final result = ConsignorSyncPolicy.decide(
        local: local(),
        remoteExists: true,
        remoteLastModifiedUtc: baseline.add(const Duration(hours: 1)),
      );

      expect(result, ConsignorSyncAction.pullRemote);
    });

    test('local-only change is pushed', () {
      final result = ConsignorSyncPolicy.decide(
        local: local(
          status: RecordSyncStatus.pendingSync,
          modified: baseline.add(const Duration(hours: 1)),
        ),
        remoteExists: true,
        remoteLastModifiedUtc: baseline,
      );

      expect(result, ConsignorSyncAction.pushLocal);
    });

    test('app wins when both sides changed even if report is newest', () {
      final result = ConsignorSyncPolicy.decide(
        local: local(
          status: RecordSyncStatus.pendingSync,
          modified: baseline.add(const Duration(hours: 1)),
        ),
        remoteExists: true,
        remoteLastModifiedUtc: baseline.add(const Duration(hours: 2)),
      );

      expect(result, ConsignorSyncAction.pushLocal);
    });

    test('equal instants are a no-op, including different offsets', () {
      final sameInstant = DateTime.parse('2026-09-09T12:00:00+02:00');
      final result = ConsignorSyncPolicy.decide(
        local: local(),
        remoteExists: true,
        remoteLastModifiedUtc: sameInstant,
      );

      expect(result, ConsignorSyncAction.noOp);
    });

    test('new remote is pulled and clean missing remote is retained', () {
      expect(
        ConsignorSyncPolicy.decide(
          local: null,
          remoteExists: true,
          remoteLastModifiedUtc: baseline,
        ),
        ConsignorSyncAction.pullRemote,
      );
      expect(
        ConsignorSyncPolicy.decide(
          local: local(),
          remoteExists: false,
        ),
        ConsignorSyncAction.noOp,
      );
    });

    test('a report row without a timestamp is never pulled blindly', () {
      expect(
        ConsignorSyncPolicy.decide(
          local: null,
          remoteExists: true,
        ),
        ConsignorSyncAction.noOp,
      );
      expect(
        ConsignorSyncPolicy.decide(
          local: local(),
          remoteExists: true,
        ),
        ConsignorSyncAction.noOp,
      );
    });

    test('legacy clean records without a baseline compare both timestamps', () {
      Consignor legacy(DateTime modified) => Consignor(
            id: '42',
            systemReferenceConsignor: 84,
            systemReferenceCustomer: 42,
            abacusSubjectId: 7001,
            lastModifiedUtc: modified,
            remoteLastModifiedUtc: null,
            syncStatus: RecordSyncStatus.synced,
          );

      expect(
        ConsignorSyncPolicy.decide(
          local: legacy(baseline.add(const Duration(hours: 2))),
          remoteExists: true,
          remoteLastModifiedUtc: baseline.add(const Duration(hours: 1)),
        ),
        ConsignorSyncAction.pushLocal,
      );
      expect(
        ConsignorSyncPolicy.decide(
          local: legacy(baseline),
          remoteExists: true,
          remoteLastModifiedUtc: baseline.add(const Duration(hours: 1)),
        ),
        ConsignorSyncAction.pullRemote,
      );
    });

    test('new pending local is pushed while new draft stays local', () {
      final pending = Consignor(
        id: 'local-pending',
        syncStatus: RecordSyncStatus.pendingSync,
        lastModifiedUtc: baseline,
      );
      final draft = Consignor(
        id: 'local-draft',
        syncStatus: RecordSyncStatus.draft,
        lastModifiedUtc: baseline,
      );

      expect(
        ConsignorSyncPolicy.decide(
          local: pending,
          remoteExists: false,
        ),
        ConsignorSyncAction.pushLocal,
      );
      expect(
        ConsignorSyncPolicy.decide(local: draft, remoteExists: false),
        ConsignorSyncAction.skipDraft,
      );
    });

    test('failed sync retries without replacing its baseline', () {
      final failed = local(
        status: RecordSyncStatus.syncFailed,
        modified: baseline.add(const Duration(minutes: 10)),
      );

      expect(
        ConsignorSyncPolicy.decide(
          local: failed,
          remoteExists: true,
          remoteLastModifiedUtc: baseline.add(const Duration(minutes: 20)),
        ),
        ConsignorSyncAction.pushLocal,
      );
      expect(failed.remoteLastModifiedUtc, baseline);
    });

    test('matches by Abacus subject id when local ids differ', () {
      final appRecord = local(id: '42', abacusSubjectId: 7001);
      final reportRecord = Consignor(
        id: '7001',
        systemReferenceCustomer: 7001,
        abacusSubjectId: 7001,
        lastModifiedUtc: baseline.add(const Duration(hours: 1)),
        syncStatus: RecordSyncStatus.synced,
      );

      expect(
        ConsignorSyncPolicy.matchesReportSubject(appRecord, 7001),
        isTrue,
      );
      expect(
        ConsignorSyncPolicy.refersToSameRecord(appRecord, reportRecord),
        isTrue,
      );
    });

    test('remote pull preserves local Backoffice identity and credentials', () {
      final appRecord = local(id: '42', abacusSubjectId: 7001)
        ..existingCustomerId = 42
        ..existingCustomerLabel = 'Customer 42'
        ..username = 'local-user'
        ..password = 'local-secret'
        ..phonePrefixOriginId = 12;
      final reportRecord = Consignor(
        id: '7001',
        systemReferenceCustomer: 7001,
        abacusSubjectId: 7001,
        tradingName: 'New Abacus name',
        lastModifiedUtc: baseline.add(const Duration(hours: 1)),
        syncStatus: RecordSyncStatus.synced,
      );

      final merged = ConsignorSyncPolicy.preserveLocalIdentity(
        remote: reportRecord,
        local: appRecord,
      );

      expect(merged.id, '42');
      expect(merged.systemReferenceConsignor, 84);
      expect(merged.systemReferenceCustomer, 42);
      expect(merged.abacusSubjectId, 7001);
      expect(merged.existingCustomerId, 42);
      expect(merged.username, 'local-user');
      expect(merged.password, 'local-secret');
      expect(merged.phonePrefixOriginId, 12);
      expect(merged.tradingName, 'New Abacus name');
    });
  });
}
