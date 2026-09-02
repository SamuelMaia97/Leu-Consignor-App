import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/app_settings.dart';
import 'package:leu_consignor_app/src/models/customer_lookup_result.dart';
import 'package:leu_consignor_app/src/services/api_service.dart';

void main() {
  group('Customer lookup identity mapping', () {
    test('does not promote lookup metadata to a consignor reference', () {
      final result = CustomerLookupResult.fromJson({
        'customerId': 11217,
        'consignorId': 2342,
        'displayLabel': 'Customer 11217',
        'prefill': {
          'id': 2342,
          'systemReferenceConsignor': 2342,
          'systemReferenceCustomer': 2342,
          'abacusSubjectId': 765432,
          'existingCustomerId': 2342,
          'firstName': 'Correct',
          'lastName': 'Customer',
        },
      });

      expect(result.customerId, 11217);
      expect(result.prefill.systemReferenceConsignor, 0);
      expect(result.prefill.systemReferenceCustomer, 0);
      expect(result.prefill.existingCustomerId, 11217);
      expect(result.prefill.abacusSubjectId, 11217);
    });

    test('hydrates details using only the authoritative customer ID', () async {
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      Future<void> writeJson(HttpRequest request, Object payload) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(payload));
        await request.response.close();
      }

      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');

        if (request.uri.path == '/api/consignors-app/customers/search') {
          await writeJson(request, [
            {
              'customerId': 11217,
              'consignorId': 2342,
              'displayLabel': 'Customer 11217',
              'prefill': {
                'systemReferenceConsignor': 2342,
                'tradingName': 'Stale search prefill',
              },
            },
          ]);
          return;
        }

        if (request.uri.path == '/api/consignors-app/consignors/get/11217') {
          await writeJson(request, {
            'systemReferenceConsignor': 2342,
            'systemReferenceCustomer': 11217,
            'tradingName': 'Correct customer detail',
            'contracts': [],
          });
          return;
        }

        if (request.uri.path == '/api/consignors-app/consignors/get/2342') {
          await writeJson(request, {
            'systemReferenceConsignor': 2342,
            'systemReferenceCustomer': 99999,
            'tradingName': 'Wrong consignor detail',
            'contracts': [],
          });
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      try {
        final api = ApiService(
          AppSettings(apiBaseUrl: 'http://127.0.0.1:${server.port}'),
          'test-token',
        );

        final results = await api.searchExistingCustomers('11217');
        final prefill = results.single.prefill;

        expect(prefill.tradingName, 'Correct customer detail');
        expect(prefill.systemReferenceConsignor, 0);
        expect(prefill.systemReferenceCustomer, 0);
        expect(prefill.existingCustomerId, 11217);
        expect(prefill.abacusSubjectId, 11217);
        expect(
          requests,
          equals([
            'GET /api/consignors-app/customers/search',
            'GET /api/consignors-app/consignors/get/11217',
          ]),
        );
      } finally {
        await server.close(force: true);
      }
    });
  });
}
