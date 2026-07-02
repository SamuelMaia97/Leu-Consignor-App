import 'package:flutter/material.dart';

import '../models/consignor.dart';
import '../models/contract_record.dart';
import '../utils/workflow_status.dart';
import 'ready_to_sync_checklist.dart';

Future<bool> showSyncPreviewDialog({
  required BuildContext context,
  required Iterable<Consignor> consignors,
  required Iterable<ContractRecord> contracts,
}) async {
  final contractList = contracts.toList(growable: false);
  final syncCandidateContracts = contractList
      .where((contract) => contract.shouldUploadDuringWorkspaceSync)
      .toList(growable: false);
  final summary = WorkflowStatus.buildSyncPreview(
    consignors: consignors,
    contracts: contractList,
  );
  final issues = WorkflowStatus.readinessIssuesForWorkspace(
    consignors: consignors,
    contracts: syncCandidateContracts,
  );

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sync preview'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewLine(
                icon: Icons.people_outline,
                label:
                    '${summary.changedConsignorCount} consignor${summary.changedConsignorCount == 1 ? '' : 's'} changed locally',
              ),
              _PreviewLine(
                icon: Icons.description_outlined,
                label:
                    '${summary.knownContractCount} known COC contract${summary.knownContractCount == 1 ? '' : 's'} in the local workspace',
              ),
              _PreviewLine(
                icon: Icons.cloud_upload_outlined,
                label:
                    '${summary.pendingContractCount} local contract${summary.pendingContractCount == 1 ? '' : 's'} pending upload/update',
              ),
              _PreviewLine(
                icon: Icons.attach_file_outlined,
                label:
                    '${summary.pendingUploadCount} pending file upload${summary.pendingUploadCount == 1 ? '' : 's'}, ${summary.failedUploadCount} failed file${summary.failedUploadCount == 1 ? '' : 's'}',
              ),
              _PreviewLine(
                icon: Icons.content_copy_outlined,
                label:
                    '${summary.localConflictCount} duplicate contract-number warning${summary.localConflictCount == 1 ? '' : 's'}',
              ),
              const SizedBox(height: 14),
              Text(
                'Abacus changes and new contracts are checked once sync starts.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              ReadyToSyncChecklist(
                issues: issues,
                maxVisibleItems: 5,
                emptyTitle: 'No checklist warnings',
                emptyMessage: 'The local workspace looks ready for sync.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Start sync'),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
