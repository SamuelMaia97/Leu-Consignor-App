import 'sync_status.dart';

enum UploadType { passport, agreement, product }

extension UploadTypeX on UploadType {
  int get apiValue => switch (this) {
        UploadType.passport => 1,
        UploadType.agreement => 2,
        UploadType.product => 3,
      };

  static UploadType fromApiValue(int value) => switch (value) {
        1 => UploadType.passport,
        3 => UploadType.product,
        _ => UploadType.agreement,
      };
}

class ContractAttachment {
  ContractAttachment({
    required this.path,
    required this.type,
    this.kind = '',
  });

  final String path;
  final UploadType type;
  final String kind;

  factory ContractAttachment.fromJson(Map<String, dynamic> json) {
    final typeIndex = _toInt(json['typeIndex'] ?? json['TypeIndex']) ?? -1;
    final fileType = _toInt(json['fileType'] ?? json['FileType']);

    final resolvedType = typeIndex >= 0
        ? UploadType.values[typeIndex < UploadType.values.length
            ? typeIndex
            : UploadType.values.length - 1]
        : UploadTypeX.fromApiValue(fileType ?? UploadType.agreement.apiValue);

    return ContractAttachment(
      path:
          (json['path'] ?? json['Path'] ?? json['fileName'] ?? json['FileName'])
                  ?.toString() ??
              '',
      type: resolvedType,
      kind: (json['kind'] ?? json['Kind'])?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'typeIndex': type.index,
        'kind': kind.trim().isEmpty ? null : kind.trim(),
      };

  static int? _toInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
}

class ContractUpload {
  ContractUpload({
    required this.localId,
    required this.fileName,
    required this.fileType,
    this.kind = '',
    this.fileId,
    this.auctionId,
    this.path = '',
    this.fileData = '',
    this.isDeleted = false,
    this.signedAt,
    DateTime? localLastModifiedUtc,
    this.serverLastModifiedUtc,
  }) : localLastModifiedUtc = localLastModifiedUtc ??
            serverLastModifiedUtc ??
            DateTime.now().toUtc();

  String localId;
  int? fileId;
  int? auctionId;
  String fileName;
  UploadType fileType;
  String kind;
  String path;
  String fileData;
  bool isDeleted;
  DateTime? signedAt;
  DateTime localLastModifiedUtc;
  DateTime? serverLastModifiedUtc;

  bool get hasServerReference => (fileId ?? 0) > 0;

  bool get isGeneratedContractPdf {
    if (fileType != UploadType.agreement) return false;

    final normalizedKind = _normalizeGeneratedContractToken(kind);
    if (normalizedKind == 'agreement' ||
        normalizedKind == 'contract' ||
        normalizedKind == 'generatedcontract') {
      return true;
    }

    final normalizedName = _normalizeGeneratedContractToken('$fileName $path');
    return normalizedName.contains('einlieferungsvertrag') ||
        normalizedName.contains('consignorcontract') ||
        normalizedName.contains('consignoragreement') ||
        normalizedName.contains('provconsignoragreement');
  }

  bool get needsSync {
    final server = serverLastModifiedUtc;
    if (server == null) return true;
    return localLastModifiedUtc.isAfter(server);
  }

  ContractAttachment toAttachment() =>
      ContractAttachment(path: path, type: fileType, kind: kind);

