import 'dart:convert';

class PentaPassportReport {
  const PentaPassportReport({
    this.validUntil,
    this.validationPassed,
    this.validationResult,
  });

  final DateTime? validUntil;
  final bool? validationPassed;
  final String? validationResult;
}

DateTime? parsePentaPassportExpiryDate(String content) {
  return parsePentaPassportReport(content)?.validUntil;
}

PentaPassportReport? parsePentaPassportReport(String content) {
  if (content.trim().isEmpty) return null;

  dynamic decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException {
    return null;
  }

  if (decoded is! Map<String, dynamic>) return null;
  final validationResult = _validationResult(decoded);
  return PentaPassportReport(
    validUntil: _parseDateFromDynamic(_fieldBestValue(decoded, 'ExpiryDate')),
    validationPassed: _validationPassed(validationResult),
    validationResult: validationResult,
  );
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

String? _validationResult(Map<String, dynamic> decoded) {
  final validations = decoded['Validations'];
  if (validations is! Map<String, dynamic>) return null;

  final expiryResult = _validationFieldResult(validations, 'Expiry');
  if (_isFailedValidationResult(expiryResult)) return expiryResult;

  for (final fieldName in const ['OverallManual', 'Overall', 'OverallAuto']) {
    final result = _validationFieldResult(validations, fieldName);
    if (result != null && result.trim().isNotEmpty) {
      return result;
    }
  }

  return expiryResult;
}

String? _validationFieldResult(
  Map<String, dynamic> validations,
  String fieldName,
) {
  final field = validations[fieldName];
  if (field is Map<String, dynamic>) {
    return field['Result']?.toString();
  }

  return field?.toString();
}

bool? _validationPassed(String? result) {
  if (result == null || result.trim().isEmpty) return null;
  final normalized = result.trim().toLowerCase();
  if (normalized == 'passed') return true;
  if (normalized == 'none') return null;
  return false;
}

bool _isFailedValidationResult(String? result) {
  final passed = _validationPassed(result);
  return passed == false;
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
