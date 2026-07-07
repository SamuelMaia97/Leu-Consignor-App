import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/services/phone_capture_service.dart';

void main() {
  group('PhoneCaptureService address ranking', () {
    test('prefers iPhone hotspot WLAN over VPN-only computer adapter', () {
      final ranked = PhoneCaptureService.rankAddressCandidatesForTesting(
        const [
          PhoneCaptureAddressCandidate(
            interfaceName: 'Ethernet 3',
            address: '10.202.36.200',
          ),
          PhoneCaptureAddressCandidate(
            interfaceName: 'WLAN',
            address: '172.20.10.8',
          ),
        ],
      );

      expect(ranked, isNotEmpty);
      expect(ranked.first.address, '172.20.10.8');
    });

    test('filters link-local addresses from phone capture links', () {
      final ranked = PhoneCaptureService.rankAddressCandidatesForTesting(
        const [
          PhoneCaptureAddressCandidate(
            interfaceName: 'Wi-Fi',
            address: '169.254.12.34',
          ),
          PhoneCaptureAddressCandidate(
            interfaceName: 'Wi-Fi',
            address: '192.168.1.44',
          ),
        ],
      );

      expect(ranked.map((candidate) => candidate.address), ['192.168.1.44']);
    });
  });
}
