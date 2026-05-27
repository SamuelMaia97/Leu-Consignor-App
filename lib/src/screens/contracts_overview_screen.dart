import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/contract_record.dart';
import '../models/sync_status.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/page_header.dart';
import '../widgets/searchable_select_field.dart';
import '../widgets/section_card.dart';
import '../widgets/status_badge.dart';

class ContractsOverviewScreen extends StatefulWidget {
  const ContractsOverviewScreen({super.key, required this.consignorId});

  final String consignorId;

  @override
  State<ContractsOverviewScreen> createState() =>
      _ContractsOverviewScreenState();
}

class _ContractsOverviewScreenState extends State<ContractsOverviewScreen> {
  late final TextEditingController _searchController;

  String _query = '';
  int? _selectedAuctionId;
  _ContractQuickFilter _quickFilter = _ContractQuickFilter.all;
  String? _lastRouteFilter;

  String get _baseRoute => '/contracts/${widget.consignorId}';

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

  void _clearAllFilters() {
    _clearQuery();
    setState(() {
      _selectedAuctionId = null;
      _quickFilter = _ContractQuickFilter.all;
    });
    context.go(_baseRoute);
  }

  void _setQuickFilter(_ContractQuickFilter filter) {
    setState(() {
      _quickFilter = filter;
    });

    final value = _filterToQuery(filter);
    if (value == null) {
      context.go(_baseRoute);
      return;
    }

    context.go('$_baseRoute?filter=$value');
  }

