enum RecordSyncStatus {
  draft,
  pendingSync,
  synced,
  finalized,
  syncFailed,
}

extension RecordSyncStatusX on RecordSyncStatus {
  bool get needsSync =>
      this != RecordSyncStatus.synced && this != RecordSyncStatus.finalized;

  static RecordSyncStatus fromAny(
    Object? value, {
    required bool hasRemoteReference,
    bool? legacySynced,
  }) {
    final text = value?.toString().trim();
    final normalized = text?.toLowerCase();

    switch (normalized) {
      case 'draft':
      case 'recordsyncstatus.draft':
        return RecordSyncStatus.draft;
      case 'pending':
      case 'pendingsync':
      case 'recordsyncstatus.pendingsync':
        return RecordSyncStatus.pendingSync;
      case 'synced':
      case 'recordsyncstatus.synced':
        return RecordSyncStatus.synced;
      case 'final':
      case 'finalized':
      case 'finalised':
      case 'recordsyncstatus.finalized':
        return RecordSyncStatus.finalized;
      case 'failed':
      case 'syncfailed':
      case 'recordsyncstatus.syncfailed':
        return RecordSyncStatus.syncFailed;
    }

    if (legacySynced == true) {
      return RecordSyncStatus.synced;
    }

    return hasRemoteReference
        ? RecordSyncStatus.synced
        : RecordSyncStatus.draft;
  }
}