  factory ContractUpload.fromJson(Map<String, dynamic> json) {
    final lastModifiedUtc = DateTime.tryParse(
      (json['lastModifiedUtc'] ?? json['LastModifiedUtc'])?.toString() ?? '',
    )?.toUtc();

    final localLastModifiedUtc = DateTime.tryParse(
      (json['localLastModifiedUtc'] ?? json['LocalLastModifiedUtc'])
              ?.toString() ??
          '',
    )?.toUtc();

    return ContractUpload(
      localId: (json['localId'] ??
              json['LocalId'] ??
              json['fileId'] ??
              json['FileId'] ??
              DateTime.now().microsecondsSinceEpoch)
          .toString(),
      fileId: _toInt(json['fileId'] ?? json['FileId']),
      auctionId: _toInt(json['auctionId'] ?? json['AuctionId']),
      fileName:
          (json['fileName'] ?? json['FileName'] ?? json['path'] ?? json['Path'])
                  ?.toString() ??
              '',
      fileType: UploadTypeX.fromApiValue(
        _toInt(json['fileType'] ?? json['FileType']) ??
            UploadType.agreement.apiValue,
      ),
      kind: (json['kind'] ?? json['Kind'])?.toString() ?? '',
      path:
          (json['path'] ?? json['Path'] ?? json['fileName'] ?? json['FileName'])
                  ?.toString() ??
              '',
      fileData: (json['fileData'] ?? json['FileData'])?.toString() ?? '',
      isDeleted: (json['isDeleted'] ?? json['IsDeleted']) as bool? ?? false,
      signedAt: DateTime.tryParse(
        (json['signedAt'] ?? json['SignedAt'])?.toString() ?? '',
      )?.toUtc(),
      localLastModifiedUtc: localLastModifiedUtc ?? lastModifiedUtc,
      serverLastModifiedUtc: lastModifiedUtc,
    );
  }

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'fileId': fileId,
        'auctionId': auctionId,
        'fileName': fileName,
        'fileType': fileType.apiValue,
        'kind': kind.trim().isEmpty ? null : kind.trim(),
        'path': path,
        'fileData': fileData,
        'isDeleted': isDeleted,
        'signedAt': signedAt?.toUtc().toIso8601String(),
        'localLastModifiedUtc': localLastModifiedUtc.toUtc().toIso8601String(),
        'lastModifiedUtc': serverLastModifiedUtc?.toUtc().toIso8601String(),
      };

  ContractUpload copyWith({
    String? localId,
    int? fileId,
    int? auctionId,
    String? fileName,
    UploadType? fileType,
    String? kind,
    String? path,
    String? fileData,
    bool? isDeleted,
    DateTime? signedAt,
    DateTime? localLastModifiedUtc,
    DateTime? serverLastModifiedUtc,
  }) =>
      ContractUpload(
        localId: localId ?? this.localId,
        fileId: fileId ?? this.fileId,
        auctionId: auctionId ?? this.auctionId,
        fileName: fileName ?? this.fileName,
        fileType: fileType ?? this.fileType,
        kind: kind ?? this.kind,
        path: path ?? this.path,
        fileData: fileData ?? this.fileData,
        isDeleted: isDeleted ?? this.isDeleted,
        signedAt: signedAt ?? this.signedAt,
        localLastModifiedUtc: localLastModifiedUtc ?? this.localLastModifiedUtc,
        serverLastModifiedUtc:
            serverLastModifiedUtc ?? this.serverLastModifiedUtc,
      );