  Future<void> _syncContract(ContractRecord contract) async {
    final auctionId = contract.auctionId;
    if (auctionId == null) return;

    final updated = await context
        .read<AppState>()
        .syncContract(contract.consignorId, auctionId);

    if (!mounted) return;

    final message =
        updated != null && updated.syncStatus == RecordSyncStatus.synced
            ? 'Contract synced successfully.'
            : (updated?.syncErrorMessage ??
                context.read<AppState>().lastMessage ??
                'Contract sync finished.');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openContract(ContractRecord contract) {
    if (contract.syncStatus == RecordSyncStatus.draft) {
      context.go(
        '/contracts/${contract.consignorId}/record/${contract.id}/resume',
      );
      return;
    }

    final auctionId = contract.auctionId;
    if (auctionId == null) {
      context.go('/contracts/${contract.consignorId}/record/${contract.id}');
      return;
    }

    context.go('/contracts/${contract.consignorId}/$auctionId');
  }

  _AuctionFilterOption? _selectedAuctionOption(
    List<_AuctionFilterOption> options,
  ) {
    if (_selectedAuctionId == null) return null;

    for (final option in options) {
      if (option.auctionId == _selectedAuctionId) {
        return option;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Contracts overview',
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final consignor = state.consignorById(widget.consignorId);

          if (consignor == null) {
            return AppEmptyState(
              title: 'Consignor not found',
              message:
                  'Return to the consignor list and choose a valid record.',
              icon: Icons.description_outlined,
              action: OutlinedButton.icon(
                onPressed: () => context.go('/consignors'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to consignors'),
              ),
            );
          }

          final consignorContracts = state.contractsForConsignor(
            widget.consignorId,
          );
          final auctionOptions =
              _buildAuctionOptions(consignorContracts, state);

          final summary = _ContractsOverviewSummary.from(
            contracts: consignorContracts,
            query: _query,
            quickFilter: _quickFilter,
            selectedAuctionId: _selectedAuctionId,
          );

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: PageHeader(
                  eyebrow: 'CONTRACT OVERVIEW',
                  title:
                      'Contracts for ${consignor.displayName.isEmpty ? 'consignor' : consignor.displayName}',
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
                          'Contract status',
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
                                  _setQuickFilter(_ContractQuickFilter.synced),
                            ),
                            StatusBadge(
                              label: '${summary.pendingCount} pending sync',
                              tone: StatusBadgeTone.info,
                              icon: Icons.cloud_upload_outlined,
                              onTap: () => _setQuickFilter(
                                _ContractQuickFilter.pendingSync,
                              ),
                            ),
                            StatusBadge(
                              label:
                                  '${summary.draftCount} draft${summary.draftCount == 1 ? '' : 's'}',
                              tone: StatusBadgeTone.warning,
                              icon: Icons.edit_note_outlined,
                              onTap: () =>
                                  _setQuickFilter(_ContractQuickFilter.draft),
                            ),
                            StatusBadge(
                              label: '${summary.failedCount} failed',
                              tone: StatusBadgeTone.warning,
                              icon: Icons.error_outline_rounded,
                              onTap: () =>
                                  _setQuickFilter(_ContractQuickFilter.failed),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    ElevatedButton.icon(
                      onPressed: () =>
                          context.go('/contracts/${widget.consignorId}/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('New contract'),
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: SectionCard(
                  title: 'Search and manage',
                  subtitle:
                      'Search by auction, contract ID, or file name, then use the quick status filters below.',
                  icon: Icons.manage_search_outlined,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stack = constraints.maxWidth < 900;
                      final fieldWidth = stack
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 16) / 2;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.search_rounded),
                                    labelText: 'Search contracts',
                                    hintText:
                                        'Try an auction, contract ID, or file name',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: summary.hasActiveFilters
                                    ? _clearAllFilters
                                    : null,
                                icon: const Icon(Icons.clear_rounded),
                                label: const Text('Clear'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              SizedBox(
                                width: fieldWidth,
                                child: SearchableSelectFormField<
                                    _AuctionFilterOption>(
                                  key: ValueKey<int?>(_selectedAuctionId),
                                  label: 'Auction',
                                  items: auctionOptions,
                                  itemLabel: (item) => item.displayName,
                                  initialValue:
                                      _selectedAuctionOption(auctionOptions),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedAuctionId = value?.auctionId;
                                    });
                                  },
                                  hintText: 'Search auction',
                                  leading: const Icon(Icons.gavel_outlined),
                                ),
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
                                selected:
                                    _quickFilter == _ContractQuickFilter.all,
                                onSelected: () =>
                                    _setQuickFilter(_ContractQuickFilter.all),
                              ),
                              _QuickFilterChip(
                                label: 'Draft',
                                selected:
                                    _quickFilter == _ContractQuickFilter.draft,
                                onSelected: () =>
                                    _setQuickFilter(_ContractQuickFilter.draft),
                              ),
                              _QuickFilterChip(
                                label: 'Pending sync',
                                selected: _quickFilter ==
                                    _ContractQuickFilter.pendingSync,
                                onSelected: () => _setQuickFilter(
                                  _ContractQuickFilter.pendingSync,
                                ),
                              ),
                              _QuickFilterChip(
                                label: 'Synced',
                                selected:
                                    _quickFilter == _ContractQuickFilter.synced,
                                onSelected: () => _setQuickFilter(
                                    _ContractQuickFilter.synced),
                              ),
                              _QuickFilterChip(
                                label: 'Failed',
                                selected:
                                    _quickFilter == _ContractQuickFilter.failed,
                                onSelected: () => _setQuickFilter(
                                    _ContractQuickFilter.failed),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              _InfoPill(label: '${summary.totalCount} total'),
                              const SizedBox(width: 10),
                              _InfoPill(
                                label: '${summary.visibleCount} visible',
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              if (summary.visibleItems.isEmpty)
                SliverToBoxAdapter(
                  child: AppEmptyState(
                    title: summary.totalCount == 0
                        ? 'No contracts yet'
                        : 'No results match the current filters',
                    message: summary.totalCount == 0
                        ? 'Create a contract for this consignor to start managing uploads and sync state.'
                        : 'Try a different search term or switch the current status filter.',
                    icon: Icons.description_outlined,
                    action: summary.totalCount == 0
                        ? ElevatedButton.icon(
                            onPressed: () => context.go(
                              '/contracts/${widget.consignorId}/new',
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Create contract'),
                          )
                        : OutlinedButton.icon(
                            onPressed: _clearAllFilters,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset filters'),
                          ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final contract = summary.visibleItems[index];
                    final isSyncing = contract.auctionId != null &&
                        state.isSyncingContract(
                          contract.consignorId,
                          contract.auctionId!,
                        );

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom:
                            index == summary.visibleItems.length - 1 ? 0 : 12,
                      ),
                      child: _ContractOverviewRow(
                        contract: contract,
                        isSyncing: isSyncing,
                        onOpen: () => _openContract(contract),
                        onOpenWizard: () => context.go(
                          '/contracts/${contract.consignorId}/record/${contract.id}/resume',
                        ),
                        onSync: contract.auctionId == null
                            ? null
                            : () => _syncContract(contract),
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

  static List<_AuctionFilterOption> _buildAuctionOptions(
    List<ContractRecord> contracts,
    AppState state,
  ) {
    final byId = <int, _AuctionFilterOption>{};

    for (final contract in contracts) {
      final auctionId = contract.auctionId;
      if (auctionId == null) continue;

      final matchingAuction = state.auctions.where(
        (auction) => auction.auctionId == auctionId,
      );

      final displayName = matchingAuction.isNotEmpty
          ? matchingAuction.first.displayName
          : (contract.auctionDisplayName.isEmpty
              ? 'Auction $auctionId'
              : contract.auctionDisplayName);

      byId[auctionId] = _AuctionFilterOption(
        auctionId: auctionId,
        displayName: displayName,
      );
    }

    final values = byId.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return values;
  }

  static _ContractQuickFilter _filterFromQuery(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'draft':
        return _ContractQuickFilter.draft;
      case 'pending':
      case 'pending-sync':
        return _ContractQuickFilter.pendingSync;
      case 'synced':
        return _ContractQuickFilter.synced;
      case 'failed':
      case 'sync-failed':
        return _ContractQuickFilter.failed;
      default:
        return _ContractQuickFilter.all;
    }
  }

  static String? _filterToQuery(_ContractQuickFilter filter) {
    switch (filter) {
      case _ContractQuickFilter.all:
        return null;
      case _ContractQuickFilter.draft:
        return 'draft';
      case _ContractQuickFilter.pendingSync:
        return 'pending';
      case _ContractQuickFilter.synced:
        return 'synced';
      case _ContractQuickFilter.failed:
        return 'failed';
    }
  }
}

enum _ContractQuickFilter {
  all,
  draft,
  pendingSync,
  synced,
  failed,
}

class _AuctionFilterOption {
  const _AuctionFilterOption({
    required this.auctionId,
    required this.displayName,
  });

  final int auctionId;
  final String displayName;
}

class _ContractsOverviewSummary {
  const _ContractsOverviewSummary({
    required this.visibleItems,
    required this.totalCount,
    required this.syncedCount,
    required this.pendingCount,
    required this.draftCount,
    required this.failedCount,
    required this.hasActiveFilters,
  });

  final List<ContractRecord> visibleItems;
  final int totalCount;
  final int syncedCount;
  final int pendingCount;
  final int draftCount;
  final int failedCount;
  final bool hasActiveFilters;

  int get visibleCount => visibleItems.length;

  factory _ContractsOverviewSummary.from({
    required List<ContractRecord> contracts,
    required String query,
    required _ContractQuickFilter quickFilter,
    required int? selectedAuctionId,
  }) {
    final normalizedQuery = query.trim().toLowerCase();

    final all = contracts.where((contract) {
      if (selectedAuctionId != null &&
          contract.auctionId != selectedAuctionId) {
        return false;
      }
      return true;
    }).toList()
      ..sort(
        (left, right) => right.lastModifiedUtc.compareTo(left.lastModifiedUtc),
      );

    var syncedCount = 0;
    var pendingCount = 0;
    var draftCount = 0;
    var failedCount = 0;

    final visibleItems = <ContractRecord>[];

    for (final contract in all) {
      final status = _effectiveStatus(contract);

      switch (status) {
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

      if (!_matchesQuickFilter(contract, quickFilter)) {
        continue;
      }

      if (normalizedQuery.isEmpty ||
          _buildSearchText(contract).contains(normalizedQuery)) {
        visibleItems.add(contract);
      }
    }

    return _ContractsOverviewSummary(
      visibleItems: visibleItems,
      totalCount: all.length,
      syncedCount: syncedCount,
      pendingCount: pendingCount,
      draftCount: draftCount,
      failedCount: failedCount,
      hasActiveFilters: normalizedQuery.isNotEmpty ||
          selectedAuctionId != null ||
          quickFilter != _ContractQuickFilter.all,
    );
  }

  static bool _matchesQuickFilter(
    ContractRecord contract,
    _ContractQuickFilter quickFilter,
  ) {
    final status = _effectiveStatus(contract);

    switch (quickFilter) {
      case _ContractQuickFilter.all:
        return true;
      case _ContractQuickFilter.draft:
        return status == RecordSyncStatus.draft;
      case _ContractQuickFilter.pendingSync:
        return status == RecordSyncStatus.pendingSync;
      case _ContractQuickFilter.synced:
        return status == RecordSyncStatus.synced;
      case _ContractQuickFilter.failed:
        return status == RecordSyncStatus.syncFailed;
    }
  }

  static RecordSyncStatus _effectiveStatus(ContractRecord contract) {
    if (contract.syncStatus == RecordSyncStatus.syncFailed) {
      return RecordSyncStatus.syncFailed;
    }

    if (contract.syncStatus == RecordSyncStatus.draft ||
        contract.auctionId == null) {
      return RecordSyncStatus.draft;
    }

    if (contract.hasLocalChanges ||
        contract.syncStatus == RecordSyncStatus.pendingSync) {
      return RecordSyncStatus.pendingSync;
    }

    return RecordSyncStatus.synced;
  }

  static String _buildSearchText(ContractRecord contract) {
    final fileNames = contract.uploads
        .where((upload) => !upload.isDeleted)
        .map((upload) => upload.fileName)
        .join(' ');

    return [
      contract.id,
      contract.auctionDisplayName,
      contract.auctionId?.toString() ?? '',
      fileNames,
      contract.syncErrorMessage ?? '',
      _statusSearchTerms(_effectiveStatus(contract)),
    ].join(' ').toLowerCase();
  }

  static String _statusSearchTerms(RecordSyncStatus status) {
    switch (status) {
      case RecordSyncStatus.draft:
        return 'draft local draft unsynced not synced';
      case RecordSyncStatus.pendingSync:
        return 'pending sync pending unsynced not synced';
      case RecordSyncStatus.synced:
        return 'synced';
      case RecordSyncStatus.syncFailed:
        return 'sync failed failed error';
    }
  }
}

class _ContractOverviewRow extends StatelessWidget {
  const _ContractOverviewRow({
    required this.contract,
    required this.isSyncing,
    required this.onOpen,
    required this.onOpenWizard,
    this.onSync,
  });

  final ContractRecord contract;
  final bool isSyncing;
  final VoidCallback onOpen;
  final VoidCallback onOpenWizard;
  final Future<void> Function()? onSync;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fileCount = contract.uploads.where((item) => !item.isDeleted).length;
    final displayName = contract.auctionDisplayName.isEmpty
        ? (contract.auctionId == null
            ? 'Draft contract'
            : 'Auction ${contract.auctionId}')
        : contract.auctionDisplayName;
    final modifiedText = DateFormat(
      'yyyy-MM-dd HH:mm',
    ).format(contract.lastModifiedUtc.toLocal());
    final status = _ContractsOverviewSummary._effectiveStatus(contract);

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
                color: palette.brandSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.gavel_outlined, color: palette.brand),
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
                          onTap: onOpenWizard,
                          child: Text(
                            displayName,
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
                        label: _statusLabel(status),
                        tone: _statusTone(status),
                        icon: _statusIcon(status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$fileCount file${fileCount == 1 ? '' : 's'} • $modifiedText',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (status == RecordSyncStatus.syncFailed &&
                      (contract.syncErrorMessage?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 10),
                    Text(
                      contract.syncErrorMessage!,
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
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(isSyncing ? 'Syncing…' : 'Sync'),
                  ),
                IconButton(
                  tooltip: 'Open contract',
                  onPressed: onOpen,
                  icon: const Icon(Icons.edit_outlined),
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
        return 'Draft';
      case RecordSyncStatus.pendingSync:
        return 'Pending sync';
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
        return Icons.sync_alt;
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
