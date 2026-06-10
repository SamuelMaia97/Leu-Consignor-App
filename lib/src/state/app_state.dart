import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/abacus_sync.dart';
import '../models/auction_option.dart';
import '../models/consignor.dart';
import '../models/contract_record.dart';
import '../models/country.dart';
import '../models/phone_prefix.dart';
import '../models/sync_status.dart';
import '../repositories/consignor_repository.dart';
import '../repositories/contract_repository.dart';
import '../repositories/country_repository.dart';
import '../repositories/phone_prefix_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/wizard_draft_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class AppState extends ChangeNotifier {
  final _consignorRepo = ConsignorRepository();
  final _contractRepo = ContractRepository();
  final _countryRepo = CountryRepository();
  final _phonePrefixRepo = PhonePrefixRepository();
  final _settingsRepo = SettingsRepository();
  final _wizardDraftRepo = WizardDraftRepository();

  final Set<String> _syncingConsignorIds = <String>{};
  final Set<String> _syncingContractKeys = <String>{};

  Object? _leaveGuardToken;
  Future<bool> Function()? _leaveGuard;
  Timer? _authMonitor;

  List<Country> countries = const [];
  List<PhonePrefix> phonePrefixes = const [];
  List<Consignor> consignors = const [];
  List<ContractRecord> contracts = const [];
  List<AuctionOption> auctions = const [];
  AppSettings settings = const AppSettings();
  String token = '';
  DateTime? tokenExpiresAtUtc;
  bool loading = true;
  bool signingIn = false;
  bool syncingAllDrafts = false;
  bool syncingNow = false;
  int syncProgressCurrent = 0;
  int syncProgressTotal = 0;
  String syncProgressMessage = '';
  String? lastMessage;
  String? activeUsername;

  bool get isAdminUser => activeUsername == 'admin';

  double? get syncProgressValue {
    if (syncProgressTotal <= 0) {
      return null;
    }

    final value = syncProgressCurrent / syncProgressTotal;
    return value.clamp(0.0, 1.0);
  }

  void setActiveUsername(String username) {
    activeUsername = username.trim().toLowerCase();
    notifyListeners();
  }

  void logoutLocalUser() {
    activeUsername = null;
    _leaveGuardToken = null;
    _leaveGuard = null;
    lastMessage = null;
    notifyListeners();
  }

  bool get hasStoredToken => token.trim().isNotEmpty;
  bool get hasValidToken => AuthService.hasUsableAccessToken(token);
  bool get tokenExpiringSoon =>
      hasValidToken && AuthService.isTokenExpiringSoon(token);
  DateTime? get tokenExpiresAtLocal => tokenExpiresAtUtc?.toLocal();

  bool isSyncingConsignor(String id) => _syncingConsignorIds.contains(id);

  bool isSyncingContract(String consignorId, int auctionId) =>
      _syncingContractKeys.contains(_contractKey(consignorId, auctionId));

  void registerLeaveGuard({
    required Object token,
    required Future<bool> Function() handler,
  }) {
    _leaveGuardToken = token;
    _leaveGuard = handler;
  }

  void unregisterLeaveGuard(Object token) {
    if (!identical(_leaveGuardToken, token)) return;
    _leaveGuardToken = null;
    _leaveGuard = null;
  }

  Future<bool> canLeaveCurrentRoute({bool consume = false}) async {
    final handler = _leaveGuard;
    final tokenMarker = _leaveGuardToken;

    if (handler == null) return true;

    final canLeave = await handler();

    if (canLeave && consume && identical(_leaveGuardToken, tokenMarker)) {
      _leaveGuardToken = null;
      _leaveGuard = null;
    }

    return canLeave;
  }

  Future<void> bootstrap() async {
    loading = true;
    notifyListeners();

    countries = await _countryRepo.loadCountries();
    phonePrefixes = await _phonePrefixRepo.loadBundledPrefixes();
    settings = _settingsRepo.loadSettings();
    token = await _settingsRepo.loadToken();
    await refreshAuthSessionState(notify: false);
    _startAuthMonitor();
    await _refreshLocalCollections();
    await refreshPhonePrefixes(silent: true);

    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authMonitor?.cancel();
    super.dispose();
  }

  void _startAuthMonitor() {
    _authMonitor?.cancel();
    _authMonitor = Timer.periodic(const Duration(minutes: 1), (_) {
      refreshAuthSessionState();
    });
  }

  Future<void> refreshAuthSessionState({bool notify = true}) async {
    final previousToken = token;
    final previousExpiry = tokenExpiresAtUtc;
    final previousMessage = lastMessage;

    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      token = '';
      tokenExpiresAtUtc = null;

      final changed = previousToken != token ||
          previousExpiry != tokenExpiresAtUtc ||
          previousMessage != lastMessage;

      if (notify && changed) {
        notifyListeners();
      }
      return;
    }

    final nextExpiry = AuthService.getAccessTokenExpiryUtc(trimmedToken);
    final expired = AuthService.isTokenExpired(trimmedToken);

    if (expired) {
      token = '';
      tokenExpiresAtUtc = null;
      lastMessage = 'Microsoft login expired. Sign in again.';
      await _settingsRepo.saveToken('');
    } else {
      token = trimmedToken;
      tokenExpiresAtUtc = nextExpiry;
    }

    final changed = previousToken != token ||
        previousExpiry != tokenExpiresAtUtc ||
        previousMessage != lastMessage;

    if (notify && changed) {
      notifyListeners();
    }
  }

  Future<bool> _ensureActiveMicrosoftSession() async {
    await refreshAuthSessionState(notify: false);

    if (!hasStoredToken) {
      lastMessage = 'Microsoft login required. Sign in again to continue.';
      notifyListeners();
      return false;
    }

    if (!hasValidToken) {
      lastMessage = 'Microsoft login expired. Sign in again to continue.';
      notifyListeners();
      return false;
    }

    return true;
  }

  Consignor? consignorById(String id) {
    try {
      return consignors.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  List<ContractRecord> contractsForConsignor(String consignorId) =>
      _contractRepo.getByConsignorId(consignorId);

  ContractRecord? contractById(String id) => _contractRepo.getById(id);

  ContractRecord contractForAuction(String consignorId, int auctionId) {
    return _contractRepo.getByConsignorAndAuction(consignorId, auctionId) ??
        ContractRecord.empty(consignorId, auctionId: auctionId);
  }

  Future<Consignor> saveConsignor(Consignor consignor) async {
    await _consignorRepo.saveReadyForSync(
      consignor,
      editorUsername: activeUsername,
    );
    await _refreshLocalCollections();
    final saved = consignorById(consignor.id) ?? consignor;
    notifyListeners();
    return saved;
  }

  Future<Consignor> saveConsignorDraft(Consignor consignor) async {
    await _consignorRepo.saveDraft(consignor, editorUsername: activeUsername);
    await _refreshLocalCollections();
    final saved = consignorById(consignor.id) ?? consignor;
    notifyListeners();
    return saved;
  }

  Future<void> deleteConsignor(String id) async {
    await _deleteConsignorLocalData(id);
    await _refreshLocalCollections();
    notifyListeners();
  }

  Future<bool> deleteLocalConsignorDraft(String id) async {
    final item = consignorById(id);
    if (item == null || !_canDeleteLocalConsignorDraft(item)) {
      return false;
    }

    final displayName = item.displayName.trim().isEmpty
        ? 'Unnamed consignor'
        : item.displayName.trim();

    await _deleteConsignorLocalData(id);
    await _refreshLocalCollections();
    lastMessage = 'Deleted local consignor draft: $displayName.';
    notifyListeners();
    return true;
  }

  Future<void> saveContract(ContractRecord contract) async {
    if (contract.syncStatus.needsSync) {
      contract.markLocalChange(activeUsername);
    }
    await _contractRepo.put(contract);
    await _refreshLocalCollections();
    notifyListeners();
  }

  Future<void> deleteContract(String id) async {
    await _wizardDraftRepo.deleteForContract(id);
    await _contractRepo.delete(id);
    await _refreshLocalCollections();
    notifyListeners();
  }

  Future<bool> deleteLocalContractDraft(String id) async {
    final item = contractById(id);
    if (item == null || !_canDeleteLocalContractDraft(item)) {
      return false;
    }

    final displayName = item.auctionDisplayName.trim().isEmpty
        ? (item.auctionId == null
            ? 'Draft contract'
            : 'Auction ${item.auctionId}')
        : item.auctionDisplayName.trim();

    await _wizardDraftRepo.deleteForContract(id);
    await _contractRepo.delete(id);
    await _refreshLocalCollections();
    lastMessage = 'Deleted local contract draft: $displayName.';
    notifyListeners();
    return true;
  }

  Future<void> saveSettings(AppSettings value, String bearerToken) async {
    settings = value;
    token = bearerToken;
    await _settingsRepo.saveSettings(value);
    await _settingsRepo.saveToken(bearerToken);
    await refreshAuthSessionState(notify: false);
    _startAuthMonitor();
    await refreshPhonePrefixes(silent: true);
    notifyListeners();
  }

  Future<void> signInWithMicrosoft() async {
    signingIn = true;
    lastMessage = null;
    notifyListeners();

    try {
      final newToken = await AuthService(settings).signInWithMicrosoft();
      token = newToken;
      await _settingsRepo.saveToken(newToken);
      await refreshAuthSessionState(notify: false);
      await refreshPhonePrefixes(silent: true);
      await refreshAuctions(silent: true);
      lastMessage = 'Microsoft sign-in succeeded.';
    } catch (e) {
      lastMessage = 'Microsoft sign-in failed: $e';
    } finally {
      signingIn = false;
      notifyListeners();
    }
  }

  Future<void> clearToken() async {
    token = '';
    tokenExpiresAtUtc = null;
    await _settingsRepo.saveToken('');
    lastMessage = 'Stored token cleared.';
    notifyListeners();
  }

  Future<void> testConnection() async {
    if (!await _ensureActiveMicrosoftSession()) return;

    try {
      final api = ApiService(settings, token);
      await api.validateConnection();
      lastMessage = 'Connection test succeeded.';
    } catch (e) {
      lastMessage = 'Connection test failed: $e';
    }

    notifyListeners();
  }

  Future<void> refreshPhonePrefixes({bool silent = false}) async {
    final fallback = await _phonePrefixRepo.loadBundledPrefixes();
    phonePrefixes = fallback;
    if (!silent) notifyListeners();

    await refreshAuthSessionState(notify: false);

    if (settings.apiBaseUrl.trim().isEmpty || !hasValidToken) {
      return;
    }

    try {
      final remote = await ApiService(settings, token).fetchPhonePrefixes();
      if (remote.isNotEmpty) {
        phonePrefixes = _phonePrefixRepo.normalize(remote);
      }
    } catch (_) {
      // Keep bundled fallback silently.
    }

    if (!silent) notifyListeners();
  }

  Future<void> refreshAuctions({bool silent = false}) async {
    if (!silent) notifyListeners();

    await refreshAuthSessionState(notify: false);

    if (settings.apiBaseUrl.trim().isEmpty || !hasValidToken) {
      auctions = const [];
      if (!silent) notifyListeners();
      return;
    }

    try {
      auctions = await ApiService(settings, token).fetchAuctionOptions();
    } catch (_) {
      auctions = const [];
    }

    if (!silent) notifyListeners();
  }

  Future<Consignor?> syncConsignorDraft(String id) => syncConsignor(id);

  Future<int> syncAllDraftConsignors() async {
    if (syncingAllDrafts) return 0;

    final dirtyIds = consignors
        .where((e) => e.needsSync)
        .map((e) => e.id)
        .toList(growable: false);

    if (dirtyIds.isEmpty) {
      lastMessage = 'No local consignors need syncing.';
      notifyListeners();
      return 0;
    }

    if (!await _ensureActiveMicrosoftSession()) return 0;

    syncingAllDrafts = true;
    lastMessage = null;
    notifyListeners();

    var syncedCount = 0;
    try {
      for (final id in dirtyIds) {
        final updated = await syncConsignor(id);
        if (updated?.synced == true) {
          syncedCount++;
        }
      }
      lastMessage =
          'Consignor sync completed. Synced $syncedCount of ${dirtyIds.length} record${dirtyIds.length == 1 ? '' : 's'}.';
      return syncedCount;
    } finally {
      syncingAllDrafts = false;
      notifyListeners();
    }
  }

  Future<Consignor?> syncConsignor(
    String id, {
    Consignor? authorizedRepresentative,
  }) async {
    final initial = consignorById(id);
    if (initial == null) return null;
    if (!initial.needsSync && authorizedRepresentative == null) return initial;
    if (_syncingConsignorIds.contains(id)) return initial;
    if (!await _ensureActiveMicrosoftSession()) return initial;

    _syncingConsignorIds.add(id);
    notifyListeners();

    try {
      final api = ApiService(settings, token);
      final pushResult = await api.pushConsignors(
        [initial],
        authorizedRepresentatives: authorizedRepresentative == null
            ? const {}
            : {initial.id: authorizedRepresentative},
      );
      final reference = pushResult.references[id];
      final syncedFromServer = pushResult.syncedConsignors[id];

      if (reference == null) {
        initial.markSyncFailed(
          'No sync confirmation was returned for this consignor.',
        );
        await _consignorRepo.put(initial);
        await _refreshLocalCollections();
        lastMessage = 'Consignor sync failed.';
        return consignorById(id);
      }

      final previousId = initial.id;
      final nextId = (reference.systemReferenceCustomer > 0
              ? reference.systemReferenceCustomer
              : previousId)
          .toString();

      final updated = syncedFromServer ?? initial;
      updated.systemReferenceConsignor = reference.systemReferenceConsignor;
      updated.systemReferenceCustomer = reference.systemReferenceCustomer;
      updated.id = nextId;
      updated.markSynced(remoteModifiedUtc: updated.lastModifiedUtc);

      await _consignorRepo.put(updated);

      if (previousId != nextId) {
        await _reassignContractsToConsignorId(previousId, nextId);
      }

      await _refreshLocalCollections();
      if (reference.linkedExistingCustomer) {
        lastMessage =
            'Consignor synced successfully. Existing customer linked and consignor created.';
      } else if (reference.customerAction.toLowerCase() == 'created' &&
          reference.consignorAction.toLowerCase() == 'created') {
        lastMessage =
            'Consignor synced successfully. Customer and consignor created.';
      } else {
        lastMessage = 'Consignor synced successfully.';
      }
      return consignorById(updated.id);
    } catch (e) {
      final current = consignorById(id) ?? initial;
      current.markSyncFailed('Sync failed: $e');
      await _consignorRepo.put(current);
      await _refreshLocalCollections();
      lastMessage = 'Consignor sync failed: $e';
      return consignorById(current.id);
    } finally {
      _syncingConsignorIds.remove(id);
      notifyListeners();
    }
  }

  Future<ContractRecord?> syncContract(
    String consignorId,
    int auctionId, {
    AbacusContractSyncEvent syncEvent = AbacusContractSyncEvent.manualSync,
  }) async {
    final current = _contractRepo.getByConsignorAndAuction(
      consignorId,
      auctionId,
    );
    final backendConsignorId =
        consignorById(consignorId)?.systemReferenceConsignor ??
            int.tryParse(consignorId);

    if (current == null) return null;
    if (!current.hasLocalChanges &&
        syncEvent == AbacusContractSyncEvent.manualSync) {
      return current;
    }
    if (!await _ensureActiveMicrosoftSession()) return current;

    final key = _contractKey(consignorId, auctionId);
    if (_syncingContractKeys.contains(key)) return current;

    _syncingContractKeys.add(key);
    notifyListeners();

    try {
      final api = ApiService(settings, token);
      if (backendConsignorId == null || backendConsignorId <= 0) {
        throw Exception(
          'Sync the consignor first before syncing this contract.',
        );
      }

      final synced = await api.syncContractRecord(
        backendConsignorId,
        current,
        syncEvent: syncEvent,
      );
      final updated = synced.copyWith(
        id: current.id,
        consignorId: current.consignorId,
        syncStatus: RecordSyncStatus.synced,
        syncErrorMessage: null,
        lastSyncedUtc: DateTime.now().toUtc(),
        remoteLastModifiedUtc: synced.lastModifiedUtc,
      );
      updated.markSynced(remoteModifiedUtc: synced.lastModifiedUtc);
      await _contractRepo.put(updated);
      await _refreshLocalCollections();
      lastMessage = 'Contract synced successfully.';
      return _contractRepo.getByConsignorAndAuction(consignorId, auctionId);
    } catch (e) {
      current.markSyncFailed('Sync failed: $e');
      await _contractRepo.put(current);
      await _refreshLocalCollections();
      lastMessage = 'Contract sync failed: $e';
      return _contractRepo.getByConsignorAndAuction(consignorId, auctionId);
    } finally {
      _syncingContractKeys.remove(key);
      notifyListeners();
    }
  }

  Future<void> syncNow() async {
    if (syncingNow) return;
    if (!await _ensureActiveMicrosoftSession()) return;

    syncingNow = true;
    lastMessage = null;
    _setSyncProgress(0, 0, 'Starting sync…');

    try {
      final api = ApiService(settings, token);

      // Compute the highest LastModifiedUtc we already have locally so the
      // backend can return only the records that changed since then.
      // On the very first sync sinceUtc is null and we download everything.
      final sinceUtc = _computeSinceUtc();

      final remoteSnapshot = await api.fetchRemoteSnapshot(
        sinceUtc: sinceUtc,
        onProgress: (current, total, message) {
          _setSyncProgress(current, total, message);
        },
      );

      var workCurrent = remoteSnapshot.consignors.length;
      var workTotal = remoteSnapshot.consignors.length + 3;
      if (workTotal <= 0) {
        workTotal = 1;
      }

      _setSyncProgress(
        workCurrent,
        workTotal,
        'Merging downloaded records…',
      );

      await _mergeRemoteConsignors(remoteSnapshot.consignors);
      await _mergeRemoteContracts(remoteSnapshot.contracts);
      await _refreshLocalCollections();

      workCurrent++;
      _setSyncProgress(
        workCurrent,
        workTotal,
        'Checking local consignors…',
      );

      final dirtyConsignors =
          consignors.where((e) => e.needsSync).toList(growable: false);

      workTotal += dirtyConsignors.length;

      var uploadedConsignors = 0;
      if (dirtyConsignors.isNotEmpty) {
        // Phase 2: show 'Syncing X of Y' for local pending consignors.
        _setSyncProgress(
          workCurrent,
          workTotal,
          'Syncing 0 of ${dirtyConsignors.length}…',
        );

        final pushResult = await api.pushConsignors(dirtyConsignors);
        uploadedConsignors = pushResult.pushedCount;

        for (var i = 0; i < dirtyConsignors.length; i++) {
          final consignor = dirtyConsignors[i];
          final reference = pushResult.references[consignor.id];
          final synced = pushResult.syncedConsignors[consignor.id];

          if (reference != null) {
            final previousId = consignor.id;
            final nextId = (reference.systemReferenceCustomer > 0
                    ? reference.systemReferenceCustomer
                    : previousId)
                .toString();

            final updated = synced ?? consignor;
            updated.systemReferenceConsignor =
                reference.systemReferenceConsignor;
            updated.systemReferenceCustomer = reference.systemReferenceCustomer;
            updated.id = nextId;
            updated.markSynced(remoteModifiedUtc: updated.lastModifiedUtc);

            await _consignorRepo.put(updated);

            if (previousId != nextId) {
              await _reassignContractsToConsignorId(previousId, nextId);
            }
          } else {
            consignor.markSyncFailed(
              'No sync confirmation was returned for this consignor.',
            );
            await _consignorRepo.put(consignor);
          }

          workCurrent++;
          _setSyncProgress(
            workCurrent,
            workTotal,
            'Syncing ${i + 1} of ${dirtyConsignors.length}…',
          );
        }
      }

      await _refreshLocalCollections();

      workCurrent++;
      _setSyncProgress(
        workCurrent,
        workTotal,
        'Checking local contracts…',
      );

      final dirtyContracts = contracts
          .where((e) => e.auctionId != null && e.hasLocalChanges)
          .toList(growable: false);

      workTotal += dirtyContracts.length;

      var uploadedContracts = 0;
      for (var index = 0; index < dirtyContracts.length; index++) {
        final contract = dirtyContracts[index];

        _setSyncProgress(
          workCurrent,
          workTotal,
          'Syncing contract ${index + 1} of ${dirtyContracts.length}…',
        );

        final synced = await syncContract(
          contract.consignorId,
          contract.auctionId!,
        );

        if (synced != null && synced.synced) {
          uploadedContracts++;
        }

        workCurrent++;
        _setSyncProgress(
          workCurrent,
          workTotal,
          'Syncing contract ${index + 1} of ${dirtyContracts.length}…',
        );
      }

      await _refreshLocalCollections();

      workCurrent = workTotal;
      _setSyncProgress(
        workCurrent,
        workTotal,
        'Sync finished.',
      );

      lastMessage =
          'Sync completed. Fetched ${remoteSnapshot.consignors.length} updated consignor${remoteSnapshot.consignors.length == 1 ? '' : 's'}, '
          'synced $uploadedConsignors pending consignor${uploadedConsignors == 1 ? '' : 's'} and $uploadedContracts contract${uploadedContracts == 1 ? '' : 's'}.';
    } catch (e) {
      final message = 'Sync failed: $e';
      lastMessage = message;
      await _markDirtyRecordsSyncFailed(message);
      await _refreshLocalCollections();

      final total = syncProgressTotal <= 0 ? 1 : syncProgressTotal;
      _setSyncProgress(
        syncProgressCurrent.clamp(0, total),
        total,
        message,
      );
    } finally {
      syncingNow = false;
      notifyListeners();
    }
  }

  /// Returns the highest [Consignor.remoteLastModifiedUtc] across all locally
  /// stored consignors. This is passed to the backend as the [sinceUtc] cutoff
  /// so only records changed after that timestamp are returned.
  ///
  /// Returns `null` when there are no locally synced consignors yet (first sync).
  DateTime? _computeSinceUtc() {
    DateTime? maxUtc;
    for (final consignor in consignors) {
      final ts = consignor.remoteLastModifiedUtc;
      if (ts != null && (maxUtc == null || ts.isAfter(maxUtc))) {
        maxUtc = ts;
      }
    }
    return maxUtc;
  }

  void _setSyncProgress(int current, int total, String message) {
    final safeTotal = total < 0 ? 0 : total;
    final safeCurrent = safeTotal <= 0
        ? (current < 0 ? 0 : current)
        : current.clamp(0, safeTotal);

    syncProgressCurrent = safeCurrent;
    syncProgressTotal = safeTotal;
    syncProgressMessage = message;
    notifyListeners();
  }

  bool _canDeleteLocalConsignorDraft(Consignor item) {
    return !item.hasRemoteReference &&
        (item.syncStatus == RecordSyncStatus.draft ||
            item.syncStatus == RecordSyncStatus.syncFailed);
  }

  bool _canDeleteLocalContractDraft(ContractRecord item) {
    return !_contractHasRemoteReference(item) &&
        (item.syncStatus == RecordSyncStatus.draft ||
            item.syncStatus == RecordSyncStatus.syncFailed ||
            item.auctionId == null);
  }

  bool _contractHasRemoteReference(ContractRecord item) {
    return item.systemReferenceContract > 0 || item.hasRemoteReference;
  }

  Future<void> _deleteConsignorLocalData(String id) async {
    await _wizardDraftRepo.deleteForConsignor(id);

    final relatedContracts = _contractRepo.getByConsignorId(id);
    for (final contract in relatedContracts) {
      await _wizardDraftRepo.deleteForContract(contract.id);
      await _contractRepo.delete(contract.id);
    }

    await _consignorRepo.delete(id);
  }

  Future<void> _refreshLocalCollections() async {
    consignors = _consignorRepo.getAll();
    contracts = _contractRepo.getAll();
  }

  Future<void> _mergeRemoteConsignors(List<Consignor> remoteConsignors) async {
    if (remoteConsignors.isEmpty) return;

    final localById = {
      for (final item in _consignorRepo.getAll()) item.id: item,
    };
    final toPersist = <Consignor>[];

    for (final remote in remoteConsignors) {
      final local = localById[remote.id];
      if (local != null && local.needsSync) {
        continue;
      }

      remote.markRemoteSnapshot();
      toPersist.add(remote);
    }

    if (toPersist.isNotEmpty) {
      await _consignorRepo.putAll(toPersist);
    }
  }

  Future<void> _mergeRemoteContracts(
    List<ContractRecord> remoteContracts,
  ) async {
    if (remoteContracts.isEmpty) return;

    final localById = {
      for (final item in _contractRepo.getAll()) item.id: item,
    };
    final toPersist = <ContractRecord>[];

    for (final remote in remoteContracts) {
      final local = localById[remote.id];
      if (local != null && local.hasLocalChanges) {
        continue;
      }

      remote.markRemoteSnapshot();
      toPersist.add(remote);
    }

    if (toPersist.isNotEmpty) {
      await _contractRepo.putAll(toPersist);
    }
  }

  Future<void> _reassignContractsToConsignorId(
    String previousId,
    String nextId,
  ) async {
    final allContracts = _contractRepo.getAll();

    for (final contract
        in allContracts.where((e) => e.consignorId == previousId)) {
      final updated = contract.copyWith(
        consignorId: nextId,
        id: contract.auctionIds.isEmpty
            ? nextId
            : '${nextId}_${contract.auctionIds.join('_')}',
      );
      await _contractRepo.delete(contract.id);
      await _contractRepo.put(updated);
    }
  }

  Future<void> _markDirtyRecordsSyncFailed(String message) async {
    final currentConsignors = _consignorRepo.getAll();
    for (final consignor in currentConsignors.where((e) => e.needsSync)) {
      consignor.markSyncFailed(message);
      await _consignorRepo.put(consignor);
    }

    final currentContracts = _contractRepo.getAll();
    for (final contract in currentContracts.where((e) => e.hasLocalChanges)) {
      contract.markSyncFailed(message);
      await _contractRepo.put(contract);
    }
  }

  String _contractKey(String consignorId, int auctionId) =>
      '${consignorId}_$auctionId';
}
