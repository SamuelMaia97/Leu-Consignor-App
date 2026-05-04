import 'package:intl/intl.dart';

class PhonePrefix {
  const PhonePrefix({
    required this.label,
    required this.dialCode,
    this.iso2 = '',
    this.iso3 = '',
    this.countryName = '',
    this.countryNameDe = '',
    this.originId,
  });

  final String label;
  final String dialCode;
  final String iso2;
  final String iso3;
  final String countryName;
  final String countryNameDe;
  final int? originId;

  factory PhonePrefix.fromJson(Map<String, dynamic> json) {
    final rawPrefix = (json['phonePrefix'] ??
            json['dialCode'] ??
            json['prefix'] ??
            json['originPrefix'])
        ?.toString()
        .trim();

    final normalizedPrefix = _normalizeDialCode(rawPrefix ?? '');
    final englishName = (json['countryName'] ?? json['name'] ?? json['label'])
            ?.toString()
            .trim() ??
        '';
    final germanName = (json['countryNameDe'] ?? json['nameDe'])
            ?.toString()
            .trim() ??
        '';
    final displayName = _bestCountryName(
      englishName: englishName,
      germanName: germanName,
    );

    return PhonePrefix(
      label: displayName.isEmpty
          ? normalizedPrefix
          : '$displayName ($normalizedPrefix)',
      dialCode: normalizedPrefix,
      iso2: (json['isoCountryCode2'] ??
              json['iso2'] ??
              json['originShort'] ??
              json['origin_short'] ??
              json['isoCountryCode'])
          .toString()
          .trim()
          .toUpperCase(),
      iso3: (json['isoCountryCode3'] ??
              json['iso3'] ??
              json['originIso'] ??
              json['origin_iso'])
          .toString()
          .trim()
          .toUpperCase(),
      countryName: englishName,
      countryNameDe: germanName,
      originId: _toInt(json['originId'] ?? json['id']),
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'dialCode': dialCode,
        'iso2': iso2,
        'iso3': iso3,
        'countryName': countryName,
        'countryNameDe': countryNameDe,
        'originId': originId,
      };

  static String _normalizeDialCode(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return '+$digits';
  }

  static String _bestCountryName({
    required String englishName,
    required String germanName,
  }) {
    final locale = Intl.getCurrentLocale().toLowerCase();
    if (locale.startsWith('de') && germanName.isNotEmpty) {
      return germanName;
    }
    if (englishName.isNotEmpty) return englishName;
    return germanName;
  }

  static int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
