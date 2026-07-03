import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/utils/penta_scan_parser.dart';

void main() {
  group('parsePentaPassportExpiryDate', () {
    test('reads DESKO ExpiryDate Best value', () {
      const json = '''
{
  "Version": "1.1",
  "ApplicationName": "DESKO ID|Analyze",
  "Fields": {
    "ExpiryDate": {
      "Mrz": "2006-12-16T00:00:00.0000000+01:00",
      "Best": "2006-12-16T00:00:00.0000000+01:00"
    }
  }
}
''';

      final parsed = parsePentaPassportExpiryDate(json);

      expect(parsed, DateTime(2006, 12, 16));
    });

    test('reads DESKO report expiry and validation result', () {
      const json = '''
{
  "Version": "1.1",
  "ApplicationName": "DESKO ID|Analyze",
  "Fields": {
    "ExpiryDate": {
      "Mrz": "2031-05-26T00:00:00.0000000+02:00",
      "Viz": "2031-05-26T00:00:00.0000000+02:00",
      "Best": "2031-05-26T00:00:00.0000000+02:00"
    }
  },
  "Validations": {
    "Expiry": {
      "Result": "Passed",
      "PartialResults": {}
    },
    "Overall": {
      "Result": "Passed",
      "PartialResults": {}
    }
  }
}
''';

      final parsed = parsePentaPassportReport(json);

      expect(parsed?.validUntil, DateTime(2031, 5, 26));
      expect(parsed?.validationPassed, isTrue);
      expect(parsed?.validationResult, 'Passed');
    });

    test('marks failed DESKO validation as not passed', () {
      const json = '''
{
  "Fields": {
    "ExpiryDate": {
      "Best": "2031-05-26T00:00:00.0000000+02:00"
    }
  },
  "Validations": {
    "Expiry": {
      "Result": "Failed"
    },
    "Overall": {
      "Result": "Passed"
    }
  }
}
''';

      final parsed = parsePentaPassportReport(json);

      expect(parsed?.validUntil, DateTime(2031, 5, 26));
      expect(parsed?.validationPassed, isFalse);
      expect(parsed?.validationResult, 'Failed');
    });

    test('returns null for non-json reports', () {
      expect(parsePentaPassportExpiryDate('not json'), isNull);
    });
  });
}
