import 'dart:io';

import '../data/contract_template_api_client.dart';
import '../data/contract_template_payload.dart';
import '../models/consignor.dart';
import '../models/contract_record.dart';
import '../services/contract_pdf_service.dart';

class ContractTemplatePdfService {
  ContractTemplatePdfService({
    required ContractTemplateApiClient apiClient,
    ContractRenderPayloadBuilder payloadBuilder = const ContractRenderPayloadBuilder(),
  })  : _apiClient = apiClient,
        _payloadBuilder = payloadBuilder;

  final ContractTemplateApiClient _apiClient;
  final ContractRenderPayloadBuilder _payloadBuilder;

  Future<File> generate({
    required Consignor consignor,
    required ContractRecord record,
    required String outputPath,
    Consignor? authorizedRepresentative,
    ContractSignatureData? signatureData,
  }) async {
    final payload = await _payloadBuilder.build(
      consignor: consignor,
      record: record,
      authorizedRepresentative: authorizedRepresentative,
      signatureData: signatureData,
    );

    final bytes = await _apiClient.renderPdf(payload);
    final file = File(outputPath);
    await file.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
