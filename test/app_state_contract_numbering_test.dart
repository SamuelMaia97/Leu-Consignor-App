import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:leu_consignor_app/src/models/abacus_sync.dart';
import 'package:leu_consignor_app/src/models/app_settings.dart';
import 'package:leu_consignor_app/src/models/contract_record.dart';
import 'package:leu_consignor_app/src/models/sync_status.dart';
import 'package:leu_consignor_app/src/state/app_state.dart';
import 'package:leu_consignor_app/src/storage/local_store.dart';

void main() {
  group('AppState contract numbering', () {
    late Directory tempDir;
    late HttpServer server;
    Map<String, dynamic>? capturedCreatePayload;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('leu_contract_numbering_');
      Hive.init(tempDir.path);
      await Hive.openBox(LocalStore.consignorsBox);
      await Hive.openBox(LocalStore.contractsBox);
      await Hive.openBox(LocalStore.settingsBox);
      await Hive.openBox(LocalStore.wizardDraftsBox);
      await Hive.openBox(LocalStore.activityBox);

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.method == 'POST' &&
            request.uri.path ==
                '/api/consignors-app/consignors/116505/contracts') {
          capturedCreatePayload = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          final file = ((capturedCreatePayload!['files'] as List).single
              as Map<String, dynamic>);

          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'consignorId': 116505,
            'auctionId': 68,
            'lastModifiedUtc': DateTime.now().toUtc().toIso8601String(),
            'list': [
              {
                'localId': 'server-contract',
                'fileId': 42,
                'auctionId': 68,
                'fileType': UploadType.agreement.apiValue,
                'fileName': file['fileName'],
                'lastModifiedUtc': DateTime.now().toUtc().toIso8601String(),
              },
            ],
          }));
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

    test('renames id-shaped generated PDF before Abacus sync', () async {
      final pdf = File('${tempDir.path}${Platform.pathSeparator}contract.pdf');
      await pdf.writeAsBytes([0x25, 0x50, 0x44, 0x46]);

      final state = AppState()
        ..settings = AppSettings(
          apiBaseUrl: 'http://127.0.0.1:${server.port}',
        )
        ..token = 'test-token';
      addTearDown(state.dispose);

      await state.saveContract(
        ContractRecord(
          id: '16505_68_75_82',
          consignorId: '116505',
          auctionId: 68,
          pdfName: '16505_68_75_82.pdf',
          pdfPath: pdf.path,
          uploads: [
            ContractUpload(
              localId: 'generated-contract',
              auctionId: 68,
              fileName: '16505_68_75_82.pdf',
              fileType: UploadType.agreement,
              kind: 'GeneratedContract',
              path: pdf.path,
            ),
          ],
          syncStatus: RecordSyncStatus.pendingSync,
        ),
      );

      final synced = await state.syncContract(
        '116505',
        68,
        syncEvent: AbacusContractSyncEvent.contractGenerated,
      );

      final expectedNumber =
          'PROV-COA-${(DateTime.now().year % 100).toString().padLeft(2, '0')}-1';
      final files = capturedCreatePayload!['files'] as List;
      final file = files.single as Map<String, dynamic>;
      final abacusSync = file['abacusSync'] as Map<String, dynamic>;

      expect(file['fileName'], '$expectedNumber.pdf');
      expect(abacusSync['label'], expectedNumber);
      expect(abacusSync['documentName'], '$expectedNumber.pdf');
      expect(synced?.pdfName, '$expectedNumber.pdf');
    });
  });
}
