import '../models/contract_record.dart';
import '../storage/local_store.dart';

class ContractRepository {
  final _box = LocalStore.instance.getBox(LocalStore.contractsBox);

  List<ContractRecord> getAll() {
    final records = _box.values
        .map((e) => ContractRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    records.sort((a, b) {
      final auctionCompare = (b.auctionId ?? 0).compareTo(a.auctionId ?? 0);
      if (auctionCompare != 0) return auctionCompare;
      return b.lastModifiedUtc.compareTo(a.lastModifiedUtc);
    });
    return records;
  }

  ContractRecord? getById(String id) {
    final raw = _box.get(id);
    if (raw == null) return null;
    return ContractRecord.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  List<ContractRecord> getByConsignorId(String consignorId) {
    final records = getAll().where((e) => e.consignorId == consignorId).toList();
    records.sort((a, b) => (b.auctionId ?? 0).compareTo(a.auctionId ?? 0));
    return records;
  }

  ContractRecord? getByConsignorAndAuction(String consignorId, int auctionId) {
    try {
      return getAll().firstWhere(
        (e) => e.consignorId == consignorId && e.auctionIds.contains(auctionId),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLocal(
    ContractRecord record, {
    String? editorUsername,
  }) async {
    record.markLocalChange(editorUsername);
    await _box.put(record.id, record.toJson());
  }

  Future<void> put(ContractRecord record) async {
    await _box.put(record.id, record.toJson());
  }

  Future<void> putAll(Iterable<ContractRecord> records) async {
    for (final record in records) {
      await _box.put(record.id, record.toJson());
    }
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
  }

  Future<void> replaceAll(List<ContractRecord> records) async {
    await _box.clear();
    await putAll(records);
  }
}
