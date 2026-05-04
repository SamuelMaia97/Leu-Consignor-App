import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/consignor.dart';
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

class ContractListScreen extends StatefulWidget {
  const ContractListScreen({super.key});

  @override
  State<ContractListScreen> createState() => _ContractListScreenState();
}

class _ContractListScreenState extends State<ContractListScreen> {
  late final TextEditingController _searchController;

  String _query = '';
  String? _selectedConsignorId;
  int? _selectedAuctionId;
  _ContractQuickFilter _quickFilter = _ContractQuickFilter.all;
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

  void _clearAllFilters() {
    _clearQuery();
    setState(() {
      _selectedConsignorId = null;
      _selectedAuctionId = null;
      _quickFilter = _ContractQuickFilter.all;
    });
    context.go('/contracts');
  }

  void _setQuickFilter(_ContractQuickFilter filter) {
    setState(() {
      _quickFilter = filter;
    });

    final value = _filterToQuery(filter);
    if (value == null) {
      context.go('/contracts');
      return;
    }

    context.go('/contracts?filter=$value');
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

  _ConsignorFilterOption? _selectedConsignorOption(
    List<_ConsignorFilterOption> options,
  ) {
    if (_selectedConsignorId == null) return null;

    for (final option in options) {
      if (option.consignorId == _selectedConsignorId) {
        return option;
      }
    }

    return null;
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

  Future<void> _deleteLocalDraft(ContractRecord contract) async {
    final confirmed = await _confirmDeleteLocalContractDraft(contract);
    if (!confirmed || !mounted) return;

    final deleted = await context.read<AppState>().deleteLocalContractDraft(
          contract.id,
        );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Local contract draft deleted.'
              : 'This contract is not a local-only draft.',
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteLocalContractDraft(ContractRecord contract) async {
    final displayName = contract.auctionDisplayName.trim().isEmpty
        ? (contract.auctionId == null
            ? 'Draft contract'
            : 'Auction ${contract.auctionId}')
        : contract.auctionDisplayName.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete draft?'),
        content: Text(
          'This will permanently delete the local contract draft "$displayName" from this device. '
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

  void _showSyncError(ContractRecord contract) {
    final displayName = contract.auctionDisplayName.trim().isEmpty
        ? (contract.auctionId == null
            ? 'Draft contract'
            : 'Auction ${contract.auctionId}')
        : contract.auctionDisplayName.trim();
    final message = contract.syncErrorMessage?.trim();
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

  static _LocalDraftAction? _localDraftActionFor(ContractRecord contract) {
    final status = _ContractListSummary._effectiveStatus(contract);
    if (!_contractHasRemoteReference(contract) &&
        (status == RecordSyncStatus.draft ||
            status == RecordSyncStatus.syncFailed)) {
      return _LocalDraftAction.deleteDraft;
    }

    return null;
  }

  static bool _contractHasRemoteReference(ContractRecord contract) {
    return contract.systemReferenceContract > 0 || contract.hasRemoteReference;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Contract list',
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final consignorOptions = _buildConsignorOptions(state);
          final auctionOptions = _buildAuctionOptions(state);

          final summary = _ContractListSummary.from(
            contracts: state.contracts,
            consignorsById: {
              for (final consignor in state.consignors)
                consignor.id: consignor,
            },
            query: _query,
            quickFilter: _quickFilter,
            selectedConsignorId: _selectedConsignorId,
            selectedAuctionId: _selectedAuctionId,
          );


          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: PageHeader(
                  eyebrow: 'ALL CONTRACTS',
                  title: 'Contract list',
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
                      onPressed: () => context.go('/contracts/new'),
                      icon: const Icon(Icons.post_add_outlined),
                      label: const Text('Create contract'),
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: SectionCard(
                  title: 'Search and manage',
                  subtitle:
                      'Search by consignor, auction, contract ID, or file name, then use the status filters below.',
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
                          TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded),
                              labelText: 'Search contracts',
                              hintText:
                                  'Try a consignor, auction, contract ID, or file name',
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              SizedBox(
                                width: fieldWidth,
                                child: SearchableSelectFormField<
                                    _ConsignorFilterOption>(
                                  key: ValueKey<String?>(
                                    'consignor-filter-${_selectedConsignorId ?? 'all'}',
                                  ),
                                  label: 'Consignor',
                                  items: consignorOptions,
                                  itemLabel: (item) => item.displayName,
                                  initialValue:
                                      _selectedConsignorOption(consignorOptions),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedConsignorId = value?.consignorId;
                                    });
                                  },
                                  hintText: 'Search consignor',
                                  leading: const Icon(Icons.person_outline),
                                ),
                              ),
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
                                onSelected: () =>
                                    _setQuickFilter(_ContractQuickFilter.synced),
                              ),
                              _QuickFilterChip(
                                label: 'Failed',
                                selected:
                                    _quickFilter == _ContractQuickFilter.failed,
                                onSelected: () =>
                                    _setQuickFilter(_ContractQuickFilter.failed),
                              ),
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
                        ? 'No contracts available'
                        : 'No results match the current filters',
                    message: summary.totalCount == 0
                        ? 'Create a contract and upload files to start tracking sync state here.'
                        : 'Try a different search term or switch the current status filter.',
                    icon: Icons.description_outlined,
                    action: summary.hasActiveFilters
                        ? OutlinedButton.icon(
                            onPressed: _clearAllFilters,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset filters'),
                          )
                        : null,
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final contract = summary.visibleItems[index];
                    final isSyncing =
                        contract.auctionId != null &&
                        state.isSyncingContract(
                          contract.consignorId,
                          contract.auctionId!,
                        );
                    final consignor = state.consignorById(contract.consignorId);

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom:
                            index == summary.visibleItems.length - 1 ? 0 : 12,
                      ),
                      child: _ContractListRow(
                        contract: contract,
                        consignor: consignor,
                        isSyncing: isSyncing,
                        onOpen: () => _openContract(contract),
                        onSync: contract.auctionId != null &&
                                _ContractListSummary._effectiveStatus(contract) !=
                                    RecordSyncStatus.synced
                            ? () => _syncContract(contract)
                            : null,
                        localAction: _localDraftActionFor(contract),
                        onDeleteDraft: () => _deleteLocalDraft(contract),
                        onViewError: _ContractListSummary._effectiveStatus(contract) ==
                                    RecordSyncStatus.syncFailed &&
                                (contract.syncErrorMessage?.trim().isNotEmpty ??
                                    false)
                            ? () => _showSyncError(contract)
                            : null,
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

  static List<_ConsignorFilterOption> _buildConsignorOptions(AppState state) {
    final values = state.consignors
        .map(
          (consignor) => _ConsignorFilterOption(
            consignorId: consignor.id,
            displayName: consignor.displayName.isEmpty
                ? 'Unnamed consignor'
                : consignor.displayName,
          ),
        )
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return values;
  }

  static List<_AuctionFilterOption> _buildAuctionOptions(AppState state) {
    final byId = <int, _AuctionFilterOption>{};

    for (final auction in state.auctions) {
      byId[auction.auctionId] = _AuctionFilterOption(
        auctionId: auction.auctionId,
        displayName: auction.displayName,
      );
    }

    for (final contract in state.contracts) {
      final auctionId = contract.auctionId;
      if (auctionId == null) continue;

      byId.putIfAbsent(
        auctionId,
        () => _AuctionFilterOption(
          auctionId: auctionId,
          displayName: contract.auctionDisplayName.isEmpty
              ? 'Auction $auctionId'
              : contract.auctionDisplayName,
        ),
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

enum _LocalDraftAction {
  deleteDraft,
}

class _ConsignorFilterOption {
  const _ConsignorFilterOption({
    required this.consignorId,
    required this.displayName,
  });

  final String? consignorId;
  final String displayName;
}

class _AuctionFilterOption {
  const _AuctionFilterOption({
    required this.auctionId,
    required this.displayName,
  });

  final int? auctionId;
  final String displayName;
}

class _ContractListSummary {
  const _ContractListSummary({
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

  factory _ContractListSummary.from({
    required List<ContractRecord> contracts,
    required Map<String, Consignor> consignorsById,
    required String query,
    required _ContractQuickFilter quickFilter,
    required String? selectedConsignorId,
    required int? selectedAuctionId,
  }) {
    final normalizedQuery = query.trim().toLowerCase();

    final scopedContracts = contracts.where((contract) {
      if (selectedConsignorId != null &&
          contract.consignorId != selectedConsignorId) {
        return false;
      }
      if (selectedAuctionId != null && contract.auctionId != selectedAuctionId) {
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

    for (final contract in scopedContracts) {
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

      final consignor = consignorsById[contract.consignorId];
      if (normalizedQuery.isEmpty ||
          _buildSearchText(contract, consignor).contains(normalizedQuery)) {
        visibleItems.add(contract);
      }
    }

    return _ContractListSummary(
      visibleItems: visibleItems,
      totalCount: scopedContracts.length,
      syncedCount: syncedCount,
      pendingCount: pendingCount,
      draftCount: draftCount,
      failedCount: failedCount,
      hasActiveFilters: normalizedQuery.isNotEmpty ||
          selectedConsignorId != null ||
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

  static String _buildSearchText(ContractRecord contract, Consignor? consignor) {
    final fileNames = contract.uploads
        .where((upload) => !upload.isDeleted)
        .map((upload) => upload.fileName)
        .join(' ');

    return [
      contract.id,
      contract.auctionDisplayName,
      contract.auctionId?.toString() ?? '',
      consignor?.displayName ?? '',
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

class _ContractListRow extends StatelessWidget {
  const _ContractListRow({
    required this.contract,
    required this.consignor,
    required this.isSyncing,
    required this.onOpen,
    this.onSync,
    this.localAction,
    this.onDeleteDraft,
    this.onViewError,
  });

  final ContractRecord contract;
  final Consignor? consignor;
  final bool isSyncing;
  final VoidCallback onOpen;
  final Future<void> Function()? onSync;
  final _LocalDraftAction? localAction;
  final Future<void> Function()? onDeleteDraft;
  final VoidCallback? onViewError;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fileCount = contract.uploads.where((item) => !item.isDeleted).length;
    final displayName = contract.auctionDisplayName.isEmpty
        ? (contract.auctionId == null
            ? 'Draft contract'
            : 'Auction ${contract.auctionId}')
        : contract.auctionDisplayName;
    final consignorName = consignor == null || consignor!.displayName.isEmpty
        ? 'Unknown consignor'
        : consignor!.displayName;
    final modifiedText = DateFormat(
      'yyyy-MM-dd HH:mm',
    ).format(contract.lastModifiedUtc.toLocal());
    final status = _ContractListSummary._effectiveStatus(contract);

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
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleLarge,
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
                    '$consignorName • $fileCount file${fileCount == 1 ? '' : 's'} • $modifiedText',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (status == RecordSyncStatus.syncFailed &&
                      (contract.syncErrorMessage?.trim().isNotEmpty ?? false)) ...[
                    const SizedBox(height: 10),
                    Text(
                      contract.syncErrorMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.palette.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Open'),
                      ),
                      if (onSync != null)
                        ElevatedButton.icon(
                          onPressed: isSyncing ? null : () => onSync!(),
                          icon: isSyncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  status == RecordSyncStatus.syncFailed
                                      ? Icons.refresh_rounded
                                      : Icons.cloud_upload_outlined,
                                ),
                          label: Text(
                            isSyncing
                                ? 'Syncing…'
                                : status == RecordSyncStatus.syncFailed
                                    ? 'Retry sync'
                                    : 'Sync contract',
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
                      if (localAction == _LocalDraftAction.deleteDraft)
                        OutlinedButton.icon(
                          onPressed: () => onDeleteDraft?.call(),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Delete draft'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.palette.error,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
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