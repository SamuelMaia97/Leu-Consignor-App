import '../models/consignor.dart';
import '../models/sync_status.dart';

enum ConsignorSyncAction {
  skipDraft,
  pullRemote,
  pushLocal,
  noOp,
}

/// Resolves one consignor against the last Abacus version seen by the app.
///
/// [Consignor.remoteLastModifiedUtc] is the shared baseline. This lets us tell
/// a remote-only edit from a conflict where both sides changed. In a conflict,
/// the local app record is authoritative.
class ConsignorSyncPolicy {
  const ConsignorSyncPolicy._();

  static ConsignorSyncAction decide({
    required Consignor? local,
    required bool remoteExists,
    DateTime? remoteLastModifiedUtc,
  }) {
    if (local == null) {
      return remoteExists && remoteLastModifiedUtc != null
          ? ConsignorSyncAction.pullRemote
          : ConsignorSyncAction.noOp;
    }

    if (local.syncStatus == RecordSyncStatus.draft) {
      return ConsignorSyncAction.skipDraft;
    }

    // Check the app first: when both sides changed, the app wins.
    if (local.shouldUploadDuringWorkspaceSync) {
      return ConsignorSyncAction.pushLocal;
    }

    if (!remoteExists) return ConsignorSyncAction.noOp;

    if (remoteLastModifiedUtc == null) return ConsignorSyncAction.noOp;

    final baseline = local.remoteLastModifiedUtc;
    if (baseline == null) {
      // Older app data may not have a recorded common baseline. Compare the
      // two available versions directly so neither side is silently assumed
      // to be newer. Exact ties remain unchanged.
      if (local.lastModifiedUtc.isAfter(remoteLastModifiedUtc)) {
        return ConsignorSyncAction.pushLocal;
      }
      return remoteLastModifiedUtc.isAfter(local.lastModifiedUtc)
          ? ConsignorSyncAction.pullRemote
          : ConsignorSyncAction.noOp;
    }

    return remoteLastModifiedUtc.isAfter(baseline)
        ? ConsignorSyncAction.pullRemote
        : ConsignorSyncAction.noOp;
  }

  /// Matches a report SubjectId to a local record without assuming that the
  /// app's primary id is also the Abacus id.
  static bool matchesReportSubject(Consignor local, int subjectId) {
    if (subjectId <= 0) return false;

    final abacusSubjectId = local.abacusSubjectId;
    if (abacusSubjectId != null && abacusSubjectId > 0) {
      return abacusSubjectId == subjectId;
    }

    return int.tryParse(local.id) == subjectId ||
        local.existingCustomerId == subjectId ||
        (local.systemReferenceConsignor <= 0 &&
            local.systemReferenceCustomer == subjectId);
  }

  /// Matches hydrated remote data to its local record. Abacus identity takes
  /// precedence because a pushed record's local customer id can differ from
  /// its Abacus SubjectId.
  static bool refersToSameRecord(Consignor local, Consignor remote) {
    final localAbacusId = local.abacusSubjectId;
    final remoteAbacusId = remote.abacusSubjectId;
    if (localAbacusId != null &&
        localAbacusId > 0 &&
        remoteAbacusId != null &&
        remoteAbacusId > 0) {
      return localAbacusId == remoteAbacusId;
    }

    if (remoteAbacusId != null &&
        remoteAbacusId > 0 &&
        matchesReportSubject(local, remoteAbacusId)) {
      return true;
    }

    if (local.id == remote.id) return true;

    if (local.systemReferenceConsignor > 0 &&
        remote.systemReferenceConsignor > 0 &&
        local.systemReferenceConsignor == remote.systemReferenceConsignor) {
      return true;
    }

    return localAbacusId == null &&
        remoteAbacusId == null &&
        local.systemReferenceCustomer > 0 &&
        local.systemReferenceCustomer == remote.systemReferenceCustomer;
  }

  /// Keeps device/Backoffice identity stable while accepting Abacus business
  /// fields from a newer report snapshot.
  static Consignor preserveLocalIdentity({
    required Consignor remote,
    required Consignor local,
  }) {
    remote.id = local.id;
    if (local.systemReferenceConsignor > 0) {
      remote.systemReferenceConsignor = local.systemReferenceConsignor;
    }
    if (local.systemReferenceCustomer > 0) {
      remote.systemReferenceCustomer = local.systemReferenceCustomer;
    }
    remote.abacusSubjectId ??= local.abacusSubjectId;
    remote.existingCustomerId ??= local.existingCustomerId;
    remote.existingCustomerLabel ??= local.existingCustomerLabel;
    if (remote.username.trim().isEmpty) remote.username = local.username;
    if (remote.password.trim().isEmpty) remote.password = local.password;
    remote.phonePrefixOriginId ??= local.phonePrefixOriginId;
    return remote;
  }
}
