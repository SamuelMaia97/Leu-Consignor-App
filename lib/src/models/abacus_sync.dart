import 'consignor.dart';
import 'contract_record.dart';

enum AbacusContractSyncEvent {
  manualSync,
  contractGenerated,
  contractSigned,
  contractFinalized,
}

extension AbacusContractSyncEventX on AbacusContractSyncEvent {
  String get apiName => switch (this) {
        AbacusContractSyncEvent.manualSync => 'ManualSync',
        AbacusContractSyncEvent.contractGenerated => 'ContractGenerated',
        AbacusContractSyncEvent.contractSigned => 'ContractSigned',
        AbacusContractSyncEvent.contractFinalized => 'ContractFinalized',
      };

  bool get requiresDossierReceipt =>
      this == AbacusContractSyncEvent.contractGenerated ||
      this == AbacusContractSyncEvent.contractSigned ||
      this == AbacusContractSyncEvent.contractFinalized;
}

enum AbacusDocumentKind {
  consignmentContract,
  passport,
  representativePassport,
  idValidationReport,
  representativeIdValidationReport,
  coinImage,
}

extension AbacusDocumentKindX on AbacusDocumentKind {
  String get apiName => switch (this) {
        AbacusDocumentKind.consignmentContract => 'ConsignmentContract',
        AbacusDocumentKind.passport => 'Passport',
        AbacusDocumentKind.representativePassport => 'RepresentativePassport',
        AbacusDocumentKind.idValidationReport => 'IdValidationReport',
        AbacusDocumentKind.representativeIdValidationReport =>
          'RepresentativeIdValidationReport',
        AbacusDocumentKind.coinImage => 'CoinImage',
      };
}

class AbacusStorageReference {
  const AbacusStorageReference({
    required this.lookupText,
    this.storageId,
    this.abbreviation,
    this.dossierObjectId = 'ADR',
    this.documentsEndpoint = 'SubjectDocuments',
  });

  static const passport = AbacusStorageReference(
    lookupText: 'Passport',
    storageId: '39c1d257-327c-bb79-0408-9be8b5a1dcca',
    abbreviation: 'PASS',
  );

  static const consignmentPhotos = AbacusStorageReference(
    lookupText: 'Einlieferung Fotos',
    storageId: '56d62f82-6053-d8b8-1dc8-abd6970e5aaf',
    abbreviation: 'EINL',
  );

  static const consignmentContract = AbacusStorageReference(
    lookupText: 'Vertrag Einlieferung',
    abbreviation: 'Contract',
  );

  final String lookupText;
  final String? storageId;
  final String? abbreviation;
  final String dossierObjectId;
  final String documentsEndpoint;

  Map<String, dynamic> toJson() => {
        'lookupText': lookupText,
        'storageId': storageId,
        'abbreviation': abbreviation,
        'dossierObjectId': dossierObjectId,
        'documentsEndpoint': documentsEndpoint,
      };
}

class AbacusFileSyncMetadata {
  const AbacusFileSyncMetadata({
    required this.documentKind,
    required this.storage,
    required this.subjectId,
    required this.label,
    required this.documentName,
    required this.sourceFileName,
    required this.contentType,
    required this.trigger,
    required this.verifyReceipt,
    this.maxAttempts = 3,
  });

  final AbacusDocumentKind documentKind;
  final AbacusStorageReference storage;
  final int subjectId;
  final String label;
  final String documentName;
  final String sourceFileName;
  final String contentType;
  final AbacusContractSyncEvent trigger;
  final bool verifyReceipt;
  final int maxAttempts;

  static AbacusFileSyncMetadata? forUpload({
    required ContractUpload upload,
    required int consignorSubjectId,
    required String contractNumber,
    required DateTime eventUtc,
    required AbacusContractSyncEvent trigger,
    String? labelOverride,
  }) {
    if (upload.isDeleted) return null;

    final fileName = _effectiveFileName(upload);
    final lowerFileName = fileName.toLowerCase();
    final date = _compactDate(eventUtc);
    final normalizedConsignor = _safeToken(consignorSubjectId.toString());
    final extension = _extension(fileName);

    final AbacusDocumentKind documentKind;
    final AbacusStorageReference storage;
    final String label;

    switch (upload.fileType) {
      case UploadType.passport:
        final kind = upload.kind.trim();
        final representative = kind == 'RepresentativeId' ||
            kind == 'RepresentativeIdValidationReport';
        final validationReport = kind == 'NaturalPersonIdValidationReport' ||
            kind == 'RepresentativeIdValidationReport';
        documentKind = validationReport
            ? representative
                ? AbacusDocumentKind.representativeIdValidationReport
                : AbacusDocumentKind.idValidationReport
            : representative
                ? AbacusDocumentKind.representativePassport
                : AbacusDocumentKind.passport;
        storage = AbacusStorageReference.passport;
        label = labelOverride?.trim().isNotEmpty == true
            ? labelOverride!.trim()
            : validationReport
                ? representative
                    ? 'Representative_Id_Validation_Report_${normalizedConsignor}_$date'
                    : 'Id_Validation_Report_${normalizedConsignor}_$date'
                : representative
                    ? 'Representative'
                    : 'Passport';
        break;

      case UploadType.product:
        documentKind = AbacusDocumentKind.coinImage;
        storage = AbacusStorageReference.consignmentPhotos;
        final lotOrTempId = _productIndexToken(upload);
        label = labelOverride?.trim().isNotEmpty == true
            ? labelOverride!.trim()
            : '${_safeToken(_baseContractNumber(contractNumber))}-Product-$lotOrTempId';
        break;

      case UploadType.agreement:
        if (!lowerFileName.endsWith('.pdf')) return null;
        documentKind = AbacusDocumentKind.consignmentContract;
        storage = AbacusStorageReference.consignmentContract;
        label = labelOverride?.trim().isNotEmpty == true
            ? labelOverride!.trim()
            : _safeToken(contractNumber);
        break;
    }

    return AbacusFileSyncMetadata(
      documentKind: documentKind,
      storage: storage,
      subjectId: consignorSubjectId,
      label: label,
      documentName: '$label$extension',
      sourceFileName: fileName,
      contentType: _contentType(lowerFileName),
      trigger: trigger,
      verifyReceipt: trigger.requiresDossierReceipt ||
          documentKind == AbacusDocumentKind.passport ||
          documentKind == AbacusDocumentKind.representativePassport ||
          documentKind == AbacusDocumentKind.idValidationReport ||
          documentKind == AbacusDocumentKind.representativeIdValidationReport ||
          documentKind == AbacusDocumentKind.coinImage,
    );
  }

