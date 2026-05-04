import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/phone_prefix.dart';

class PhonePrefixRepository {
  Future<List<PhonePrefix>> loadBundledPrefixes() async {
    final jsonString = await rootBundle.loadString('assets/data/phone_prefixes.json');
    final list = (json.decode(jsonString) as List)
        .whereType<Map>()
        .map((item) => PhonePrefix.fromJson(item.cast<String, dynamic>()))
        .where((item) => item.dialCode.isNotEmpty)
        .toList();
    return _normalize(list);
  }

  List<PhonePrefix> normalize(Iterable<PhonePrefix> values) => _normalize(values);

  List<PhonePrefix> _normalize(Iterable<PhonePrefix> values) {
    final byIdentity = <String, PhonePrefix>{};
    for (final value in values) {
      final dialCode = value.dialCode.trim();
      if (dialCode.isEmpty) continue;

      final key = value.originId == null
          ? 'dial:$dialCode'
          : 'origin:${value.originId}';

      byIdentity[key] = value;
    }

    final result = byIdentity.values.toList()
      ..sort((a, b) {
        final labelComparison = a.label.toLowerCase().compareTo(b.label.toLowerCase());
        if (labelComparison != 0) return labelComparison;
        final dialComparison = a.dialCode.compareTo(b.dialCode);
        if (dialComparison != 0) return dialComparison;
        return (a.originId ?? 0).compareTo(b.originId ?? 0);
      });

    return result;
  }
}
