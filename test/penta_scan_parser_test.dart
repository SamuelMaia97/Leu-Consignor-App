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

    test('returns null for non-json reports', () {
      expect(parsePentaPassportExpiryDate('not json'), isNull);
    });
  });
}
