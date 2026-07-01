import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../domain/consignor_type.dart';
import '../models/address.dart';
import '../models/consignor.dart';
import '../models/contract_record.dart';
import '../models/payment_option.dart';
import '../services/contract_pdf_service.dart';
import '../utils/attachment_utils.dart';
import '../utils/address_formatter.dart';

class ContractRenderPayload {
  ContractRenderPayload(this.values);

  final Map<String, Object?> values;

  Map<String, Object?> toJson() => values;
}

class ContractAttachmentPayload {
  ContractAttachmentPayload({
    required this.kind,
    required this.fileName,
    required this.contentType,
    required this.base64Content,
  });

  final String kind;
  final String fileName;
  final String contentType;
  final String base64Content;

  Map<String, Object?> toJson() => {
        'kind': kind,
        'fileName': fileName,
        'contentType': contentType,
        'base64Content': base64Content,
      };
}

class ContractRenderPayloadBuilder {
  const ContractRenderPayloadBuilder();

  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  Future<ContractRenderPayload> build({
    required Consignor consignor,
    required ContractRecord record,
    Consignor? authorizedRepresentative,
    ContractSignatureData? signatureData,
  }) async {
    final attachmentPayloads = await _buildAttachments(record);
    final hasOrdererIdAttachment = record.uploads.any(
      (upload) =>
          !upload.isDeleted &&
          upload.fileType == UploadType.passport &&
          upload.kind != 'RepresentativeId' &&
          upload.kind != 'RepresentativeIdValidationReport' &&
          upload.kind != 'NaturalPersonIdValidationReport',
    );
    final hasRepresentativeIdAttachment = record.uploads.any(
      (upload) =>
          !upload.isDeleted &&
          upload.fileType == UploadType.passport &&
          upload.kind == 'RepresentativeId',
    );
    final consignorIsOwner = authorizedRepresentative == null;
    final consignorType = consignor.consignorType;
    final includeAnnexA =
        !consignorIsOwner || consignorType == ConsignorType.legalEntity;
    final hasCommercialRegisterAttachment =
        record.registrationFiles.isNotEmpty &&
            consignorType != ConsignorType.naturalPerson;
    final hasLegalEntityRegisterAttachment =
        record.registrationFiles.isNotEmpty &&
            consignorType == ConsignorType.legalEntity;
    final leuSignature = await _readAssetAsBase64(
        signatureData?.leuRepresentativeSignatureAsset);
    final contractSignature = _encodeBytes(signatureData?.contractSignaturePng);
    final annexASignature = _encodeBytes(signatureData?.annexASignaturePng);
    final annexCSignature = _encodeBytes(signatureData?.annexCSignaturePng);
    final auctionDate = record.signedAt;
    final isProvisional = signatureData == null;
    final placeDate = isProvisional ? '' : _dateFormat.format(record.signedAt);
    final watermarkText = isProvisional ? 'PROVISIONAL' : '';
    final pdfFileName = _resolvedPdfName(record);
    final pdfTitle = _pdfTitle(pdfFileName);
    final consignorPersonName = _personNameLastFirst(consignor);
    final authorizedRepresentativePersonName = authorizedRepresentative == null
        ? ''
        : _personNameLastFirst(authorizedRepresentative);

    final bankAccountValue = consignor.bankingDetails.accountNumber;
    final ibanValue = consignor.bankingDetails.isIban ? bankAccountValue : '';
    final accountNumberValue =
        consignor.bankingDetails.isIban ? '' : bankAccountValue;

    return ContractRenderPayload({
      'consignorType': consignorType.apiName,
      'isProvisional': isProvisional,
      'watermarkText': watermarkText,
      'watermark_text': watermarkText,
      'pageWatermarkText': watermarkText,
      'watermark': {'text': watermarkText},
      'pageWatermark': {'text': watermarkText},
      'includePageNumbers': true,
      'pdfName': pdfFileName,
      'pdfFileName': pdfFileName,
      'pdfTitle': pdfTitle,
      'documentTitle': pdfTitle,
      'consignorFullName': consignorPersonName,
      'consignorDateOfBirth': _dateOrNull(consignor.consignorInfo.dateOfBirth),
      'consignorNationality': consignor.consignorInfo.nationalityName,
      'consignorAddress1': _addressLine1(consignor.consignorAddress),
      'consignorAddress2': _addressLine2(consignor.consignorAddress),
      'consignorAddress3': _addressLine3(consignor.consignorAddress),
      'consignorPhone': consignor.fullPhoneNumber,
      'consignorEmail': consignor.emailAddress,
      'consignorIsOwner': consignorIsOwner,
      'legalEntityName': consignorType == ConsignorType.legalEntity
          ? consignor.tradingName
          : '',
      'representativeName': authorizedRepresentative == null
          ? consignorPersonName
          : authorizedRepresentativePersonName,
      'consignorFunction':
          consignorType == ConsignorType.legalEntity ? 'Vertreter' : '',
      'ownerFullName': authorizedRepresentative == null
          ? consignorPersonName
          : authorizedRepresentativePersonName,
      'ownerDateOfBirth':
          _dateOrNull(authorizedRepresentative?.consignorInfo.dateOfBirth),
      'ownerNationality':
          authorizedRepresentative?.consignorInfo.nationalityName ?? '',
      'ownerAddress1': authorizedRepresentative == null
          ? ''
          : _addressLine1(authorizedRepresentative.consignorAddress),
      'ownerAddress2': authorizedRepresentative == null
          ? ''
          : _addressLine2(authorizedRepresentative.consignorAddress),
      'ownerAddress3': authorizedRepresentative == null
          ? ''
          : _addressLine3(authorizedRepresentative.consignorAddress),
      'ownerPhone': authorizedRepresentative?.fullPhoneNumber ?? '',
      'ownerEmail': authorizedRepresentative?.emailAddress ?? '',
      'paymentMethod': consignor.paymentOption.apiName,
      'paymentMethodText': consignor.paymentOption.label,
      'bankName': consignor.bankingDetails.bankName,
      'bankAddress1': _addressLine1(consignor.bankingDetails.bankAddress),
      'bankAddress2': _addressLine2(consignor.bankingDetails.bankAddress),
      'bankAddress3': _addressLine3(consignor.bankingDetails.bankAddress),
      'accountNumber': accountNumberValue,
      'clearingNumber': consignor.bankingDetails.clearingNumber,
      'iban': ibanValue,
      'bicSwift': consignor.bankingDetails.bicSwift,
      'routingNumber': consignor.bankingDetails.routingNumber,
      'beneficiaryName': consignor.bankingDetails.beneficiary.fullName,
      'beneficiaryAddress1':
          _addressLine1(consignor.bankingDetails.beneficiaryAddress),
      'beneficiaryAddress2':
          _addressLine2(consignor.bankingDetails.beneficiaryAddress),
      'beneficiaryAddress3':
          _addressLine3(consignor.bankingDetails.beneficiaryAddress),
      'auctionName': record.auctionDisplayName,
      'auctionDate': _dateFormat.format(auctionDate),
      'commissionPercent': consignor.discount,
      'consignmentCountry': consignor.consignorAddress.countryName,
      'originCountry': consignor.consignorInfo.nationalityName,
      'contractPlaceDate': placeDate,
      'leuPlaceDate': placeDate,
      'annexPlaceDate': placeDate,
      'annexAPlaceDate': placeDate,
      'annexCPlaceDate': placeDate,
      'leuRepresentativeName':
          signatureData?.leuRepresentativeName ?? 'Yves Gunzenreiner',
      'leuRepresentativeCompany': 'Leu Numismatik AG',
      'leuRepresentativeFunction': 'CEO',
      'consignorSignatureBase64Png': contractSignature,
      'leuSignatureBase64Png': leuSignature,
      'annexConsignorSignatureBase64Png': annexASignature,
      'annexAConsignorSignatureBase64Png': annexASignature,
      'annexCConsignorSignatureBase64Png': annexCSignature,
      'hasNaturalPersonIdAttachment':
          hasOrdererIdAttachment && consignorType != ConsignorType.legalEntity,
      'hasCommercialRegisterAttachment': hasCommercialRegisterAttachment,
      'hasRepresentativeIdAttachment':
          authorizedRepresentative != null && hasRepresentativeIdAttachment,
      'hasLegalEntityRegisterAttachment': hasLegalEntityRegisterAttachment,
      'block_attach_commercial_register': hasCommercialRegisterAttachment,
      'show_block_attach_commercial_register': hasCommercialRegisterAttachment,
      'block_attach_commercial_register_start': '',
      'block_attach_commercial_register_end': '',
      'block_attach_register_legal': hasLegalEntityRegisterAttachment,
      'show_block_attach_register_legal': hasLegalEntityRegisterAttachment,
      'block_attach_register_legal_start': '',
      'block_attach_register_legal_end': '',
      'hasAnnexAAttachment': includeAnnexA,
      'hasAnnexBAttachment': record.productFiles.isNotEmpty,
      'hasAnnexCAttachment': true,
      'includeAnnexA': includeAnnexA,
      'templateVersion': 'Einlieferungsvertrag.template.docx',
      'attachments': attachmentPayloads
          .map((item) => item.toJson())
          .toList(growable: false),
    });
  }

