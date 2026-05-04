import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/consignor.dart';
import '../models/contract_record.dart';
import 'api_service.dart';

class ContractSignatureData {
  const ContractSignatureData({
    required this.leuRepresentativeName,
    required this.leuRepresentativeSignatureAsset,
    required this.customerSignaturePng,
    this.leuRepresentativeFunction = 'CEO',
  });

  final String leuRepresentativeName;
  final String leuRepresentativeSignatureAsset;
  final Uint8List customerSignaturePng;
  final String leuRepresentativeFunction;
}

/// Contract PDF generation now delegates the official document rendering to the
/// .NET backend. Flutter still owns the wizard, validation, signature capture,
/// local saving, previewing, and upload flow; the backend owns the Word template,
/// DOCX filling, DOCX-to-PDF conversion, and iText PDF finalization.
class ContractPdfService {
  Future<File> buildContractPdf({
    required ApiService apiService,
    required Consignor consignor,
    required ContractRecord record,
    required String outputPath,
    Consignor? authorizedRepresentative,
    ContractSignatureData? signatureData,
    String commissionPercent = '',
    String consignmentCountry = '',
    String originCountry = '',
    DateTime? auctionDate,
  }) async {
    final payload = await _buildRenderPayload(
      consignor: consignor,
      record: record,
      authorizedRepresentative: authorizedRepresentative,
      signatureData: signatureData,
      commissionPercent: commissionPercent,
      consignmentCountry: consignmentCountry,
      originCountry: originCountry,
      auctionDate: auctionDate,
    );

    final bytes = await apiService.renderContractPdf(payload);
    if (bytes.isEmpty) {
      throw Exception('The backend returned an empty PDF.');
    }

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Map<String, dynamic>> _buildRenderPayload({
    required Consignor consignor,
    required ContractRecord record,
    required Consignor? authorizedRepresentative,
    required ContractSignatureData? signatureData,
    required String commissionPercent,
    required String consignmentCountry,
    required String originCountry,
    required DateTime? auctionDate,
  }) async {
    final leuSignatureBase64 = signatureData == null
        ? ''
        : await _assetAsBase64(signatureData.leuRepresentativeSignatureAsset);

    final customerSignatureBase64 = signatureData == null
        ? ''
        : base64Encode(signatureData.customerSignaturePng);

    final leuRepresentativeFunction =
        (signatureData?.leuRepresentativeFunction.trim().isNotEmpty ?? false)
            ? signatureData!.leuRepresentativeFunction.trim()
            : 'CEO';

    final attachments = <Map<String, dynamic>>[];
    for (final upload in record.uploads) {
      if (upload.isDeleted) continue;

      final fileData = await _uploadFileData(upload);
      if (fileData.trim().isEmpty) continue;

      attachments.add({
        'localId': upload.localId,
        'fileId': upload.fileId ?? 0,
        'auctionId': upload.auctionId ?? record.auctionId,
        'fileType': upload.fileType.apiValue,
        'fileName': _uploadFileName(upload),
        'fileData': fileData,
        'isDeleted': upload.isDeleted,
        'signedAt': upload.signedAt?.toUtc().toIso8601String(),
        'lastModifiedUtc': upload.localLastModifiedUtc.toUtc().toIso8601String(),
      });
    }

    final auctionName = _auctionName(record);
    final consignorIsOwner = authorizedRepresentative == null &&
        consignor.consignorInfo.owner;

    return {
      'templateVersion': 'Einlieferungsvertrag',
      'record': {
        'consignorId': _parseInt(consignor.id) ??
            consignor.systemReferenceConsignor.takeIfPositive ??
            consignor.systemReferenceCustomer.takeIfPositive,
        'auctionId': record.auctionId,
        'auctionDisplayName': auctionName,
        'auctionDate': auctionDate?.toUtc().toIso8601String(),
        'signedAt': record.signedAt.toUtc().toIso8601String(),
        'lastModifiedUtc': record.lastModifiedUtc.toUtc().toIso8601String(),
      },
      'consignor': consignor.toJson(),
      'authorizedRepresentative': authorizedRepresentative?.toJson(),
      'beneficialOwner': authorizedRepresentative?.toJson(),
      'consignorType': consignor.isLegalEntity ? 'LegalEntity' : 'NaturalPerson',
      'consignorIsOwner': consignorIsOwner,
      'auctionName': auctionName,
      'auctionDate': auctionDate?.toUtc().toIso8601String(),
      'commissionPercent': commissionPercent,
      'consignmentCountry': consignmentCountry,
      'originCountry': originCountry,
      'leuRepresentativeName': signatureData?.leuRepresentativeName ?? '',
      'leuRepresentativeFunction': leuRepresentativeFunction,
      'signatureData': {
        'customerSignaturePngBase64': customerSignatureBase64,
        'leuSignaturePngBase64': leuSignatureBase64,
        'annexASignaturePngBase64': customerSignatureBase64,
        'annexCSignaturePngBase64': customerSignatureBase64,
        'leuRepresentativeName': signatureData?.leuRepresentativeName ?? '',
        'leuRepresentativeFunction': leuRepresentativeFunction,
        'consignorSignerNameFunction': consignor.displayName,
      },
      'attachments': attachments,
      'saveToUploads': false,
    };
  }

  Future<String> _assetAsBase64(String assetPath) async {
    final normalized = assetPath.trim();
    if (normalized.isEmpty) return '';

    final data = await rootBundle.load(normalized);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return base64Encode(bytes);
  }

  Future<String> _uploadFileData(ContractUpload upload) async {
    if (upload.fileData.trim().isNotEmpty) {
      return upload.fileData.trim();
    }

    final path = upload.path.trim();
    if (path.isEmpty) return '';

    final file = File(path);
    if (!await file.exists()) return '';

    return base64Encode(await file.readAsBytes());
  }

  String _uploadFileName(ContractUpload upload) {
    if (upload.fileName.trim().isNotEmpty) return upload.fileName.trim();

    final path = upload.path.trim();
    if (path.isEmpty) return 'attachment';

    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    if (slash < 0 || slash == normalized.length - 1) return normalized;
    return normalized.substring(slash + 1);
  }

  String _auctionName(ContractRecord record) {
    if (record.auctionDisplayNames.isNotEmpty) {
      return record.auctionDisplayNames
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .join(', ');
    }
    return record.auctionDisplayName.trim();
  }

  int? _parseInt(String value) => int.tryParse(value.trim());
}

extension _PositiveIntX on int {
  int? get takeIfPositive => this > 0 ? this : null;
}