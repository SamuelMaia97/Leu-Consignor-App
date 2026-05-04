import '../models/contract_record.dart';

class AttachmentUtils {
  static List<ContractAttachment> mergeUnique(
    Iterable<ContractAttachment> current,
    Iterable<ContractAttachment> incoming,
  ) {
    final result = <ContractAttachment>[];
    final seen = <String>{};

    void append(ContractAttachment attachment) {
      final key = _keyFor(attachment);
      if (seen.contains(key)) return;
      seen.add(key);
      result.add(attachment);
    }

    for (final attachment in current) {
      append(attachment);
    }
    for (final attachment in incoming) {
      append(attachment);
    }

    return result;
  }

  static List<ContractAttachment> remove(
    Iterable<ContractAttachment> attachments,
    ContractAttachment target,
  ) {
    final targetKey = _keyFor(target);
    return attachments.where((item) => _keyFor(item) != targetKey).toList();
  }

  static String _keyFor(ContractAttachment attachment) {
    final path = attachment.path.trim().toLowerCase();
    return '${attachment.type.name}::$path';
  }
}
