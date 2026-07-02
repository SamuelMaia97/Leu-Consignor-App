import 'consignor.dart';
import 'contract_record.dart';

class CustomerLookupResult {
  const CustomerLookupResult({
    required this.customerId,
    required this.displayLabel,
    required this.emailAddress,
    required this.prefill,
    this.passportUploads = const [],
  });

  final int customerId;
  final String displayLabel;
  final String emailAddress;
  final Consignor prefill;
  final List<ContractUpload> passportUploads;

  factory CustomerLookupResult.fromJson(
    Map<String, dynamic> json, {
    List<ContractUpload> passportUploads = const [],
  }) {
    final prefillJson = ((json['prefill'] ?? json['Prefill']) as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final mergedPrefillJson = _mergeLookupPrefill(json, prefillJson);
    final customerId = _toInt(json['customerId'] ?? json['CustomerId']) ?? 0;
    final displayLabel =
        (json['displayLabel'] ?? json['DisplayLabel'])?.toString() ?? '';
    final prefill = Consignor.fromJson(mergedPrefillJson);

    if (customerId > 0) {
      prefill.existingCustomerId ??= customerId;
      if (prefill.systemReferenceCustomer <= 0) {
        prefill.systemReferenceCustomer = customerId;
      }
    }
    if ((prefill.existingCustomerLabel ?? '').trim().isEmpty &&
        displayLabel.trim().isNotEmpty) {
      prefill.existingCustomerLabel = displayLabel;
    }

    return CustomerLookupResult(
      customerId: customerId,
      displayLabel: displayLabel,
      emailAddress:
          (json['emailAddress'] ?? json['EmailAddress'])?.toString() ?? '',
      prefill: prefill,
      passportUploads: List<ContractUpload>.unmodifiable(passportUploads),
    );
  }

  String get searchSubtitle {
    if (customerId > 0) {
      return 'ID $customerId';
    }

    return emailAddress.trim().isNotEmpty ? emailAddress.trim() : displayLabel;
  }

  static int? _toInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  static Map<String, dynamic> _mergeLookupPrefill(
    Map<String, dynamic> root,
    Map<String, dynamic> prefill,
  ) {
    final merged = <String, dynamic>{};

    void addEntries(Map<String, dynamic> source, {required bool override}) {
      for (final entry in source.entries) {
        final key = entry.key;
        if (key == 'prefill' || key == 'Prefill') continue;
        if (!override && merged.containsKey(key)) continue;
        final value = entry.value;
        if (value == null) continue;
        if (value is String && value.trim().isEmpty) continue;
        merged[key] = value;
      }
    }

    // Root lookup rows often carry contact-person or Abacus bank fields beside
    // the prefill object, so keep them as fallback data.
    addEntries(root, override: false);
    addEntries(prefill, override: true);
    return merged;
  }
}
