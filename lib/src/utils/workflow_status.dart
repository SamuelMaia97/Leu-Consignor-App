import 'dart:io';

import '../models/consignor.dart';
import '../models/contract_record.dart';
import '../models/payment_option.dart';
import '../models/sync_status.dart';

enum AttachmentSourceStatus {
  fromAbacus,
  downloaded,
  localOnly,
}

enum AttachmentSyncStatus {
  pendingSync,
  synced,
  failed,
}

class AttachmentStatusInfo {
  const AttachmentStatusInfo({
    required this.source,
    required this.sync,
  });

  final AttachmentSourceStatus source;
  final AttachmentSyncStatus sync;
}

enum PassportStatusKind {
  valid,
  expired,
  missing,
  expiryMissing,
}

class PassportStatusInfo {
  const PassportStatusInfo({
    required this.kind,
    required this.label,
    this.validUntil,
  });

  final PassportStatusKind kind;
  final String label;
  final DateTime? validUntil;

  bool get isProblem =>
      kind == PassportStatusKind.expired ||
      kind == PassportStatusKind.missing ||
      kind == PassportStatusKind.expiryMissing;
}

enum ReadinessSeverity {
  warning,
  error,
}

class ReadinessIssue {
  const ReadinessIssue({
    required this.title,
    required this.detail,
    required this.severity,
    this.relatedConsignorId,
    this.relatedContractId,
  });

  final String title;
  final String detail;
  final ReadinessSeverity severity;
  final String? relatedConsignorId;
  final String? relatedContractId;
}

class ContractConflict {
  const ContractConflict({
    required this.contractNumber,
    required this.contracts,
  });

  final String contractNumber;
  final List<ContractRecord> contracts;
}

class SyncPreviewSummary {
  const SyncPreviewSummary({
    required this.changedConsignorCount,
    required this.pendingContractCount,
    required this.pendingUploadCount,
    required this.failedUploadCount,
    required this.knownContractCount,
    required this.localConflictCount,
    required this.readinessIssueCount,
  });

  final int changedConsignorCount;
  final int pendingContractCount;
  final int pendingUploadCount;
  final int failedUploadCount;
  final int knownContractCount;
  final int localConflictCount;
  final int readinessIssueCount;
}

class WorkflowStatus {
  static AttachmentStatusInfo attachmentStatus(
    ContractUpload upload, {
    ContractRecord? contract,
  }) {
    final hasLocalFile =
        upload.path.trim().isNotEmpty && File(upload.path.trim()).existsSync();
    final hasRemoteEvidence =
        upload.hasServerReference || upload.serverLastModifiedUtc != null;
    final source = hasRemoteEvidence
        ? hasLocalFile
            ? AttachmentSourceStatus.downloaded
            : AttachmentSourceStatus.fromAbacus
        : AttachmentSourceStatus.localOnly;

    final sync = contract?.syncStatus == RecordSyncStatus.syncFailed
        ? AttachmentSyncStatus.failed
        : upload.needsSync
            ? AttachmentSyncStatus.pendingSync
            : AttachmentSyncStatus.synced;

    return AttachmentStatusInfo(source: source, sync: sync);
  }

  static PassportStatusInfo passportStatus({
    required DateTime? validUntil,
    required Iterable<ContractUpload> uploads,
    DateTime? now,
  }) {
    final activeUploads = uploads.where(
        (item) => !item.isDeleted && item.fileType == UploadType.passport);
    final hasPassportFile = activeUploads.isNotEmpty;
    final effectiveNow = now ?? DateTime.now();

    if (!hasPassportFile && validUntil == null) {
      return const PassportStatusInfo(
        kind: PassportStatusKind.missing,
        label: 'Passport missing',
      );
    }

    if (validUntil == null) {
      return const PassportStatusInfo(
        kind: PassportStatusKind.expiryMissing,
        label: 'Passport expiry missing',
      );
    }

    final expiresAtEndOfDay = DateTime(
      validUntil.year,
      validUntil.month,
      validUntil.day,
      23,
      59,
      59,
    );

    if (expiresAtEndOfDay.isBefore(effectiveNow)) {
      return PassportStatusInfo(
        kind: PassportStatusKind.expired,
        label: 'Passport expired',
        validUntil: validUntil,
      );
    }

    return PassportStatusInfo(
      kind: PassportStatusKind.valid,
      label: 'Passport valid',
      validUntil: validUntil,
    );
  }

