import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/app_settings.dart';
import 'package:leu_consignor_app/src/services/api_service.dart';

void main() {
  late HttpServer server;
  late ApiService api;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = ApiService(
      AppSettings(apiBaseUrl: 'http://127.0.0.1:${server.port}'),
      'test-token',
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('renders with JSON including Unicode and preserves PDF bytes', () async {
    final payload = <String, dynamic>{
      'consignor_signature_name': 'Jörg Müller',
      'signatureData': {'contractSignaturePngBase64': 'AQID'},
    };
    final pdfBytes = utf8.encode('%PDF-1.7\n');
    final handled = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/consignors-app/contracts/render-pdf');
      expect(request.headers.contentType?.mimeType, 'application/json');
      expect(jsonDecode(await utf8.decoder.bind(request).join()), payload);
      request.response.headers.contentType = ContentType('application', 'pdf');
      request.response.add(pdfBytes);
      await request.response.close();
    });

    expect(await api.renderContractPdf(payload), pdfBytes);
    await handled;
  });

  test('413 identifies the server limit and exact UTF-8 request size',
      () async {
    final payload = <String, dynamic>{
      'consignor_signature_name': 'Jörg Müller'
    };
    final handled = server.first.then((request) async {
      final bytes =
          await request.fold<List<int>>([], (all, next) => all..addAll(next));
      expect(bytes, utf8.encode(jsonEncode(payload)));
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
      request.response.write('Request Entity Too Large');
      await request.response.close();
    });

    await expectLater(
      api.renderContractPdf(payload),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          allOf(
            contains('HTTP 413'),
            contains(
                'request size: ${utf8.encode(jsonEncode(payload)).length} bytes'),
            contains('API or its proxy'),
            contains('signatures and attachments'),
          ),
        ),
      ),
    );
    await handled;
  });
}
