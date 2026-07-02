import 'dart:convert';

DateTime? parsePentaPassportExpiryDate(String content) {
  if (content.trim().isEmpty) return null;

  dynamic decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException {
    return null;
  }

  if (decoded is! Map<String, dynamic>) return null;
  return _parseDateFromDynamic(_fieldBestValue(decoded, 'ExpiryDate'));
}

dynamic _fieldBestValue(Map<String, dynamic> decoded, String fieldName) {
  final fields = decoded['Fields'];
  if (fields is Map<String, dynamic>) {
    final field = fields[fieldName];
    if (field is Map<String, dynamic>) {
      return field['Best'] ?? field['Mrz'] ?? field['Ocr'] ?? field['Image'];
    }

    if (field != null) return field;
  }

  return decoded[fieldName];
}

DateTime? _parseDateFromDynamic(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  final dateMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
  if (dateMatch != null) {
    final year = int.tryParse(dateMatch.group(1)!);
    final month = int.tryParse(dateMatch.group(2)!);
    final day = int.tryParse(dateMatch.group(3)!);
    if (year != null && month != null && day != null) {
      return DateTime(year, month, day);
    }
  }

  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}