  static int? _toInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  static String _normalizeGeneratedContractToken(String value) {
    if (value.trim().isEmpty) return '';
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\.[a-z0-9]+$'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}

class ContractRecord {
  ContractRecord({
    required this.id,
    required this.consignorId,
    List<int>? auctionIds,
    List<String>? auctionDisplayNames,
    int? auctionId,
    String? auctionDisplayName,
    this.systemReferenceContract = 0,
    this.pdfName = '',
    DateTime? signedAt,
    DateTime? lastModifiedUtc,
    this.pdfPath = '',
    List<ContractUpload>? uploads,
    this.syncStatus = RecordSyncStatus.draft,
    this.syncErrorMessage,
    this.lastSyncedUtc,
    this.remoteLastModifiedUtc,
    this.lastEditedByUsername,
    this.lastEditedAtUtc,
  })  : auctionIds = List<int>.unmodifiable(
          auctionIds ?? (auctionId == null ? const <int>[] : <int>[auctionId]),
        ),
        auctionDisplayNames = List<String>.unmodifiable(
          auctionDisplayNames ??
              (auctionDisplayName == null || auctionDisplayName.trim().isEmpty
                  ? const <String>[]
                  : <String>[auctionDisplayName]),
        ),
        signedAt = signedAt ?? DateTime.now(),
        lastModifiedUtc = lastModifiedUtc ?? DateTime.now().toUtc(),
        uploads = uploads ?? const <ContractUpload>[];

  String id;
  String consignorId;
  List<int> auctionIds;
  List<String> auctionDisplayNames;
  int systemReferenceContract;
  String pdfName;
  DateTime signedAt;
  DateTime lastModifiedUtc;
  String pdfPath;
  List<ContractUpload> uploads;
  RecordSyncStatus syncStatus;
  String? syncErrorMessage;
  DateTime? lastSyncedUtc;
  DateTime? remoteLastModifiedUtc;
  String? lastEditedByUsername;
  DateTime? lastEditedAtUtc;

  int? get auctionId => auctionIds.isEmpty ? null : auctionIds.first;

  String get auctionDisplayName =>
      auctionDisplayNames.isEmpty ? '' : auctionDisplayNames.first;

  bool get hasRemoteReference => uploads.any((e) => e.hasServerReference);

  bool get synced =>
      syncStatus == RecordSyncStatus.synced ||
      syncStatus == RecordSyncStatus.finalized;

  bool get needsSync => uploads.any((e) => e.needsSync) || syncStatus.needsSync;

  List<ContractAttachment> get attachments => uploads
      .where((e) => !e.isDeleted && e.path.trim().isNotEmpty)
      .map((e) => e.toAttachment())
      .toList(growable: false);

  List<String> get passportFiles => uploads
      .where((e) => !e.isDeleted && e.fileType == UploadType.passport)
      .map((e) => e.path)
      .where((e) => e.trim().isNotEmpty)
      .toList(growable: false);

  List<String> get registrationFiles => uploads
      .where((e) => !e.isDeleted && e.fileType == UploadType.agreement)
      .map((e) => e.path)
      .where((e) => e.trim().isNotEmpty)
      .toList(growable: false);

  List<String> get productFiles => uploads
      .where((e) => !e.isDeleted && e.fileType == UploadType.product)
      .map((e) => e.path)
      .where((e) => e.trim().isNotEmpty)
      .toList(growable: false);

  bool get hasLocalChanges => uploads.any((e) => e.needsSync);

  factory ContractRecord.empty(
    String consignorId, {
    int? auctionId,
    List<int> auctionIds = const <int>[],
    List<String> auctionDisplayNames = const <String>[],
  }) {
    final selectedAuctionIds = auctionIds.isNotEmpty
        ? auctionIds
        : (auctionId == null ? const <int>[] : <int>[auctionId]);
    return ContractRecord(
      id: _buildId(consignorId, selectedAuctionIds),
      consignorId: consignorId,
      auctionIds: selectedAuctionIds,
      auctionDisplayNames: auctionDisplayNames,
      pdfName: 'consignor_contract.pdf',
      syncStatus: RecordSyncStatus.draft,
    );
  }

  factory ContractRecord.fromJson(Map<String, dynamic> json) {
    final uploadsJson = ((json['uploads'] ??
                json['Uploads'] ??
                json['list'] ??
                json['List']) as List?)
            ?.whereType<Map>()
            .map((e) => ContractUpload.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        <ContractUpload>[];

    if (uploadsJson.isEmpty) {
      final attachments = <ContractAttachment>[];
      attachments.addAll(
        (((json['attachments'] ?? json['Attachments']) as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ContractAttachment.fromJson(e.cast<String, dynamic>())),
      );

      void addLegacy(List<dynamic>? paths, UploadType type) {
        if (paths == null) return;
        attachments.addAll(
          paths
              .whereType<String>()
              .map((path) => ContractAttachment(path: path, type: type)),
        );
      }

      addLegacy(
        ((json['passportFiles'] ?? json['PassportFiles']) as List?)
            ?.cast<dynamic>(),
        UploadType.passport,
      );
      addLegacy(
        ((json['registrationFiles'] ?? json['RegistrationFiles']) as List?)
            ?.cast<dynamic>(),
        UploadType.agreement,
      );
      addLegacy(
        ((json['productFiles'] ?? json['ProductFiles']) as List?)
            ?.cast<dynamic>(),
        UploadType.product,
      );

      for (final attachment in attachments) {
        uploadsJson.add(
          ContractUpload(
            localId: '${attachment.type.name}_${attachment.path.hashCode}',
            fileName: attachment.path.split('/').isEmpty
                ? attachment.path
                : attachment.path.split('/').last,
            fileType: attachment.type,
            path: attachment.path,
            localLastModifiedUtc: DateTime.tryParse(
              (json['lastModifiedUtc'] ?? json['LastModifiedUtc'])
                      ?.toString() ??
                  '',
            )?.toUtc(),
            serverLastModifiedUtc: DateTime.tryParse(
              (json['remoteLastModifiedUtc'] ?? json['RemoteLastModifiedUtc'])
                      ?.toString() ??
                  '',
            )?.toUtc(),
          ),
        );
      }
    }

    final deduplicatedUploads = _deduplicateUploads(uploadsJson);

    final legacyAuctionId = _toInt(json['auctionId'] ?? json['AuctionId']);
    final parsedAuctionIds = _parseIntList(
      json['auctionIds'] ?? json['AuctionIds'],
    );
    final auctionIds = parsedAuctionIds.isNotEmpty
        ? parsedAuctionIds
        : (legacyAuctionId == null ? const <int>[] : <int>[legacyAuctionId]);
    final auctionDisplayNames = _parseStringList(
      json['auctionDisplayNames'] ?? json['AuctionDisplayNames'],
    );
    final legacyDisplayName =
        (json['auctionDisplayName'] ?? json['AuctionDisplayName'])
                ?.toString() ??
            '';
    final resolvedDisplayNames = auctionDisplayNames.isNotEmpty
        ? auctionDisplayNames
        : (legacyDisplayName.trim().isEmpty
            ? const <String>[]
            : <String>[legacyDisplayName]);

    final consignorId =
        (json['consignorId'] ?? json['ConsignorId'])?.toString() ?? '';
    final systemReferenceContract = _toInt(json['systemReferenceContract'] ??
            json['SystemReferenceContract']) ??
        0;
    final lastModifiedUtc = DateTime.tryParse(
      (json['lastModifiedUtc'] ?? json['LastModifiedUtc'])?.toString() ?? '',
    )?.toUtc();

    return ContractRecord(
      id: (json['id'] ??
              json['Id'] ??
              (auctionIds.isNotEmpty
                  ? _buildId(consignorId, auctionIds)
                  : null) ??
              systemReferenceContract.toString())
          .toString(),
      consignorId: consignorId,
      auctionIds: auctionIds,
      auctionDisplayNames: resolvedDisplayNames,
      systemReferenceContract: systemReferenceContract,
      pdfName: ((json['pdfName'] ??
                          json['PdfName'] ??
                          json['fileName'] ??
                          json['FileName'])
                      ?.toString() ??
                  '')
              .trim()
              .isEmpty
          ? 'consignor_contract.pdf'
          : (json['pdfName'] ??
                  json['PdfName'] ??
                  json['fileName'] ??
                  json['FileName'])
              .toString(),
      signedAt: DateTime.tryParse(
            (json['signedAt'] ?? json['SignedAt'])?.toString() ?? '',
          ) ??
          DateTime.now(),
      lastModifiedUtc: lastModifiedUtc ?? DateTime.now().toUtc(),
      pdfPath: (json['pdfPath'] ?? json['PdfPath']) as String? ?? '',
      uploads: deduplicatedUploads,
      syncStatus: RecordSyncStatusX.fromAny(
        json['syncStatus'] ?? json['SyncStatus'],
        hasRemoteReference:
            deduplicatedUploads.any((e) => e.hasServerReference),
        legacySynced: (json['synced'] ?? json['Synced']) as bool?,
      ),
      syncErrorMessage:
          (json['syncErrorMessage'] ?? json['SyncErrorMessage'])?.toString(),
      lastSyncedUtc: DateTime.tryParse(
        (json['lastSyncedUtc'] ?? json['LastSyncedUtc'])?.toString() ?? '',
      )?.toUtc(),
      remoteLastModifiedUtc: DateTime.tryParse(
        (json['remoteLastModifiedUtc'] ?? json['RemoteLastModifiedUtc'])
                ?.toString() ??
            '',
      )?.toUtc(),
      lastEditedByUsername:
          (json['lastEditedByUsername'] ?? json['LastEditedByUsername'])
              ?.toString(),
      lastEditedAtUtc: DateTime.tryParse(
        (json['lastEditedAtUtc'] ?? json['LastEditedAtUtc'])?.toString() ?? '',
      )?.toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'consignorId': consignorId,
        'auctionId': auctionId,
        'auctionIds': auctionIds,
        'auctionDisplayNames': auctionDisplayNames,
        'systemReferenceContract': systemReferenceContract,
        'pdfName': pdfName,
        'signedAt': signedAt.toUtc().toIso8601String(),
        'lastModifiedUtc': lastModifiedUtc.toUtc().toIso8601String(),
        'pdfPath': pdfPath,
        'uploads': uploads.map((e) => e.toJson()).toList(),
        'syncStatus': syncStatus.name,
        'syncErrorMessage': syncErrorMessage,
        'lastSyncedUtc': lastSyncedUtc?.toUtc().toIso8601String(),
        'remoteLastModifiedUtc':
            remoteLastModifiedUtc?.toUtc().toIso8601String(),
        'lastEditedByUsername': lastEditedByUsername,
        'lastEditedAtUtc': lastEditedAtUtc?.toUtc().toIso8601String(),
        'synced': synced,
      };

  void markLocalChange([String? editorUsername]) {
    _markEdited(editorUsername);
    syncErrorMessage = null;
    syncStatus = hasRemoteReference
        ? RecordSyncStatus.pendingSync
        : RecordSyncStatus.draft;
  }

  void markSynced({DateTime? remoteModifiedUtc}) {
    syncStatus = RecordSyncStatus.synced;
    syncErrorMessage = null;
    lastSyncedUtc = DateTime.now().toUtc();
    remoteLastModifiedUtc = remoteModifiedUtc ?? lastModifiedUtc;
  }

  void markRemoteSnapshot() {
    syncStatus = RecordSyncStatus.synced;
    syncErrorMessage = null;
    lastSyncedUtc = DateTime.now().toUtc();
    remoteLastModifiedUtc = lastModifiedUtc;
  }

  void markSyncFailed(String message) {
    syncStatus = RecordSyncStatus.syncFailed;
    syncErrorMessage = message.trim();
  }

  ContractRecord copyWith({
    String? id,
    String? consignorId,
    List<int>? auctionIds,
    List<String>? auctionDisplayNames,
    int? auctionId,
    String? auctionDisplayName,
    int? systemReferenceContract,
    String? pdfPath,
    String? pdfName,
    DateTime? signedAt,
    DateTime? lastModifiedUtc,
    List<ContractUpload>? uploads,
    RecordSyncStatus? syncStatus,
    String? syncErrorMessage,
    DateTime? lastSyncedUtc,
    DateTime? remoteLastModifiedUtc,
    String? lastEditedByUsername,
    DateTime? lastEditedAtUtc,
  }) {
    final nextAuctionIds =
        auctionIds ?? (auctionId == null ? this.auctionIds : <int>[auctionId]);
    final nextDisplayNames = auctionDisplayNames ??
        (auctionDisplayName == null
            ? this.auctionDisplayNames
            : (auctionDisplayName.trim().isEmpty
                ? const <String>[]
                : <String>[auctionDisplayName]));

    return ContractRecord(
      id: id ?? this.id,
      consignorId: consignorId ?? this.consignorId,
      auctionIds: nextAuctionIds,
      auctionDisplayNames: nextDisplayNames,
      systemReferenceContract:
          systemReferenceContract ?? this.systemReferenceContract,
      pdfName: pdfName ?? this.pdfName,
      signedAt: signedAt ?? this.signedAt,
      lastModifiedUtc: lastModifiedUtc ?? this.lastModifiedUtc,
      pdfPath: pdfPath ?? this.pdfPath,
      uploads: uploads ?? this.uploads,
      syncStatus: syncStatus ?? this.syncStatus,
      syncErrorMessage: syncErrorMessage ?? this.syncErrorMessage,
      lastSyncedUtc: lastSyncedUtc ?? this.lastSyncedUtc,
      remoteLastModifiedUtc:
          remoteLastModifiedUtc ?? this.remoteLastModifiedUtc,
      lastEditedByUsername: lastEditedByUsername ?? this.lastEditedByUsername,
      lastEditedAtUtc: lastEditedAtUtc ?? this.lastEditedAtUtc,
    );
  }

  void _markEdited(String? editorUsername) {
    final nowUtc = DateTime.now().toUtc();
    lastModifiedUtc = nowUtc;
    lastEditedAtUtc = nowUtc;
    final normalized = editorUsername?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      lastEditedByUsername = normalized;
    }
  }

  static List<ContractUpload> _deduplicateUploads(
      List<ContractUpload> uploads) {
    final seenKeys = <String>{};
    final result = <ContractUpload>[];

    for (final upload in uploads) {
      final normalizedPath = upload.path.trim();
      final key = '${upload.fileType.index}|${upload.kind}|$normalizedPath';

      if (normalizedPath.isEmpty || seenKeys.add(key)) {
        result.add(upload);
      }
    }

    return result;
  }

  static String _buildId(String consignorId, List<int> auctionIds) {
    if (auctionIds.isEmpty) {
      return DateTime.now().microsecondsSinceEpoch.toString();
    }
    return '${consignorId}_${auctionIds.join('_')}';
  }

  static List<int> _parseIntList(Object? value) {
    if (value is! List) return const <int>[];
    return value.map(_toInt).whereType<int>().toList(growable: false);
  }

  static List<String> _parseStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
