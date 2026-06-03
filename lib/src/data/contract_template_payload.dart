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
    final leuSignature = await _readAssetAsBase64(
        signatureData?.leuRepresentativeSignatureAsset);
    final customerSignature = _encodeBytes(signatureData?.customerSignaturePng);
    final auctionDate = record.signedAt;

    return ContractRenderPayload({
      'consignorType': consignorType.apiName,
      'consignorFullName': consignor.displayName,
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
      'representativeName': authorizedRepresentative?.displayName ??
          consignor.consignorInfo.fullName,
      'consignorFunction':
          consignorType == ConsignorType.legalEntity ? 'Vertreter' : '',
      'ownerFullName':
          authorizedRepresentative?.displayName ?? consignor.displayName,
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
      'accountNumber': consignor.bankingDetails.accountNumber,
      'clearingNumber': consignor.bankingDetails.clearingNumber,
      'iban': consignor.bankingDetails.isIban
          ? consignor.bankingDetails.accountNumber
          : '',
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
      'contractPlaceDate': _dateFormat.format(record.signedAt),
      'leuPlaceDate': _dateFormat.format(record.signedAt),
      'annexPlaceDate': _dateFormat.format(record.signedAt),
      'leuRepresentativeName':
          signatureData?.leuRepresentativeName ?? 'Yves Gunzenreiner',
      'leuRepresentativeFunction': 'CEO',
      'consignorSignatureBase64Png': customerSignature,
      'leuSignatureBase64Png': leuSignature,
      'annexConsignorSignatureBase64Png': customerSignature,
      'hasNaturalPersonIdAttachment':
          hasOrdererIdAttachment && consignorType != ConsignorType.legalEntity,
      'hasCommercialRegisterAttachment': record.registrationFiles.isNotEmpty &&
          consignorType != ConsignorType.naturalPerson,
      'hasRepresentativeIdAttachment':
          authorizedRepresentative != null && hasRepresentativeIdAttachment,
      'hasLegalEntityRegisterAttachment': record.registrationFiles.isNotEmpty &&
          consignorType == ConsignorType.legalEntity,
      'hasAnnexAAttachment': includeAnnexA,
      'hasAnnexBAttachment': record.productFiles.isNotEmpty,
      'hasAnnexCAttachment': true,
      'includeAnnexA': includeAnnexA,
      'includePageNumbers': false,
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
      return lower.endsWith('.pdf') ? 'UploadedPdf' : 'CommercialRegister';
    }
    if (lower.endsWith('.pdf')) {
      return 'UploadedPdf';
    }
    if (_isImageFile(lower)) {
      return 'UploadedImage';
    }
    return 'Other';
  }

  static String _contentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  static bool _isImageFile(String lowerFileName) =>
      lowerFileName.endsWith('.png') ||
      lowerFileName.endsWith('.jpg') ||
      lowerFileName.endsWith('.jpeg') ||
      lowerFileName.endsWith('.webp');

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\\\', '/');
    final parts =
        normalized.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? 'attachment' : parts.last;
  }

  static String? _dateOrNull(DateTime? value) =>
      value?.toUtc().toIso8601String();

  static String _addressLine1(Address address) {
    final street = [address.streetAddress, address.streetNumber]
        .where((part) => part.toString().trim().isNotEmpty)
        .join(' ');
    return street.trim();
  }

  static String _addressLine2(Address address) {
    final parts = [address.streetAddressOptional, address.addressInfo]
        .where((part) => part.toString().trim().isNotEmpty)
        .join(', ');
    return parts.trim();
  }

  static String _addressLine3(Address address) {
    final cityLine = [address.postalCode, address.city]
        .where((part) => part.toString().trim().isNotEmpty)
        .join(' ');
    return [cityLine, address.countryName]
        .where((part) => part.toString().trim().isNotEmpty)
        .join(', ');
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
}
