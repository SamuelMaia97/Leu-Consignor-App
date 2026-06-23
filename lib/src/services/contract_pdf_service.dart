import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../domain/consignor_type.dart';
import '../models/address.dart';
import '../models/consignor.dart';
import '../models/contract_record.dart';
import '../models/payment_option.dart';
import '../models/person.dart';
import '../utils/address_formatter.dart';
import 'api_service.dart';

class ContractSignatureData {
  const ContractSignatureData({
    required this.leuRepresentativeName,
    required this.leuRepresentativeSignatureAsset,
    required this.contractSignaturePng,
    required this.annexASignaturePng,
    required this.annexCSignaturePng,
    this.leuRepresentativeFunction = 'CEO',
  });

  final String leuRepresentativeName;
  final String leuRepresentativeSignatureAsset;
  final Uint8List contractSignaturePng;
  final Uint8List annexASignaturePng;
  final Uint8List annexCSignaturePng;
  final String leuRepresentativeFunction;

  Uint8List get customerSignaturePng => contractSignaturePng;
}

/// Contract PDF generation now delegates the official document rendering to the
/// .NET backend. Flutter still owns the wizard, validation, signature capture,
/// local saving, previewing, and upload flow; the backend owns the Word template,
/// DOCX filling, DOCX-to-PDF conversion, and iText PDF finalization.
class ContractPdfService {
  ContractPdfService({
    ContractPdfPayloadBuilder payloadBuilder =
        const ContractPdfPayloadBuilder(),
  }) : _payloadBuilder = payloadBuilder;

  final ContractPdfPayloadBuilder _payloadBuilder;

