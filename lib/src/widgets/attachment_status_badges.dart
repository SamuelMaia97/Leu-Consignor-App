import 'package:flutter/material.dart';

import '../models/contract_record.dart';
import '../utils/workflow_status.dart';
import 'status_badge.dart';

class AttachmentStatusBadges extends StatelessWidget {
  const AttachmentStatusBadges({
    super.key,
    required this.upload,
    this.contract,
  });

  final ContractUpload upload;
  final ContractRecord? contract;

  @override
  Widget build(BuildContext context) {
    final status = WorkflowStatus.attachmentStatus(
      upload,
      contract: contract,
    );

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        Tooltip(
          message: _sourceTooltip(status.source),
          child: StatusBadge(
            label: _sourceLabel(status.source),
            tone: _sourceTone(status.source),
            icon: _sourceIcon(status.source),
          ),
        ),
        Tooltip(
          message: _syncTooltip(status.sync),
          child: StatusBadge(
            label: _syncLabel(status.sync),
            tone: _syncTone(status.sync),
            icon: _syncIcon(status.sync),
          ),
        ),
      ],
    );
  }

  static String _sourceLabel(AttachmentSourceStatus status) {
    switch (status) {
      case AttachmentSourceStatus.fromAbacus:
        return 'From Abacus';
      case AttachmentSourceStatus.downloaded:
        return 'Downloaded';
      case AttachmentSourceStatus.localOnly:
        return 'Local only';
    }
  }

  static String _sourceTooltip(AttachmentSourceStatus status) {
    switch (status) {
      case AttachmentSourceStatus.fromAbacus:
        return 'Stored in Abacus; file content is not downloaded locally yet.';
      case AttachmentSourceStatus.downloaded:
        return 'Stored in Abacus and downloaded to this device.';
      case AttachmentSourceStatus.localOnly:
        return 'Only available on this device until the next successful sync.';
    }
  }

  static StatusBadgeTone _sourceTone(AttachmentSourceStatus status) {
    switch (status) {
      case AttachmentSourceStatus.fromAbacus:
        return StatusBadgeTone.info;
      case AttachmentSourceStatus.downloaded:
        return StatusBadgeTone.success;
      case AttachmentSourceStatus.localOnly:
        return StatusBadgeTone.warning;
    }
  }

  static IconData _sourceIcon(AttachmentSourceStatus status) {
    switch (status) {
      case AttachmentSourceStatus.fromAbacus:
        return Icons.cloud_queue_outlined;
      case AttachmentSourceStatus.downloaded:
        return Icons.download_done_outlined;
      case AttachmentSourceStatus.localOnly:
        return Icons.laptop_windows_outlined;
    }
  }

  static String _syncLabel(AttachmentSyncStatus status) {
    switch (status) {
      case AttachmentSyncStatus.pendingSync:
        return 'Pending sync';
      case AttachmentSyncStatus.synced:
        return 'Synced';
      case AttachmentSyncStatus.failed:
        return 'Failed';
    }
  }

  static String _syncTooltip(AttachmentSyncStatus status) {
    switch (status) {
      case AttachmentSyncStatus.pendingSync:
        return 'This file still needs to be uploaded or updated in Abacus.';
      case AttachmentSyncStatus.synced:
        return 'This file is in sync with Abacus.';
      case AttachmentSyncStatus.failed:
        return 'The last upload or update failed.';
    }
  }

  static StatusBadgeTone _syncTone(AttachmentSyncStatus status) {
    switch (status) {
      case AttachmentSyncStatus.pendingSync:
        return StatusBadgeTone.warning;
      case AttachmentSyncStatus.synced:
        return StatusBadgeTone.success;
      case AttachmentSyncStatus.failed:
        return StatusBadgeTone.error;
    }
  }

  static IconData _syncIcon(AttachmentSyncStatus status) {
    switch (status) {
      case AttachmentSyncStatus.pendingSync:
        return Icons.cloud_upload_outlined;
      case AttachmentSyncStatus.synced:
        return Icons.cloud_done_outlined;
      case AttachmentSyncStatus.failed:
        return Icons.error_outline_rounded;
    }
  }
}
