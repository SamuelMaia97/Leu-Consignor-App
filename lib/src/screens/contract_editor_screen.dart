import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/auction_option.dart';
import '../models/contract_record.dart';
import '../models/sync_status.dart';
import '../services/api_service.dart';
import '../services/contract_pdf_service.dart';
import '../services/file_service.dart';
import '../state/app_state.dart';
import '../utils/file_preview.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/page_header.dart';
import '../widgets/multi_auction_select_field.dart';
import '../widgets/section_card.dart';

enum _UnsavedChangesAction { save, addToDraft, closeWithoutSaving }

class ContractEditorScreen extends StatefulWidget {
  const ContractEditorScreen({
    super.key,
    required this.consignorId,
    this.auctionId,
    this.contractId,
  });

  final String consignorId;
  final int? auctionId;
  final String? contractId;

  @override
  State<ContractEditorScreen> createState() => _ContractEditorScreenState();
}

class _ContractEditorScreenState extends State<ContractEditorScreen> {
  final _fileService = FileService();
  final _pdfService = ContractPdfService();
  final Object _leaveGuardToken = Object();

  late ContractRecord _record;

  bool _initialized = false;
  bool _busy = false;
  bool _guardRegistered = false;

  String _initialSnapshot = '';
  String? _lastPersistedRecordId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    final state = context.read<AppState>();
    _record = widget.contractId != null
        ? (state.contractById(widget.contractId!) ??
            ContractRecord.empty(widget.consignorId))
        : widget.auctionId == null
            ? ContractRecord.empty(widget.consignorId)
            : state.contractForAuction(widget.consignorId, widget.auctionId!);

