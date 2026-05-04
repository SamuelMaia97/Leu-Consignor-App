import '../storage/local_store.dart';

class WizardDraftRepository {
  final _box = LocalStore.instance.getBox(LocalStore.wizardDraftsBox);

  static String consignorKey(String consignorId) => 'consignor:$consignorId';
  static String contractKey(String contractId) => 'contract:$contractId';

  Map<String, dynamic>? getByConsignorId(String consignorId) {
    return _read(consignorKey(consignorId));
  }

  Map<String, dynamic>? getByContractId(String contractId) {
    return _read(contractKey(contractId));
  }

  Future<void> saveForConsignor({
    required String consignorId,
    required Map<String, dynamic> state,
  }) async {
    await _box.put(consignorKey(consignorId), state);
  }

  Future<void> saveForContract({
    required String contractId,
    required Map<String, dynamic> state,
  }) async {
    await _box.put(contractKey(contractId), state);
  }

  Future<void> deleteForConsignor(String consignorId) async {
    await _box.delete(consignorKey(consignorId));
  }

  Future<void> deleteForContract(String contractId) async {
    await _box.delete(contractKey(contractId));
  }

  Map<String, dynamic>? _read(String key) {
    final raw = _box.get(key);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }
}
