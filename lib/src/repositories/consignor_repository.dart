import '../models/consignor.dart';
import '../storage/local_store.dart';

class ConsignorRepository {
  final _box = LocalStore.instance.getBox(LocalStore.consignorsBox);

  List<Consignor> getAll() {
    final items = _box.values
        .map((e) => Consignor.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    items.sort((a, b) {
      final aNumber = a.systemReferenceConsignor;
      final bNumber = b.systemReferenceConsignor;
      if (aNumber != bNumber) {
        return bNumber.compareTo(aNumber);
      }
      return b.lastModifiedUtc.compareTo(a.lastModifiedUtc);
    });

    return items;
  }

  Consignor? getById(String id) {
    final raw = _box.get(id);
    if (raw == null) return null;
    return Consignor.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> saveLocal(
    Consignor consignor, {
    String? editorUsername,
  }) async {
    consignor.markLocalChange(editorUsername);
    await _box.put(consignor.id, consignor.toJson());
  }

  Future<void> saveDraft(
    Consignor consignor, {
    String? editorUsername,
  }) async {
    consignor.markDraft(editorUsername);
    await _box.put(consignor.id, consignor.toJson());
  }

  Future<void> saveReadyForSync(
    Consignor consignor, {
    String? editorUsername,
  }) async {
    consignor.markReadyForSync(editorUsername);
    await _box.put(consignor.id, consignor.toJson());
  }

  Future<void> put(Consignor consignor) async {
    await _box.put(consignor.id, consignor.toJson());
  }

  Future<void> putAll(Iterable<Consignor> consignors) async {
    for (final consignor in consignors) {
      await _box.put(consignor.id, consignor.toJson());
    }
  }

  Future<void> delete(String id) => _box.delete(id);

  Future<void> replaceAll(List<Consignor> consignors) async {
    await _box.clear();
    await putAll(consignors);
  }
}
