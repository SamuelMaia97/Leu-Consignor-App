import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/abacus_sync.dart';
import 'package:leu_consignor_app/src/models/app_settings.dart';
import 'package:leu_consignor_app/src/models/consignor.dart';
import 'package:leu_consignor_app/src/models/contract_record.dart';
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

    test('falls back to full get-all report rows when detail is unavailable',
        () async {
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
        contains('GET /api/consignors-app/consignors/get/121013'),
      );
    });

    test('hydrates changed consignors from Abacus detail before bank mapping',
        () async {
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/consignors/get-all') {
          await writeJson(request, [
            {
              'systemReferenceCustomer': 113945,
              'tradingName': 'Stale Report Consignor',
              'emailAddress': 'stale@example.test',
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
                'bankName': 'Stale SQL Bank',
                'accountNumber': 'CH9300762011623852957',
                'bankCountry': {
                  'isoCountryCode': 'AFG',
                  'countryName': 'Afghanistan',
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

        if (request.uri.path == '/api/consignors-app/consignors/get/113945') {
          await writeJson(request, {
            'systemReferenceCustomer': 113945,
            'tradingName': 'Abacus Detail Consignor',
            'emailAddress': 'abacus@example.test',
            'phoneNumber': '+41 44 123 45 67',
            'consignorAddress': {
              'streetAddress': 'Detail Street',
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
              'bankCountry': {
                'isoCountryCode': 'CHE',
                'countryName': 'Switzerland',
              },
            },
            'paymentOption': 'BankTransfer',
            'correspondence': 'de',
            'lastModifiedUtc': '2026-07-02T08:00:00Z',
            'contracts': [],
          });
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final snapshot = await buildApi().fetchRemoteSnapshot();
      final consignor = snapshot.consignors.single;

      expect(consignor.id, '113945');
      expect(consignor.bankingDetails.bankName, 'Abacus Maintained Bank');
      expect(consignor.bankingDetails.bankCountryIso3, 'CHE');
      expect(consignor.bankingDetails.bankCountryName, 'Switzerland');
      expect(
        requests,
        containsAll([
          'GET /api/consignors-app/consignors/get-all',
          'GET /api/consignors-app/consignors/get/113945',
        ]),
      );
    });

    test('hydrates existing customer search results from Abacus detail',
        () async {
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/customers/search') {
          await writeJson(request, [
            {
              'customerId': 113945,
              'displayLabel': 'Customer 113945',
              'prefill': {
                'customerId': 113945,
                'tradingName': 'Search Prefill',
                'bankingDetails': {
                  'bankName': 'Search Bank',
                  'accountNumber': 'CH9300762011623852957',
                  'bankCountry': {
                    'isoCountryCode': 'AFG',
                    'countryName': 'Afghanistan',
                  },
                },
              },
            },
          ]);
          return;
        }

        if (request.uri.path == '/api/consignors-app/consignors/get/113945') {
          await writeJson(request, {
            'systemReferenceCustomer': 113945,
            'tradingName': 'Abacus Detail Consignor',
            'bankingDetails': {
              'bankName': 'Abacus Maintained Bank',
              'accountNumber': 'CH9300762011623852957',
              'bankCountry': {
                'isoCountryCode': 'CHE',
                'countryName': 'Switzerland',
              },
            },
            'lastModifiedUtc': '2026-07-02T08:00:00Z',
            'contracts': [],
          });
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final results = await buildApi().searchExistingCustomers('113945');
      final prefill = results.single.prefill;

      expect(prefill.bankingDetails.bankName, 'Abacus Maintained Bank');
      expect(prefill.bankingDetails.bankCountryIso3, 'CHE');
      expect(prefill.bankingDetails.bankCountryName, 'Switzerland');
    });

    test('recreates a missing consignor once using its existing customer',
        () async {
      Map<String, dynamic>? createPayload;
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/consignors/update/2342') {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.badRequest;
          await writeJson(request, {'Error': 'Consignor not found.'});
          return;
        }

        if (request.uri.path == '/api/consignors-app/consignors/bulk-create') {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          final rows = body as List<dynamic>;
          createPayload = (rows.single as Map).cast<String, dynamic>();
          await writeJson(request, [
            {
              'SystemReferenceConsignor': 2401,
              'SystemReferenceCustomer': 12001,
              'AbacusSubjectId': 11217,
              'CustomerAction': 'Existing',
              'ConsignorAction': 'Created',
            },
          ]);
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final consignor = Consignor.empty()
        ..id = 'local-1'
        ..systemReferenceConsignor = 2342
        ..systemReferenceCustomer = 11217
        ..abacusSubjectId = null
        ..existingCustomerId = 11217;

      final result = await buildApi().pushConsignors([consignor]);
      final reference = result.references['local-1']!;

      expect(
        requests,
        equals([
          'PUT /api/consignors-app/consignors/update/2342',
          'POST /api/consignors-app/consignors/bulk-create',
        ]),
      );
      expect(createPayload, isNotNull);
      expect(createPayload!['id'], 'local-1');
      expect(createPayload!['systemReferenceConsignor'], 0);
      expect(createPayload!['systemReferenceCustomer'], 0);
      expect(createPayload!['abacusSubjectId'], isNull);
      expect(createPayload!['existingCustomerId'], 11217);
      expect(consignor.systemReferenceConsignor, 2342);
      expect(consignor.systemReferenceCustomer, 11217);
      expect(result.pushedCount, 1);
      expect(reference.systemReferenceConsignor, 2401);
      expect(reference.systemReferenceCustomer, 12001);
      expect(reference.abacusSubjectId, 11217);
      expect(reference.linkedExistingCustomer, isTrue);
    });

    test('sends customer dates and the invariant single consignment rate',
        () async {
      Map<String, dynamic>? payload;
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/consignors/bulk-create') {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          payload =
              ((body as List<dynamic>).single as Map).cast<String, dynamic>();
          await writeJson(request, [
            {
              'SystemReferenceConsignor': 2402,
              'SystemReferenceCustomer': 12002,
              'AbacusSubjectId': 12002,
              'CustomerAction': 'Created',
              'ConsignorAction': 'Created',
            },
          ]);
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final consignor = Consignor.empty()
        ..id = 'local-date-rate'
        ..passportValidUntil = DateTime.utc(2031, 4, 5)
        ..consignmentRate = '9.25';
      consignor.consignorInfo.dateOfBirth = DateTime.utc(1988, 2, 3);

      await buildApi().pushConsignors([consignor]);

      expect(payload, isNotNull);
      expect(
        (payload!['consignorInfo'] as Map)['dateOfBirth'],
        '1988-02-03',
      );
      expect(payload!['passportDate'], '2031-04-05');
      expect(payload!['passportValidUntil'], '2031-04-05');
      expect(payload!['consignmentRate'], '9.25');
      expect(payload, isNot(contains('UserField16')));
    });

    test('does not recreate a consignor for unrelated update failures',
        () async {
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/consignors/update/77') {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.badRequest;
          await writeJson(request, {'Error': 'Bank details invalid.'});
          return;
        }

        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      };

      final consignor = Consignor.empty()
        ..id = 'local-1'
        ..systemReferenceConsignor = 77
        ..systemReferenceCustomer = 115015;

      await expectLater(
        buildApi().pushConsignors([consignor]),
        throwsA(
          isA<Exception>()
              .having(
                (error) => error.toString(),
                'message',
                contains('HTTP 400'),
              )
              .having(
                (error) => error.toString(),
                'message',
                contains('Bank details invalid.'),
              ),
        ),
      );

      expect(
        requests,
        equals(['PUT /api/consignors-app/consignors/update/77']),
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
        contains('GET /api/consignors-app/consignors/get/121013'),
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

    test('contract sync skips 404 consignors and keeps fetching', () async {
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/consignors/get/121097') {
          await writeJson(request, {
            'consignorId': 121097,
            'systemReferenceCustomer': 121097,
            'consignorInfo': {
              'firstName': 'Test',
              'lastName': 'Consignor',
            },
            'lastModifiedUtc': '2026-07-02T07:00:00Z',
            'contracts': [
              {
                'contractId': 'COA-26-1',
                'auctionDisplayName': 'COA-26-1',
                'lastModifiedUtc': '2026-07-02T08:00:00Z',
                'list': [
                  {
                    'localId': 'abacus-doc-1',
                    'fileType': 2,
                    'fileName': 'COA-26-1.pdf',
                    'lastModifiedUtc': '2026-07-02T08:00:00Z',
                  },
                ],
              },
            ],
          });
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final result = await buildApi().fetchContractsForConsignors([
        100000,
        121097,
      ]);

      expect(result.checkedConsignorCount, 2);
      expect(result.skippedConsignorIds, contains(100000));
      expect(result.failedMessages, isEmpty);
      expect(result.contracts, hasLength(1));
      expect(result.contracts.single.id, 'COA-26-1');
      expect(result.contracts.single.auctionId, isNull);
      expect(result.contracts.single.synced, isTrue);
    });

    test('global contract sync imports Abacus COA metadata', () async {
      handler = (request) async {
        if (request.uri.path == '/api/consignors-app/contracts/get-all') {
          await writeJson(request, [
            {
              'consignorId': 121097,
              'contractId': 'COA-26-1',
              'auctionDisplayName': 'COA-26-1',
              'lastModifiedUtc': '2026-07-02T08:00:00Z',
              'list': [
                {
                  'localId': 'abacus-doc-1',
                  'fileType': 2,
                  'fileName': 'COA-26-1.pdf',
                  'lastModifiedUtc': '2026-07-02T08:00:00Z',
                },
              ],
            },
          ]);
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final result = await buildApi().fetchAllContracts();

      expect(result.analyzedDocumentCount, 1);
      expect(result.contracts, hasLength(1));
      expect(result.contracts.single.id, 'COA-26-1');
      expect(result.contracts.single.consignorId, '121097');
      expect(result.contracts.single.pdfName, 'COA-26-1.pdf');
      expect(result.contracts.single.synced, isTrue);
      expect(
        requests,
        isNot(contains('GET /api/consignors-app/consignors/get/121097')),
      );
    });

    test('contract sync preserves local auction when Abacus omits auction id',
        () async {
      handler = (request) async {
        if (request.uri.path ==
            '/api/consignors-app/consignors/121097/contracts/7/sync') {
          await writeJson(request, {
            'contractId': 'COA-26-1',
            'auctionDisplayName': 'COA-26-1',
            'lastModifiedUtc': '2026-07-02T08:00:00Z',
            'list': [
              {
                'localId': 'abacus-doc-1',
                'fileId': 10,
                'fileType': 2,
                'fileName': 'COA-26-1.pdf',
                'lastModifiedUtc': '2026-07-02T08:00:00Z',
              },
            ],
          });
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final timestamp = DateTime.utc(2026, 7, 2, 8);
      final record = ContractRecord.empty(
        '121097',
        auctionIds: [7],
        auctionDisplayNames: ['Auction 7'],
      ).copyWith(
        uploads: [
          ContractUpload(
            localId: 'abacus-doc-1',
            fileId: 10,
            fileType: UploadType.agreement,
            fileName: 'COA-26-1.pdf',
            localLastModifiedUtc: timestamp,
            serverLastModifiedUtc: timestamp,
          ),
        ],
      );

      final synced = await buildApi().syncContractRecord(
        121097,
        record,
        syncEvent: AbacusContractSyncEvent.contractGenerated,
      );

      expect(synced.auctionId, 7);
      expect(synced.auctionDisplayName, 'Auction 7');
      expect(synced.synced, isTrue);
    });
  });
}