  static List<ReadinessIssue> readinessIssuesForContract({
    required Consignor? consignor,
    required ContractRecord contract,
    Iterable<ContractRecord> allContracts = const <ContractRecord>[],
  }) {
    final issues = <ReadinessIssue>[];
    final activeUploads = contract.uploads.where((item) => !item.isDeleted);
    final passportUploads = activeUploads.where(
      (item) =>
          item.fileType == UploadType.passport &&
          !_isRepresentativeUpload(item),
    );
    final representativeUploads = activeUploads.where(
      (item) =>
          item.fileType == UploadType.passport && _isRepresentativeUpload(item),
    );
    final productUploads =
        activeUploads.where((item) => item.fileType == UploadType.product);

    final passportStatus = WorkflowStatus.passportStatus(
      validUntil: consignor?.passportValidUntil,
      uploads: passportUploads,
    );

    if (passportStatus.kind == PassportStatusKind.missing) {
      issues.add(
        ReadinessIssue(
          title: 'No consignor passport',
          detail: 'Add or download a passport image before syncing.',
          severity: ReadinessSeverity.warning,
          relatedConsignorId: contract.consignorId,
          relatedContractId: contract.id,
        ),
      );
    } else if (passportStatus.kind == PassportStatusKind.expired) {
      issues.add(
        ReadinessIssue(
          title: 'Consignor passport expired',
          detail: 'Update the passport images or valid-until date.',
          severity: ReadinessSeverity.warning,
          relatedConsignorId: contract.consignorId,
          relatedContractId: contract.id,
        ),
      );
    } else if (passportStatus.kind == PassportStatusKind.expiryMissing) {
      issues.add(
        ReadinessIssue(
          title: 'Consignor passport expiry missing',
          detail: 'Enter the passport valid-until date.',
          severity: ReadinessSeverity.warning,
          relatedConsignorId: contract.consignorId,
          relatedContractId: contract.id,
        ),
      );
    }

    if (productUploads.isEmpty) {
      issues.add(
        ReadinessIssue(
          title: 'No product pictures',
          detail: 'Attach at least one product picture for this contract.',
          severity: ReadinessSeverity.warning,
          relatedConsignorId: contract.consignorId,
          relatedContractId: contract.id,
        ),
      );
    }

    if (!_hasBankInfo(consignor)) {
      issues.add(
        ReadinessIssue(
          title: 'Bank information missing',
          detail: 'Check the payment method and bank details.',
          severity: ReadinessSeverity.warning,
          relatedConsignorId: contract.consignorId,
          relatedContractId: contract.id,
        ),
      );
    }

    if (_requiresRepresentativeDocument(contract, consignor) &&
        representativeUploads.isEmpty) {
      issues.add(
        ReadinessIssue(
          title: 'Representative document missing',
          detail: 'Add passport images for the authorized representative.',
          severity: ReadinessSeverity.warning,
          relatedConsignorId: contract.consignorId,
          relatedContractId: contract.id,
        ),
      );
    }

    final hasPdf = contract.pdfPath.trim().isNotEmpty ||
        activeUploads.any((item) => item.isGeneratedContractPdf);
    if (!hasPdf) {
      issues.add(
        ReadinessIssue(
          title: 'PDF not generated',
          detail: 'Generate the contract PDF before upload/update.',
          severity: ReadinessSeverity.warning,
          relatedConsignorId: contract.consignorId,
          relatedContractId: contract.id,
        ),
      );
    }

    final contractNumber = extractContractNumber(contract);
    if (contractNumber != null &&
        allContracts.any((item) =>
            item.id != contract.id &&
            extractContractNumber(item)?.toUpperCase() ==
                contractNumber.toUpperCase())) {
      issues.add(
        ReadinessIssue(
          title: 'Duplicate contract number',
          detail:
              '$contractNumber already exists locally. Review before upload/update.',
          severity: ReadinessSeverity.error,
          relatedConsignorId: contract.consignorId,
          relatedContractId: contract.id,
        ),
      );
    }

    return issues;
  }

