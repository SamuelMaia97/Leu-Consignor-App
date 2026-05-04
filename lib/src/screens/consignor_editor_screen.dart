import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/consignor.dart';
import '../models/customer_lookup_result.dart';
import '../models/payment_option.dart';
import '../models/phone_prefix.dart';
import '../models/sync_status.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/form_validators.dart';
import '../widgets/app_shell.dart';
import '../widgets/country_dropdown.dart';
import '../widgets/page_header.dart';
import '../widgets/searchable_select_field.dart';
import '../widgets/section_card.dart';

class ConsignorEditorScreen extends StatefulWidget {
  const ConsignorEditorScreen({super.key, this.consignorId});

  final String? consignorId;

  @override
  State<ConsignorEditorScreen> createState() => _ConsignorEditorScreenState();
}

class _ConsignorEditorScreenState extends State<ConsignorEditorScreen> {
  static const List<_LookupOption<int>> _titleOptions = [
    _LookupOption(value: 1, label: 'Dr.'),
    _LookupOption(value: 5, label: 'Prof.'),
    _LookupOption(value: 6, label: 'Prof. Dr.'),
  ];

  static const List<_LookupOption<int>> _salutationOptions = [
    _LookupOption(value: 2, label: 'Mr.'),
    _LookupOption(value: 4, label: 'Ms.'),
  ];

  static const List<_LookupOption<String>> _correspondenceOptions = [
    _LookupOption(value: 'en', label: 'English'),
    _LookupOption(value: 'de', label: 'German'),
  ];

  final _formKey = GlobalKey<FormState>();
  final Object _leaveGuardToken = Object();

  late Consignor _model;
  late final TextEditingController _existingCustomerSearchController;
  Timer? _existingCustomerSearchDebounce;
  List<CustomerLookupResult> _existingCustomerResults = const [];
  bool _initialized = false;
  bool _guardRegistered = false;
  bool _searchingExistingCustomers = false;
  bool _useExistingCustomer = false;
  int _formVersion = 0;
  String _initialSnapshot = '';
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  bool get _isNew => widget.consignorId == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    final state = context.read<AppState>();
    _model = _isNew
        ? _buildEmptyConsignor()
        : (state.consignorById(widget.consignorId!) ?? _buildEmptyConsignor());

    _model.paymentOption = PaymentOption.bankTransfer;
    _useExistingCustomer = _isNew && _model.existingCustomerId != null;
    _existingCustomerSearchController = TextEditingController(
      text: _model.existingCustomerLabel ?? '',
    );

