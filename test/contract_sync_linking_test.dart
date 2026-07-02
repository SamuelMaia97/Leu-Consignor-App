import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:leu_consignor_app/src/models/app_settings.dart';
import 'package:leu_consignor_app/src/repositories/contract_repository.dart';
import 'package:leu_consignor_app/src/services/api_service.dart';
import 'package:leu_consignor_app/src/state/app_state.dart';
import 'package:leu_consignor_app/src/storage/local_store.dart';

void main() {
  group('global contract sync linking', () {
    late Directory tempDir;
    late HttpServer server;
    late List<String> requests;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('leu_contract_sync_');
      Hive.init(tempDir.path);
      await Hive.openBox(LocalStore.consignorsBox);
      await Hive.openBox(LocalStore.contractsBox);
      await Hive.openBox(LocalStore.settingsBox);
      await Hive.openBox(LocalStore.wizardDraftsBox);

      requests = <String>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        if (request.uri.path == '/api/consignors-app/contracts/get-all') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode([
            {
              'consignorId': 121097,
              'contractId': 'COC-26-142037',
              'auctionDisplayName': 'COC-26-142037',
              'lastModifiedUtc': '2026-07-02T14:29:21+02:00',
              'list': [
                {
                  'localId': 'abacus-contract-doc-1',
                  'fileType': 2,
                  'fileName': 'COC-26-142037.pdf',
                  'lastModifiedUtc': '2026-07-02T14:29:21+02:00',
                },
              ],
            },
            {
              'consignorId': 121098,
              'contractId': 'PROV-COC-26-142037',
              'auctionDisplayName': 'PROV-COC-26-142037',
              'lastModifiedUtc': '2026-07-02T14:19:20+02:00',
              'list': [
                {
                  'localId': 'abacus-contract-doc-2',
                  'fileType': 2,
                  'fileName': 'PROV-COC-26-142037.pdf',
                  'lastModifiedUtc': '2026-07-02T14:19:20+02:00',
                },
              ],
            },
          ]));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('imports global Abacus contracts and links them to consignors',
        () async {
      final api = ApiService(
        AppSettings(apiBaseUrl: 'http://127.0.0.1:${server.port}'),
        'test-token',
      );

      final result = await api.fetchAllContracts();
      expect(result.contracts, hasLength(2));
      expect(result.analyzedDocumentCount, 2);
      expect(
        requests,
        ['GET /api/consignors-app/contracts/get-all'],
      );

      final repository = ContractRepository();
      await repository.putAll(result.contracts);

      final state = AppState();
      addTearDown(state.dispose);

      final cocContracts = state.contractsForConsignor('121097');
      expect(cocContracts, hasLength(1));
      expect(cocContracts.single.id, 'COC-26-142037');
      expect(cocContracts.single.pdfName, 'COC-26-142037.pdf');

      final provisionalContracts = state.contractsForConsignor('121098');
      expect(provisionalContracts, hasLength(1));
      expect(provisionalContracts.single.id, 'PROV-COC-26-142037');
      expect(provisionalContracts.single.pdfName, 'PROV-COC-26-142037.pdf');
    });
  });
}
