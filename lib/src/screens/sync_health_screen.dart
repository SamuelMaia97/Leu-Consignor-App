import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/activity_event.dart';
import '../models/consignor.dart';
import '../models/contract_record.dart';
import '../models/sync_status.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/workflow_status.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/page_header.dart';
import '../widgets/ready_to_sync_checklist.dart';
import '../widgets/section_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/sync_preview_dialog.dart';

class SyncHealthScreen extends StatefulWidget {
  const SyncHealthScreen({super.key});

  @override
  State<SyncHealthScreen> createState() => _SyncHealthScreenState();
}

class _SyncHealthScreenState extends State<SyncHealthScreen> {
  bool _initialConnectionCheckStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runInitialConnectionCheck();
    });
  }

  Future<void> _runInitialConnectionCheck() async {
    if (_initialConnectionCheckStarted || !mounted) return;
    _initialConnectionCheckStarted = true;

    final state = context.read<AppState>();
    if (!state.hasStoredToken || !state.hasValidToken || state.syncingNow) {
      return;
    }

    await state.testConnection();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Sync health',
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final preview = WorkflowStatus.buildSyncPreview(
            consignors: state.consignors,
            contracts: state.contracts,
          );
          final syncCandidateContracts = state.contracts
              .where((contract) => contract.shouldUploadDuringWorkspaceSync)
              .toList(growable: false);
          final issues = WorkflowStatus.readinessIssuesForWorkspace(
            consignors: state.consignors,
            contracts: syncCandidateContracts,
          );
          final conflicts = WorkflowStatus.findContractConflicts(
            state.contracts,
          );
          final pendingUploadContracts = syncCandidateContracts
              .where((contract) => contract.uploads.any(
                    (upload) => !upload.isDeleted && upload.needsSync,
                  ))
              .toList(growable: false);
          final failedContracts = state.contracts
              .where((contract) =>
                  contract.syncStatus == RecordSyncStatus.syncFailed)
              .toList(growable: false);

          return ListView(
            children: [
              PageHeader(
                eyebrow: 'SYNC',
                title: 'Sync health',
                actions: [
                  OutlinedButton.icon(
                    onPressed: state.syncingNow
                        ? null
                        : () async {
                            final confirmed = await showSyncPreviewDialog(
                              context: context,
                              consignors: state.consignors,
                              contracts: state.contracts,
                            );
                            if (!context.mounted || !confirmed) return;
                            await state.syncNow();
                            if (!context.mounted || state.lastMessage == null) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(state.lastMessage!)),
                            );
                          },
                    icon: state.syncingNow
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(state.syncingNow ? 'Syncing' : 'Preview sync'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await state.testConnection();
                      if (!context.mounted || state.lastMessage == null) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(state.lastMessage!)),
                      );
                    },
                    icon: const Icon(Icons.wifi_tethering_outlined),
                    label: const Text('Connection check'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1100
                      ? 4
                      : constraints.maxWidth >= 760
                          ? 2
                          : 1;
                  final width = columns == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - (16 * (columns - 1))) / columns;

                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: width,
                        child: _HealthMetric(
                          label: 'Abacus connection',
                          value: _connectionLabel(state),
                          icon: _connectionIcon(state),
                          tone: _connectionTone(state),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _HealthMetric(
                          label: 'Last sync',
                          value: _formatDateTime(state.lastSyncCompletedLocal),
                          icon: Icons.schedule_outlined,
                          tone: StatusBadgeTone.info,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _HealthMetric(
                          label: 'Pending uploads',
                          value: preview.pendingUploadCount.toString(),
                          icon: Icons.cloud_upload_outlined,
                          tone: preview.pendingUploadCount > 0
                              ? StatusBadgeTone.warning
                              : StatusBadgeTone.success,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _HealthMetric(
                          label: 'Failed uploads',
                          value: preview.failedUploadCount.toString(),
                          icon: Icons.error_outline_rounded,
                          tone: preview.failedUploadCount > 0
                              ? StatusBadgeTone.error
                              : StatusBadgeTone.success,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: 'Current sync state',
                icon: Icons.monitor_heart_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusBadge(
                          label:
                              '${preview.changedConsignorCount} consignor${preview.changedConsignorCount == 1 ? '' : 's'} changed',
                          tone: preview.changedConsignorCount > 0
                              ? StatusBadgeTone.warning
                              : StatusBadgeTone.success,
                          icon: Icons.people_outline,
                        ),
                        StatusBadge(
                          label:
                              '${preview.pendingContractCount} contract${preview.pendingContractCount == 1 ? '' : 's'} pending',
                          tone: preview.pendingContractCount > 0
                              ? StatusBadgeTone.warning
                              : StatusBadgeTone.success,
                          icon: Icons.description_outlined,
                        ),
                        StatusBadge(
                          label:
                              '${preview.knownContractCount} known COC contract${preview.knownContractCount == 1 ? '' : 's'}',
                          tone: StatusBadgeTone.info,
                          icon: Icons.find_in_page_outlined,
                        ),
                        StatusBadge(
                          label:
                              '${conflicts.length} conflict${conflicts.length == 1 ? '' : 's'}',
                          tone: conflicts.isEmpty
                              ? StatusBadgeTone.success
                              : StatusBadgeTone.error,
                          icon: Icons.content_copy_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _ProgressText(state: state),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: 'Ready-to-sync contracts',
                icon: Icons.checklist_rtl_outlined,
                child: _ContractChecklistSection(
                  consignors: state.consignors,
                  contracts: state.contracts,
                  issues: issues,
                ),
              ),
              if (conflicts.isNotEmpty) ...[
                const SizedBox(height: 18),
                SectionCard(
                  title: 'Duplicate / conflict warnings',
                  icon: Icons.content_copy_outlined,
                  child: Column(
                    children: conflicts
                        .map((conflict) => _ConflictRow(conflict: conflict))
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SectionCard(
                title: 'Pending and failed uploads',
                icon: Icons.cloud_queue_outlined,
                child: pendingUploadContracts.isEmpty && failedContracts.isEmpty
                    ? const AppEmptyState(
                        title: 'No upload queue issues',
                        message:
                            'There are no pending or failed contract uploads.',
                        icon: Icons.cloud_done_outlined,
                      )
                    : Column(
                        children: [
                          ...pendingUploadContracts.take(8).map(
                                (contract) => _UploadQueueRow(
                                  contract: contract,
                                  label: 'Pending upload/update',
                                ),
                              ),
                          ...failedContracts.take(8).map(
                                (contract) => _UploadQueueRow(
                                  contract: contract,
                                  label: 'Failed',
                                ),
                              ),
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: 'Activity history',
                icon: Icons.history_toggle_off_outlined,
                child: state.activityEvents.isEmpty
                    ? const AppEmptyState(
                        title: 'No activity yet',
                        message:
                            'Local save, PDF, download, and sync events will appear here.',
                        icon: Icons.history_outlined,
                      )
                    : Column(
                        children: state.activityEvents
                            .take(25)
                            .map((event) => _ActivityRow(event: event))
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _connectionLabel(AppState state) {
    if (!state.hasStoredToken) return 'Sign-in required';
    if (!state.hasValidToken) return 'Login expired';
    final succeeded = state.lastConnectionSucceeded;
    if (succeeded == true) return 'Reachable';
    if (succeeded == false) return 'Failed';
    return 'Not checked';
  }

  static IconData _connectionIcon(AppState state) {
    if (!state.hasStoredToken || !state.hasValidToken) {
      return Icons.lock_outline_rounded;
    }
    if (state.lastConnectionSucceeded == false) {
      return Icons.wifi_off_outlined;
    }
    if (state.lastConnectionSucceeded == true) {
      return Icons.wifi_tethering_outlined;
    }
    return Icons.help_outline_rounded;
  }

  static StatusBadgeTone _connectionTone(AppState state) {
    if (!state.hasStoredToken || !state.hasValidToken) {
      return StatusBadgeTone.warning;
    }
    if (state.lastConnectionSucceeded == false) return StatusBadgeTone.error;
    if (state.lastConnectionSucceeded == true) return StatusBadgeTone.success;
    return StatusBadgeTone.info;
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) return 'Never';
    return DateFormat('yyyy-MM-dd HH:mm').format(value);
  }
}

class _ContractChecklistSection extends StatelessWidget {
  const _ContractChecklistSection({
    required this.consignors,
    required this.contracts,
    required this.issues,
  });

  final List<Consignor> consignors;
  final List<ContractRecord> contracts;
  final List<ReadinessIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return const ReadyToSyncChecklist(
        issues: [],
        emptyTitle: 'All contracts ready',
        emptyMessage: 'No missing or suspicious contract items detected.',
      );
    }

    final groups = _ContractChecklistGroup.from(
      consignors: consignors,
      contracts: contracts,
      issues: issues,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          _ContractChecklistGroupTile(group: groups[index]),
          if (index != groups.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _ContractChecklistGroupTile extends StatelessWidget {
  const _ContractChecklistGroupTile({required this.group});

  final _ContractChecklistGroup group;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final contract = group.contract;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.description_outlined, color: palette.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(group.subtitle),
                  ],
                ),
              ),
              if (contract != null) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => context.go(_contractPath(contract)),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open contract'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ReadyToSyncChecklist(
            issues: group.issues,
            maxVisibleItems: 6,
          ),
        ],
      ),
    );
  }

  static String _contractPath(ContractRecord contract) {
    if (contract.isEditableDraft) {
      return '/contracts/${contract.consignorId}/record/${contract.id}/resume';
    }

    if (contract.auctionId == null) {
      return '/contracts/${contract.consignorId}/record/${contract.id}';
    }

    return '/contracts/${contract.consignorId}/${contract.auctionId}';
  }
}

class _ContractChecklistGroup {
  const _ContractChecklistGroup({
    required this.title,
    required this.subtitle,
    required this.issues,
    this.contract,
  });

  final String title;
  final String subtitle;
  final List<ReadinessIssue> issues;
  final ContractRecord? contract;

  static List<_ContractChecklistGroup> from({
    required List<Consignor> consignors,
    required List<ContractRecord> contracts,
    required List<ReadinessIssue> issues,
  }) {
    final consignorsById = {
      for (final consignor in consignors) consignor.id: consignor,
    };
    final contractsById = {
      for (final contract in contracts) contract.id: contract,
    };
    final grouped = <String, List<ReadinessIssue>>{};

    for (final issue in issues) {
      final key = issue.relatedContractId ?? issue.relatedConsignorId ?? '_';
      grouped.putIfAbsent(key, () => <ReadinessIssue>[]).add(issue);
    }

    final groups = grouped.entries.map((entry) {
      final contract = contractsById[entry.key];
      final consignorId =
          contract?.consignorId ?? entry.value.first.relatedConsignorId;
      final consignor =
          consignorId == null ? null : consignorsById[consignorId];
      final contractNumber = contract == null
          ? ''
          : WorkflowStatus.extractContractNumber(contract) ?? contract.pdfName;
      final safeContractNumber = contractNumber.trim().isEmpty
          ? 'Contract ${contract?.id ?? entry.key}'
          : contractNumber.trim();
      final consignorName = consignor == null || consignor.displayName.isEmpty
          ? 'Unknown consignor'
          : consignor.displayName;

      return _ContractChecklistGroup(
        title: 'Consignor contract: $safeContractNumber',
        subtitle: consignorName,
        issues: entry.value,
        contract: contract,
      );
    }).toList(growable: false);

    groups.sort((a, b) => a.title.compareTo(b.title));
    return groups;
  }
}

class _ProgressText extends StatelessWidget {
  const _ProgressText({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final message = state.syncingNow
        ? state.syncProgressMessage
        : state.lastMessage ?? 'Workspace ready';
    final contractMessage = state.contractSyncProgressMessage.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message.trim().isEmpty ? 'Workspace ready' : message),
        if (contractMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(contractMessage),
        ],
      ],
    );
  }
}

class _HealthMetric extends StatelessWidget {
  const _HealthMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final StatusBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tone) {
      StatusBadgeTone.success => palette.success,
      StatusBadgeTone.warning => palette.warning,
      StatusBadgeTone.error => palette.error,
      StatusBadgeTone.info => palette.info,
      StatusBadgeTone.neutral => palette.textMuted,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 14),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({required this.conflict});

  final ContractConflict conflict;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.content_copy_outlined, color: context.palette.error),
      title: Text(conflict.contractNumber),
      subtitle: Text(
        '${conflict.contracts.length} local records use this contract number.',
      ),
    );
  }
}