    _captureSnapshot();
    _registerLeaveGuard();
    _initialized = true;
  }

  @override
  void dispose() {
    _existingCustomerSearchDebounce?.cancel();
    _existingCustomerSearchController.dispose();
    _unregisterLeaveGuard();
    super.dispose();
  }

  Consignor _buildEmptyConsignor() {
    final model = Consignor.empty();
    model.paymentOption = PaymentOption.bankTransfer;
    return model;
  }

  void _registerLeaveGuard() {
    if (_guardRegistered) return;

    context.read<AppState>().registerLeaveGuard(
          token: _leaveGuardToken,
          handler: _handlePendingChangesBeforeLeave,
        );

    _guardRegistered = true;
  }

  void _unregisterLeaveGuard() {
    if (!_guardRegistered) return;
    context.read<AppState>().unregisterLeaveGuard(_leaveGuardToken);
    _guardRegistered = false;
  }

  bool get _hasUnsavedChanges => _buildSnapshot() != _initialSnapshot;

  void _captureSnapshot() {
    _initialSnapshot = _buildSnapshot();
  }

  String _buildSnapshot() {
    final snapshot = <String, dynamic>{
      'isLegalEntity': _model.isLegalEntity,
      'tradingName': _model.tradingName,
      'title': _model.consignorInfo.title,
      'salutation': _model.consignorInfo.salutation,
      'firstName': _model.consignorInfo.firstName,
      'lastName': _model.consignorInfo.lastName,
      'dateOfBirth':
          _model.consignorInfo.dateOfBirth?.toUtc().toIso8601String(),
      'nationalityIso3': _model.consignorInfo.nationalityIso3,
      'nationalityName': _model.consignorInfo.nationalityName,
      'phonePrefix': _model.phonePrefix,
      'phonePrefixOriginId': _model.phonePrefixOriginId,
      'phoneNumber': _model.phoneNumber,
      'emailAddress': _model.emailAddress,
      'eori': _model.eori,
      'streetAddress': _model.consignorAddress.streetAddress,
      'streetNumber': _model.consignorAddress.streetNumber,
      'streetAddressOptional': _model.consignorAddress.streetAddressOptional,
      'postalCode': _model.consignorAddress.postalCode,
      'city': _model.consignorAddress.city,
      'adminRegion': _model.consignorAddress.adminRegion,
      'countryIso3': _model.consignorAddress.countryIso3,
      'countryName': _model.consignorAddress.countryName,
      'vatLiability': _model.vatLiability,
      'vatNumber': _model.vatNumber,
      'correspondence': _model.correspondence,
      'checkedByLeu': _model.checkedByLeu,
      'newsletterSubscribed': _model.newsletterSubscribed,
      'ancientCoinsSubscribed': _model.ancientCoinsSubscribed,
      'worldCoinsSubscribed': _model.worldCoinsSubscribed,
      'existingCustomer': _useExistingCustomer,
      'existingCustomerId': _model.existingCustomerId,
      'existingCustomerLabel': _model.existingCustomerLabel,
      'bankName': _model.bankingDetails.bankName,
      'accountNumber': _model.bankingDetails.accountNumber,
    };

    return jsonEncode(snapshot);
  }

  String _normalizeLookupQuery(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<void> _navigateAway(String location) async {
    _unregisterLeaveGuard();
    if (!mounted) return;
    context.go(location);
  }

  Future<void> _attemptLeaveTo(String location) async {
    final canLeave = await _handlePendingChangesBeforeLeave();
    if (!mounted || !canLeave) return;
    await _navigateAway(location);
  }

  Future<void> _saveAndContinue() async {
    final saved = await _saveAsPendingSync();
    if (!saved || !mounted) return;
    await _navigateAway('/contracts/${_model.id}');
  }

  Future<void> _addToDraftAndStay() async {
    await _saveAsDraft();
  }

  void _toggleExistingCustomer(bool enabled) {
    setState(() {
      _useExistingCustomer = enabled;
      _existingCustomerResults = const [];
      _searchingExistingCustomers = false;

      if (!enabled) {
        _existingCustomerSearchController.clear();
        _model = _buildEmptyConsignor();
        _formVersion++;
        _autovalidateMode = AutovalidateMode.disabled;
      }
    });
  }

  void _queueExistingCustomerSearch(String query) {
    final normalizedQuery = _normalizeLookupQuery(query);
    _existingCustomerSearchDebounce?.cancel();

    setState(() {
      if ((_model.existingCustomerLabel ?? '').trim() != normalizedQuery) {
        _model.clearExistingCustomerSelection();
      }
      _searchingExistingCustomers = normalizedQuery.isNotEmpty;
      if (normalizedQuery.isEmpty) {
        _existingCustomerResults = const [];
      }
    });

    if (normalizedQuery.isEmpty) {
      return;
    }

    _existingCustomerSearchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchExistingCustomers(normalizedQuery),
    );
  }

  Future<void> _searchExistingCustomers(String query) async {
    final trimmed = _normalizeLookupQuery(query);
    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searchingExistingCustomers = false;
        _existingCustomerResults = const [];
      });
      return;
    }

    final appState = context.read<AppState>();
    await appState.refreshAuthSessionState(notify: false);

    if (!appState.hasValidToken) {
      if (!mounted) return;
      setState(() {
        _searchingExistingCustomers = false;
        _existingCustomerResults = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microsoft login expired. Refresh your login from Dashboard or Settings and try again.',
          ),
        ),
      );
      return;
    }

    try {
      final api = ApiService(appState.settings, appState.token);
      final matches = await api.searchExistingCustomers(trimmed);

      if (!mounted ||
          _normalizeLookupQuery(_existingCustomerSearchController.text) !=
              trimmed) {
        return;
      }

      setState(() {
        _searchingExistingCustomers = false;
        _existingCustomerResults = matches;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchingExistingCustomers = false;
        _existingCustomerResults = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Existing customer lookup failed: $e')),
      );
    }
  }

  void _applyExistingCustomer(CustomerLookupResult result) {
    final nextModel = Consignor.fromJson(result.prefill.toJson());

    nextModel.consignorInfo.dateOfBirth =
        result.prefill.consignorInfo.dateOfBirth;

    nextModel.id = _model.id;
    nextModel.systemReferenceConsignor = 0;
    nextModel.systemReferenceCustomer = 0;
    nextModel.existingCustomerId = result.customerId;
    nextModel.existingCustomerLabel = result.displayLabel;
    nextModel.syncStatus = _model.syncStatus == RecordSyncStatus.synced
        ? RecordSyncStatus.pendingSync
        : _model.syncStatus;
    nextModel.syncErrorMessage = null;
    nextModel.lastSyncedUtc = null;
    nextModel.remoteLastModifiedUtc = null;
    nextModel.lastModifiedUtc = DateTime.now().toUtc();

    setState(() {
      _model = nextModel;
      _formVersion++;
      _existingCustomerSearchController.value = TextEditingValue(
        text: result.displayLabel,
        selection: TextSelection.collapsed(offset: result.displayLabel.length),
      );
      _existingCustomerResults = const [];
      _searchingExistingCustomers = false;
    });
  }

  Widget _buildExistingCustomerSection() {
    if (!_isNew) {
      return const SizedBox.shrink();
    }

    return SectionCard(
      title: 'Customer lookup',
      subtitle:
          'Reuse an existing customer record when this consignor already exists in the customer database.',
      icon: Icons.person_search_outlined,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.palette.brandSoft.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.palette.border),
            ),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Existing customer?'),
              subtitle: const Text(
                'When checked, you can search by name, first name, ID, or email and auto-fill the form.',
              ),
              value: _useExistingCustomer,
              onChanged: (value) => _toggleExistingCustomer(value ?? false),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: !_useExistingCustomer
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      key: const ValueKey('existingCustomerLookup'),
                      children: [
                        TextField(
                          controller: _existingCustomerSearchController,
                          decoration: InputDecoration(
                            labelText: 'Search existing customers',
                            hintText:
                                'Search by last name, first name, ID, or email',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchingExistingCustomers
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : ((_existingCustomerSearchController.text
                                        .trim()
                                        .isEmpty)
                                    ? null
                                    : IconButton(
                                        onPressed: () {
                                          _existingCustomerSearchController
                                              .clear();
                                          setState(() {
                                            _existingCustomerResults = const [];
                                            _model
                                                .clearExistingCustomerSelection();
                                          });
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      )),
                          ),
                          onChanged: _queueExistingCustomerSearch,
                        ),
                        if ((_model.existingCustomerLabel ?? '')
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F8FF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: context.palette.border),
                            ),
                            child: Text(
                              'Selected customer: ${_model.existingCustomerLabel}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                        if (_existingCustomerResults.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: context.palette.border),
                            ),
                            child: Column(
                              children: [
                                for (var index = 0;
                                    index < _existingCustomerResults.length;
                                    index++) ...[
                                  ListTile(
                                    title: Text(
                                      _existingCustomerResults[index]
                                          .displayLabel,
                                    ),
                                    subtitle: Text(
                                      _existingCustomerResults[index]
                                          .searchSubtitle,
                                    ),
                                    trailing: const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                    ),
                                    onTap: () => _applyExistingCustomer(
                                      _existingCustomerResults[index],
                                    ),
                                  ),
                                  if (index <
                                      _existingCustomerResults.length - 1)
                                    const Divider(height: 1),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  PhonePrefix? _findSelectedPhonePrefix(List<PhonePrefix> options) {
    final originId = _model.phonePrefixOriginId;
    if (originId != null) {
      final byOrigin = options.where((item) => item.originId == originId);
      if (byOrigin.isNotEmpty) {
        return byOrigin.first;
      }
    }

    final byDialCode =
        options.where((item) => item.dialCode == _model.phonePrefix);
    return byDialCode.isEmpty ? null : byDialCode.first;
  }

  Future<void> _syncConsignor() async {
    if (_isNew || !_model.needsSync) return;
    if (!_validateForm()) return;

    final appState = context.read<AppState>();

    _normalizeModelBeforeSave();
    final locallySaved = _model.syncStatus == RecordSyncStatus.draft
        ? await appState.saveConsignorDraft(_model)
        : await appState.saveConsignor(_model);

    if (!mounted) return;

    setState(() {
      _model = locallySaved;
    });

    final previousId = _model.id;
    final updated = await appState.syncConsignor(previousId);

    if (!mounted) return;

    if (updated != null) {
      setState(() {
        _model = updated;
      });
      _captureSnapshot();

      if (widget.consignorId != null && widget.consignorId != updated.id) {
        await _navigateAway('/consignors/${updated.id}');
        return;
      }
    }

    final message =
        updated != null && updated.syncStatus == RecordSyncStatus.synced
            ? (appState.lastMessage ?? 'Consignor synced successfully.')
            : (updated?.syncErrorMessage ??
                appState.lastMessage ??
                'Consignor sync finished.');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool> _handlePendingChangesBeforeLeave() async {
    if (!_hasUnsavedChanges) return true;

    final action = await showDialog<_UnsavedChangesAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('You have unsaved changes'),
          content: const Text(
            'Do you want to save this consignor, add it to draft, or close without saving?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_UnsavedChangesAction.closeWithoutSaving),
              child: const Text('Close without saving'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_UnsavedChangesAction.addToDraft),
              child: const Text('Add to draft'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedChangesAction.save),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    switch (action) {
      case _UnsavedChangesAction.save:
        return _saveAsPendingSync();
      case _UnsavedChangesAction.addToDraft:
        return _saveAsDraft();
      case _UnsavedChangesAction.closeWithoutSaving:
        return true;
      case null:
        return false;
    }
  }

  Future<bool> _saveAsPendingSync() async {
    if (!_validateForm()) return false;

    _normalizeModelBeforeSave();

    if (_isNew && !_model.linksExistingCustomer) {
      _model.ensureGeneratedCredentials();
    }

    final saved = await context.read<AppState>().saveConsignor(_model);

    if (!mounted) return false;

    setState(() {
      _model = saved;
    });
    _captureSnapshot();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Consignor saved and marked for sync.')),
    );

    return true;
  }

  Future<bool> _saveAsDraft() async {
    _normalizeModelBeforeSave();

    if (_isNew && !_model.linksExistingCustomer) {
      _model.ensureGeneratedCredentials();
    }

    final saved = await context.read<AppState>().saveConsignorDraft(_model);

    if (!mounted) return false;

    setState(() {
      _model = saved;
    });
    _captureSnapshot();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Consignor saved as draft.')),
    );

    return true;
  }

  bool _validateForm() {
    setState(() {
      _autovalidateMode = AutovalidateMode.onUserInteraction;
    });

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix the validation errors before saving.'),
        ),
      );
    }
    return isValid;
  }

  void _normalizeModelBeforeSave() {
    _model.paymentOption = PaymentOption.bankTransfer;
    if (!_useExistingCustomer) {
      _model.clearExistingCustomerSelection();
    }

    _model.tradingName = _model.tradingName.trim();
    _model.phonePrefix = _model.phonePrefix.trim();
    _model.phoneNumber = _model.phoneNumber.trim();
    _model.emailAddress = _model.emailAddress.trim();
    _model.vatNumber = _model.vatNumber.trim();
    _model.eori = _model.eori.trim();
    _model.correspondence = _model.correspondence?.trim();

    _model.consignorInfo.firstName = _model.consignorInfo.firstName.trim();
    _model.consignorInfo.lastName = _model.consignorInfo.lastName.trim();

    _model.consignorAddress.streetAddress =
        _model.consignorAddress.streetAddress.trim();
    _model.consignorAddress.streetNumber =
        _model.consignorAddress.streetNumber.trim();
    _model.consignorAddress.streetAddressOptional =
        _model.consignorAddress.streetAddressOptional.trim();
    _model.consignorAddress.postalCode =
        _model.consignorAddress.postalCode.trim();
    _model.consignorAddress.city = _model.consignorAddress.city.trim();
    _model.consignorAddress.adminRegion =
        _model.consignorAddress.adminRegion.trim();

    final normalizedIban = _normalizeIban(_model.bankingDetails.accountNumber);
    _model.bankingDetails.accountNumber = normalizedIban;
    _model.bankingDetails.isIban = normalizedIban.isNotEmpty;
    _model.bankingDetails.bankName = _model.bankingDetails.bankName.trim();
    _model.bankingDetails.clearingNumber = '';
    _model.bankingDetails.bicSwift = '';
  }

  String _normalizeIban(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  List<Widget> _buildBottomActions({
    required bool showSyncButton,
    required bool syncing,
  }) {
    final actions = <Widget>[
      OutlinedButton.icon(
        onPressed: _addToDraftAndStay,
        icon: const Icon(Icons.edit_note_outlined),
        label: const Text('Add to draft'),
      ),
      ElevatedButton.icon(
        onPressed: _saveAndContinue,
        icon: const Icon(Icons.save_rounded),
        label: const Text('Save and continue'),
      ),
      OutlinedButton(
        onPressed: () => _attemptLeaveTo('/consignors'),
        child: const Text('Cancel'),
      ),
    ];

    if (showSyncButton) {
      actions.insert(
        0,
        OutlinedButton.icon(
          onPressed: syncing ? null : _syncConsignor,
          icon: syncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(syncing ? 'Syncing…' : 'Sync consignor'),
        ),
      );
    }

    return actions;
  }

  List<Widget> _withSpacing(List<Widget> widgets, {double spacing = 12}) {
    final result = <Widget>[];
    for (var i = 0; i < widgets.length; i++) {
      result.add(widgets[i]);
      if (i < widgets.length - 1) {
        result.add(SizedBox(width: spacing));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final countries = state.countries;
    final phonePrefixes = state.phonePrefixes;
    final syncing = !_isNew && state.isSyncingConsignor(_model.id);
    final showSyncButton = !_isNew && _model.needsSync;
    final bottomActions = _buildBottomActions(
      showSyncButton: showSyncButton,
      syncing: syncing,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _attemptLeaveTo('/consignors');
      },
      child: AppShell(
        title: _isNew ? 'New consignor' : 'Edit consignor',
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidateMode,
          child: KeyedSubtree(
            key: ValueKey(_formVersion),
            child: ListView(
              children: [
                PageHeader(
                  eyebrow: _isNew ? 'NEW CONSIGNOR' : 'CONSIGNOR PROFILE',
                  title: _isNew
                      ? 'Create a new consignor record'
                      : 'Update consignor details',
                  trailing: _EditorSummary(model: _model),
                  actions: [
                    if (showSyncButton)
                      OutlinedButton.icon(
                        onPressed: syncing ? null : _syncConsignor,
                        icon: syncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(syncing ? 'Syncing…' : 'Sync consignor'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _addToDraftAndStay,
                      icon: const Icon(Icons.edit_note_outlined),
                      label: const Text('Add to draft'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _saveAndContinue,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Save and continue'),
                    ),
                  ],
                ),
                if (_model.lastEditedByUsername != null) ...[
                  const SizedBox(height: 10),
                  _AuditText(
                    username: _model.lastEditedByUsername!,
                    editedAtUtc: _model.lastEditedAtUtc,
                  ),
                ],
                const SizedBox(height: 24),
                if (_isNew) ...[
                  _buildExistingCustomerSection(),
                  const SizedBox(height: 18),
                ],
                if (!_isNew) ...[
                  SectionCard(
                    title: 'Audit',
                    icon: Icons.history_outlined,
                    child: _ResponsiveFormGrid(
                      children: [
                        TextFormField(
                          key: const ValueKey('editor-field-last-modified-by'),
                          initialValue: _model.lastEditedByUsername ?? '—',
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Last modified by',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (!_isNew && _model.hasRemoteReference) ...[
                  SectionCard(
                    title: 'Assigned identifiers',
                    subtitle: 'These identifiers are assigned by backend sync.',
                    icon: Icons.tag_outlined,
                    child: _ResponsiveFormGrid(
                      children: [
                        TextFormField(
                          key: const ValueKey('editor-field-consignor-id'),
                          initialValue:
                              _model.systemReferenceConsignor.toString(),
                          readOnly: true,
                          decoration:
                              const InputDecoration(labelText: 'Consignor ID'),
                        ),
                        TextFormField(
                          key: const ValueKey('editor-field-customer-id'),
                          initialValue:
                              _model.systemReferenceCustomer.toString(),
                          readOnly: true,
                          decoration:
                              const InputDecoration(labelText: 'Customer ID'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                SectionCard(
                  title: 'Consignor profile',
                  subtitle: 'Identity, contact, and legal-entity information.',
                  icon: Icons.badge_outlined,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.palette.brandSoft
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: context.palette.border),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Legal entity'),
                          subtitle: const Text(
                            'Enable this when the consignor is a company or institution.',
                          ),
                          value: _model.isLegalEntity,
                          onChanged: (value) =>
                              setState(() => _model.isLegalEntity = value),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ResponsiveFormGrid(
                        children: [
                          SearchableSelectFormField<_LookupOption<int>>(
                            key: const ValueKey('editor-field-title'),
                            label: 'Title',
                            items: _titleOptions,
                            itemLabel: (item) => item.label,
                            initialValue: _titleOptions
                                .where((item) =>
                                    item.value == _model.consignorInfo.title)
                                .cast<_LookupOption<int>?>()
                                .firstOrNull,
                            onChanged: (value) =>
                                _model.consignorInfo.title = value?.value,
                          ),
                          SearchableSelectFormField<_LookupOption<int>>(
                            key: const ValueKey('editor-field-salutation'),
                            label: 'Salutation',
                            items: _salutationOptions,
                            itemLabel: (item) => item.label,
                            initialValue: _salutationOptions
                                .where((item) =>
                                    item.value ==
                                    _model.consignorInfo.salutation)
                                .cast<_LookupOption<int>?>()
                                .firstOrNull,
                            onChanged: (value) =>
                                _model.consignorInfo.salutation = value?.value,
                          ),
                          TextFormField(
                            key: const ValueKey('editor-field-first-name'),
                            initialValue: _model.consignorInfo.firstName,
                            decoration:
                                const InputDecoration(labelText: 'First name *'),
                            validator: (value) =>
                                FormValidators.requiredText(value, 'First name'),
                            onChanged: (value) =>
                                _model.consignorInfo.firstName = value,
                          ),
                          TextFormField(
                            key: const ValueKey('editor-field-last-name'),
                            initialValue: _model.consignorInfo.lastName,
                            decoration:
                                const InputDecoration(labelText: 'Last name *'),
                            validator: (value) =>
                                FormValidators.requiredText(value, 'Last name'),
                            onChanged: (value) =>
                                _model.consignorInfo.lastName = value,
                          ),
                          if (_model.isLegalEntity)
                            TextFormField(
                              key: const ValueKey('editor-field-trading-name'),
                              initialValue: _model.tradingName,
                              decoration: const InputDecoration(
                                labelText: 'Trading name *',
                              ),
                              validator: (value) => _model.isLegalEntity
                                  ? FormValidators.requiredText(
                                      value,
                                      'Trading name',
                                    )
                                  : null,
                              onChanged: (value) => _model.tradingName = value,
                            ),
                          _DatePickerFormField(
                            key: ValueKey(
                              'editor-field-date-of-birth-${_model.consignorInfo.dateOfBirth?.toIso8601String() ?? 'empty'}',
                            ),
                            label: 'Date of birth *',
                            value: _model.consignorInfo.dateOfBirth,
                            validator: (value) => value == null
                                ? 'Date of birth is required'
                                : null,
                            onChanged: (picked) => setState(
                              () => _model.consignorInfo.dateOfBirth = picked,
                            ),
                          ),
                          CountryDropdown(
                            key: const ValueKey('editor-field-nationality'),
                            label: 'Nationality *',
                            value: _model.consignorInfo.nationalityIso3,
                            countries: countries,
                            hintText: 'Search nationality',
                            validator: (value) =>
                                value == null ? 'Nationality is required' : null,
                            onChanged: (country) => setState(() {
                              _model.consignorInfo.nationalityIso3 =
                                  country?.iso3 ?? '';
                              _model.consignorInfo.nationalityName =
                                  country?.name ?? '';
                            }),
                          ),
                          SearchableSelectFormField<PhonePrefix>(
                            key: ValueKey(
                              'editor-field-phone-prefix-${_model.phonePrefixOriginId ?? _model.phonePrefix}-${phonePrefixes.length}',
                            ),
                            label: 'Phone prefix *',
                            items: phonePrefixes,
                            itemLabel: (item) => item.label,
                            initialValue:
                                _findSelectedPhonePrefix(phonePrefixes),
                            validator: (value) =>
                                FormValidators.phonePrefix(value?.dialCode),
                            onChanged: (value) {
                              _model.phonePrefix = value?.dialCode ?? '';
                              _model.phonePrefixOriginId = value?.originId;
                            },
                            hintText: 'Search phone prefix',
                            leading: const Icon(Icons.call_outlined),
                          ),
                          TextFormField(
                            key: const ValueKey('editor-field-phone-number'),
                            initialValue: _model.phoneNumber,
                            decoration:
                                const InputDecoration(labelText: 'Telephone *'),
                            validator: FormValidators.phoneLocalNumber,
                            onChanged: (value) => _model.phoneNumber = value,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9+\-()/. ]'),
                              ),
                            ],
                          ),
                          TextFormField(
                            key: const ValueKey('editor-field-email-address'),
                            initialValue: _model.emailAddress,
                            decoration:
                                const InputDecoration(labelText: 'Email *'),
                            validator: FormValidators.email,
                            onChanged: (value) => _model.emailAddress = value,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          if (_model.isLegalEntity)
                            TextFormField(
                              key: const ValueKey('editor-field-eori'),
                              initialValue: _model.eori,
                              decoration:
                                  const InputDecoration(labelText: 'EORI *'),
                              validator: (value) => _model.isLegalEntity
                                  ? FormValidators.requiredText(value, 'EORI')
                                  : null,
                              onChanged: (value) => _model.eori = value,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionCard(
                  title: 'Address',
                  subtitle:
                      'Primary correspondence and residence address details.',
                  icon: Icons.location_on_outlined,
                  child: _ResponsiveFormGrid(
                    children: [
                      TextFormField(
                        key: const ValueKey('editor-field-street-address'),
                        initialValue: _model.consignorAddress.streetAddress,
                        decoration:
                            const InputDecoration(labelText: 'Street *'),
                        validator: (value) =>
                            FormValidators.requiredText(value, 'Street'),
                        onChanged: (value) =>
                            _model.consignorAddress.streetAddress = value,
                      ),
                      TextFormField(
                        key: const ValueKey('editor-field-street-number'),
                        initialValue: _model.consignorAddress.streetNumber,
                        decoration: const InputDecoration(
                          labelText: 'House number *',
                        ),
                        validator: (value) =>
                            FormValidators.requiredText(value, 'House number'),
                        onChanged: (value) =>
                            _model.consignorAddress.streetNumber = value,
                      ),
                      TextFormField(
                        key: const ValueKey(
                          'editor-field-street-address-optional',
                        ),
                        initialValue:
                            _model.consignorAddress.streetAddressOptional,
                        decoration:
                            const InputDecoration(labelText: 'Address line 2'),
                        onChanged: (value) => _model
                            .consignorAddress.streetAddressOptional = value,
                      ),
                      TextFormField(
                        key: const ValueKey('editor-field-postal-code'),
                        initialValue: _model.consignorAddress.postalCode,
                        decoration:
                            const InputDecoration(labelText: 'Postal code *'),
                        validator: (value) =>
                            FormValidators.requiredText(value, 'Postal code'),
                        onChanged: (value) =>
                            _model.consignorAddress.postalCode = value,
                      ),
                      TextFormField(
                        key: const ValueKey('editor-field-city'),
                        initialValue: _model.consignorAddress.city,
                        decoration: const InputDecoration(labelText: 'City *'),
                        validator: (value) =>
                            FormValidators.requiredText(value, 'City'),
                        onChanged: (value) =>
                            _model.consignorAddress.city = value,
                      ),
                      TextFormField(
                        key: const ValueKey('editor-field-admin-region'),
                        initialValue: _model.consignorAddress.adminRegion,
                        decoration: const InputDecoration(
                          labelText: 'State / region',
                        ),
                        onChanged: (value) =>
                            _model.consignorAddress.adminRegion = value,
                      ),
                      CountryDropdown(
                        key: const ValueKey('editor-field-country'),
                        label: 'Country *',
                        value: _model.consignorAddress.countryIso3,
                        countries: countries,
                        hintText: 'Search country',
                        validator: (value) =>
                            value == null ? 'Country is required' : null,
                        onChanged: (country) => setState(() {
                          _model.consignorAddress.countryIso3 =
                              country?.iso3 ?? '';
                          _model.consignorAddress.countryName =
                              country?.name ?? '';
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionCard(
                  title: 'VAT and preferences',
                  subtitle:
                      'Tax flags, correspondence language, and subscription preferences.',
                  icon: Icons.account_balance_wallet_outlined,
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stack = constraints.maxWidth < 760;
                          final vatToggle = Container(
                            key: const ValueKey('editor-field-vat-toggle'),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.palette.brandSoft
                                  .withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: context.palette.border),
                            ),
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('VAT obligatory'),
                              subtitle: const Text(
                                'When enabled, a VAT number is required.',
                              ),
                              value: _model.vatLiability,
                              onChanged: (value) => setState(
                                () => _model.vatLiability = value ?? false,
                              ),
                            ),
                          );

                          final vatNumber = TextFormField(
                            key: const ValueKey('editor-field-vat-number'),
                            initialValue: _model.vatNumber,
                            decoration:
                                const InputDecoration(labelText: 'VAT number'),
                            validator: (value) => _model.vatLiability
                                ? FormValidators.requiredText(
                                    value,
                                    'VAT number',
                                  )
                                : null,
                            onChanged: (value) => _model.vatNumber = value,
                          );

                          if (stack) {
                            return Column(
                              children: [
                                vatToggle,
                                const SizedBox(height: 16),
                                vatNumber,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: vatToggle),
                              const SizedBox(width: 16),
                              Expanded(child: vatNumber),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _ResponsiveFormGrid(
                        children: [
                          SearchableSelectFormField<_LookupOption<String>>(
                            key: const ValueKey('editor-field-correspondence'),
                            label: 'Correspondence *',
                            items: _correspondenceOptions,
                            itemLabel: (item) => item.label,
                            initialValue: _correspondenceOptions
                                .where((item) =>
                                    item.value == _model.correspondence)
                                .cast<_LookupOption<String>?>()
                                .firstOrNull,
                            validator: (value) => value == null
                                ? 'Correspondence is required'
                                : null,
                            onChanged: (value) =>
                                _model.correspondence = value?.value,
                          ),
                          _BooleanCard(
                            key: const ValueKey('editor-field-checked-by-leu'),
                            title: 'Checked by Leu',
                            subtitle: 'Internal review flag.',
                            value: _model.checkedByLeu,
                            onChanged: (value) =>
                                setState(() => _model.checkedByLeu = value),
                          ),
                          _BooleanCard(
                            key: const ValueKey(
                              'editor-field-newsletter-subscribed',
                            ),
                            title: 'Newsletter subscribed',
                            subtitle: 'Marketing communication preference.',
                            value: _model.newsletterSubscribed,
                            onChanged: (value) => setState(
                              () => _model.newsletterSubscribed = value,
                            ),
                          ),
                          _BooleanCard(
                            key: const ValueKey(
                              'editor-field-ancient-coins-subscribed',
                            ),
                            title: 'Ancient coins subscribed',
                            subtitle: 'Collector preference.',
                            value: _model.ancientCoinsSubscribed,
                            onChanged: (value) => setState(
                              () => _model.ancientCoinsSubscribed = value,
                            ),
                          ),
                          _BooleanCard(
                            key: const ValueKey(
                              'editor-field-world-coins-subscribed',
                            ),
                            title: 'World coins subscribed',
                            subtitle: 'Collector preference.',
                            value: _model.worldCoinsSubscribed,
                            onChanged: (value) => setState(
                              () => _model.worldCoinsSubscribed = value,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SectionCard(
                  title: 'Bank transfer details',
                  subtitle:
                      'The consignor app supports bank transfer only. A valid IBAN is required.',
                  icon: Icons.account_balance_outlined,
                  child: _ResponsiveFormGrid(
                    children: [
                      TextFormField(
                        key: const ValueKey('editor-field-bank-name'),
                        initialValue: _model.bankingDetails.bankName,
                        decoration:
                            const InputDecoration(labelText: 'Bank name'),
                        onChanged: (value) =>
                            _model.bankingDetails.bankName = value,
                      ),
                      TextFormField(
                        key: const ValueKey('editor-field-iban'),
                        initialValue: _model.bankingDetails.accountNumber,
                        decoration: const InputDecoration(labelText: 'IBAN *'),
                        validator: FormValidators.iban,
                        onChanged: (value) =>
                            _model.bankingDetails.accountNumber = value,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: context.palette.border),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 760;

                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Primary action',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: bottomActions,
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Primary action',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ..._withSpacing(bottomActions),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditText extends StatelessWidget {
  const _AuditText({required this.username, required this.editedAtUtc});

  final String username;
  final DateTime? editedAtUtc;

  @override
  Widget build(BuildContext context) {
    final local = editedAtUtc?.toLocal();
    final dateText = local == null
        ? 'unknown date'
        : DateFormat('dd MMM yyyy HH:mm').format(local);
    return Text(
      'Last edited by $username on $dateText',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.black54,
          ),
    );
  }
}

class _EditorSummary extends StatelessWidget {
  const _EditorSummary({required this.model});

  final Consignor model;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (model.syncStatus) {
      RecordSyncStatus.draft => 'Draft',
      RecordSyncStatus.pendingSync => 'Pending sync',
      RecordSyncStatus.synced => 'Synced',
      RecordSyncStatus.syncFailed => 'Sync failed',
    };

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Record summary',
            style: TextStyle(
              color: Color(0xFFDCE6F3),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _SummaryLine(label: 'Status', value: statusLabel),
          const SizedBox(height: 8),
          _SummaryLine(
            label: 'Phone',
            value: model.fullPhoneNumber.isEmpty ? '-' : model.fullPhoneNumber,
          ),
          const SizedBox(height: 8),
          _SummaryLine(
            label: 'Language',
            value: model.correspondence?.toUpperCase() ?? '-',
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFDCE6F3))),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DatePickerFormField extends FormField<DateTime> {
  _DatePickerFormField({
    super.key,
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
    super.validator,
  }) : super(
          initialValue: value,
          builder: (field) {
            final date = field.value;

            return InkWell(
              onTap: () async {
                final picked = await showDialog<DateTime>(
                  context: field.context,
                  builder: (context) => _MonthYearDayPickerDialog(
                    initialDate: date ?? DateTime(1990, 1, 1),
                    firstDate: DateTime(1900, 1, 1),
                    lastDate: DateTime.now(),
                  ),
                );

                if (picked != null) {
                  field.didChange(picked);
                  onChanged(picked);
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  errorText: field.errorText,
                ),
                child: Text(
                  date == null
                      ? 'Select date'
                      : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                  style: date == null
                      ? TextStyle(color: Theme.of(field.context).hintColor)
                      : null,
                ),
              ),
            );
          },
        );
}

class _MonthYearDayPickerDialog extends StatefulWidget {
  const _MonthYearDayPickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_MonthYearDayPickerDialog> createState() =>
      _MonthYearDayPickerDialogState();
}

class _MonthYearDayPickerDialogState extends State<_MonthYearDayPickerDialog> {
  static const List<String> _monthLabels = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  @override
  void initState() {
    super.initState();
    final safeInitial = _clampDate(
      widget.initialDate,
      widget.firstDate,
      widget.lastDate,
    );

    _selectedYear = safeInitial.year;
    _selectedMonth = safeInitial.month;
    _selectedDay = safeInitial.day;
  }

  DateTime _clampDate(DateTime value, DateTime min, DateTime max) {
    if (value.isBefore(min)) return min;
    if (value.isAfter(max)) return max;
    return value;
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  List<int> get _availableYears => [
        for (var year = widget.lastDate.year;
            year >= widget.firstDate.year;
            year--)
          year,
      ];

  List<int> get _availableMonths {
    var startMonth = 1;
    var endMonth = 12;

    if (_selectedYear == widget.firstDate.year) {
      startMonth = widget.firstDate.month;
    }
    if (_selectedYear == widget.lastDate.year) {
      endMonth = widget.lastDate.month;
    }

    return [
      for (var month = startMonth; month <= endMonth; month++) month,
    ];
  }

  List<int> get _availableDays {
    var startDay = 1;
    var endDay = _daysInMonth(_selectedYear, _selectedMonth);

    if (_selectedYear == widget.firstDate.year &&
        _selectedMonth == widget.firstDate.month) {
      startDay = widget.firstDate.day;
    }

    if (_selectedYear == widget.lastDate.year &&
        _selectedMonth == widget.lastDate.month) {
      endDay = widget.lastDate.day;
    }

    return [
      for (var day = startDay; day <= endDay; day++) day,
    ];
  }

  InputDecoration _pickerDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    );
  }

  Widget _pickerItemText(String value) {
    return Transform.translate(
      offset: const Offset(0, -1.5),
      child: Text(
        value,
        style: const TextStyle(height: 1.0),
      ),
    );
  }

  void _updateSelection({
    int? year,
    int? month,
    int? day,
  }) {
    final nextYear = year ?? _selectedYear;
    final nextMonth = month ?? _selectedMonth;
    final maxDay = _daysInMonth(nextYear, nextMonth);
    final desiredDay = day ?? _selectedDay;
    final nextDay = desiredDay > maxDay ? maxDay : desiredDay;

    setState(() {
      _selectedYear = nextYear;
      _selectedMonth = nextMonth;
      _selectedDay = nextDay;
    });

    final validMonths = _availableMonths;
    if (!validMonths.contains(_selectedMonth)) {
      setState(() {
        _selectedMonth = validMonths.first;
        _selectedDay = _selectedDay > _daysInMonth(_selectedYear, _selectedMonth)
            ? _daysInMonth(_selectedYear, _selectedMonth)
            : _selectedDay;
      });
    }

    final validDays = _availableDays;
    if (!validDays.contains(_selectedDay)) {
      setState(() {
        _selectedDay = validDays.first;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = _availableYears;
    final months = _availableMonths;
    final days = _availableDays;

    return AlertDialog(
      title: const Text('Select date of birth'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Choose year, month, and day directly.'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _selectedYear,
              decoration: _pickerDecoration('Year'),
              items: years
                  .map(
                    (year) => DropdownMenuItem<int>(
                      value: year,
                      child: _pickerItemText(year.toString()),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  _updateSelection(year: value);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _selectedMonth,
              decoration: _pickerDecoration('Month'),
              items: months
                  .map(
                    (month) => DropdownMenuItem<int>(
                      value: month,
                      child: _pickerItemText(_monthLabels[month - 1]),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  _updateSelection(month: value);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _selectedDay,
              decoration: _pickerDecoration('Day'),
              items: days
                  .map(
                    (day) => DropdownMenuItem<int>(
                      value: day,
                      child: _pickerItemText(day.toString().padLeft(2, '0')),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  _updateSelection(day: value);
                }
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime(
                      _selectedYear,
                      _selectedMonth,
                      _selectedDay,
                    ),
                    firstDate: widget.firstDate,
                    lastDate: widget.lastDate,
                    initialDatePickerMode: DatePickerMode.year,
                  );

                  if (!context.mounted) return;

                  if (picked != null) {
                    Navigator.of(context).pop(picked);
                  }
                },
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Use calendar view instead'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final result = DateTime(
              _selectedYear,
              _selectedMonth,
              _selectedDay,
            );
            Navigator.of(context).pop(result);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ResponsiveFormGrid extends StatelessWidget {
  const _ResponsiveFormGrid({required this.children});

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
          children: children
              .map(
                (child) => SizedBox(
                  key: child.key == null ? null : ValueKey<Object?>(child.key),
                  width: itemWidth,
                  child: child,
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _BooleanCard extends StatelessWidget {
  const _BooleanCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _LookupOption<T> {
  const _LookupOption({required this.value, required this.label});

  final T value;
  final String label;
}

enum _UnsavedChangesAction { save, addToDraft, closeWithoutSaving }

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}