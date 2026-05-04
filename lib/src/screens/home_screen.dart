import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/sync_status.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/page_header.dart';
import '../widgets/responsive.dart';
import '../widgets/section_card.dart';
import '../widgets/status_badge.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Dashboard',
      child: Consumer<AppState>(
        builder: (context, state, _) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          final palette = context.palette;
          final consignorCount = state.consignors.length;
          final contractCount = state.contracts.length;
          final draftCount = state.consignors
              .where((c) => c.syncStatus == RecordSyncStatus.draft)
              .length;
          final pendingCount = state.consignors
              .where((c) => c.syncStatus == RecordSyncStatus.pendingSync)
              .length;
          final syncedCount = state.consignors
              .where((c) => c.syncStatus == RecordSyncStatus.synced)
              .length;
          final failedCount = state.consignors
              .where((c) => c.syncStatus == RecordSyncStatus.syncFailed)
              .length;
          final recentConsignors = state.consignors.take(5).toList();

          void goToFilter(String filter) {
            context.go('/consignors?filter=$filter');
          }

          return ListView(
            children: [
              PageHeader(
                eyebrow: '',
                title: 'Dashboard',
                trailing: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'System status',
                        style: TextStyle(
                          color: Color(0xFFDCE6F3),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          StatusBadge(
                            label: _authBadgeLabel(state),
                            tone: _authBadgeTone(state),
                            icon: _authBadgeIcon(state),
                            onTap: () => context.go('/settings'),
                          ),
                          StatusBadge(
                            label: '$syncedCount synced',
                            tone: StatusBadgeTone.success,
                            icon: Icons.cloud_done_outlined,
                            onTap: () => goToFilter('synced'),
                          ),
                          StatusBadge(
                            label: '$pendingCount pending sync',
                            tone: StatusBadgeTone.info,
                            icon: Icons.cloud_upload_outlined,
                            onTap: () => goToFilter('pending'),
                          ),
                          StatusBadge(
                            label:
                                '$draftCount local draft${draftCount == 1 ? '' : 's'}',
                            tone: draftCount > 0
                                ? StatusBadgeTone.warning
                                : StatusBadgeTone.info,
                            icon: draftCount > 0
                                ? Icons.edit_note_outlined
                                : Icons.checklist_rtl_outlined,
                            onTap: () => goToFilter('draft'),
                          ),
                          StatusBadge(
                            label: '$failedCount failed',
                            tone: failedCount > 0
                                ? StatusBadgeTone.warning
                                : StatusBadgeTone.info,
                            icon: Icons.error_outline_rounded,
                            onTap: () => goToFilter('failed'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  ElevatedButton.icon(
                    onPressed: () => context.go('/consignors/new'),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Create consignor'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/contracts/new'),
                    icon: const Icon(Icons.post_add_outlined),
                    label: const Text('Create contract'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await state.syncNow();
                      if (context.mounted && state.lastMessage != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(state.lastMessage!)),
                        );
                      }
                    },
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Run sync'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.signingIn
                        ? null
                        : () async {
                            await state.signInWithMicrosoft();
                            if (context.mounted && state.lastMessage != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(state.lastMessage!)),
                              );
                            }
                          },
                    icon: state.signingIn
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(
                      state.signingIn
                          ? 'Signing in…'
                          : state.hasValidToken
                              ? 'Refresh Microsoft login'
                              : 'Microsoft login required',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.syncingAllDrafts
                        ? null
                        : () async {
                            await state.syncAllDraftConsignors();
                            if (context.mounted && state.lastMessage != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(state.lastMessage!)),
                              );
                            }
                          },
                    icon: state.syncingAllDrafts
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      state.syncingAllDrafts ? 'Syncing…' : 'Sync pending',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/settings'),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Configuration'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1240
                      ? 4
                      : constraints.maxWidth >= 860
                          ? 2
                          : 1;
                  final cards = [
                    _MetricCard(
                      label: 'Consignors in workspace',
                      value: consignorCount.toString(),
                      icon: Icons.people_outline,
                      accent: palette.brand,
                      onTap: () => context.go('/consignors'),
                    ),
                    _MetricCard(
                      label: 'Contracts recorded',
                      value: contractCount.toString(),
                      icon: Icons.description_outlined,
                      accent: palette.info,
                      onTap: () => context.go('/contracts'),
                    ),
                    _MetricCard(
                      label: 'Pending local drafts',
                      value: draftCount.toString(),
                      icon: Icons.edit_calendar_outlined,
                      accent:
                          draftCount > 0 ? palette.warning : palette.success,
                      onTap: () => goToFilter('draft'),
                    ),
                    _MetricCard(
                      label: 'Authentication state',
                      value: _authMetricLabel(state),
                      icon: Icons.security_outlined,
                      accent: _authMetricColor(state, palette),
                      onTap: () => context.go('/settings'),
                    ),
                  ];
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: cards
                        .map(
                          (card) => SizedBox(
                            width: columns == 1
                                ? constraints.maxWidth
                                : columns == 2
                                    ? (constraints.maxWidth - 16) / 2
                                    : (constraints.maxWidth - 48) / 4,
                            child: card,
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final split = constraints.maxWidth >= 1100;
                  return split
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: SectionCard(
                                title: 'Operational actions',
                                icon: Icons.flash_on_outlined,
                                child: Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    _ActionTile(
                                      title: 'Create consignor',
                                      icon: Icons.person_add_alt_1_outlined,
                                      onTap: () =>
                                          context.go('/consignors/new'),
                                    ),
                                    _ActionTile(
                                      title: 'Create contract',
                                      icon: Icons.post_add_outlined,
                                      onTap: () => context.go('/contracts/new'),
                                    ),
                                    _ActionTile(
                                      title: 'Open list',
                                      icon:
                                          Icons.format_list_bulleted_rounded,
                                      onTap: () => context.go('/consignors'),
                                    ),
                                    _ActionTile(
                                      title: 'Connection check',
                                      icon: Icons.wifi_tethering_outlined,
                                      onTap: () async {
                                        await state.testConnection();
                                        if (context.mounted &&
                                            state.lastMessage != null) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content:
                                                  Text(state.lastMessage!),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 5,
                              child: SectionCard(
                                title: 'Workspace status',
                                icon: Icons.monitor_heart_outlined,
                                child: Column(
                                  children: [
                                    _StatusRow(
                                      label: 'Sync ready',
                                      value: state.hasValidToken
                                          ? 'Yes'
                                          : 'Sign-in required',
                                    ),
                                    const Divider(height: 24),
                                    _StatusRow(
                                      label: 'Microsoft session',
                                      value: _authDetailLabel(state),
                                    ),
                                    const Divider(height: 24),
                                    _StatusRow(
                                      label: 'Token expiry',
                                      value:
                                          _formatExpiry(state.tokenExpiresAtLocal),
                                    ),
                                    const Divider(height: 24),
                                    _StatusRow(
                                      label: 'Latest feedback',
                                      value: state.lastMessage ??
                                          'No recent system message',
                                    ),
                                    const Divider(height: 24),
                                    _StatusRow(
                                      label: 'Local workspace',
                                      value: draftCount > 0
                                          ? '$draftCount draft${draftCount == 1 ? '' : 's'} waiting locally'
                                          : 'All current consignors marked synced',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            SectionCard(
                              title: 'Operational actions',
                              icon: Icons.flash_on_outlined,
                              child: Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  _ActionTile(
                                    title: 'Create consignor',
                                    icon: Icons.person_add_alt_1_outlined,
                                    onTap: () =>
                                        context.go('/consignors/new'),
                                  ),
                                  _ActionTile(
                                    title: 'Create contract',
                                    icon: Icons.post_add_outlined,
                                    onTap: () => context.go('/contracts/new'),
                                  ),
                                  _ActionTile(
                                    title: 'Open list',
                                    icon:
                                        Icons.format_list_bulleted_rounded,
                                    onTap: () => context.go('/consignors'),
                                  ),
                                  _ActionTile(
                                    title: 'Connection check',
                                    icon: Icons.wifi_tethering_outlined,
                                    onTap: () async {
                                      await state.testConnection();
                                      if (context.mounted &&
                                          state.lastMessage != null) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content:
                                                Text(state.lastMessage!),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SectionCard(
                              title: 'Workspace status',
                              icon: Icons.monitor_heart_outlined,
                              child: Column(
                                children: [
                                  _StatusRow(
                                    label: 'Sync ready',
                                    value: state.hasValidToken
                                        ? 'Yes'
                                        : 'Sign-in required',
                                  ),
                                  const Divider(height: 24),
                                  _StatusRow(
                                    label: 'Microsoft session',
                                    value: _authDetailLabel(state),
                                  ),
                                  const Divider(height: 24),
                                  _StatusRow(
                                    label: 'Token expiry',
                                    value:
                                        _formatExpiry(state.tokenExpiresAtLocal),
                                  ),
                                  const Divider(height: 24),
                                  _StatusRow(
                                    label: 'Latest feedback',
                                    value: state.lastMessage ??
                                        'No recent system message',
                                  ),
                                  const Divider(height: 24),
                                  _StatusRow(
                                    label: 'Local workspace',
                                    value: draftCount > 0
                                        ? '$draftCount draft${draftCount == 1 ? '' : 's'} waiting locally'
                                        : 'All current consignors marked synced',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                },
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: 'Recent consignor activity',
                icon: Icons.history_toggle_off_outlined,
                trailing: TextButton(
                  onPressed: () => context.go('/consignors'),
                  child: const Text('View all'),
                ),
                child: recentConsignors.isEmpty
                    ? AppEmptyState(
                        title: 'No consignors yet',
                        message:
                            'Create your first consignor to begin the contract workflow and sync process.',
                        icon: Icons.people_outline,
                        action: ElevatedButton.icon(
                          onPressed: () => context.go('/consignors/new'),
                          icon: const Icon(Icons.add),
                          label: const Text('Create consignor'),
                        ),
                      )
                    : Column(
                        children: recentConsignors
                            .map(
                              (consignor) => InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () =>
                                    context.go('/consignors/${consignor.id}'),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    border: Border.all(
                                      color: palette.border,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor:
                                            palette.brandSoft,
                                        child: Text(
                                          consignor.displayName.isNotEmpty
                                              ? consignor.displayName
                                                  .trim()
                                                  .substring(0, 1)
                                                  .toUpperCase()
                                              : '#',
                                          style: TextStyle(
                                            color: palette.brand,
                                            fontWeight:
                                                FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              consignor.displayName
                                                      .isEmpty
                                                  ? 'Unnamed consignor'
                                                  : consignor.displayName,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              consignor.emailAddress
                                                      .isEmpty
                                                  ? 'No email stored'
                                                  : consignor.emailAddress,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                            ),
                                          ],
                                        ),
                                      ),
                                      StatusBadge(
                                        label: _statusLabel(
                                          consignor.syncStatus,
                                        ),
                                        tone: _statusTone(
                                          consignor.syncStatus,
                                        ),
                                        icon: _statusIcon(
                                          consignor.syncStatus,
                                        ),
                                        onTap: () => context.go(
                                          '/consignors?filter=${_filterValue(consignor.syncStatus)}',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _authBadgeLabel(AppState state) {
    if (!state.hasStoredToken) return 'Sign-in required';
    if (!state.hasValidToken) return 'Login expired';
    if (state.tokenExpiringSoon) return 'Login expiring soon';
    return 'Microsoft connected';
  }

  static StatusBadgeTone _authBadgeTone(AppState state) {
    if (!state.hasStoredToken || !state.hasValidToken) {
      return StatusBadgeTone.warning;
    }
    if (state.tokenExpiringSoon) {
      return StatusBadgeTone.info;
    }
    return StatusBadgeTone.success;
  }

  static IconData _authBadgeIcon(AppState state) {
    if (!state.hasStoredToken || !state.hasValidToken) {
      return Icons.lock_outline;
    }
    if (state.tokenExpiringSoon) {
      return Icons.access_time_rounded;
    }
    return Icons.verified_user_outlined;
  }

  static String _authMetricLabel(AppState state) {
    if (!state.hasStoredToken) return 'Inactive';
    if (!state.hasValidToken) return 'Expired';
    if (state.tokenExpiringSoon) return 'Expiring soon';
    return 'Active';
  }

  static Color _authMetricColor(AppState state, AppPalette palette) {
    if (!state.hasStoredToken || !state.hasValidToken) {
      return palette.warning;
    }
    if (state.tokenExpiringSoon) {
      return palette.info;
    }
    return palette.success;
  }

  static String _authDetailLabel(AppState state) {
    if (!state.hasStoredToken) {
      return 'No Microsoft token stored';
    }
    if (!state.hasValidToken) {
      return 'Stored token expired. Refresh your login.';
    }
    if (state.tokenExpiringSoon) {
      return 'Token is still valid but should be refreshed soon';
    }
    return 'Token is valid';
  }

  static String _formatExpiry(DateTime? value) {
    if (value == null) {
      return 'Unknown';
    }

    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  static String _statusLabel(RecordSyncStatus status) {
    switch (status) {
      case RecordSyncStatus.draft:
        return 'Draft';
      case RecordSyncStatus.pendingSync:
        return 'Pending';
      case RecordSyncStatus.synced:
        return 'Synced';
      case RecordSyncStatus.syncFailed:
        return 'Failed';
    }
  }

  static StatusBadgeTone _statusTone(RecordSyncStatus status) {
    switch (status) {
      case RecordSyncStatus.synced:
        return StatusBadgeTone.success;
      case RecordSyncStatus.pendingSync:
        return StatusBadgeTone.info;
      case RecordSyncStatus.draft:
        return StatusBadgeTone.warning;
      case RecordSyncStatus.syncFailed:
        return StatusBadgeTone.warning;
    }
  }

  static IconData _statusIcon(RecordSyncStatus status) {
    switch (status) {
      case RecordSyncStatus.synced:
        return Icons.cloud_done_outlined;
      case RecordSyncStatus.pendingSync:
        return Icons.cloud_upload_outlined;
      case RecordSyncStatus.draft:
        return Icons.edit_note_outlined;
      case RecordSyncStatus.syncFailed:
        return Icons.error_outline_rounded;
    }
  }

  static String _filterValue(RecordSyncStatus status) {
    switch (status) {
      case RecordSyncStatus.draft:
        return 'draft';
      case RecordSyncStatus.pendingSync:
        return 'pending';
      case RecordSyncStatus.synced:
        return 'synced';
      case RecordSyncStatus.syncFailed:
        return 'failed';
    }
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(height: 22),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(fontSize: 30),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: content,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: isMobileWidth(context) ? double.infinity : 270,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.border),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  palette.brandSoft.withValues(alpha: 0.44),
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: palette.brand,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.brand),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}