class _UploadQueueRow extends StatelessWidget {
  const _UploadQueueRow({
    required this.contract,
    required this.label,
  });

  final ContractRecord contract;
  final String label;

  @override
  Widget build(BuildContext context) {
    final contractNumber =
        WorkflowStatus.extractContractNumber(contract) ?? contract.pdfName;
    final pending = contract.uploads
        .where((upload) => !upload.isDeleted && upload.needsSync)
        .length;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.attach_file_outlined),
      title: Text(contractNumber.trim().isEmpty ? contract.id : contractNumber),
      subtitle:
          Text('$label - $pending pending file${pending == 1 ? '' : 's'}'),
      trailing: TextButton(
        onPressed: () => context.go(
          contract.auctionId == null
              ? '/contracts/${contract.consignorId}/record/${contract.id}'
              : '/contracts/${contract.consignorId}/${contract.auctionId}',
        ),
        child: const Text('Open'),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event});

  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon(event.type), color: _color(context, event.type)),
      title: Text(event.title),
      subtitle: Text(
        [
          if (event.description.trim().isNotEmpty) event.description.trim(),
          DateFormat('yyyy-MM-dd HH:mm').format(event.occurredAtUtc.toLocal()),
        ].join(' - '),
      ),
    );
  }

  static IconData _icon(ActivityEventType type) {
    switch (type) {
      case ActivityEventType.consignorSaved:
        return Icons.person_outline;
      case ActivityEventType.contractCreated:
        return Icons.post_add_outlined;
      case ActivityEventType.contractUpdated:
        return Icons.edit_document;
      case ActivityEventType.pdfGenerated:
        return Icons.picture_as_pdf_outlined;
      case ActivityEventType.passportDownloaded:
        return Icons.download_done_outlined;
      case ActivityEventType.syncStarted:
        return Icons.sync_rounded;
      case ActivityEventType.syncSucceeded:
        return Icons.cloud_done_outlined;
      case ActivityEventType.syncFailed:
        return Icons.error_outline_rounded;
      case ActivityEventType.connectionSucceeded:
        return Icons.wifi_tethering_outlined;
      case ActivityEventType.connectionFailed:
        return Icons.wifi_off_outlined;
      case ActivityEventType.warning:
        return Icons.warning_amber_rounded;
    }
  }

  static Color _color(BuildContext context, ActivityEventType type) {
    final palette = context.palette;
    switch (type) {
      case ActivityEventType.syncFailed:
      case ActivityEventType.connectionFailed:
      case ActivityEventType.warning:
        return palette.error;
      case ActivityEventType.syncSucceeded:
      case ActivityEventType.connectionSucceeded:
      case ActivityEventType.passportDownloaded:
        return palette.success;
      default:
        return palette.brand;
    }
  }
}
