import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/sync_report_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _getAll;
  late final TextEditingController _getOne;
  late final TextEditingController _updateOne;
  late final TextEditingController _bulkConsignors;
  late final TextEditingController _getContracts;
  late final TextEditingController _getContractOne;
  late final TextEditingController _updateContractOne;
  late final TextEditingController _bulkContracts;
  late final TextEditingController _originPrefixes;
  late final TextEditingController _customersSearch;
  late final TextEditingController _oauthClientId;
  late final TextEditingController _oauthTenantId;
  late final TextEditingController _oauthScope;
  late final TextEditingController _oauthRedirectUri;
  late final TextEditingController _token;
  bool _initialized = false;
  bool _hideToken = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    final s = context.read<AppState>().settings;
    final token = context.read<AppState>().token;

    _baseUrl = TextEditingController(text: s.apiBaseUrl);
    _getAll = TextEditingController(text: s.consignorsGetAll);
    _getOne = TextEditingController(text: s.consignorsGetOne);
    _updateOne = TextEditingController(text: s.consignorsUpdateOne);
    _bulkConsignors = TextEditingController(text: s.consignorsBulkUpdate);
    _getContracts = TextEditingController(text: s.contractsGetAll);
    _getContractOne = TextEditingController(text: s.contractsGetOne);
    _updateContractOne = TextEditingController(text: s.contractsUpdateOne);
    _bulkContracts = TextEditingController(text: s.contractsBulkUpdate);
    _originPrefixes = TextEditingController(text: s.originPrefixesGetAll);
    _customersSearch = TextEditingController(text: s.customersSearch);
    _oauthClientId = TextEditingController(text: s.oauthClientId);
    _oauthTenantId = TextEditingController(text: s.oauthTenantId);
    _oauthScope = TextEditingController(text: s.oauthScope);
    _oauthRedirectUri = TextEditingController(text: s.oauthRedirectUri);
    _token = TextEditingController(text: token);

    _initialized = true;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _getAll.dispose();
    _getOne.dispose();
    _updateOne.dispose();
    _bulkConsignors.dispose();
    _getContracts.dispose();
    _getContractOne.dispose();
    _updateContractOne.dispose();
    _bulkContracts.dispose();
    _originPrefixes.dispose();
    _customersSearch.dispose();
    _oauthClientId.dispose();
    _oauthTenantId.dispose();
    _oauthScope.dispose();
    _oauthRedirectUri.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _saveSettings({bool showFeedback = true}) async {
    await context
        .read<AppState>()
        .saveSettings(_buildSettings(), _token.text.trim());

    if (!mounted || !showFeedback) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved.')),
    );
  }

  Future<void> _saveSettingsIfAdmin(
    AppState state, {
    bool showFeedback = true,
  }) async {
    if (!state.isAdminUser) {
      return;
    }

    await _saveSettings(showFeedback: showFeedback);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Settings',
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final statusLabel = _authStatusLabel(state);
          final statusTone = _authStatusTone(state);
          final signedIn = state.hasValidToken;
          final isAdmin = state.isAdminUser;

          if (_token.text != state.token) {
            _token.text = state.token;
          }

          return ListView(
            children: [
              PageHeader(
                eyebrow: 'CONFIGURATION CENTER',
                title: isAdmin
                    ? 'Secure API, OAuth, and sync controls'
                    : 'Connection and sync status',
                trailing: Container(
                  constraints: const BoxConstraints(maxWidth: 320),
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
                        'Access status',
                        style: TextStyle(
                          color: Color(0xFFDCE6F3),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      StatusBadge(
                        label: statusLabel,
                        tone: statusTone,
                        icon: signedIn
                            ? (state.tokenExpiringSoon
                                ? Icons.access_time_rounded
                                : Icons.verified_user_outlined)
                            : Icons.lock_outline,
                      ),
                    ],
                  ),
                ),
                actions: [
                  if (isAdmin)
                    ElevatedButton.icon(
                      onPressed:
                          state.syncingNow ? null : () => _saveSettings(),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save settings'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final split = constraints.maxWidth >= 1180;

                  final left = Column(
                    children: [
                      if (isAdmin) ...[
                        SectionCard(
                          title: 'API configuration',
                          icon: Icons.hub_outlined,
                          child: _ResponsiveSettingsGrid(
                            children: [
                              _wideField(_baseUrl, 'API base URL'),
                              _field(_getAll, 'Consignors get-all endpoint'),
                              _field(_getOne, 'Consignor get-one endpoint'),
                              _field(
                                _updateOne,
                                'Consignor update-one endpoint',
                              ),
                              _field(
                                _bulkConsignors,
                                'Consignors bulk-create endpoint',
                              ),
                              _field(
                                _getContracts,
                                'Contracts get-all endpoint',
                              ),
                              _field(
                                _getContractOne,
                                'Contract get-one endpoint',
                              ),
                              _field(
                                _updateContractOne,
                                'Contract update-one endpoint',
                              ),
                              _field(
                                _bulkContracts,
                                'Contracts bulk-create endpoint',
                              ),
                              _field(
                                _originPrefixes,
                                'Origin prefixes endpoint',
                              ),
                              _field(
                                _customersSearch,
                                'Existing customers search endpoint',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        SectionCard(
                          title: 'Microsoft OAuth',
                          icon: Icons.shield_outlined,
                          child: _ResponsiveSettingsGrid(
                            children: [
                              _field(_oauthClientId, 'Client ID'),
                              _field(_oauthTenantId, 'Tenant ID'),
                              _wideField(_oauthScope, 'Scope'),
                              _field(_oauthRedirectUri, 'Redirect URI'),
                              _wideTokenField(),
                            ],
                          ),
                        ),
                      ] else ...[
                        SectionCard(
                          title: 'Admin-managed settings',
                          icon: Icons.lock_outline_rounded,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'API configuration and Microsoft OAuth settings are managed by the admin user.',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'You can still use Microsoft sign-in, sync records, and continue normal app work with the saved configuration.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );

                  final right = Column(
                    children: [
                      SectionCard(
                        title: 'Actions',
                        icon: Icons.play_circle_outline,
                        child: Column(
                          children: [
                            if (isAdmin) ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: state.syncingNow
                                      ? null
                                      : () => _saveSettings(),
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('Save settings'),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: state.signingIn || state.syncingNow
                                    ? null
                                    : () async {
                                        final appState =
                                            context.read<AppState>();
                                        final messenger =
                                            ScaffoldMessenger.of(context);

                                        await _saveSettingsIfAdmin(
                                          appState,
                                          showFeedback: false,
                                        );
                                        await appState.signInWithMicrosoft();

                                        if (!mounted) return;

                                        _token.text = appState.token;
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              appState.lastMessage ??
                                                  'Finished',
                                            ),
                                          ),
                                        );
                                      },
                                icon: state.signingIn
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.login_rounded),
                                label: Text(
                                  state.signingIn
                                      ? 'Signing in…'
                                      : state.hasValidToken
                                          ? 'Refresh Microsoft login'
                                          : 'Sign in with Microsoft',
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: state.syncingNow
                                    ? null
                                    : () async {
                                        final appState =
                                            context.read<AppState>();
                                        final messenger =
                                            ScaffoldMessenger.of(context);

                                        await appState.clearToken();

                                        if (!mounted) return;

                                        _token.clear();
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              appState.lastMessage ??
                                                  'Finished',
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.logout_rounded),
                                label: const Text('Clear token'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: state.syncingNow
                                    ? null
                                    : () async {
                                        final appState =
                                            context.read<AppState>();
                                        final messenger =
                                            ScaffoldMessenger.of(context);

                                        await _saveSettingsIfAdmin(
                                          appState,
                                          showFeedback: false,
                                        );
                                        await appState.testConnection();

                                        if (!mounted) return;

                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              appState.lastMessage ??
                                                  'Finished',
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.wifi_tethering_rounded),
                                label: const Text('Test connection'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: state.syncingNow
                                    ? null
                                    : () async {
                                        final appState =
                                            context.read<AppState>();
                                        final messenger =
                                            ScaffoldMessenger.of(context);

                                        await _saveSettingsIfAdmin(
                                          appState,
                                          showFeedback: false,
                                        );
                                        await appState.syncNow();

                                        if (!context.mounted) return;

                                        if (appState.isAdminUser &&
                                            appState.lastSyncMissingReportFields
                                                .isNotEmpty) {
                                          await showSyncReportDialog(
                                            context,
                                            appState
                                                .lastSyncMissingReportFields,
                                          );
                                          if (!context.mounted) return;
                                        }

                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              appState.lastMessage ??
                                                  'Finished',
                                            ),
                                          ),
                                        );
                                      },
                                icon: state.syncingNow
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.sync_rounded),
                                label: Text(
                                  state.syncingNow ? 'Syncing…' : 'Run sync',
                                ),
                              ),
                            ),
                            if (state.syncingNow) ...[
                              const SizedBox(height: 16),
                              _SyncProgressView(state: state),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SectionCard(
                        title: 'Current status',
                        icon: Icons.analytics_outlined,
                        child: Column(
                          children: [
                            _StatusLine(
                              label: 'Stored token',
                              value: state.hasStoredToken
                                  ? 'Available'
                                  : 'Missing',
                            ),
                            const Divider(height: 24),
                            _StatusLine(
                              label: 'Session state',
                              value: _authStatusLabel(state),
                            ),
                            const Divider(height: 24),
                            _StatusLine(
                              label: 'Token expiry',
                              value: _formatExpiry(state.tokenExpiresAtLocal),
                            ),
                            const Divider(height: 24),
                            _StatusLine(
                              label: 'Latest message',
                              value: state.lastMessage ??
                                  'No recent status message',
                            ),
                            if (isAdmin &&
                                state.lastSyncMissingReportFields
                                    .isNotEmpty) ...[
                              const Divider(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => showSyncReportDialog(
                                    context,
                                    state.lastSyncMissingReportFields,
                                  ),
                                  icon: const Icon(Icons.fact_check_outlined),
                                  label: const Text('View sync report'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );

                  return split
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: left),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: right),
                          ],
                        )
                      : Column(
                          children: [
                            left,
                            const SizedBox(height: 16),
                            right,
                          ],
                        );
                },
              ),
              if (state.lastMessage != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: state.lastMessage!.toLowerCase().contains('failed')
                        ? const Color(0xFFFFF1F1)
                        : const Color(0xFFF1FBF4),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: state.lastMessage!.toLowerCase().contains('failed')
                          ? const Color(0xFFFFD8D8)
                          : const Color(0xFFD6F2DF),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        state.lastMessage!.toLowerCase().contains('failed')
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        color:
                            state.lastMessage!.toLowerCase().contains('failed')
                                ? context.palette.error
                                : context.palette.success,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SelectableText(
                          state.lastMessage!,
                          style: TextStyle(
                            color: state.lastMessage!
                                    .toLowerCase()
                                    .contains('failed')
                                ? context.palette.error
                                : context.palette.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _wideField(TextEditingController controller, String label) {
    return _WideGridField(child: _field(controller, label));
  }

  Widget _wideTokenField() {
    return _WideGridField(
      child: TextField(
        controller: _token,
        obscureText: _hideToken,
        maxLines: 1,
        decoration: InputDecoration(
          labelText: 'Bearer token',
          suffixIcon: IconButton(
            onPressed: () => setState(() => _hideToken = !_hideToken),
            icon: Icon(_hideToken ? Icons.visibility_off : Icons.visibility),
          ),
        ),
      ),
    );
  }

  AppSettings _buildSettings() {
    return AppSettings(
      apiBaseUrl: _baseUrl.text.trim(),
      consignorsGetAll: _getAll.text.trim(),
      consignorsGetOne: _getOne.text.trim(),
      consignorsUpdateOne: _updateOne.text.trim(),
      consignorsBulkUpdate: _bulkConsignors.text.trim(),
      contractsGetAll: _getContracts.text.trim(),
      contractsGetOne: _getContractOne.text.trim(),
      contractsUpdateOne: _updateContractOne.text.trim(),
      contractsBulkUpdate: _bulkContracts.text.trim(),
      originPrefixesGetAll: _originPrefixes.text.trim(),
      customersSearch: _customersSearch.text.trim(),
      oauthClientId: _oauthClientId.text.trim(),
      oauthTenantId: _oauthTenantId.text.trim(),
      oauthScope: _oauthScope.text.trim(),
      oauthRedirectUri: _oauthRedirectUri.text.trim(),
    );
  }

  String _authStatusLabel(AppState state) {
    if (!state.hasStoredToken) {
      return 'No active token';
    }
    if (!state.hasValidToken) {
      return 'Microsoft login expired';
    }
    if (state.tokenExpiringSoon) {
      return 'Token expiring soon';
    }
    return 'Microsoft token valid';
  }

  StatusBadgeTone _authStatusTone(AppState state) {
    if (!state.hasStoredToken || !state.hasValidToken) {
      return StatusBadgeTone.warning;
    }
    if (state.tokenExpiringSoon) {
      return StatusBadgeTone.info;
    }
    return StatusBadgeTone.success;
  }

  String _formatExpiry(DateTime? value) {
    if (value == null) {
      return 'Unknown';
    }

    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }
}

class _SyncProgressView extends StatelessWidget {
  const _SyncProgressView({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final hasTotal = state.syncProgressTotal > 0;
    final progressText = hasTotal
        ? '${state.syncProgressCurrent} / ${state.syncProgressTotal}'
        : 'Working…';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E7F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.syncProgressMessage.trim().isEmpty
                ? 'Syncing…'
                : state.syncProgressMessage,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: state.syncProgressValue),
          const SizedBox(height: 8),
          Text(
            progressText,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (state.contractSyncProgressMessage.trim().isNotEmpty ||
              state.contractSyncProgressTotal > 0) ...[
            const SizedBox(height: 14),
            Text(
              state.contractSyncProgressMessage.trim().isEmpty
                  ? 'Analyzing contracts...'
                  : state.contractSyncProgressMessage,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: state.contractSyncProgressValue),
            const SizedBox(height: 8),
            Text(
              state.contractSyncProgressTotal > 0
                  ? '${state.contractSyncProgressCurrent} / ${state.contractSyncProgressTotal}'
                  : 'Working...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _ResponsiveSettingsGrid extends StatelessWidget {
  const _ResponsiveSettingsGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 3
            : constraints.maxWidth >= 760
                ? 2
                : 1;
        const spacing = 16.0;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children.map((child) {
            final wide = child is _WideGridField;
            final content = wide ? child.child : child;

            if (wide && columns > 1) {
              return SizedBox(
                width: columns == 2
                    ? constraints.maxWidth
                    : (itemWidth * 2) + spacing,
                child: content,
              );
            }

            return SizedBox(width: itemWidth, child: content);
          }).toList(),
        );
      },
    );
  }
}

class _WideGridField extends StatelessWidget {
  const _WideGridField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 3,
          child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
