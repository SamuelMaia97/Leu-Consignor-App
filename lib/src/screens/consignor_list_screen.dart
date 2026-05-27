import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/consignor.dart';
import '../models/sync_status.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';
import '../widgets/status_badge.dart';

class ConsignorListScreen extends StatefulWidget {
  const ConsignorListScreen({super.key});

  @override
  State<ConsignorListScreen> createState() => _ConsignorListScreenState();
}

class _ConsignorListScreenState extends State<ConsignorListScreen> {
  late final TextEditingController _searchController;
  String _query = '';
  _ConsignorQuickFilter _quickFilter = _ConsignorQuickFilter.all;
  String? _lastRouteFilter;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()
      ..addListener(_handleSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final routeFilter = GoRouterState.of(context).uri.queryParameters['filter'];
    if (routeFilter == _lastRouteFilter) return;

    _lastRouteFilter = routeFilter;
    _quickFilter = _filterFromQuery(routeFilter);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final nextQuery = _searchController.text;
    if (nextQuery == _query) return;

    setState(() {
      _query = nextQuery;
    });
  }

  void _clearQuery() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
  }

  void _setQuickFilter(_ConsignorQuickFilter filter) {
    setState(() {
      _quickFilter = filter;
    });

    final value = _filterToQuery(filter);
    if (value == null) {
      context.go('/consignors');
      return;
    }

    context.go('/consignors?filter=$value');
  }

  Future<void> _launchExternal(String uriString) async {
    final uri = Uri.parse(uriString);
    if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $uriString')),
      );
    }
  }

  Future<void> _callNumber(String phone) =>
      _launchExternal('tel:${Uri.encodeComponent(phone)}');

  Future<void> _sendEmail(String email) =>
      _launchExternal('mailto:${Uri.encodeComponent(email)}');

  Future<void> _openAddress(String address) {
    final encoded = Uri.encodeComponent(address);
    if (kIsWeb) {
      return _launchExternal(
        'https://www.google.com/maps/search/?api=1&query=$encoded',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _launchExternal('http://maps.apple.com/?q=$encoded');
      case TargetPlatform.android:
        return _launchExternal('geo:0,0?q=$encoded');
      default:
        return _launchExternal(
          'https://www.google.com/maps/search/?api=1&query=$encoded',
        );
    }
  }

  Future<void> _syncDraft(Consignor item) async {
    final updated = await context.read<AppState>().syncConsignor(item.id);

    if (!mounted) return;

    final message =
        updated != null && updated.syncStatus == RecordSyncStatus.synced
            ? 'Consignor synced successfully.'
            : (updated?.syncErrorMessage ??
                context.read<AppState>().lastMessage ??
                'Draft sync finished.');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteLocalDraft(Consignor item) async {
    final confirmed = await _confirmDeleteLocalConsignorDraft(item);
    if (!confirmed || !mounted) return;

    final deleted = await context.read<AppState>().deleteLocalConsignorDraft(
          item.id,
        );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Local consignor draft deleted.'
              : 'This consignor is not a local-only draft.',
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteLocalConsignorDraft(Consignor item) async {
    final displayName = item.displayName.trim().isEmpty
        ? 'Unnamed consignor'
        : item.displayName.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete draft?'),
        content: Text(
          'This will permanently delete the local draft "$displayName" from this device, including any local contract drafts for this consignor. '
          'Nothing will be deleted from the backend/server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete draft'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  void _showSyncError(Consignor item) {
    final displayName = item.displayName.trim().isEmpty
        ? 'Unnamed consignor'
        : item.displayName.trim();
    final message = item.syncErrorMessage?.trim();
    if (message == null || message.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sync error: $displayName'),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static _LocalDraftAction? _localDraftActionFor(Consignor item) {
    if (!item.hasRemoteReference &&
        (item.syncStatus == RecordSyncStatus.draft ||
            item.syncStatus == RecordSyncStatus.syncFailed)) {
      return _LocalDraftAction.deleteDraft;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Consignors',
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final summary = _ConsignorListSummary.from(
            consignors: state.consignors,
            query: _query,
            quickFilter: _quickFilter,
          );

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: PageHeader(
                  eyebrow: 'DIRECTORY',
                  title: 'Consignor records and ongoing work',
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
                          'Directory status',
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
                              label: '${summary.syncedCount} synced',
                              tone: StatusBadgeTone.success,
                              icon: Icons.sync_alt,
                              onTap: () =>
                                  _setQuickFilter(_ConsignorQuickFilter.synced),
                            ),
                            StatusBadge(
                              label: '${summary.pendingCount} pending sync',
                              tone: StatusBadgeTone.info,
                              icon: Icons.cloud_upload_outlined,
                              onTap: () => _setQuickFilter(
                                _ConsignorQuickFilter.pendingSync,
                              ),
                            ),
                            StatusBadge(
                              label:
                                  '${summary.draftCount} draft${summary.draftCount == 1 ? '' : 's'}',
                              tone: StatusBadgeTone.warning,
                              icon: Icons.edit_note_outlined,
                              onTap: () =>
                                  _setQuickFilter(_ConsignorQuickFilter.draft),
                            ),
                            StatusBadge(
                              label: '${summary.failedCount} failed',
                              tone: StatusBadgeTone.warning,
                              icon: Icons.error_outline_rounded,
                              onTap: () =>
                                  _setQuickFilter(_ConsignorQuickFilter.failed),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    ElevatedButton.icon(
                      onPressed: () => context.go('/consignors/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('New consignor'),
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: SectionCard(
                  title: 'Search and manage',
                  subtitle:
                      'Search by name, email, phone, address, or use the quick status filters below.',
                  icon: Icons.manage_search_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search_rounded),
                                labelText: 'Search consignors',
                                hintText:
                                    'Try a name, email, city, or error text',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _query.isEmpty ? null : _clearQuery,
                            icon: const Icon(Icons.clear_rounded),
                            label: const Text('Clear'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _QuickFilterChip(
                            label: 'All',
                            selected: _quickFilter == _ConsignorQuickFilter.all,
                            onSelected: () =>
                                _setQuickFilter(_ConsignorQuickFilter.all),
                          ),
                          _QuickFilterChip(
                            label: 'Draft',
                            selected:
                                _quickFilter == _ConsignorQuickFilter.draft,
                            onSelected: () =>
                                _setQuickFilter(_ConsignorQuickFilter.draft),
                          ),
                          _QuickFilterChip(
                            label: 'Pending sync',
                            selected: _quickFilter ==
                                _ConsignorQuickFilter.pendingSync,
                            onSelected: () => _setQuickFilter(
                              _ConsignorQuickFilter.pendingSync,
                            ),
                          ),
                          _QuickFilterChip(
                            label: 'Synced',
                            selected:
                                _quickFilter == _ConsignorQuickFilter.synced,
                            onSelected: () =>
                                _setQuickFilter(_ConsignorQuickFilter.synced),
                          ),
                          _QuickFilterChip(
                            label: 'Failed',
                            selected:
                                _quickFilter == _ConsignorQuickFilter.failed,
                            onSelected: () =>
                                _setQuickFilter(_ConsignorQuickFilter.failed),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          _InfoPill(label: '${summary.totalCount} total'),
                          const SizedBox(width: 10),
                          _InfoPill(label: '${summary.visibleCount} visible'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              if (summary.visibleItems.isEmpty)
                SliverToBoxAdapter(
                  child: AppEmptyState(
                    title: summary.totalCount == 0
                        ? 'No consignors available'
                        : 'No results match the current filters',
                    message: summary.totalCount == 0
                        ? 'Create your first consignor to start building contracts and syncing records.'
                        : 'Try a different search term or switch the current status filter.',
                    icon: Icons.people_outline,
                    action: summary.totalCount == 0
                        ? ElevatedButton.icon(
                            onPressed: () => context.go('/consignors/new'),
                            icon: const Icon(Icons.add),
                            label: const Text('Create consignor'),
                          )
                        : OutlinedButton.icon(
                            onPressed: () {
                              _setQuickFilter(_ConsignorQuickFilter.all);
                              _clearQuery();
                            },
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset filters'),
                          ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = summary.visibleItems[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom:
                            index == summary.visibleItems.length - 1 ? 0 : 12,
                      ),
                      child: _ConsignorRow(
                        item: item,
                        isSyncing: state.isSyncingConsignor(item.id),
                        onSync: item.needsSync ? () => _syncDraft(item) : null,
                        localAction: _localDraftActionFor(item),
                        onDeleteDraft: () => _deleteLocalDraft(item),
                        onViewError:
                            item.syncStatus == RecordSyncStatus.syncFailed &&
                                    (item.syncErrorMessage?.trim().isNotEmpty ??
                                        false)
                                ? () => _showSyncError(item)
                                : null,
                        onSendEmail: _sendEmail,
                        onCallNumber: _callNumber,
                        onOpenAddress: _openAddress,
                      ),
                    );
                  }, childCount: summary.visibleItems.length),
                ),
            ],
          );
        },
      ),
    );
  }

  static _ConsignorQuickFilter _filterFromQuery(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'draft':
        return _ConsignorQuickFilter.draft;
      case 'pending':
      case 'pending-sync':
        return _ConsignorQuickFilter.pendingSync;
      case 'synced':
        return _ConsignorQuickFilter.synced;
      case 'failed':
      case 'sync-failed':
        return _ConsignorQuickFilter.failed;
      default:
        return _ConsignorQuickFilter.all;
    }
  }

  static String? _filterToQuery(_ConsignorQuickFilter filter) {
    switch (filter) {
      case _ConsignorQuickFilter.all:
        return null;
      case _ConsignorQuickFilter.draft:
        return 'draft';
      case _ConsignorQuickFilter.pendingSync:
        return 'pending';
      case _ConsignorQuickFilter.synced:
        return 'synced';
      case _ConsignorQuickFilter.failed:
        return 'failed';
    }
  }
}

enum _ConsignorQuickFilter {
  all,
  draft,
  pendingSync,
  synced,
  failed,
}

enum _LocalDraftAction {
  deleteDraft,
}

class _ConsignorListSummary {
  const _ConsignorListSummary({
    required this.visibleItems,
    required this.totalCount,
    required this.syncedCount,
    required this.pendingCount,
    required this.draftCount,
    required this.failedCount,
  });

  final List<Consignor> visibleItems;
  final int totalCount;
  final int syncedCount;
  final int pendingCount;
  final int draftCount;
  final int failedCount;

  int get visibleCount => visibleItems.length;

  factory _ConsignorListSummary.from({
    required List<Consignor> consignors,
    required String query,
    required _ConsignorQuickFilter quickFilter,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final visibleItems = <Consignor>[];

    var syncedCount = 0;
    var pendingCount = 0;
    var draftCount = 0;
    var failedCount = 0;

    for (final consignor in consignors) {
      switch (consignor.syncStatus) {
        case RecordSyncStatus.synced:
          syncedCount++;
          break;
        case RecordSyncStatus.pendingSync:
          pendingCount++;
          break;
        case RecordSyncStatus.draft:
          draftCount++;
          break;
        case RecordSyncStatus.syncFailed:
          failedCount++;
          break;
      }

      if (!_matchesQuickFilter(consignor, quickFilter)) {
        continue;
      }

      if (normalizedQuery.isEmpty ||
          _buildSearchText(consignor).contains(normalizedQuery)) {
        visibleItems.add(consignor);
      }
    }

    return _ConsignorListSummary(
      visibleItems: visibleItems,
      totalCount: consignors.length,
      syncedCount: syncedCount,
      pendingCount: pendingCount,
      draftCount: draftCount,
      failedCount: failedCount,
    );
  }

  static bool _matchesQuickFilter(
    Consignor consignor,
    _ConsignorQuickFilter quickFilter,
  ) {
    switch (quickFilter) {
      case _ConsignorQuickFilter.all:
        return true;
      case _ConsignorQuickFilter.draft:
        return consignor.syncStatus == RecordSyncStatus.draft;
      case _ConsignorQuickFilter.pendingSync:
        return consignor.syncStatus == RecordSyncStatus.pendingSync;
      case _ConsignorQuickFilter.synced:
        return consignor.syncStatus == RecordSyncStatus.synced;
      case _ConsignorQuickFilter.failed:
        return consignor.syncStatus == RecordSyncStatus.syncFailed;
    }
  }

  static String _buildSearchText(Consignor consignor) {
    final address = consignor.consignorAddress.toSingleLine();

    return [
      consignor.displayName,
      consignor.emailAddress,
      consignor.fullPhoneNumber,
      address,
      consignor.syncErrorMessage ?? '',
      _statusSearchTerms(consignor.syncStatus),
    ].join(' ').toLowerCase();
  }

  static String _statusSearchTerms(RecordSyncStatus status) {
    switch (status) {
      case RecordSyncStatus.draft:
        return 'draft local draft unsynced not synced';
      case RecordSyncStatus.pendingSync:
        return 'pending sync pending unsynced not synced';
      case RecordSyncStatus.synced:
        return 'synced synced profile';
      case RecordSyncStatus.syncFailed:
        return 'sync failed failed error';
    }
  }
}

class _ConsignorRow extends StatelessWidget {
  const _ConsignorRow({
    required this.item,
    required this.isSyncing,
    required this.onSendEmail,
    required this.onCallNumber,
    required this.onOpenAddress,
    this.onSync,
    this.localAction,
    this.onDeleteDraft,
    this.onViewError,
  });

  final Consignor item;
  final bool isSyncing;
  final Future<void> Function()? onSync;
  final _LocalDraftAction? localAction;
  final Future<void> Function()? onDeleteDraft;
  final VoidCallback? onViewError;
  final Future<void> Function(String email) onSendEmail;
  final Future<void> Function(String phone) onCallNumber;
  final Future<void> Function(String address) onOpenAddress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final displayName = item.displayName.trim();
    final email = item.emailAddress.trim();
    final phone = item.fullPhoneNumber.trim();
    final address = item.consignorAddress.toSingleLine().trim();
    final initials = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : '#';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [palette.brand, palette.brandAccent],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => context.go('/consignors/${item.id}'),
                          child: Text(
                            displayName.isEmpty
                                ? 'Unnamed consignor'
                                : displayName,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: palette.brand,
                                  decoration: TextDecoration.underline,
                                  decorationColor: palette.brand,
                                ),
                          ),
                        ),
                      ),
                      StatusBadge(
                        label: _statusLabel(item.syncStatus),
                        tone: _statusTone(item.syncStatus),
                        icon: _statusIcon(item.syncStatus),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _MetaText(
                        icon: Icons.alternate_email_rounded,
                        text: email.isEmpty ? 'No email' : email,
                        onTap: email.isEmpty ? null : () => onSendEmail(email),
                      ),
                      _MetaText(
                        icon: Icons.phone_outlined,
                        text: phone.isEmpty ? 'No phone' : phone,
                        onTap: phone.isEmpty ? null : () => onCallNumber(phone),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _MetaText(
                    icon: Icons.location_on_outlined,
                    text: address.isEmpty ? 'No address stored' : address,
                    onTap:
                        address.isEmpty ? null : () => onOpenAddress(address),
                  ),
                  if (item.syncStatus == RecordSyncStatus.syncFailed &&
                      (item.syncErrorMessage?.trim().isNotEmpty ?? false)) ...[
                    const SizedBox(height: 10),
                    Text(
                      item.syncErrorMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.palette.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (onSync != null)
                  OutlinedButton.icon(
                    onPressed: isSyncing ? null : () => onSync!(),
                    icon: isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            item.syncStatus == RecordSyncStatus.syncFailed
                                ? Icons.refresh_rounded
                                : Icons.cloud_upload_outlined,
                          ),
                    label: Text(
                      isSyncing
                          ? 'Syncing…'
                          : item.syncStatus == RecordSyncStatus.syncFailed
                              ? 'Retry sync'
                              : 'Sync',
                    ),
                  ),
                if (onViewError != null)
                  OutlinedButton.icon(
                    onPressed: onViewError,
                    icon: const Icon(Icons.error_outline_rounded),
                    label: const Text('View error'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.palette.error,
                    ),
                  ),
                IconButton(
                  tooltip: 'Edit consignor',
                  onPressed: () => context.go(
                    item.syncStatus == RecordSyncStatus.draft
                        ? '/consignors/${item.id}/resume'
                        : '/consignors/${item.id}',
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Go to contracts',
                  onPressed: () => context.go('/contracts/${item.id}'),
                  icon: const Icon(Icons.description_outlined),
                ),
                if (localAction == _LocalDraftAction.deleteDraft)
                  IconButton(
                    tooltip: 'Delete draft',
                    onPressed: () => onDeleteDraft?.call(),
                    color: context.palette.error,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(RecordSyncStatus status) {
    switch (status) {
      case RecordSyncStatus.draft:
        return 'Local draft';
      case RecordSyncStatus.pendingSync:
        return 'Pending sync';
      case RecordSyncStatus.synced:
        return 'Synced';
      case RecordSyncStatus.syncFailed:
        return 'Sync failed';
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
}

class _QuickFilterChip extends StatelessWidget {
  const _QuickFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        color: selected ? Colors.white : context.palette.brand,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: context.palette.brand,
      backgroundColor: context.palette.brandSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: context.palette.border),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clickable = onTap != null;

    final child = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: EdgeInsets.symmetric(
        horizontal: clickable ? 10 : 0,
        vertical: clickable ? 7 : 0,
      ),
      decoration: clickable
          ? BoxDecoration(
              color: palette.brandSoft.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: clickable ? palette.brand : palette.textMuted,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: clickable ? palette.brand : palette.text,
                    fontWeight: clickable ? FontWeight.w600 : FontWeight.w400,
                    decoration: clickable
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: clickable ? palette.brand : null,
                  ),
            ),
          ),
        ],
      ),
    );

    if (!clickable) {
      return child;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: child,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.brandSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.palette.brand,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