  static List<ReadinessIssue> readinessIssuesForWorkspace({
    required Iterable<Consignor> consignors,
    required Iterable<ContractRecord> contracts,
  }) {
    final consignorsById = {
      for (final consignor in consignors) consignor.id: consignor,
    };
    return contracts
        .expand(
          (contract) => readinessIssuesForContract(
            consignor: consignorsById[contract.consignorId],
            contract: contract,
            allContracts: contracts,
          ),
        )
        .toList(growable: false);
  }

  static SyncPreviewSummary buildSyncPreview({
    required Iterable<Consignor> consignors,
    required Iterable<ContractRecord> contracts,
  }) {
    final allContracts = contracts.toList(growable: false);
    final uploadCandidates = allContracts
        .where((contract) => contract.shouldUploadDuringWorkspaceSync)
        .toList(growable: false);
    final conflicts = findContractConflicts(allContracts);
    final issues = readinessIssuesForWorkspace(
      consignors: consignors,
      contracts: uploadCandidates,
    );
    return SyncPreviewSummary(
      changedConsignorCount: consignors.where((item) => item.needsSync).length,
      pendingContractCount: uploadCandidates.length,
      pendingUploadCount: uploadCandidates
          .expand((contract) => contract.uploads)
          .where((upload) => !upload.isDeleted && upload.needsSync)
          .length,
      failedUploadCount: allContracts
          .where(
              (contract) => contract.syncStatus == RecordSyncStatus.syncFailed)
          .expand((contract) => contract.uploads)
          .where((upload) => !upload.isDeleted)
          .length,
      knownContractCount: allContracts
          .where((contract) => extractContractNumber(contract) != null)
          .length,
      localConflictCount: conflicts.length,
      readinessIssueCount: issues.length,
    );
  }

  static List<ContractConflict> findContractConflicts(
    Iterable<ContractRecord> contracts,
  ) {
    final byNumber = <String, List<ContractRecord>>{};
    for (final contract in contracts) {
      final number = extractContractNumber(contract);
      if (number == null) continue;
      byNumber.putIfAbsent(number.toUpperCase(), () => <ContractRecord>[]);
      byNumber[number.toUpperCase()]!.add(contract);
    }

    return byNumber.entries
        .where((entry) => entry.value.length > 1)
        .map(
          (entry) => ContractConflict(
            contractNumber: entry.key,
            contracts: List<ContractRecord>.unmodifiable(entry.value),
          ),
        )
        .toList(growable: false);
  }

  static String? extractContractNumber(ContractRecord contract) {
    final pattern =
        RegExp(r'\b(?:PROV-)?COC-\d{2}-\d+\b', caseSensitive: false);
    final candidates = <String>[
      contract.pdfName,
      contract.id,
      ...contract.uploads.map((upload) => upload.fileName),
      ...contract.uploads.map((upload) => upload.path),
    ];

    for (final candidate in candidates) {
      final match = pattern.firstMatch(candidate);
      if (match != null) return match.group(0)!.toUpperCase();
    }

    return null;
  }

  static bool hasRepresentative(ContractRecord contract) {
    return contract.authorizedRepresentative != null ||
        contract.uploads.any(_isRepresentativeUpload);
  }

  static String representativeName(ContractRecord contract) {
    final representative = contract.authorizedRepresentative;
    if (representative == null) return '';
    return representative.displayName.trim().isNotEmpty
        ? representative.displayName.trim()
        : representative.consignorInfo.fullName.trim();
  }

  static bool _hasBankInfo(Consignor? consignor) {
    if (consignor == null) return false;
    if (consignor.paymentOption == PaymentOption.cash) return true;
    final details = consignor.bankingDetails;
    return details.accountNumber.trim().isNotEmpty ||
        details.bankName.trim().isNotEmpty ||
        details.bicSwift.trim().isNotEmpty;
  }

  static bool _requiresRepresentativeDocument(
    ContractRecord contract,
    Consignor? consignor,
  ) {
    if (contract.authorizedRepresentative != null) return true;
    if (consignor?.isLegalEntity == true) return true;
    return contract.uploads.any(_isRepresentativeUpload);
  }

  static bool _isRepresentativeUpload(ContractUpload upload) {
    final kind = upload.kind.trim().toLowerCase();
    return kind == 'representativeid' ||
        kind == 'representativeidvalidationreport';
  }
}
