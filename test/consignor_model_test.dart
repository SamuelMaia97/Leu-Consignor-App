import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/consignor.dart';
import 'package:leu_consignor_app/src/models/sync_status.dart';

void main() {
  group('Consignor', () {
    test('serializes full phone number with prefix', () {
      final consignor = Consignor.empty()
        ..phonePrefix = '+41'
        ..phoneNumber = '44 123 45 67';

      consignor.phonePrefixOriginId = 204;

      final json = consignor.toJson();
      expect(json['phonePrefix'], '+41');
      expect(json['phonePrefixOriginId'], 204);
      expect(json['phoneNumber'], '+41 44 123 45 67');
    });

    test('parses persisted phone fields', () {
      final consignor = Consignor.fromJson({
        'id': '1',
        'phonePrefix': '+49',
        'phonePrefixOriginId': 80,
        'phoneNumber': '89 123456',
      });

      expect(consignor.phonePrefix, '+49');
      expect(consignor.phonePrefixOriginId, 80);
      expect(consignor.phoneNumber, '89 123456');
    });

    test('markLocalChange sets audit fields', () {
      final consignor = Consignor.empty();

      consignor.markLocalChange('admin');

      expect(consignor.lastEditedByUsername, 'admin');
      expect(consignor.lastEditedAtUtc, isNotNull);
      expect(consignor.lastEditedAtUtc!.isUtc, isTrue);
    });

    test('markDraft sets audit fields', () {
      final consignor = Consignor.empty();

      consignor.markDraft('admin');

      expect(consignor.lastEditedByUsername, 'admin');
      expect(consignor.lastEditedAtUtc, isNotNull);
      expect(consignor.lastEditedAtUtc!.isUtc, isTrue);
    });

    test('audit fields round-trip through json', () {
      final consignor = Consignor.empty()..markLocalChange('admin');

      final restored = Consignor.fromJson(consignor.toJson());

      expect(restored.lastEditedByUsername, 'admin');
      expect(restored.lastEditedAtUtc, consignor.lastEditedAtUtc);
    });

    test('displayName returns tradingName for legal entities and fullName for individuals', () {
      final company = Consignor.empty()
        ..isLegalEntity = true
        ..tradingName = 'Leu AG';
      final person = Consignor.empty()
        ..consignorInfo.firstName = 'Anna'
        ..consignorInfo.lastName = 'Muster';

      expect(company.displayName, 'Leu AG');
      expect(person.displayName, 'Anna Muster');
    });

    test('markSynced sets syncStatus and updates lastSyncedUtc', () {
      final consignor = Consignor.empty();

      consignor.markSynced();

      expect(consignor.syncStatus, RecordSyncStatus.synced);
      expect(consignor.lastSyncedUtc, isNotNull);
    });

    test('markSyncFailed sets syncStatus and stores the message', () {
      final consignor = Consignor.empty();

      consignor.markSyncFailed('No connection');

      expect(consignor.syncStatus, RecordSyncStatus.syncFailed);
      expect(consignor.syncErrorMessage, 'No connection');
    });
  });
}
