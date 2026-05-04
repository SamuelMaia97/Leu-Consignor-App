enum RecordSyncStatus {
  draft,
  pendingSync,
  synced,
  syncFailed,
}

extension RecordSyncStatusX on RecordSyncStatus {
  bool get needsSync => this != RecordSyncStatus.synced;

  static RecordSyncStatus fromAny(
    Object? value, {
    required bool hasRemoteReference,
    bool? legacySynced,
  }) {
    final text = value?.toString().trim();

    switch (text) {
      case 'draft':
        return RecordSyncStatus.draft;
      case 'pendingSync':
        return RecordSyncStatus.pendingSync;
      case 'synced':
        return RecordSyncStatus.synced;
      case 'syncFailed':
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