  Future<File> buildContractPdf({
    required ApiService apiService,
    required Consignor consignor,
    required ContractRecord record,
    required String outputPath,
    Consignor? authorizedRepresentative,
    ContractSignatureData? signatureData,
    String commissionPercent = '',
    String consignmentCountry = '',
    String consignmentCountryIso3 = '',
    String originCountry = '',
    DateTime? auctionDate,
  }) async {
    final payload = await _payloadBuilder.build(
      consignor: consignor,
      record: record,
      authorizedRepresentative: authorizedRepresentative,
      signatureData: signatureData,
      commissionPercent: commissionPercent,
      consignmentCountry: consignmentCountry,
      consignmentCountryIso3: consignmentCountryIso3,
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
}

class ContractPdfPayloadBuilder {
  const ContractPdfPayloadBuilder();

  static final DateFormat _displayDateFormat = DateFormat('dd.MM.yyyy');

  Future<Map<String, dynamic>> build({
    required Consignor consignor,
    required ContractRecord record,
    Consignor? authorizedRepresentative,
    ContractSignatureData? signatureData,
    String commissionPercent = '',
    String consignmentCountry = '',
    String consignmentCountryIso3 = '',
    String originCountry = '',
    DateTime? auctionDate,
  }) async {
    final leuSignatureBase64 = signatureData == null
        ? ''
        : await _assetAsBase64(signatureData.leuRepresentativeSignatureAsset);

    final contractSignatureBase64 = signatureData == null
        ? ''
        : base64Encode(signatureData.contractSignaturePng);
    final annexASignatureBase64 = signatureData == null
        ? ''
        : base64Encode(signatureData.annexASignaturePng);
    final annexCSignatureBase64 = signatureData == null
        ? ''
        : base64Encode(signatureData.annexCSignaturePng);
    final isProvisional = signatureData == null;
    final watermarkText = isProvisional ? 'PROVISIONAL' : '';

    final attachments = <Map<String, dynamic>>[];
    for (final upload in record.uploads) {
      if (upload.isDeleted) continue;
      if (upload.isGeneratedContractPdf) continue;

      final fileData = await _uploadFileData(upload);
      if (fileData.trim().isEmpty) continue;

      attachments.add({
        'localId': upload.localId,
        'fileId': upload.fileId ?? 0,
        'auctionId': upload.auctionId ?? record.auctionId,
        'fileType': upload.fileType.apiValue,
        'kind': upload.kind.trim().isEmpty ? null : upload.kind.trim(),
        'fileName': _uploadFileName(upload),
        'fileData': fileData,
        'isDeleted': upload.isDeleted,
        'signedAt': upload.signedAt?.toUtc().toIso8601String(),
        'lastModifiedUtc':
            upload.localLastModifiedUtc.toUtc().toIso8601String(),
      });
    }
    final hasOrdererIdFiles = record.uploads.any(
      (upload) =>
          !upload.isDeleted &&
          upload.fileType == UploadType.passport &&
          upload.kind != 'RepresentativeId' &&
          upload.kind != 'RepresentativeIdValidationReport' &&
          upload.kind != 'NaturalPersonIdValidationReport',
    );
    final hasRepresentativeIdFiles = record.uploads.any(
      (upload) =>
          !upload.isDeleted &&
          upload.fileType == UploadType.passport &&
          upload.kind == 'RepresentativeId',
    );

    final auctionName = _auctionName(record, consignor.correspondence);
    final scenario = _ContractRenderScenario.from(
      consignor: consignor,
      authorizedRepresentative: authorizedRepresentative,
    );
    final paragraphVisibility = _paragraphVisibilityFor(scenario);
    final paragraphVisibilityPayload = {
      for (final entry in paragraphVisibility.entries) entry.key: entry.value,
    };
    final paragraphTopLevelFlags = {
      for (final entry in paragraphVisibility.entries)
        'show${entry.key}': entry.value,
    };
    final consignorIsOwner =
        authorizedRepresentative == null && consignor.consignorInfo.owner;
    final effectiveAuctionDate = auctionDate ?? record.signedAt;
    final resolvedCommissionPercent = commissionPercent.trim().isNotEmpty
        ? commissionPercent.trim()
        : _percentText(consignor.discount);
    final resolvedConsignmentCountry = consignmentCountry.trim().isNotEmpty
        ? consignmentCountry.trim()
        : consignor.consignorAddress.countryName;
    final resolvedConsignmentCountryIso3 = consignmentCountryIso3.trim();
    final resolvedOriginCountry = originCountry.trim().isNotEmpty
        ? originCountry.trim()
        : consignor.consignorInfo.nationalityName;
    final representative = authorizedRepresentative;
    final legalRepresentativeName = representative == null
        ? _contractDisplayName(consignor)
        : _contractDisplayName(representative);
    final legalRepresentativePhone =
        representative?.fullPhoneNumber ?? consignor.fullPhoneNumber;
    final legalRepresentativeEmail =
        representative?.emailAddress ?? consignor.emailAddress;
    final owner = representative == null ? null : consignor;
    final ownerIsLegal = owner?.usesTradingName ?? false;
    final leuRepresentativeName = signatureData?.leuRepresentativeName ?? '';
    final leuRepresentativeFunction = _leuRepresentativeFunction(signatureData);
    final signerName = _contractDisplayName(consignor);
    final pdfFileName = _resolvedPdfName(record);
    final pdfTitle = _pdfTitle(pdfFileName);
    final templateValues = _templateValues(
      consignor: consignor,
      owner: owner,
      ownerIsLegal: ownerIsLegal,
      representedByAnotherParty: authorizedRepresentative != null,
      isProvisional: isProvisional,
      record: record,
      scenario: scenario,
      paragraphVisibility: paragraphVisibility,
      auctionName: auctionName,
      auctionDate: effectiveAuctionDate,
      commissionPercent: resolvedCommissionPercent,
      consignmentCountry: resolvedConsignmentCountry,
      originCountry: resolvedOriginCountry,
      leuRepresentativeName: leuRepresentativeName,
      leuRepresentativeFunction: leuRepresentativeFunction,
      legalRepresentativeName: legalRepresentativeName,
      legalRepresentativePhone: legalRepresentativePhone,
      legalRepresentativeEmail: legalRepresentativeEmail,
      contractSignatureBase64: contractSignatureBase64,
      annexASignatureBase64: annexASignatureBase64,
      annexCSignatureBase64: annexCSignatureBase64,
      leuSignatureBase64: leuSignatureBase64,
    );
    final templateFlags = _templateFlags(
      scenario: scenario,
      consignorIsOwner: consignorIsOwner,
      ownerIsLegal: ownerIsLegal,
      hasOrdererIdFiles: hasOrdererIdFiles,
      hasRepresentativeIdFiles: hasRepresentativeIdFiles,
      hasCommercialRegisterFiles: record.registrationFiles.isNotEmpty,
      paragraphVisibility: paragraphVisibility,
    );

    return {
      'templateVersion': 'Einlieferungsvertrag',
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
      'record': {
        'consignorId': _parseInt(consignor.id) ??
            consignor.systemReferenceConsignor.takeIfPositive ??
            consignor.systemReferenceCustomer.takeIfPositive,
        'auctionId': record.auctionId,
        'auctionDisplayName': auctionName,
        'auctionDate': auctionDate?.toUtc().toIso8601String(),
        'signedAt': record.signedAt.toUtc().toIso8601String(),
        'lastModifiedUtc': record.lastModifiedUtc.toUtc().toIso8601String(),
        'pdfName': pdfFileName,
        'pdfTitle': pdfTitle,
      },
      'consignor': consignor.toJson(),
      'authorizedRepresentative': authorizedRepresentative?.toJson(),
      'beneficialOwner':
          authorizedRepresentative == null ? null : consignor.toJson(),
      'consignorType': consignor.consignorType.apiName,
      'contractScenario': scenario.apiName,
      'contractScenarioColumn': scenario.excelColumnKey,
      'representativeType': scenario.representativeType?.apiName,
      'consignorIsOwner': consignorIsOwner,
      'auctionName': auctionName,
      'auctionDate': auctionDate?.toUtc().toIso8601String(),
      'commissionPercent': resolvedCommissionPercent,
      'consignmentCountry': resolvedConsignmentCountry,
      'consignmentCountryIsoCountryCode': resolvedConsignmentCountryIso3,
      'originCountry': resolvedOriginCountry,
      'leuRepresentativeName': signatureData?.leuRepresentativeName ?? '',
      'leuRepresentativeFunction': leuRepresentativeFunction,
      'paragraphVisibility': paragraphVisibilityPayload,
      'templateFlags': templateFlags,
      ...paragraphTopLevelFlags,
      ...templateValues,
      'signatureData': {
        'customerSignaturePngBase64': contractSignatureBase64,
        'contractSignaturePngBase64': contractSignatureBase64,
        'leuSignaturePngBase64': leuSignatureBase64,
        'annexASignaturePngBase64': annexASignatureBase64,
        'annexCSignaturePngBase64': annexCSignatureBase64,
        'leuRepresentativeName': signatureData?.leuRepresentativeName ?? '',
        'leuRepresentativeFunction': leuRepresentativeFunction,
        'consignorSignerNameFunction': signerName,
      },
      'attachments': attachments,
      'saveToUploads': false,
    };
  }

  Map<String, dynamic> _templateValues({
    required Consignor consignor,
    required Consignor? owner,
    required bool ownerIsLegal,
    required bool representedByAnotherParty,
    required bool isProvisional,
    required ContractRecord record,
    required _ContractRenderScenario scenario,
    required Map<String, bool> paragraphVisibility,
    required String auctionName,
    required DateTime auctionDate,
    required String commissionPercent,
    required String consignmentCountry,
    required String originCountry,
    required String leuRepresentativeName,
    required String leuRepresentativeFunction,
    required String legalRepresentativeName,
    required String legalRepresentativePhone,
    required String legalRepresentativeEmail,
    required String contractSignatureBase64,
    required String annexASignatureBase64,
    required String annexCSignatureBase64,
    required String leuSignatureBase64,
  }) {
    final ownerOrEmpty = owner;
    final ownerAddress = ownerOrEmpty?.consignorAddress;
    final legalOwnerCompany =
        ownerIsLegal ? ownerOrEmpty?.tradingName ?? '' : '';
    final legalOwnerRepName =
        ownerIsLegal ? _personNameLastFirst(ownerOrEmpty!.consignorInfo) : '';
    final consignorPersonName = _personNameLastFirst(consignor.consignorInfo);
    final ownerPersonName = ownerOrEmpty == null
        ? ''
        : _personNameLastFirst(ownerOrEmpty.consignorInfo);
    final consignorName = _contractDisplayName(consignor);
    final leuCompanyName = 'Leu Numismatik AG';
    final contractDate = isProvisional ? '' : _formatDate(record.signedAt);

    final bankAccountValue = consignor.bankingDetails.accountNumber;
    final ibanValue = consignor.bankingDetails.isIban ? bankAccountValue : '';
    final accountNumberValue =
        consignor.bankingDetails.isIban ? '' : bankAccountValue;

    final values = <String, dynamic>{
      'account_number': accountNumberValue,
      'auction_name': auctionName,
      'auction_date': _formatDate(auctionDate),
      'commission_percent': commissionPercent,
      'consignment_country': consignmentCountry,
      'CountryOfConsignment': consignmentCountry,
      'country_of_consignment': consignmentCountry,
      'origin_country': originCountry,
      'consignor_full_name': consignorPersonName,
      'consignor_dob': _formatDate(consignor.consignorInfo.dateOfBirth),
      'consignor_nationality': consignor.consignorInfo.nationalityName,
      'consignor_address_1': _addressLine1(consignor.consignorAddress),
      'consignor_address_2': _addressLine2(consignor.consignorAddress),
      'consignor_address_3': _addressLine3(consignor.consignorAddress),
      'consignor_phone': consignor.fullPhoneNumber,
      'consignor_email': consignor.emailAddress,
      'consignor_place_date': contractDate,
      'contract_place_date': contractDate,
      'contractPlaceDate': contractDate,
      'consignor_signature_image': contractSignatureBase64,
      'consignor_signature_prefix': representedByAnotherParty ? 'i.A. ' : '',
      'consignor_signature_name': consignorName,
      'consignor_signer_name_function': consignorName,
      'legal_entity_name': scenario.consignorType == ConsignorType.legalEntity
          ? consignor.tradingName
          : '',
      'legal_entity_address_1':
          scenario.consignorType == ConsignorType.legalEntity
              ? _addressLine1(consignor.consignorAddress)
              : '',
      'legal_entity_address_2':
          scenario.consignorType == ConsignorType.legalEntity
              ? _addressLine2(consignor.consignorAddress)
              : '',
      'legal_entity_address_3':
          scenario.consignorType == ConsignorType.legalEntity
              ? _addressLine3(consignor.consignorAddress)
              : '',
      'representative_name': legalRepresentativeName,
      'representative_phone': legalRepresentativePhone,
      'representative_email': legalRepresentativeEmail,
      'owner_full_name': ownerPersonName,
      'owner_dob': _formatDate(ownerOrEmpty?.consignorInfo.dateOfBirth),
      'owner_nationality': ownerOrEmpty?.consignorInfo.nationalityName ?? '',
      'owner_address_1':
          ownerAddress == null ? '' : _addressLine1(ownerAddress),
      'owner_address_2':
          ownerAddress == null ? '' : _addressLine2(ownerAddress),
      'owner_address_3':
          ownerAddress == null ? '' : _addressLine3(ownerAddress),
      'owner_phone': ownerOrEmpty?.fullPhoneNumber ?? '',
      'owner_email': ownerOrEmpty?.emailAddress ?? '',
      'payment_method': consignor.paymentOption.apiName,
      'payment_method_text': consignor.paymentOption.label,
      'bank_name': consignor.bankingDetails.bankName,
      'bank_address_1': _addressLine1(consignor.bankingDetails.bankAddress),
      'bank_address_2': _addressLine2(consignor.bankingDetails.bankAddress),
      'bank_address_3': _addressLine3(consignor.bankingDetails.bankAddress),
      'beneficiary_name': consignor.bankingDetails.beneficiary.fullName,
      'beneficiary_address_1':
          _addressLine1(consignor.bankingDetails.beneficiaryAddress),
      'beneficiary_address_2':
          _addressLine2(consignor.bankingDetails.beneficiaryAddress),
      'beneficiary_address_3':
          _addressLine3(consignor.bankingDetails.beneficiaryAddress),
      'iban': ibanValue,
      'bic_swift': consignor.bankingDetails.bicSwift,
      'clearing_nr': consignor.bankingDetails.clearingNumber,
      'routing_nr': consignor.bankingDetails.routingNumber,
      'leu_place_date': contractDate,
      'leuPlaceDate': contractDate,
      'leu_representative_company': leuCompanyName,
      'leu_representative_name': leuRepresentativeName,
      'leu_representative_function': leuRepresentativeFunction,
      'leu_representative_name_function': [
        leuCompanyName,
        leuRepresentativeName,
      ].where((part) => part.trim().isNotEmpty).join(' / '),
      'leu_signature_image': leuSignatureBase64,
      'annex_a_auction_name': auctionName,
      'annex_a_auction_date': _formatDate(auctionDate),
      'annex_a_place_date': contractDate,
      'annexAPlaceDate': contractDate,
      'annex_place_date': contractDate,
      'annexPlaceDate': contractDate,
      'annex_a_signature_image': annexASignatureBase64,
      'annex_a_signature_prefix': representedByAnotherParty ? 'i.A. ' : '',
      'annex_a_signature_name': consignorName,
      'annex_a_signer_name': consignorName,
      'annex_a_owner_full_name': ownerIsLegal ? '' : ownerPersonName,
      'annex_a_owner_dob': ownerIsLegal
          ? ''
          : _formatDate(ownerOrEmpty?.consignorInfo.dateOfBirth),
      'annex_a_owner_nationality':
          ownerIsLegal ? '' : ownerOrEmpty?.consignorInfo.nationalityName ?? '',
      'annex_a_owner_address_1': ownerIsLegal || ownerAddress == null
          ? ''
          : _addressLine1(ownerAddress),
      'annex_a_owner_address_2': ownerIsLegal || ownerAddress == null
          ? ''
          : _addressLine2(ownerAddress),
      'annex_a_owner_address_3': ownerIsLegal || ownerAddress == null
          ? ''
          : _addressLine3(ownerAddress),
      'annex_a_owner_phone':
          ownerIsLegal ? '' : ownerOrEmpty?.fullPhoneNumber ?? '',
      'annex_a_owner_email':
          ownerIsLegal ? '' : ownerOrEmpty?.emailAddress ?? '',
      'annex_a_legal_company': legalOwnerCompany,
      'annex_a_legal_rep_name': legalOwnerRepName,
      'annex_a_legal_rep_dob': ownerIsLegal
          ? _formatDate(ownerOrEmpty?.consignorInfo.dateOfBirth)
          : '',
      'annex_a_legal_rep_nationality':
          ownerIsLegal ? ownerOrEmpty?.consignorInfo.nationalityName ?? '' : '',
      'annex_a_legal_address_1': ownerIsLegal && ownerAddress != null
          ? _addressLine1(ownerAddress)
          : '',
      'annex_a_legal_address_2': ownerIsLegal && ownerAddress != null
          ? _addressLine2(ownerAddress)
          : '',
      'annex_a_legal_address_3': ownerIsLegal && ownerAddress != null
          ? _addressLine3(ownerAddress)
          : '',
      'annex_a_legal_phone':
          ownerIsLegal ? ownerOrEmpty?.fullPhoneNumber ?? '' : '',
      'annex_a_legal_email':
          ownerIsLegal ? ownerOrEmpty?.emailAddress ?? '' : '',
      'annex_c_place_date': contractDate,
      'annexCPlaceDate': contractDate,
      'annex_c_signature_image': annexCSignatureBase64,
      'annex_c_signature_prefix': representedByAnotherParty ? 'i.A. ' : '',
      'annex_c_signature_name': consignorName,
      'annex_c_signer_name': consignorName,
      'attachment_id_natural_images': '',
      'attachment_commercial_register_images': '',
      'attachment_id_representative_images': '',
      'attachment_register_legal_images': '',
      'product_images': '',
      'check_natural_person':
          _checkbox(scenario.consignorType == ConsignorType.naturalPerson),
      'check_sole_proprietor':
          _checkbox(scenario.consignorType == ConsignorType.soleProprietor),
      'check_legal_entity':
          _checkbox(scenario.consignorType == ConsignorType.legalEntity),
      'check_payment_bank_transfer':
          _checkbox(consignor.paymentOption == PaymentOption.bankTransfer),
      'check_payment_wise':
          _checkbox(consignor.paymentOption == PaymentOption.wise),
      'check_payment_cash':
          _checkbox(consignor.paymentOption == PaymentOption.cash),
      'check_payment_pending':
          _checkbox(consignor.paymentOption == PaymentOption.pending),
      'check_attach_id_natural':
          _checkbox(paragraphVisibility['Paragraf13'] ?? false),
      'check_attach_commercial_register':
          _checkbox(paragraphVisibility['Paragraf14'] ?? false),
      'check_attach_id_representative':
          _checkbox(paragraphVisibility['Paragraf15'] ?? false),
      'check_attach_register_legal':
          _checkbox(paragraphVisibility['Paragraf16'] ?? false),
      'check_attach_annex_a': _checkbox(true),
      'check_attach_annex_b': _checkbox(record.productFiles.isNotEmpty),
      'check_attach_annex_c': _checkbox(true),
    };

    for (final blockName in _blockMarkerNames) {
      values['${blockName}_start'] = '';
      values['${blockName}_end'] = '';
    }

    return values;
  }

  Map<String, bool> _templateFlags({
    required _ContractRenderScenario scenario,
    required bool consignorIsOwner,
    required bool ownerIsLegal,
    required bool hasOrdererIdFiles,
    required bool hasRepresentativeIdFiles,
    required bool hasCommercialRegisterFiles,
    required Map<String, bool> paragraphVisibility,
  }) {
    final requiresRepresentativeId = paragraphVisibility['Paragraf15'] ?? false;
    final requiresConsignorRegister =
        paragraphVisibility['Paragraf14'] ?? false;
    final requiresRepresentativeRegister =
        paragraphVisibility['Paragraf16'] ?? false;

    return {
      'blockAttachIdNatural':
          hasOrdererIdFiles && (paragraphVisibility['Paragraf13'] ?? false),
      'blockAttachCommercialRegister':
          hasCommercialRegisterFiles && requiresConsignorRegister,
      'blockAttachIdRepresentative':
          hasRepresentativeIdFiles && requiresRepresentativeId,
      'blockAttachRegisterLegal':
          hasCommercialRegisterFiles && requiresRepresentativeRegister,
      'blockAnnexASelfOwnerStatement':
          paragraphVisibility['Paragraf17'] ?? false,
      'blockAnnexANaturalOwnerDetails': !consignorIsOwner && !ownerIsLegal,
      'blockAnnexALegalOwnerDetails': !consignorIsOwner && ownerIsLegal,
      'blockAnnexALegalRepresentativeCapacity':
          scenario.consignorType == ConsignorType.legalEntity ||
              scenario.representativeType == ConsignorType.legalEntity,
      'blockAnnexAProvenanceSelf': paragraphVisibility['Paragraf22'] ?? false,
      'blockAnnexAProvenanceOnBehalf':
          paragraphVisibility['Paragraf23'] ?? false,
      'includeAnnexA': true,
      'includeAnnexB': true,
      'includeAnnexC': true,
    };
  }

  Map<String, bool> _paragraphVisibilityFor(
    _ContractRenderScenario scenario,
  ) {
    const matrix = <String, List<bool>>{
      'Paragraf1': [false, false, false, false, false, false, false, false],
      'Paragraf2': [false, false, false, false, false, true, true, true],
      'Paragraf3': [false, false, false, false, false, true, true, true],
      'Paragraf4': [true, true, true, false, false, true, true, true],
      'Paragraf5': [false, false, false, true, true, false, false, false],
      'Paragraf6': [false, false, false, true, true, false, false, false],
      'Paragraf7': [false, true, true, true, true, false, true, true],
      'Paragraf8': [false, false, true, false, true, false, false, false],
      'Paragraf9': [true, false, false, false, false, false, false, false],
      'Paragraf10': [false, true, false, false, false, false, true, false],
      'Paragraf11': [false, false, true, true, false, true, false, false],
      'Paragraf12': [false, false, false, false, true, false, false, true],
      'Paragraf13': [true, true, true, true, true, true, true, true],
      'Paragraf14': [false, false, false, true, true, true, true, true],
      'Paragraf15': [false, true, true, true, true, false, true, true],
      'Paragraf16': [false, false, true, false, true, false, false, true],
      'Paragraf17': [true, false, false, false, false, true, false, false],
      'Paragraf18': [false, true, false, false, false, false, true, false],
      'Paragraf19': [false, false, false, false, true, false, false, true],
      'Paragraf20': [false, false, true, false, false, false, false, false],
      'Paragraf21': [false, false, false, true, true, true, true, true],
      'Paragraf22': [true, false, false, false, false, true, false, false],
      'Paragraf23': [false, true, true, true, true, false, true, true],
    };

    return {
      for (final entry in matrix.entries)
        entry.key: entry.value[scenario.excelColumnIndex],
    };
  }

  static String _leuRepresentativeFunction(ContractSignatureData? value) {
    final function = value?.leuRepresentativeFunction.trim();
    return function == null || function.isEmpty ? 'CEO' : function;
  }

  static String _percentText(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  static String _formatDate(DateTime? value) {
    if (value == null) return '';
    return _displayDateFormat.format(value.toLocal());
  }

  static String _checkbox(bool checked) => checked ? '☑' : '☐';

  static String _addressLine1(Address address) {
    return AddressFormatter.contractLine(address, 0);
  }

  static String _addressLine2(Address address) {
    return AddressFormatter.contractLine(address, 1);
  }

  static String _addressLine3(Address address) {
    return AddressFormatter.contractLine(address, 2);
  }

  static String _contractDisplayName(Consignor consignor) {
    if (consignor.usesTradingName && consignor.tradingName.trim().isNotEmpty) {
      return consignor.tradingName.trim();
    }
    return _personNameLastFirst(consignor.consignorInfo);
  }

  static String _personNameLastFirst(Person person) {
    return [_titleText(person.title), person.lastName, person.firstName]
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
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

  Future<String> _assetAsBase64(String assetPath) async {
    final normalized = assetPath.trim();
    if (normalized.isEmpty) return '';

    final data = await rootBundle.load(normalized);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
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

  String _auctionName(ContractRecord record, String? correspondence) {
    if (record.auctionDisplayNames.isNotEmpty) {
      return record.auctionDisplayNames
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .map((value) => _localizedAuctionName(value, correspondence))
          .join(', ');
    }
    return _localizedAuctionName(
        record.auctionDisplayName.trim(), correspondence);
  }

  String _localizedAuctionName(String value, String? correspondence) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    final isGerman = correspondence?.trim().toLowerCase() == 'de';
    if (isGerman) {
      return trimmed
          .replaceAll(
            RegExp(r'\bWeb\s+Auction\b', caseSensitive: false),
            'Web Auktion',
          )
          .replaceAll(
            RegExp(r'\bAuction\b', caseSensitive: false),
            'Auktion',
          );
    }

    return trimmed
        .replaceAll(
          RegExp(r'\bWeb\s+Auktion\b', caseSensitive: false),
          'Web Auction',
        )
        .replaceAll(
          RegExp(r'\bAuktion\b', caseSensitive: false),
          'Auction',
        );
  }

  int? _parseInt(String value) => int.tryParse(value.trim());
}

const _blockMarkerNames = [
  'block_attach_id_natural',
  'block_attach_commercial_register',
  'block_attach_id_representative',
  'block_attach_register_legal',
  'block_annex_a_self_owner_statement',
  'block_annex_a_natural_owner_details',
  'block_annex_a_legal_owner_details',
  'block_annex_a_legal_representative_capacity',
  'block_annex_a_provenance_self',
  'block_annex_a_provenance_on_behalf',
];

enum _ContractRenderScenario {
  naturalPersonSelf(
    apiName: 'NaturalPersonSelf',
    excelColumnKey: 'Privatperson:durch sich',
    excelColumnIndex: 0,
    consignorType: ConsignorType.naturalPerson,
  ),
  naturalPersonThroughNaturalRepresentative(
    apiName: 'NaturalPersonThroughNaturalRepresentative',
    excelColumnKey: 'Privatperson:durch Bevollmaechtigte Person',
    excelColumnIndex: 1,
    consignorType: ConsignorType.naturalPerson,
    representativeType: ConsignorType.naturalPerson,
  ),
  naturalPersonThroughLegalRepresentative(
    apiName: 'NaturalPersonThroughLegalRepresentative',
    excelColumnKey: 'Privatperson:durch bevollmaechtigte jur. Person',
    excelColumnIndex: 2,
    consignorType: ConsignorType.naturalPerson,
    representativeType: ConsignorType.legalEntity,
  ),
  legalEntityThroughNaturalRepresentative(
    apiName: 'LegalEntityThroughNaturalRepresentative',
    excelColumnKey: 'jur. Person:durch Bevollmaechtigte Person',
    excelColumnIndex: 3,
    consignorType: ConsignorType.legalEntity,
    representativeType: ConsignorType.naturalPerson,
  ),
  legalEntityThroughLegalRepresentative(
    apiName: 'LegalEntityThroughLegalRepresentative',
    excelColumnKey: 'jur. Person:durch bevollmaechtigte jur. Person',
    excelColumnIndex: 4,
    consignorType: ConsignorType.legalEntity,
    representativeType: ConsignorType.legalEntity,
  ),
  soleProprietorSelf(
    apiName: 'SoleProprietorSelf',
    excelColumnKey: 'Einzelfirma:durch sich',
    excelColumnIndex: 5,
    consignorType: ConsignorType.soleProprietor,
  ),
  soleProprietorThroughNaturalRepresentative(
    apiName: 'SoleProprietorThroughNaturalRepresentative',
    excelColumnKey: 'Einzelfirma:durch Bevollmaechtigte Person',
    excelColumnIndex: 6,
    consignorType: ConsignorType.soleProprietor,
    representativeType: ConsignorType.naturalPerson,
  ),
  soleProprietorThroughLegalRepresentative(
    apiName: 'SoleProprietorThroughLegalRepresentative',
    excelColumnKey: 'Einzelfirma:durch bevollmaechtigte jur. Person',
    excelColumnIndex: 7,
    consignorType: ConsignorType.soleProprietor,
    representativeType: ConsignorType.legalEntity,
  );

  const _ContractRenderScenario({
    required this.apiName,
    required this.excelColumnKey,
    required this.excelColumnIndex,
    required this.consignorType,
    this.representativeType,
  });

  final String apiName;
  final String excelColumnKey;
  final int excelColumnIndex;
  final ConsignorType consignorType;
  final ConsignorType? representativeType;

  static _ContractRenderScenario from({
    required Consignor consignor,
    required Consignor? authorizedRepresentative,
  }) {
    final representativeType = authorizedRepresentative?.consignorType;
    final representativeIsLegal =
        representativeType == ConsignorType.legalEntity;

    return switch (consignor.consignorType) {
      ConsignorType.naturalPerson => authorizedRepresentative == null
          ? _ContractRenderScenario.naturalPersonSelf
          : representativeIsLegal
              ? _ContractRenderScenario.naturalPersonThroughLegalRepresentative
              : _ContractRenderScenario
                  .naturalPersonThroughNaturalRepresentative,
      ConsignorType.legalEntity => representativeIsLegal
          ? _ContractRenderScenario.legalEntityThroughLegalRepresentative
          : _ContractRenderScenario.legalEntityThroughNaturalRepresentative,
      ConsignorType.soleProprietor => authorizedRepresentative == null
          ? _ContractRenderScenario.soleProprietorSelf
          : representativeIsLegal
              ? _ContractRenderScenario.soleProprietorThroughLegalRepresentative
              : _ContractRenderScenario
                  .soleProprietorThroughNaturalRepresentative,
    };
  }
}

extension _PositiveIntX on int {
  int? get takeIfPositive => this > 0 ? this : null;
}
