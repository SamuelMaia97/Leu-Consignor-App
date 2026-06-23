class ParsedPhoneNumber {
  const ParsedPhoneNumber({
    required this.prefix,
    required this.localNumber,
  });

  final String prefix;
  final String localNumber;
}

class PhoneNumberParser {
  static const List<String> _knownDialCodes = <String>[
    '423',
    '420',
    '386',
    '385',
    '381',
    '380',
    '371',
    '370',
    '359',
    '358',
    '357',
    '356',
    '353',
    '352',
    '351',
    '350',
    '34',
    '33',
    '32',
    '31',
    '49',
    '48',
    '47',
    '46',
    '45',
    '44',
    '43',
    '41',
    '39',
    '36',
    '30',
    '1',
  ];

  static ParsedPhoneNumber parse(String raw) {
    final value = raw.trim();

    if (value.isEmpty) {
      return const ParsedPhoneNumber(prefix: '', localNumber: '');
    }

    if (!value.startsWith('+')) {
      return ParsedPhoneNumber(prefix: '', localNumber: value);
    }

    final separatorMatch = RegExp(r'[\s()/-]+').firstMatch(value);
    if (separatorMatch != null && separatorMatch.start > 0) {
      return ParsedPhoneNumber(
        prefix: value.substring(0, separatorMatch.start).trim(),
        localNumber: value.substring(separatorMatch.end).trim(),
      );
    }

    final compact = value.replaceAll(RegExp(r'[\s()/-]+'), '');
    if (compact.length <= 5) {
      return ParsedPhoneNumber(prefix: compact, localNumber: '');
    }

    final digits = compact.substring(1);

    String? matchedDialCode;
    for (final dialCode in _knownDialCodes) {
      if (digits.startsWith(dialCode)) {
        matchedDialCode = dialCode;
        break;
      }
    }

    if (matchedDialCode != null && digits.length > matchedDialCode.length) {
      return ParsedPhoneNumber(
        prefix: '+$matchedDialCode',
        localNumber: digits.substring(matchedDialCode.length),
      );
    }

    final splitPoint = digits.length > 10
        ? 3
        : digits.length > 9
            ? 2
            : 1;

    return ParsedPhoneNumber(
      prefix: '+${digits.substring(0, splitPoint)}',
      localNumber: digits.substring(splitPoint),
    );
  }

  static String combine({
    required String prefix,
    required String localNumber,
  }) {
    final normalizedPrefix = prefix.trim();
    final normalizedNumber = localNumber.trim();

    if (normalizedPrefix.isEmpty) return normalizedNumber;
    if (normalizedNumber.isEmpty) return normalizedPrefix;

    final parsedNumber = parse(normalizedNumber);
    if (parsedNumber.prefix == normalizedPrefix &&
        parsedNumber.localNumber.isNotEmpty) {
      return normalizedNumber;
    }

    return '$normalizedPrefix $normalizedNumber';
  }
}