  Future<List<ContractAttachmentPayload>> _buildAttachments(
      ContractRecord record) async {
    final attachments =
        AttachmentUtils.mergeUnique(const [], record.attachments);
    final payloads = <ContractAttachmentPayload>[];

    for (final attachment in attachments) {
      if (_isGeneratedContractAttachment(attachment)) {
        continue;
      }

      final file = File(attachment.path);
      if (!await file.exists()) {
        continue;
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        continue;
      }

      final fileName = _fileName(attachment.path);
      payloads.add(
        ContractAttachmentPayload(
          kind: _attachmentKind(attachment.type, fileName, attachment.kind),
          fileName: fileName,
          contentType: _contentType(fileName),
          base64Content: base64Encode(bytes),
        ),
      );
    }

    return payloads;
  }

  String _attachmentKind(UploadType type, String fileName, String kind) {
    if (kind.trim().isNotEmpty) {
      return kind.trim();
    }

    final lower = fileName.toLowerCase();
    if (type == UploadType.passport) {
      return 'IdDocument';
    }
    if (type == UploadType.agreement) {
      return 'CommercialRegister';
    }
    if (lower.endsWith('.pdf')) {
      return 'UploadedPdf';
    }
    if (_isImageFile(lower)) {
      return 'UploadedImage';
    }
    return 'Other';
  }