    _lastPersistedRecordId = _record.id;
    _captureSnapshot();
    _registerLeaveGuard();

    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().refreshAuctions(silent: false);
      }
    });
  }

  @override
  void dispose() {
    _unregisterLeaveGuard();
    super.dispose();
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

  int? get _backendConsignorId {
    final consignor = context.read<AppState>().consignorById(widget.consignorId);
    if (consignor != null && consignor.systemReferenceConsignor > 0) {
      return consignor.systemReferenceConsignor;
    }
    return int.tryParse(widget.consignorId);
  }

  bool get _hasUnsavedChanges => _buildSnapshot() != _initialSnapshot;

  Future<void> _persistLocal() async {
    await context.read<AppState>().saveContract(_record);
  }

  void _captureSnapshot() {
    _initialSnapshot = _buildSnapshot();
  }

  String _buildSnapshot() {
    final uploads = _record.uploads
        .map(
          (upload) => <String, dynamic>{
            'localId': upload.localId,
            'fileId': upload.fileId,
            'auctionId': upload.auctionId,
            'fileName': upload.fileName,
            'fileType': upload.fileType.apiValue,
            'path': upload.path,
            'isDeleted': upload.isDeleted,
            'localLastModifiedUtc':
                upload.localLastModifiedUtc.toUtc().toIso8601String(),
            'serverLastModifiedUtc':
                upload.serverLastModifiedUtc?.toUtc().toIso8601String(),
          },
        )
        .toList();

    final snapshot = <String, dynamic>{
      'id': _record.id,
      'consignorId': _record.consignorId,
      'auctionIds': _record.auctionIds,
      'auctionDisplayNames': _record.auctionDisplayNames,
      'pdfName': _record.pdfName,
      'pdfPath': _record.pdfPath,
      'signedAt': _record.signedAt.toUtc().toIso8601String(),
      'lastModifiedUtc': _record.lastModifiedUtc.toUtc().toIso8601String(),
      'uploads': uploads,
    };

    return jsonEncode(snapshot);
  }

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

  ButtonStyle _headerPrimaryButtonStyle() {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return const Color(0xFF49678E);
        }
        return const Color(0xFF163865);
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        return Colors.white;
      }),
      iconColor: WidgetStateProperty.resolveWith((states) {
        return Colors.white;
      }),
    );
  }

  ButtonStyle _headerSecondaryButtonStyle() {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        return Colors.transparent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.white.withValues(alpha: 0.72);
        }
        return Colors.white;
      }),
      iconColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.white.withValues(alpha: 0.72);
        }
        return Colors.white;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: Colors.white.withValues(alpha: 0.28));
        }
        return BorderSide(color: Colors.white.withValues(alpha: 0.72));
      }),
    );
  }

  Future<void> _updateAuctions(
    List<AuctionOption> selected,
  ) async {
    final auctionIds = selected.map((item) => item.auctionId).toList(growable: false);
    final displayNames = selected.map((item) => item.displayName).toList(growable: false);
    final nextId = auctionIds.isEmpty
        ? _record.id
         : '${widget.consignorId}_${auctionIds.join('_')}';

    setState(() {
      _record = _record.copyWith(
        id: nextId,
        auctionIds: auctionIds,
        auctionDisplayNames: displayNames,
        lastModifiedUtc: DateTime.now().toUtc(),
      );
    });
  }

  Future<bool> _saveAsDraft() async {
    final appState = context.read<AppState>();

    try {
      if (_lastPersistedRecordId != null &&
          _lastPersistedRecordId != _record.id) {
        await appState.deleteContract(_lastPersistedRecordId!);
      }

      await _persistLocal();
      _lastPersistedRecordId = _record.id;
      _captureSnapshot();

      if (!mounted) return false;
      _showSnack('Contract saved as draft.');
      return true;
    } catch (e) {
      if (!mounted) return false;
      _showSnack('Saving draft failed: $e');
      return false;
    }
  }

  Future<bool> _finishContract() async {
    final auctionId = _record.auctionId;
    final backendConsignorId = _backendConsignorId;
    final activeUploads = _record.uploads.where((u) => !u.isDeleted).toList();

    if (auctionId == null) {
      _showSnack('Select at least one auction before saving.');
      return false;
    }

    if (activeUploads.isEmpty) {
      _showSnack('Add at least one file before saving.');
      return false;
    }

    if (backendConsignorId == null || backendConsignorId <= 0) {
      _showSnack('Sync the consignor first before saving.');
      return false;
    }

    final appState = context.read<AppState>();
    final api = ApiService(appState.settings, appState.token);

    setState(() => _busy = true);
    try {
      final syncedRecord = await api.syncContractRecord(
        backendConsignorId,
        _record,
      );

      setState(() {
        _record = syncedRecord.copyWith(
          consignorId: widget.consignorId,
          syncStatus: RecordSyncStatus.synced,
        );
      });

      if (_lastPersistedRecordId != null &&
          _lastPersistedRecordId != _record.id) {
        await appState.deleteContract(_lastPersistedRecordId!);
      }

      await _persistLocal();
      _lastPersistedRecordId = _record.id;
      _captureSnapshot();

      if (!mounted) return false;
      _showSnack('Contract saved successfully.');
      return true;
    } catch (e) {
      if (!mounted) return false;
      _showSnack('Save failed: $e');
      return false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _generatePdf() async {
    final appState = context.read<AppState>();
    final consignor = appState.consignorById(widget.consignorId);

    if (consignor == null) return;

    if (_record.auctionId == null) {
      _showSnack('Select at least one auction before generating the contract PDF.');
      return;
    }

    setState(() => _busy = true);
    try {
      final output = await _fileService.getSuggestedPdfPath(
        _record.pdfName.trim().isEmpty
            ? 'consignor_contract.pdf'
            : _record.pdfName.trim(),
      );

      final file = await _pdfService.buildContractPdf(
        apiService: ApiService(appState.settings, appState.token),
        consignor: consignor,
        record: _record,
        outputPath: output,
      );

      setState(() {
        _record = _record.copyWith(
          pdfPath: file.path,
          lastModifiedUtc: DateTime.now().toUtc(),
        );
      });

      final existingPdfMatches = _record.uploads.where((upload) {
        return upload.fileType == UploadType.agreement &&
            upload.fileName.toLowerCase().endsWith('.pdf') &&
            !upload.isDeleted;
      }).toList();

      final existingPdf =
          existingPdfMatches.isEmpty ? null : existingPdfMatches.first;

      if (existingPdf != null) {
        await _replaceUpload(
          existingPdf,
          overridePath: file.path,
          overrideFileName: file.uri.pathSegments.last,
        );
      } else {
        await _addLocalFiles(
          [file.path],
          UploadType.agreement,
          openOnComplete: false,
        );
      }

      if (!mounted) return;
      _showSnack('PDF created at ${file.path}');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickFiles(
    UploadType type, {
    required bool imagesOnly,
    bool fromCamera = false,
  }) async {
    if (_record.auctionId == null) {
      _showSnack('Select at least one auction before adding files.');
      return;
    }

    List<String> paths = const [];
    if (fromCamera) {
      final captured = await _fileService.captureImage(
        context: context,
        type: type,
        filePrefix: type == UploadType.passport ? 'id' : 'product',
      );
      if (captured != null) {
        paths = [captured];
      }
    } else {
      final selectedPaths = await _fileService.pickFiles(
        imagesOnly: type != UploadType.agreement,
        allowMultiple: type != UploadType.agreement,
      );

      paths = await _fileService.importFilesForUpload(selectedPaths, type);
    }

    if (paths.isEmpty) return;
    await _addLocalFiles(paths, type);
  }

  Future<void> _addLocalFiles(
    List<String> paths,
    UploadType type, {
    bool openOnComplete = false,
  }) async {
    final auctionId = _record.auctionId;

    if (auctionId == null) {
      _showSnack('Select at least one auction before adding files.');
      return;
    }

    final nowUtc = DateTime.now().toUtc();
    final additions = paths.map((path) {
      final file = File(path);
      final fileName =
          file.uri.pathSegments.isEmpty ? path : file.uri.pathSegments.last;
      return ContractUpload(
        localId:
            '${type.name}_${fileName}_${nowUtc.microsecondsSinceEpoch}_${path.hashCode}',
        auctionId: auctionId,
        fileName: fileName,
        fileType: type,
        path: path,
        localLastModifiedUtc: nowUtc,
      );
    }).toList();

    setState(() {
      _record = _record.copyWith(
        uploads: [..._record.uploads, ...additions],
        syncStatus: _record.hasRemoteReference
            ? RecordSyncStatus.pendingSync
            : RecordSyncStatus.draft,
        lastModifiedUtc: nowUtc,
      );
    });

    if (openOnComplete && mounted && paths.isNotEmpty) {
      await _fileService.open(paths.first);
    }
  }

  Future<void> _replaceUpload(
    ContractUpload target, {
    String? overridePath,
    String? overrideFileName,
  }) async {
  final auctionId = _record.auctionId;

  if (auctionId == null) {
    _showSnack('Select at least one auction before replacing files.');
    return;
  }

  String replacementPath;

  if (overridePath != null && overridePath.trim().isNotEmpty) {
    replacementPath = overridePath;
  } else {
    final selectedPaths = await _fileService.pickFiles(
      imagesOnly: target.fileType != UploadType.agreement,
      allowMultiple: false,
    );

    if (selectedPaths.isEmpty) {
      return;
    }

    final importedPaths = await _fileService.importFilesForUpload(
      selectedPaths,
      target.fileType,
    );

    if (importedPaths.isEmpty) {
      return;
    }

    replacementPath = importedPaths.first;
  }

  final nowUtc = DateTime.now().toUtc();
  final replacementFile = File(replacementPath);

  final fileName = overrideFileName?.trim().isNotEmpty == true
      ? overrideFileName!.trim()
      : replacementFile.uri.pathSegments.isEmpty
          ? replacementPath
          : replacementFile.uri.pathSegments.last;

  final updatedLocal = target.copyWith(
    auctionId: auctionId,
    fileName: fileName,
    path: replacementPath,
    localLastModifiedUtc: nowUtc,
    isDeleted: false,
  );

  setState(() {
    _record = _record.copyWith(
      uploads: _record.uploads
          .map(
            (upload) =>
                identical(upload, target) || upload.localId == target.localId
                    ? updatedLocal
                    : upload,
          )
          .toList(),
      syncStatus: _record.hasRemoteReference
          ? RecordSyncStatus.pendingSync
          : RecordSyncStatus.draft,
      lastModifiedUtc: nowUtc,
    );
  });
}

  Future<void> _deleteUpload(ContractUpload upload) async {
    final nowUtc = DateTime.now().toUtc();

    setState(() {
      if ((upload.fileId ?? 0) > 0) {
        _record = _record.copyWith(
          uploads: _record.uploads
              .map(
                (item) => item.localId == upload.localId
                    ? item.copyWith(
                        isDeleted: true,
                        localLastModifiedUtc: nowUtc,
                      )
                    : item,
              )
              .toList(),
          syncStatus: RecordSyncStatus.pendingSync,
          lastModifiedUtc: nowUtc,
        );
      } else {
        _record = _record.copyWith(
          uploads: _record.uploads
              .where((item) => item.localId != upload.localId)
              .toList(),
          syncStatus: _record.hasRemoteReference
              ? RecordSyncStatus.pendingSync
              : RecordSyncStatus.draft,
          lastModifiedUtc: nowUtc,
        );
      }
    });
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
            'Do you want to save this contract, add it to draft, or close without saving?',
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
        return _finishContract();
      case _UnsavedChangesAction.addToDraft:
        return _saveAsDraft();
      case _UnsavedChangesAction.closeWithoutSaving:
        return true;
      case null:
        return false;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<AuctionOption> _selectedAuctionOptions(List<AuctionOption> auctions) {
    final byId = {for (final auction in auctions) auction.auctionId: auction};
    return [
      for (var index = 0; index < _record.auctionIds.length; index++)
        byId[_record.auctionIds[index]] ??
            AuctionOption(
              auctionId: _record.auctionIds[index],
              auctionNumber: 0,
              auctionType: 0,
              displayName: index < _record.auctionDisplayNames.length &&
                      _record.auctionDisplayNames[index].trim().isNotEmpty
                  ? _record.auctionDisplayNames[index]
                  : 'Auction ${_record.auctionIds[index]}',
            ),
    ];
  }

  String get _auctionSummaryText {
    if (_record.auctionDisplayNames.isNotEmpty) {
      return _record.auctionDisplayNames.join(', ');
    }
    if (_record.auctionIds.isNotEmpty) {
      return _record.auctionIds.map((id) => 'Auction $id').join(', ');
    }
    return 'Not selected';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final consignor = state.consignorById(widget.consignorId);
    final auctions = state.auctions;

    if (consignor == null) {
      return AppShell(
        title: 'Contract',
        child: AppEmptyState(
          title: 'Consignor not found',
          message: 'Return to the list and select a valid consignor record.',
          icon: Icons.description_outlined,
          action: OutlinedButton.icon(
            onPressed: () => context.go('/consignors'),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to consignors'),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _attemptLeaveTo(
          widget.contractId != null
              ? '/contracts'
              : '/contracts/${widget.consignorId}',
        );
      },
      child: AppShell(
        title: 'Contract editor',
        child: ListView(
          children: [
            PageHeader(
              eyebrow: 'CONTRACT WORKFLOW',
              title:
                  'Contract for ${consignor.displayName.isEmpty ? 'consignor' : consignor.displayName}',
              actions: [
                ElevatedButton.icon(
                  style: _headerPrimaryButtonStyle(),
                  onPressed: _busy ? null : _generatePdf,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(_busy ? 'Working…' : 'Generate PDF'),
                ),
                OutlinedButton.icon(
                  style: _headerSecondaryButtonStyle(),
                  onPressed: _record.pdfPath.isEmpty ||
                          !File(_record.pdfPath).existsSync()
                      ? null
                      : () => _fileService.open(_record.pdfPath),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open PDF'),
                ),
                OutlinedButton.icon(
                  style: _headerSecondaryButtonStyle(),
                  onPressed: _busy ? null : _saveAsDraft,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Add to draft'),
                ),
                ElevatedButton.icon(
                  style: _headerPrimaryButtonStyle(),
                  onPressed: _busy ? null : _finishContract,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                ),
              ],
            ),
            if (_record.lastEditedByUsername != null) ...[
              const SizedBox(height: 10),
              _AuditText(
                username: _record.lastEditedByUsername!,
                editedAtUtc: _record.lastEditedAtUtc,
              ),
            ],
            const SizedBox(height: 24),
            SectionCard(
              title: 'Contract settings',
              subtitle:
                  'Auction selection and signing date for this contract only.',
              icon: Icons.tune_outlined,
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: 420,
                    child: MultiAuctionSelectField(
                      key: ValueKey<String>(_record.auctionIds.join(',')),
                      label: 'Auctions *',
                      items: auctions,
                      selected: _selectedAuctionOptions(auctions),
                      validator: MultiAuctionSelectField.requireSelection,
                      onChanged: _updateAuctions,
                      enabled: widget.auctionId == null,
                      hintText: 'Search auctions',
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: _DateField(
                      label: 'Signed on',
                      value: _record.signedAt,
                      onChanged: (value) {
                        setState(() {
                          _record = _record.copyWith(
                            signedAt: value,
                            lastModifiedUtc: DateTime.now().toUtc(),
                          );
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextFormField(
                      initialValue: _record.pdfName,
                      decoration:
                          const InputDecoration(labelText: 'PDF file name'),
                      onChanged: (value) {
                        _record = _record.copyWith(pdfName: value);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Upload summary',
              subtitle:
                  'Files are only POSTed / PUT / DELETEd when you press Save.',
              icon: Icons.cloud_upload_outlined,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SummaryPill(
                    label: 'Auctions',
                    value: _auctionSummaryText,
                  ),
                  _SummaryPill(
                    label: 'Files',
                    value:
                        '${_record.uploads.where((e) => !e.isDeleted).length}',
                  ),
                  _SummaryPill(
                    label: 'State',
                    value: _record.hasLocalChanges
                        ? 'Unsynced changes'
                        : 'In sync',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _UploadSection(
              title: 'Passport photos',
              uploads: _record.uploads
                  .where(
                    (item) =>
                        item.fileType == UploadType.passport && !item.isDeleted,
                  )
                  .toList(),
              onAddFiles: () =>
                  _pickFiles(UploadType.passport, imagesOnly: true),
              onCapture: () => _pickFiles(
                UploadType.passport,
                imagesOnly: true,
                fromCamera: true,
              ),
              onOpen: _fileService.open,
              onReplace: _replaceUpload,
              onDelete: _deleteUpload,
              showReplaceButton: false,
            ),
            const SizedBox(height: 18),
            _UploadSection(
              title: 'Product photos',
              uploads: _record.uploads
                  .where(
                    (item) =>
                        item.fileType == UploadType.product && !item.isDeleted,
                  )
                  .toList(),
              onAddFiles: () =>
                  _pickFiles(UploadType.product, imagesOnly: true),
              onCapture: () => _pickFiles(
                UploadType.product,
                imagesOnly: true,
                fromCamera: true,
              ),
              onOpen: _fileService.open,
              onReplace: _replaceUpload,
              onDelete: _deleteUpload,
              showReplaceButton: false,
            ),
            const SizedBox(height: 18),
            _UploadSection(
              title: 'Registration files',
              uploads: _record.uploads
                  .where(
                    (item) =>
                        item.fileType == UploadType.agreement &&
                        !item.isDeleted,
                  )
                  .toList(),
              onAddFiles: () =>
                  _pickFiles(UploadType.agreement, imagesOnly: false),
              onOpen: _fileService.open,
              onReplace: _replaceUpload,
              onDelete: _deleteUpload,
            ),
          ],
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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('yyyy-MM-dd');
    return TextFormField(
      controller: TextEditingController(text: formatter.format(value)),
      decoration: InputDecoration(labelText: label),
      readOnly: true,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _UploadSection extends StatelessWidget {
  const _UploadSection({
    required this.title,
    required this.uploads,
    required this.onAddFiles,
    this.onCapture,
    required this.onOpen,
    required this.onReplace,
    required this.onDelete,
    this.showReplaceButton = true,
  });

  final String title;
  final List<ContractUpload> uploads;
  final VoidCallback onAddFiles;
  final VoidCallback? onCapture;
  final bool showReplaceButton;
  final Future<void> Function(String path) onOpen;
  final Future<void> Function(ContractUpload upload) onReplace;
  final Future<void> Function(ContractUpload upload) onDelete;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      subtitle: '${uploads.length} file${uploads.length == 1 ? '' : 's'}',
      icon: Icons.attach_file_outlined,
      child: Column(
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onAddFiles,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Add file'),
              ),
              if (onCapture != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onCapture,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Capture'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (uploads.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No files selected yet.'),
            )
          else
            ...uploads.map(
              (upload) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _UploadTile(
                  upload: upload,
                  onOpen: onOpen,
                  onReplace: onReplace,
                  onDelete: onDelete,
                  showReplaceButton: showReplaceButton,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.upload,
    required this.onOpen,
    required this.onReplace,
    required this.onDelete,
    this.showReplaceButton = true,
  });

  final ContractUpload upload;
  final bool showReplaceButton;
  final Future<void> Function(String path) onOpen;
  final Future<void> Function(ContractUpload upload) onReplace;
  final Future<void> Function(ContractUpload upload) onDelete;

  bool _isImagePath(String value) {
    final lower = value.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    final preview = FilePreview.fromPath(
      upload.fileName.isEmpty ? upload.path : upload.fileName,
    );

    final hasImagePreview = _isImagePath(
          upload.fileName.isEmpty ? upload.path : upload.fileName,
        ) &&
        upload.path.trim().isNotEmpty &&
        File(upload.path).existsSync();

    Widget leading;
    if (hasImagePreview) {
      leading = InkWell(
        onTap: () => onOpen(upload.path),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(upload.path),
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Icon(preview.icon),
              );
            },
          ),
        ),
      );
    } else {
      leading = Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Icon(preview.icon),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap:
                  upload.path.trim().isEmpty ? null : () => onOpen(upload.path),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      upload.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      upload.needsSync ? 'Unsynced local changes' : 'In sync',
                      style: TextStyle(
                        color: upload.needsSync
                            ? Colors.orange.shade800
                            : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 2,
            children: [
              IconButton(
                tooltip: 'Open',
                onPressed: upload.path.trim().isEmpty
                    ? null
                    : () => onOpen(upload.path),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
              if (showReplaceButton)
                IconButton(
                  tooltip: 'Replace',
                  onPressed: () => onReplace(upload),
                  icon: const Icon(Icons.swap_horiz_rounded),
                ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => onDelete(upload),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}