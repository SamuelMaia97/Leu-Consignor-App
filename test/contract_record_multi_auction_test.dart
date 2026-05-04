import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/contract_record.dart';

void main() {
  group('ContractRecord multi auction support', () {
    test('fromJson with legacy auctionId produces auctionIds list of length 1', () {
      final record = ContractRecord.fromJson({'id': 'c1', 'consignorId': '10', 'auctionId': 7});

      expect(record.auctionIds, [7]);
      expect(record.auctionId, 7);
    });

    test('fromJson with new auctionIds list round-trips correctly', () {
      final record = ContractRecord.fromJson({
        'id': 'c1',
        'consignorId': '10',
        'auctionIds': [7, 8],
        'auctionDisplayNames': ['A7', 'A8'],
      });

      final json = ContractRecord.fromJson(record.toJson());

      expect(json.auctionIds, [7, 8]);
      expect(json.auctionDisplayNames, ['A7', 'A8']);
    });

    test('toJson always writes auctionIds as a list', () {
      final record = ContractRecord.empty('10', auctionIds: [7, 8]);

      expect(record.toJson()['auctionIds'], [7, 8]);
    });

    test('toJson writes legacy auctionId as first element', () {
      final record = ContractRecord.empty('10', auctionIds: [7, 8]);

      expect(record.toJson()['auctionId'], 7);
    });

    test('copyWith replaces auctionIds and auctionDisplayNames', () {
      final record = ContractRecord.empty('10', auctionIds: [1]).copyWith(
        auctionIds: [2, 3],
        auctionDisplayNames: ['Two', 'Three'],
      );

      expect(record.auctionIds, [2, 3]);
      expect(record.auctionDisplayNames, ['Two', 'Three']);
    });

    test('markLocalChange sets lastEditedByUsername and lastEditedAtUtc', () {
      final record = ContractRecord.empty('10');

      record.markLocalChange('admin');

      expect(record.lastEditedByUsername, 'admin');
      expect(record.lastEditedAtUtc, isNotNull);
      expect(record.lastEditedAtUtc!.isUtc, isTrue);
    });
  });
}
