import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/app_settings.dart';
import 'package:leu_consignor_app/src/services/api_service.dart';

void main() {
  group('ApiService remote snapshot report fetch', () {
    late HttpServer server;
    late List<String> requests;
    late Future<void> Function(HttpRequest request) handler;

    setUp(() async {
      requests = <String>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        await handler(request);
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    ApiService buildApi() {
      return ApiService(
        AppSettings(apiBaseUrl: 'http://127.0.0.1:${server.port}'),
        'test-token',
      );
    }

    Future<void> writeJson(HttpRequest request, Object payload) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(payload));
      await request.response.close();
    }

    test('imports full get-all report rows without detail fetch', () async {
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/consignors/get-all') {
          await writeJson(request, [
            {
              'consignorId': 121013,
              'systemReferenceCustomer': 121013,
              'tradingName': 'Leu Test Consignor',
              'consignorInfo': {
                'firstName': 'Anna',
                'lastName': 'Report',
              },
              'emailAddress': 'anna.report@example.test',
              'phoneNumber': '+41 44 123 45 67',
              'consignorAddress': {
                'streetAddress': 'Report Street',
                'postalCode': '8000',
                'city': 'Zurich',
                'country': {
                  'isoCountryCode': 'CHE',
                  'countryName': 'Switzerland',
                },
              },
              'bankingDetails': {
                'bankName': 'Abacus Maintained Bank',
                'accountNumber': 'CH9300762011623852957',
              },
              'paymentOption': 'BankTransfer',
              'correspondence': 'en',
              'lastModifiedUtc': '2026-07-02T07:00:00Z',
              'contracts': [],
            },
          ]);
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final snapshot = await buildApi().fetchRemoteSnapshot();

      expect(snapshot.consignors, hasLength(1));
      expect(snapshot.missingReportFields, isEmpty);
      expect(snapshot.consignors.single.id, '121013');
      expect(snapshot.consignors.single.displayName, 'Anna Report');
      expect(
        snapshot.consignors.single.bankingDetails.bankName,
        'Abacus Maintained Bank',
      );
      expect(
        requests,
        isNot(contains('GET /api/consignors-app/consignors/get/121013')),
      );
    });

    test('imports summary-only rows and reports missing fields', () async {
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/consignors/get-all') {
          await writeJson(request, [
            {
              'consignorId': 121013,
              'customerId': 121013,
              'lastModifiedUtc': '2026-07-02T07:00:00Z',
            },
          ]);
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final snapshot = await buildApi().fetchRemoteSnapshot();
      final issue = snapshot.missingReportFields.single;

      expect(snapshot.consignors, hasLength(1));
      expect(snapshot.contracts, isEmpty);
      expect(snapshot.consignors.single.id, '121013');
      expect(snapshot.consignors.single.displayName, '');
      expect(snapshot.consignors.single.bankingDetails.bankName, '');
      expect(snapshot.missingReportFields, hasLength(1));
      expect(issue.title, 'Row 1 of 1 · ID 121013');
      expect(issue.availableFields, containsAll(['consignorId', 'customerId']));
      expect(
        issue.missingFields,
        containsAll([
          'Name',
          'Email',
          'Phone number',
          'Address street',
          'Contracts',
        ]),
      );
      expect(issue.missingFields, isNot(contains('Bank name')));
      expect(issue.missingFields, isNot(contains('Bank account / IBAN')));
      expect(
        requests,
        isNot(contains('GET /api/consignors-app/consignors/get/121013')),
      );
    });

    test('does not require bank fields for non AR DE CH countries', () async {
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/consignors/get-all') {
          await writeJson(request, [
            {
              'consignorId': 121014,
              'tradingName': 'US Report Consignor',
              'emailAddress': 'us.report@example.test',
              'phoneNumber': '+1 555 0100',
              'consignorAddress': {
                'streetAddress': 'Report Street',
                'postalCode': '10001',
                'city': 'New York',
                'country': {
                  'isoCountryCode': 'USA',
                  'countryName': 'United States',
                },
              },
              'paymentOption': 'BankTransfer',
              'correspondence': 'en',
              'lastModifiedUtc': '2026-07-02T07:00:00Z',
              'contracts': [],
            },
          ]);
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final snapshot = await buildApi().fetchRemoteSnapshot();

      expect(snapshot.missingReportFields, isEmpty);
    });

    test('requires bank fields for CH report rows', () async {
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/consignors/get-all') {
          await writeJson(request, [
            {
              'consignorId': 121015,
              'tradingName': 'CH Report Consignor',
              'emailAddress': 'ch.report@example.test',
              'phoneNumber': '+41 44 123 45 67',
              'consignorAddress': {
                'streetAddress': 'Report Street',
                'postalCode': '8000',
                'city': 'Zurich',
                'country': {
                  'isoCountryCode': 'CHE',
                  'countryName': 'Switzerland',
                },
              },
              'paymentOption': 'BankTransfer',
              'correspondence': 'de',
              'lastModifiedUtc': '2026-07-02T07:00:00Z',
              'contracts': [],
            },
          ]);
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final snapshot = await buildApi().fetchRemoteSnapshot();
      final issue = snapshot.missingReportFields.single;

      expect(issue.missingFields, contains('Bank name'));
      expect(issue.missingFields, contains('Bank account / IBAN'));
    });
  });
}
