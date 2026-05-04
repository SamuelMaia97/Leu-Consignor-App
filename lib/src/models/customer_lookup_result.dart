import 'consignor.dart';

class CustomerLookupResult {
  const CustomerLookupResult({
    required this.customerId,
    required this.displayLabel,
    required this.emailAddress,
    required this.prefill,
  });

  final int customerId;
  final String displayLabel;
  final String emailAddress;
  final Consignor prefill;

  factory CustomerLookupResult.fromJson(Map<String, dynamic> json) {
    final prefillJson = ((json['prefill'] ?? json['Prefill']) as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return CustomerLookupResult(
      customerId: _toInt(json['customerId'] ?? json['CustomerId']) ?? 0,
      displayLabel:
          (json['displayLabel'] ?? json['DisplayLabel'])?.toString() ?? '',
      emailAddress:
          (json['emailAddress'] ?? json['EmailAddress'])?.toString() ?? '',
      prefill: Consignor.fromJson(prefillJson),
    );
  }

  String get searchSubtitle {
    if (customerId <= 0 && emailAddress.trim().isEmpty) {
      return displayLabel;
    }

    final fragments = <String>[
      if (customerId > 0) 'ID $customerId',
      if (emailAddress.trim().isNotEmpty) emailAddress.trim(),
    ];

    return fragments.join(' • ');
  }

  static int? _toInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
}