  bool _isGeneratedContractAttachment(ContractAttachment attachment) {
    if (attachment.type != UploadType.agreement) return false;

    final normalizedKind = _normalizeGeneratedContractToken(attachment.kind);
    if (normalizedKind == 'agreement' ||
        normalizedKind == 'contract' ||
        normalizedKind == 'generatedcontract') {
      return true;
    }

    final normalizedName = _normalizeGeneratedContractToken(attachment.path);
    return normalizedName.contains('einlieferungsvertrag') ||
        normalizedName.contains('consignorcontract') ||
        normalizedName.contains('consignoragreement') ||
        normalizedName.contains('provconsignoragreement');
  }

  String _normalizeGeneratedContractToken(String value) {
    if (value.trim().isEmpty) return '';
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\.[a-z0-9]+$'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  static String _contentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return 'application/octet-stream';
  }

  static bool _isImageFile(String lowerFileName) =>
      lowerFileName.endsWith('.png') ||
      lowerFileName.endsWith('.jpg') ||
      lowerFileName.endsWith('.jpeg') ||
      lowerFileName.endsWith('.webp') ||
      lowerFileName.endsWith('.heic') ||
      lowerFileName.endsWith('.heif');

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\\\', '/');
    final parts =
        normalized.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? 'attachment' : parts.last;
  }

  static String? _dateOrNull(DateTime? value) =>
      value?.toUtc().toIso8601String();

  static String _addressLine1(Address address) {
    return AddressFormatter.contractLine(address, 0);
  }

  static String _addressLine2(Address address) {
    return AddressFormatter.contractLine(address, 1);
  }

  static String _addressLine3(Address address) {
    return AddressFormatter.contractLine(address, 2);
  }

  Future<String> _readAssetAsBase64(String? assetPath) async {
    if (assetPath == null || assetPath.trim().isEmpty) {
      return '';
    }

    final data = await rootBundle.load(assetPath);
    return base64Encode(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  static String _encodeBytes(Uint8List? bytes) =>
      bytes == null || bytes.isEmpty ? '' : base64Encode(bytes);

  static String _personNameLastFirst(Consignor consignor) {
    return [
      _titleText(consignor.consignorInfo.title),
      consignor.consignorInfo.lastName,
      consignor.consignorInfo.firstName,
    ].map((part) => part.trim()).where((part) => part.isNotEmpty).join(' ');
  }

  static String _titleText(int? title) => switch (title) {
        1 => 'Dr.',
        5 => 'Prof.',
        6 => 'Prof. Dr.',
        _ => '',
      };

  static String _resolvedPdfName(ContractRecord record) {
    final value = record.pdfName.trim();
    return value.isEmpty ? 'consignor_contract.pdf' : value;
  }

  static String _pdfTitle(String fileName) {
    final trimmed = fileName.trim();
    if (trimmed.isEmpty) return 'Consignment Agreement';
    return trimmed.replaceAll(RegExp(r'\.[^.]+$'), '');
  }
}