  Map<String, dynamic> toJson() => {
        'queueForAbacus': true,
        'target': 'VendorDossier',
        'documentKind': documentKind.apiName,
        'subjectId': subjectId,
        'storage': storage.toJson(),
        'label': label,
        'documentName': documentName,
        'sourceFileName': sourceFileName,
        'contentType': contentType,
        'fileStoreEndpoint': '/api/file-store/v1/user',
        'documentsEndpoint': storage.documentsEndpoint,
        'trigger': trigger.apiName,
        'verifyReceipt': verifyReceipt,
        'retry': {
          'maxAttempts': maxAttempts,
          'logBackofficeError': true,
        },
      };

  static String _effectiveFileName(ContractUpload upload) {
    final explicit = upload.fileName.trim();
    if (explicit.isNotEmpty) return explicit;

    final normalizedPath = upload.path.trim().replaceAll('\\', '/');
    if (normalizedPath.isEmpty) return 'attachment';

    final segments =
        normalizedPath.split('/').where((part) => part.isNotEmpty).toList();
    return segments.isEmpty ? 'attachment' : segments.last;
  }

  static String _compactDate(DateTime value) {
    final utc = value.toUtc();
    return [
      utc.year.toString().padLeft(4, '0'),
      utc.month.toString().padLeft(2, '0'),
      utc.day.toString().padLeft(2, '0'),
    ].join();
  }

  static String _safeToken(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Unknown';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  }

  static String _baseContractNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.toUpperCase().startsWith('PROV-COC-')) {
      return trimmed.substring(5);
    }
    return trimmed;
  }

  static String _productIndexToken(ContractUpload upload) {
    final candidates = <String>[
      upload.localId,
      upload.fileName,
      upload.path,
      (upload.fileId ?? upload.auctionId)?.toString() ?? '',
    ];
    final pattern = RegExp(r'(\d+)(?!.*\d)');
    for (final candidate in candidates) {
      final match = pattern.firstMatch(candidate);
      if (match != null) return match.group(1)!;
    }
    return _safeToken(upload.localId.isEmpty ? '1' : upload.localId);
  }

  static String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot).toLowerCase();
  }

  static String _contentType(String lowerFileName) {
    if (lowerFileName.endsWith('.pdf')) return 'application/pdf';
    if (lowerFileName.endsWith('.png')) return 'image/png';
    if (lowerFileName.endsWith('.jpg') || lowerFileName.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lowerFileName.endsWith('.webp')) return 'image/webp';
    if (lowerFileName.endsWith('.heic')) return 'image/heic';
    if (lowerFileName.endsWith('.heif')) return 'image/heif';
    return 'application/octet-stream';
  }
}

class AbacusRepresentativeLinkMetadata {
  const AbacusRepresentativeLinkMetadata({
    required this.representative,
    required this.trigger,
    this.testLinkTypeId = '899a75fc-a264-2e72-cab2-098101eb9bf0',
    this.productionLinkTypeId = 'e174dc18-df58-ff73-edec-742a9302ec72',
  });

  final Consignor representative;
  final String trigger;
  final String testLinkTypeId;
  final String productionLinkTypeId;

  Map<String, dynamic> toJson() => {
        'queueForAbacus': true,
        'target': 'LinkedAddress',
        'trigger': trigger,
        'relation': 'Representative',
        'linksEndpoint': 'Links',
        'sourceSubjectIdField': 'mainConsignor.systemReferenceCustomer',
        'targetSubjectId': _positiveOrNull(
          representative.systemReferenceCustomer,
        ),
        'targetExistingCustomerId': representative.existingCustomerId,
        'targetExistingCustomerLabel': representative.existingCustomerLabel,
        'representative': representative.toJson(),
        'linkTypeIds': {
          'test': testLinkTypeId,
          'production': productionLinkTypeId,
        },
        'verifyExistingFilter':
            'SourceSubjectId eq {sourceSubjectId} and LinkTypeId eq {linkTypeId}',
        'retry': {
          'maxAttempts': 3,
          'logBackofficeError': true,
        },
      };

  static int? _positiveOrNull(int value) => value > 0 ? value : null;
}
