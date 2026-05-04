import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/auction_option.dart';
import '../models/consignor.dart';
import '../models/contract_record.dart';
import '../models/customer_lookup_result.dart';
import '../models/payment_option.dart';
import '../repositories/wizard_draft_repository.dart';
import '../models/phone_prefix.dart';
import '../services/api_service.dart';
import '../services/contract_pdf_service.dart';
import '../services/file_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/file_preview.dart';
import '../utils/form_validators.dart';
import '../widgets/app_shell.dart';
import '../widgets/country_dropdown.dart';
import '../widgets/multi_auction_select_field.dart';
import '../widgets/searchable_select_field.dart';
import '../widgets/section_card.dart';

class ConsignorWizardScreen extends StatefulWidget {
  const ConsignorWizardScreen({
    super.key,
    this.contractOnly = false,
    this.resumeConsignorId,
    this.resumeContractId,
  });

  final bool contractOnly;
  final String? resumeConsignorId;
  final String? resumeContractId;

  @override
  State<ConsignorWizardScreen> createState() => _ConsignorWizardScreenState();
}

class _ConsignorWizardScreenState extends State<ConsignorWizardScreen> {
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

  final _controller = PageController();
  final _draft = _WizardDraft();
  final _representativeDraft = _WizardDraft(representativeMode: true);
  final _fileService = FileService();
  final _pdfService = ContractPdfService();
  final _wizardDraftRepo = WizardDraftRepository();
  final _detailsFormKey = GlobalKey<FormState>();
  final _representativeFormKey = GlobalKey<FormState>();
  final _auctionFormKey = GlobalKey<FormState>();
  final Object _leaveGuardToken = Object();

  Timer? _searchDebounce;
  int _step = 0;
  bool _saving = false;
  bool _searching = false;
  bool _guardRegistered = false;
  bool? _resumeContractOnly;
  String? _activeContractId;
  String? _generatedPdfPath;
  bool _generatedPdfIncludesSignatures = false;
  List<CustomerLookupResult> _matches = const [];

  bool get _isContractOnly => _resumeContractOnly ?? widget.contractOnly;

  List<_WizardStep> get _steps => _isContractOnly
      ? const [
          _WizardStep.existingCustomer,
          _WizardStep.auctions,
          _WizardStep.representative,
          _WizardStep.identityFiles,
          _WizardStep.productFiles,
          _WizardStep.fullReview,
          _WizardStep.signatures,
        ]
      : [
          _WizardStep.existingCustomer,
          _WizardStep.consignorType,
          _WizardStep.details,
          _WizardStep.contractDecision,
          if (_draft.createContract) ...const [
            _WizardStep.auctions,
            _WizardStep.representative,
            _WizardStep.identityFiles,
            _WizardStep.productFiles,
            _WizardStep.fullReview,
            _WizardStep.signatures,
          ],
        ];

  _WizardStep get _currentStep => _steps[_step];

  int get _businessStepNumber {
    return switch (_currentStep) {
      _WizardStep.existingCustomer => 1,
      _WizardStep.consignorType => 2,
      _WizardStep.details => 3,
      _WizardStep.contractDecision => 4,
      _WizardStep.auctions => 5,
      _WizardStep.representative => 6,
      _WizardStep.identityFiles => 7,
      _WizardStep.productFiles => 8,
      _WizardStep.fullReview => 9,
      _WizardStep.signatures => 10,
    };
  }

  bool get _hasCreationProgress {
    return _step > 0 ||
        _draft.hasMeaningfulInput ||
        _draft.selectedAuctions.isNotEmpty ||
        _draft.uploads.isNotEmpty ||
        _representativeDraft.hasMeaningfulInput;
  }

  @override
  void initState() {
    super.initState();
    _activeContractId = widget.resumeContractId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final appState = context.read<AppState>();
      await appState.refreshAuctions(silent: false);
      await appState.refreshPhonePrefixes(silent: true);
      if (!mounted) return;
      await _restoreDraftProgress();
      if (!mounted) return;
      _registerLeaveGuard();
    });
  }

  Future<void> _restoreDraftProgress() async {
    final resumeConsignorId = widget.resumeConsignorId;
    final resumeContractId = widget.resumeContractId;

    if (resumeConsignorId == null && resumeContractId == null) {
      return;
    }

    final appState = context.read<AppState>();
    final savedState = resumeContractId != null
        ? _wizardDraftRepo.getByContractId(resumeContractId)
        : resumeConsignorId == null
            ? null
            : _wizardDraftRepo.getByConsignorId(resumeConsignorId);

    if (savedState != null) {
      _restoreFromSavedWizardState(savedState);
    } else {
      _restoreFromSavedRecords(
        appState,
        consignorId: resumeConsignorId,
        contractId: resumeContractId,
      );
    }

    final safeStep = _step.clamp(0, _steps.length - 1);
    _step = safeStep;
    if (_controller.hasClients) {
      _controller.jumpToPage(safeStep);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _restoreFromSavedWizardState(
    Map<String, dynamic> savedState,
  ) {
    _resumeContractOnly = _asBool(savedState['contractOnly']) ?? _isContractOnly;
    final savedContractId = savedState['contractId']?.toString().trim();
    _activeContractId = savedContractId == null || savedContractId.isEmpty
        ? null
        : savedContractId;
    _generatedPdfPath = savedState['generatedPdfPath']?.toString();
    _generatedPdfIncludesSignatures =
        _asBool(savedState['generatedPdfIncludesSignatures']) ?? false;

    final ownerJson = _asMap(savedState['draft']);
    if (ownerJson != null) {
      _draft.restoreFromResumeJson(ownerJson);
    }

    final representativeJson = _asMap(savedState['representativeDraft']);
    if (representativeJson != null) {
      _representativeDraft.restoreFromResumeJson(representativeJson);
    }

    final consignorId = savedState['consignorId']?.toString();
    if ((_draft.localConsignorId == null || _draft.localConsignorId!.isEmpty) &&
        consignorId != null &&
        consignorId.isNotEmpty) {
      _draft.localConsignorId = consignorId;
    }

    final stepName = savedState['step']?.toString();
    final stepFromName = _wizardStepFromName(stepName);
    if (stepFromName != null && _steps.contains(stepFromName)) {
      _step = _steps.indexOf(stepFromName);
    } else {
      final fallback = _asInt(savedState['stepIndex']) ?? 0;
      _step = fallback.clamp(0, _steps.length - 1);
    }
  }

  void _restoreFromSavedRecords(
    AppState appState, {
    String? consignorId,
    String? contractId,
  }) {
    final consignor =
        consignorId == null ? null : appState.consignorById(consignorId);
    final contract = contractId == null ? null : appState.contractById(contractId);

    if (consignor != null) {
      _draft.applyPrefill(consignor);
      _draft.localConsignorId = consignor.id;
      _draft.usesExistingCustomer = consignor.existingCustomerId != null ||
          consignor.systemReferenceCustomer > 0 ||
          consignor.systemReferenceConsignor > 0;
    }

    if (contract != null) {
      _resumeContractOnly = widget.contractOnly;
      _activeContractId = contract.id;
      _draft.createContract = true;
      _draft.selectedAuctions = _auctionOptionsFromContract(contract);
      _draft.uploads
        ..clear()
        ..addAll(contract.uploads.map((upload) => upload.copyWith()));
      _generatedPdfPath = contract.pdfPath.trim().isEmpty ? null : contract.pdfPath;
      _generatedPdfIncludesSignatures = false;
      final reviewStep = _steps.indexOf(_WizardStep.fullReview);
      _step = reviewStep >= 0 ? reviewStep : _steps.length - 1;
    } else if (consignor != null) {
      final detailsStep = _steps.indexOf(_WizardStep.details);
      _step = detailsStep >= 0 ? detailsStep : 0;
    }
  }

  List<AuctionOption> _auctionOptionsFromContract(ContractRecord contract) {
    return [
      for (var index = 0; index < contract.auctionIds.length; index++)
        AuctionOption(
          auctionId: contract.auctionIds[index],
          auctionNumber: 0,
          auctionType: 0,
          displayName: index < contract.auctionDisplayNames.length &&
                  contract.auctionDisplayNames[index].trim().isNotEmpty
              ? contract.auctionDisplayNames[index]
              : 'Auction ${contract.auctionIds[index]}',
        ),
    ];
  }

  Future<void> _saveWizardResumeState({
    required String consignorId,
    String? contractId,
  }) async {
    _draft.localConsignorId = consignorId;
    _activeContractId = contractId ?? _activeContractId;

    final state = <String, dynamic>{
      'schemaVersion': 1,
      'contractOnly': _isContractOnly,
      'step': _currentStep.name,
      'stepIndex': _step,
      'businessStepNumber': _businessStepNumber,
      'consignorId': consignorId,
      'contractId': _activeContractId,
      'generatedPdfPath': _generatedPdfPath,
      'generatedPdfIncludesSignatures': _generatedPdfIncludesSignatures,
      'draft': _draft.toResumeJson(),
      'representativeDraft': _representativeDraft.toResumeJson(),
      'savedAtUtc': DateTime.now().toUtc().toIso8601String(),
    };

    if (_activeContractId != null && _activeContractId!.trim().isNotEmpty) {
      await _wizardDraftRepo.saveForContract(
        contractId: _activeContractId!,
        state: state,
      );
    } else {
      await _wizardDraftRepo.saveForConsignor(
        consignorId: consignorId,
        state: state,
      );
    }
  }

  Future<void> _clearWizardResumeState({
    String? consignorId,
    String? contractId,
  }) async {
    final ownerId = consignorId ?? _draft.localConsignorId;
    final recordId = contractId ?? _activeContractId;
    if (ownerId != null && ownerId.trim().isNotEmpty) {
      await _wizardDraftRepo.deleteForConsignor(ownerId);
    }
    if (recordId != null && recordId.trim().isNotEmpty) {
      await _wizardDraftRepo.deleteForContract(recordId);
    }
  }

  _WizardStep? _wizardStepFromName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    for (final step in _WizardStep.values) {
      if (step.name == name) return step;
    }
    return null;
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static bool? _asBool(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase().trim();
    if (text == 'true') return true;
    if (text == 'false') return false;
    return null;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    _unregisterLeaveGuard();
    super.dispose();
  }

  void _registerLeaveGuard() {
    if (_guardRegistered) return;
    context.read<AppState>().registerLeaveGuard(
          token: _leaveGuardToken,
          handler: _handlePendingCreationBeforeLeave,
        );
    _guardRegistered = true;
  }

  void _unregisterLeaveGuard() {
    if (!_guardRegistered) return;
    context.read<AppState>().unregisterLeaveGuard(_leaveGuardToken);
    _guardRegistered = false;
  }

  void _goToStep(int index) {
    final next = index.clamp(0, _steps.length - 1);
    setState(() => _step = next);
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _next() {
    if (!_validateCurrentStep()) return;
    _goToStep(_step + 1);
  }

  void _back() {
    if (_step == 0) {
      _close();
      return;
    }
    _goToStep(_step - 1);
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case _WizardStep.details:
        return _detailsFormKey.currentState?.validate() ?? false;
      case _WizardStep.representative:
        if (_draft.coinsOwnedByConsignor) return true;
        return _representativeFormKey.currentState?.validate() ?? false;
      case _WizardStep.auctions:
        return _auctionFormKey.currentState?.validate() ?? false;
      default:
        return true;
    }
  }

  void _showExistingSearch() {
    setState(() => _draft.showExistingSearch = true);
  }

  void _selectNewConsignor() {
    if (_isContractOnly) return;
    setState(() {
      _draft.usesExistingCustomer = false;
      _draft.systemReferenceConsignor = 0;
      _draft.systemReferenceCustomer = 0;
      _draft.existingCustomerId = null;
      _draft.existingCustomerLabel = null;
      _draft.showExistingSearch = false;
      _matches = const [];
    });
    _goToStep(_steps.indexOf(_WizardStep.consignorType));
  }

  void _selectExisting(CustomerLookupResult result) {
    setState(() {
      _draft.applyPrefill(result.prefill);
      _draft.usesExistingCustomer = true;
      _draft.existingCustomerId = result.customerId;
      _draft.existingCustomerLabel = result.displayLabel;
      _draft.showExistingSearch = false;
      _matches = const [];
    });

    if (_isContractOnly) {
      _goToStep(_steps.indexOf(_WizardStep.auctions));
      return;
    }

    _goToStep(_steps.indexOf(_WizardStep.consignorType));
  }

  void _queueSearch(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _matches = const []);
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchExistingCustomers(query.trim()),
    );
  }

  Future<void> _searchExistingCustomers(String query) async {
    final state = context.read<AppState>();
    await state.refreshAuthSessionState(notify: false);
    if (!state.hasValidToken) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _matches = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microsoft login is required for lookup.')),
      );
      return;
    }

    try {
      final matches =
          await ApiService(state.settings, state.token).searchExistingCustomers(query);
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _matches = const [];
        _searching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Customer lookup failed: $e')),
      );
    }
  }

  Future<void> _addFiles(UploadType type, {bool fromCamera = false}) async {
    List<String> paths;

    if (fromCamera) {
      final captured = await _fileService.captureImage(
        context: context,
        type: type,
        filePrefix: type == UploadType.passport ? 'id' : 'product',
      );

      paths = captured == null ? const [] : [captured];
    } else {
      final selectedPaths = await _fileService.pickFiles(
        imagesOnly: type != UploadType.agreement,
        allowMultiple: type != UploadType.agreement,
      );

      paths = await _fileService.importFilesForUpload(selectedPaths, type);
    }

    if (paths.isEmpty) {
      return;
    }

    setState(() => _draft.addFiles(paths, type));
  }

  void _removeFile(ContractUpload upload) {
    setState(
      () => _draft.uploads.removeWhere((item) => item.localId == upload.localId),
    );
  }

  ContractRecord _buildContract(String consignorId) {
    final nowUtc = DateTime.now().toUtc();

    final auctionIds = _draft.selectedAuctions
        .map((item) => item.auctionId)
        .toList(growable: false);

    final auctionNames = _draft.selectedAuctions
        .map((item) => item.displayName)
        .toList(growable: false);

    final firstAuctionId = auctionIds.isEmpty ? null : auctionIds.first;

    final uploads = _draft.uploads.map((upload) {
      return upload.copyWith(auctionId: firstAuctionId);
    }).toList(growable: true);

    final pdfPath = _generatedPdfPath?.trim() ?? '';
    String? pdfName;

    if (pdfPath.isNotEmpty) {
      final pdfFile = File(pdfPath);
      pdfName = pdfFile.uri.pathSegments.isEmpty
          ? 'consignor_contract.pdf'
          : pdfFile.uri.pathSegments.last;

      final alreadyAdded = uploads.any(
        (upload) =>
            !upload.isDeleted &&
            upload.fileType == UploadType.agreement &&
            upload.path == pdfPath,
      );

      if (!alreadyAdded) {
        uploads.add(
          ContractUpload(
            localId:
                'agreement_${pdfName}_${nowUtc.microsecondsSinceEpoch}_${pdfPath.hashCode}',
            auctionId: firstAuctionId,
            fileName: pdfName,
            fileType: UploadType.agreement,
            path: pdfPath,
            localLastModifiedUtc: nowUtc,
          ),
        );
      }
    }

    final baseRecord = ContractRecord.empty(
      consignorId,
      auctionIds: auctionIds,
      auctionDisplayNames: auctionNames,
    );

    final persistedContractId = _activeContractId?.trim();

    return baseRecord.copyWith(
      id: persistedContractId == null || persistedContractId.isEmpty
          ? baseRecord.id
          : persistedContractId,
      uploads: uploads,
      pdfPath: pdfPath,
      pdfName: pdfName ?? baseRecord.pdfName,
      lastModifiedUtc: nowUtc,
    );
  }

  Future<Consignor> _saveConsignorLocal({required bool draft}) async {
    final state = context.read<AppState>();
    final consignor = _draft.toConsignor();
    final saved = draft
        ? await state.saveConsignorDraft(consignor)
        : await state.saveConsignor(consignor);
    _draft.localConsignorId = saved.id;
    return saved;
  }

  Future<Consignor> _saveAndTrySyncConsignor() async {
    final state = context.read<AppState>();
    var saved = await state.saveConsignor(_draft.toConsignor());
    _draft.localConsignorId = saved.id;
    if (state.hasValidToken) {
      saved = await state.syncConsignor(saved.id) ?? saved;
      _draft.localConsignorId = saved.id;
    }
    return saved;
  }

  Future<void> _saveConsignorOnly() async {
    if (_saving) return;
    if (!(_detailsFormKey.currentState?.validate() ?? true)) return;
    setState(() => _saving = true);

    try {
      final saved = await _saveAndTrySyncConsignor();
      await _clearWizardResumeState(consignorId: saved.id);
      if (!mounted) return;
      _unregisterLeaveGuard();
      context.go('/consignors/${saved.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create consignor failed: $e')),
      );
    }
  }

  Future<ContractSignatureData?> _buildSignatureData() async {
    final signer = _draft.leuSigner;
    if (signer == null || !_draft.hasCustomerSignature) return null;

    final customerSignature = await _renderCustomerSignaturePng();
    if (customerSignature == null) return null;

    return ContractSignatureData(
      leuRepresentativeName: signer.displayName,
      leuRepresentativeSignatureAsset: signer.assetPath,
      customerSignaturePng: customerSignature,
    );
  }

  Future<Uint8List?> _renderCustomerSignaturePng() async {
    if (!_draft.hasCustomerSignature) return null;

    final sourceSize = _draft.customerSignatureCanvasSize;
    final safeSourceWidth = sourceSize.width <= 0 ? 1.0 : sourceSize.width;
    final safeSourceHeight = sourceSize.height <= 0 ? 1.0 : sourceSize.height;
    const outputWidth = 900.0;
    const outputHeight = 300.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..color = Colors.black
      ..strokeWidth = 4.5
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..style = ui.PaintingStyle.stroke;

    final scaleX = outputWidth / safeSourceWidth;
    final scaleY = outputHeight / safeSourceHeight;

    for (final stroke in _draft.customerSignatureStrokes) {
      if (stroke.length < 2) continue;
      final path = ui.Path()
        ..moveTo(stroke.first.dx * scaleX, stroke.first.dy * scaleY);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * scaleX, point.dy * scaleY);
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(outputWidth.toInt(), outputHeight.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  Future<File> _createContractPdf({required bool includeSignatures}) async {
    if (_draft.selectedAuctions.isEmpty) {
      throw Exception('Select at least one auction first.');
    }

    final appState = context.read<AppState>();
    final apiService = ApiService(appState.settings, appState.token);

    final consignor = _draft.toConsignor();
    final record = _buildContract(consignor.id);
    final authorizedRepresentative =
        _draft.coinsOwnedByConsignor ? null : _representativeDraft.toConsignor();

    final signatureData = includeSignatures ? await _buildSignatureData() : null;

    if (includeSignatures && signatureData == null) {
      throw Exception(
        'Choose who will sign the PDF and add the customer signature first.',
      );
    }

    final output = await _fileService.getSuggestedPdfPath(
      'consignor_contract_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );

    return _pdfService.buildContractPdf(
      apiService: apiService,
      consignor: consignor,
      record: record,
      outputPath: output,
      authorizedRepresentative: authorizedRepresentative,
      signatureData: signatureData,
    );
  }

  Future<bool> _generatePdf({bool includeSignatures = false}) async {
    if (_saving) return false;

    setState(() => _saving = true);
    try {
      final file = await _createContractPdf(includeSignatures: includeSignatures);
      if (!mounted) return true;
      setState(() {
        _generatedPdfPath = file.path;
        _generatedPdfIncludesSignatures = includeSignatures;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF created at ${file.path}')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF generation failed: $e')),
      );
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updateCustomerSignature(List<List<Offset>> strokes, Size size) {
    setState(() {
      _draft.customerSignatureStrokes = strokes;
      _draft.customerSignatureCanvasSize = size;
      _generatedPdfIncludesSignatures = false;
    });
  }

  void _clearCustomerSignature() {
    setState(() {
      _draft.customerSignatureStrokes = <List<Offset>>[];
      _draft.customerSignatureCanvasSize = Size.zero;
      _generatedPdfIncludesSignatures = false;
    });
  }

  void _selectLeuSigner(_LeuSigner signer) {
    setState(() {
      _draft.leuSigner = signer;
      _generatedPdfIncludesSignatures = false;
    });
  }

  Future<Consignor> _saveConsignorBeforeContract(AppState state) async {
    var saved = await state.saveConsignor(_draft.toConsignor());
    _draft.localConsignorId = saved.id;

    if (!state.hasValidToken) {
      return saved;
    }

    final synced = await state.syncConsignor(saved.id);
    saved = synced ?? state.consignorById(saved.id) ?? saved;
    _draft.localConsignorId = saved.id;

    if (saved.systemReferenceConsignor <= 0) {
      final message = saved.syncErrorMessage?.trim().isNotEmpty == true
          ? saved.syncErrorMessage!
          : state.lastMessage ??
              'Consignor sync did not return a backend consignor id.';
      throw Exception(
        'Consignor must be synced before the contract can be synced. $message',
      );
    }

    return saved;
  }

  Future<void> _saveFullFlow() async {
    if (_saving) return;
    if (!(_detailsFormKey.currentState?.validate() ?? true)) return;
    if (!_draft.signatureReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose who will sign the PDF and add the customer signature first.',
          ),
        ),
      );
      return;
    }

    final state = context.read<AppState>();

    setState(() => _saving = true);

    try {
      final savedConsignor = await _saveConsignorBeforeContract(state);

      if (_generatedPdfPath == null || !_generatedPdfIncludesSignatures) {
        final file = await _createContractPdf(includeSignatures: true);
        _generatedPdfPath = file.path;
        _generatedPdfIncludesSignatures = true;
      }

      final contract = _buildContract(savedConsignor.id);
      _activeContractId = contract.id;
      await state.saveContract(contract);

      if (state.hasValidToken && contract.auctionId != null) {
        final synced = await state.syncContract(savedConsignor.id, contract.auctionId!);
        final error = synced?.syncErrorMessage;
        if (synced == null || (error != null && error.trim().isNotEmpty)) {
          throw Exception(error ?? state.lastMessage ?? 'Contract sync failed.');
        }
      }

      await _clearWizardResumeState(
        consignorId: savedConsignor.id,
        contractId: contract.id,
      );

      if (!mounted) return;
      _unregisterLeaveGuard();
      context.go('/contracts/${savedConsignor.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create contract failed: $e')),
      );
    }
  }

  Future<bool> _handlePendingCreationBeforeLeave() async {
    if (!_hasCreationProgress) return true;

    final appState = context.read<AppState>();

    final action = await showDialog<_CreationExitAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Discard creation progress?'),
          content: const Text(
            'Close without saving or add the current progress to drafts.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_CreationExitAction.closeWithoutSaving),
              child: const Text('Close without saving'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_CreationExitAction.addToDraft),
              child: const Text('Add to draft'),
            ),
          ],
        );
      },
    );

    switch (action) {
      case _CreationExitAction.closeWithoutSaving:
        return true;
      case _CreationExitAction.addToDraft:
        final consignor = await _saveConsignorLocal(draft: true);
        if (_businessStepNumber <= 4) {
          await _saveWizardResumeState(consignorId: consignor.id);
        } else {
          final contract = _buildContract(consignor.id);
          _activeContractId = contract.id;
          await appState.saveContract(contract);
          await _saveWizardResumeState(
            consignorId: consignor.id,
            contractId: contract.id,
          );
        }
        return true;
      case null:
        return false;
    }
  }

  Future<void> _close() async {
    final canLeave = await _handlePendingCreationBeforeLeave();
    if (!mounted || !canLeave) return;
    _unregisterLeaveGuard();
    context.go(_isContractOnly ? '/contracts' : '/consignors');
  }

  @override
  Widget build(BuildContext context) {
    final title = _isContractOnly ? 'Create contract' : 'New consignor';
    return AppShell(
      title: title,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StepIndicator(
                  current: _step + 1,
                  total: _steps.length,
                  businessStep: _businessStepNumber,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _close,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Close'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: PageView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              children: _steps.map(_buildStep).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(_WizardStep step) {
    return switch (step) {
      _WizardStep.existingCustomer => _ExistingCustomerStep(
          contractOnly: _isContractOnly,
          searching: _searching,
          showSearch: _draft.showExistingSearch,
          matches: _matches,
          onFindExisting: _showExistingSearch,
          onSearchChanged: _queueSearch,
          onExistingSelected: _selectExisting,
          onNewConsignor: _selectNewConsignor,
        ),
      _WizardStep.consignorType => _ConsignorTypeStep(
          initialValue: _draft.isLegalEntity,
          onSelected: (isLegalEntity) {
            setState(() {
              _draft.isLegalEntity = isLegalEntity;
              if (isLegalEntity &&
                  _draft.prefillVatNumber.isNotEmpty &&
                  _draft.vatNumber.isEmpty) {
                _draft.vatNumber = _draft.prefillVatNumber;
              }
            });
            _next();
          },
          onBack: _back,
        ),
      _WizardStep.details => Consumer<AppState>(
          builder: (context, state, _) => _DetailsStep(
            formKey: _detailsFormKey,
            draft: _draft,
            titleOptions: _titleOptions,
            salutationOptions: _salutationOptions,
            correspondenceOptions: _correspondenceOptions,
            phonePrefixes: state.phonePrefixes,
            onChanged: () => setState(() {}),
            onBack: _back,
            onNext: _next,
          ),
        ),
      _WizardStep.contractDecision => _ContractDecisionStep(
          draft: _draft,
          saving: _saving,
          onBack: _back,
          onSaveConsignorOnly: _saveConsignorOnly,
          onCreateContract: () {
            setState(() => _draft.createContract = true);
            _goToStep(_step + 1);
          },
        ),
      _WizardStep.auctions => _AuctionStep(
          formKey: _auctionFormKey,
          draft: _draft,
          auctions: context.watch<AppState>().auctions,
          onChanged: (value) => setState(() => _draft.selectedAuctions = value),
          onBack: _back,
          onNext: _next,
        ),
      _WizardStep.representative => Consumer<AppState>(
          builder: (context, state, _) => _RepresentativeStep(
            formKey: _representativeFormKey,
            ownerDraft: _draft,
            representativeDraft: _representativeDraft,
            titleOptions: _titleOptions,
            salutationOptions: _salutationOptions,
            correspondenceOptions: _correspondenceOptions,
            phonePrefixes: state.phonePrefixes,
            onChanged: () => setState(() {}),
            onBack: _back,
            onNext: _next,
          ),
        ),
      _WizardStep.identityFiles => _FileStep(
          title: 'Passport and ID',
          files: _draft.passportFiles,
          onAdd: () => _addFiles(UploadType.passport),
          onCapture: () => _addFiles(UploadType.passport, fromCamera: true),
          onOpen: _fileService.open,
          onRemove: _removeFile,
          onBack: _back,
          onNext: _next,
        ),
      _WizardStep.productFiles => _FileStep(
          title: 'Product pictures',
          files: _draft.productFiles,
          onAdd: () => _addFiles(UploadType.product),
          onCapture: () => _addFiles(UploadType.product, fromCamera: true),
          onOpen: _fileService.open,
          onRemove: _removeFile,
          onBack: _back,
          onNext: _next,
        ),
      _WizardStep.fullReview => _FullReviewStep(
          draft: _draft,
          representative: _draft.coinsOwnedByConsignor ? null : _representativeDraft,
          saving: _saving,
          generatedPdfPath: _generatedPdfPath,
          onBack: _back,
          onGeneratePdf: () => _generatePdf(),
          onOpenPdf: _generatedPdfPath == null
              ? null
              : () => _fileService.open(_generatedPdfPath!),
          onOpenFile: _fileService.open,
          onContinue: _next,
        ),
      _WizardStep.signatures => _SignatureStep(
          draft: _draft,
          saving: _saving,
          generatedPdfPath: _generatedPdfPath,
          onBack: _back,
          onSignerChanged: _selectLeuSigner,
          onSignatureChanged: _updateCustomerSignature,
          onClearSignature: _clearCustomerSignature,
          onGeneratePdf: () => _generatePdf(includeSignatures: true),
          onOpenPdf: _generatedPdfPath == null || !_generatedPdfIncludesSignatures
              ? null
              : () => _fileService.open(_generatedPdfPath!),
          onSubmit: _saveFullFlow,
        ),
    };
  }
}

enum _WizardStep {
  existingCustomer,
  consignorType,
  details,
  contractDecision,
  auctions,
  representative,
  identityFiles,
  productFiles,
  fullReview,
  signatures,
}

enum _CreationExitAction { closeWithoutSaving, addToDraft }

enum _LeuSigner {
  larsRutten(
    displayName: 'Lars Rutten',
    assetPath: 'assets/signatures/signature_lars_rutten.jpg',
  ),
  yvesGunzenreiner(
    displayName: 'Yves Gunzenreiner',
    assetPath: 'assets/signatures/signature_yves_gunzenreiner.png',
  );

  const _LeuSigner({required this.displayName, required this.assetPath});

  final String displayName;
  final String assetPath;
}

class _WizardDraft {
  _WizardDraft({this.representativeMode = false});

  final bool representativeMode;
  String? localConsignorId;
  bool usesExistingCustomer = false;
  bool showExistingSearch = false;
  bool createContract = false;
  bool coinsOwnedByConsignor = true;
  int systemReferenceConsignor = 0;
  int systemReferenceCustomer = 0;
  int? existingCustomerId;
  String? existingCustomerLabel;
  String prefillVatNumber = '';

  bool isLegalEntity = false;
  String tradingName = '';
  int? title;
  int? salutation;
  String firstName = '';
  String lastName = '';
  DateTime? dateOfBirth;
  String nationalityIso3 = '';
  String nationalityName = '';
  bool vatLiability = false;
  String vatNumber = '';
  String eori = '';
  String phonePrefix = '';
  int? phonePrefixOriginId;
  String phone = '';
  String email = '';
  String street = '';
  String streetNumber = '';
  String streetAddressOptional = '';
  String postalCode = '';
  String city = '';
  String adminRegion = '';
  String countryIso3 = '';
  String countryName = '';
  String bankName = '';
  String iban = '';
  String? correspondence = 'en';
  bool checkedByLeu = true;
  bool newsletterSubscribed = true;
  bool ancientCoinsSubscribed = false;
  bool worldCoinsSubscribed = false;
  String collectingArea = '';
  String references = '';
  double creditLimit = 0;
  double? discount;

  List<AuctionOption> selectedAuctions = const [];
  final List<ContractUpload> uploads = [];
  _LeuSigner? leuSigner;
  List<List<Offset>> customerSignatureStrokes = <List<Offset>>[];
  Size customerSignatureCanvasSize = Size.zero;

  bool get hasCustomerSignature =>
      customerSignatureStrokes.any((stroke) => stroke.length > 1);

  bool get signatureReady => leuSigner != null && hasCustomerSignature;

  bool get hasMeaningfulInput {
    return [
      tradingName,
      firstName,
      lastName,
      phone,
      email,
      street,
      city,
      iban,
    ].any((value) => value.trim().isNotEmpty);
  }

  List<ContractUpload> get passportFiles => uploads
      .where((e) => e.fileType == UploadType.passport && !e.isDeleted)
      .toList(growable: false);
  List<ContractUpload> get productFiles => uploads
      .where((e) => e.fileType == UploadType.product && !e.isDeleted)
      .toList(growable: false);
  List<ContractUpload> get registrationFiles => uploads
      .where((e) => e.fileType == UploadType.agreement && !e.isDeleted)
      .toList(growable: false);

  Map<String, dynamic> toResumeJson() => {
        'localConsignorId': localConsignorId,
        'representativeMode': representativeMode,
        'usesExistingCustomer': usesExistingCustomer,
        'showExistingSearch': showExistingSearch,
        'createContract': createContract,
        'coinsOwnedByConsignor': coinsOwnedByConsignor,
        'systemReferenceConsignor': systemReferenceConsignor,
        'systemReferenceCustomer': systemReferenceCustomer,
        'existingCustomerId': existingCustomerId,
        'existingCustomerLabel': existingCustomerLabel,
        'prefillVatNumber': prefillVatNumber,
        'isLegalEntity': isLegalEntity,
        'tradingName': tradingName,
        'title': title,
        'salutation': salutation,
        'firstName': firstName,
        'lastName': lastName,
        'dateOfBirth': dateOfBirth?.toIso8601String(),
        'nationalityIso3': nationalityIso3,
        'nationalityName': nationalityName,
        'vatLiability': vatLiability,
        'vatNumber': vatNumber,
        'eori': eori,
        'phonePrefix': phonePrefix,
        'phonePrefixOriginId': phonePrefixOriginId,
        'phone': phone,
        'email': email,
        'street': street,
        'streetNumber': streetNumber,
        'streetAddressOptional': streetAddressOptional,
        'postalCode': postalCode,
        'city': city,
        'adminRegion': adminRegion,
        'countryIso3': countryIso3,
        'countryName': countryName,
        'bankName': bankName,
        'iban': iban,
        'correspondence': correspondence,
        'checkedByLeu': checkedByLeu,
        'newsletterSubscribed': newsletterSubscribed,
        'ancientCoinsSubscribed': ancientCoinsSubscribed,
        'worldCoinsSubscribed': worldCoinsSubscribed,
        'collectingArea': collectingArea,
        'references': references,
        'creditLimit': creditLimit,
        'discount': discount,
        'selectedAuctions': selectedAuctions
            .map(
              (auction) => {
                'auctionId': auction.auctionId,
                'auctionNumber': auction.auctionNumber,
                'auctionType': auction.auctionType,
                'displayName': auction.displayName,
              },
            )
            .toList(),
        'uploads': uploads.map((upload) => upload.toJson()).toList(),
        'leuSigner': leuSigner?.name,
        'customerSignatureCanvasSize': {
          'width': customerSignatureCanvasSize.width,
          'height': customerSignatureCanvasSize.height,
        },
        'customerSignatureStrokes': customerSignatureStrokes
            .map(
              (stroke) => stroke
                  .map((point) => {'dx': point.dx, 'dy': point.dy})
                  .toList(),
            )
            .toList(),
      };

  void restoreFromResumeJson(Map<String, dynamic> json) {
    localConsignorId = _stringOrNull(json['localConsignorId']);
    usesExistingCustomer = _toBool(json['usesExistingCustomer']) ?? false;
    showExistingSearch = _toBool(json['showExistingSearch']) ?? false;
    createContract = _toBool(json['createContract']) ?? false;
    coinsOwnedByConsignor = _toBool(json['coinsOwnedByConsignor']) ?? true;
    systemReferenceConsignor = _toInt(json['systemReferenceConsignor']) ?? 0;
    systemReferenceCustomer = _toInt(json['systemReferenceCustomer']) ?? 0;
    existingCustomerId = _toInt(json['existingCustomerId']);
    existingCustomerLabel = _stringOrNull(json['existingCustomerLabel']);
    prefillVatNumber = _toString(json['prefillVatNumber']);
    isLegalEntity = _toBool(json['isLegalEntity']) ?? false;
    tradingName = _toString(json['tradingName']);
    title = _toInt(json['title']);
    salutation = _toInt(json['salutation']);
    firstName = _toString(json['firstName']);
    lastName = _toString(json['lastName']);
    dateOfBirth = DateTime.tryParse(_toString(json['dateOfBirth']));
    nationalityIso3 = _toString(json['nationalityIso3']);
    nationalityName = _toString(json['nationalityName']);
    vatLiability = _toBool(json['vatLiability']) ?? false;
    vatNumber = _toString(json['vatNumber']);
    eori = _toString(json['eori']);
    phonePrefix = _toString(json['phonePrefix']);
    phonePrefixOriginId = _toInt(json['phonePrefixOriginId']);
    phone = _toString(json['phone']);
    email = _toString(json['email']);
    street = _toString(json['street']);
    streetNumber = _toString(json['streetNumber']);
    streetAddressOptional = _toString(json['streetAddressOptional']);
    postalCode = _toString(json['postalCode']);
    city = _toString(json['city']);
    adminRegion = _toString(json['adminRegion']);
    countryIso3 = _toString(json['countryIso3']);
    countryName = _toString(json['countryName']);
    bankName = _toString(json['bankName']);
    iban = _toString(json['iban']);
    correspondence = _stringOrNull(json['correspondence']) ?? 'en';
    checkedByLeu = _toBool(json['checkedByLeu']) ?? true;
    newsletterSubscribed = _toBool(json['newsletterSubscribed']) ?? true;
    ancientCoinsSubscribed = _toBool(json['ancientCoinsSubscribed']) ?? false;
    worldCoinsSubscribed = _toBool(json['worldCoinsSubscribed']) ?? false;
    collectingArea = _toString(json['collectingArea']);
    references = _toString(json['references']);
    creditLimit = _toDouble(json['creditLimit']) ?? 0;
    discount = _toDouble(json['discount']);

    selectedAuctions = (((json['selectedAuctions'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => AuctionOption.fromJson(item.cast<String, dynamic>()))
        .where((auction) => auction.auctionId > 0)
        .toList(growable: false));

    uploads
      ..clear()
      ..addAll((((json['uploads'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => ContractUpload.fromJson(item.cast<String, dynamic>()))));

    leuSigner = _leuSignerFromName(_stringOrNull(json['leuSigner']));

    final sizeJson = json['customerSignatureCanvasSize'];
    if (sizeJson is Map) {
      customerSignatureCanvasSize = Size(
        _toDouble(sizeJson['width']) ?? 0,
        _toDouble(sizeJson['height']) ?? 0,
      );
    } else {
      customerSignatureCanvasSize = Size.zero;
    }

    customerSignatureStrokes = (((json['customerSignatureStrokes'] as List?) ?? const [])
        .whereType<List>()
        .map(
          (stroke) => stroke
              .whereType<Map>()
              .map(
                (point) => Offset(
                  _toDouble(point['dx']) ?? 0,
                  _toDouble(point['dy']) ?? 0,
                ),
              )
              .toList(),
        )
        .where((stroke) => stroke.isNotEmpty)
        .toList());
  }

  static _LeuSigner? _leuSignerFromName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    for (final signer in _LeuSigner.values) {
      if (signer.name == name) return signer;
    }
    return null;
  }

  static String _toString(Object? value) => value?.toString() ?? '';

  static String? _stringOrNull(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _toInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static bool? _toBool(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase().trim();
    if (text == 'true') return true;
    if (text == 'false') return false;
    return null;
  }

  void applyPrefill(Consignor prefill) {
    localConsignorId = prefill.id;
    systemReferenceConsignor = prefill.systemReferenceConsignor;
    systemReferenceCustomer = prefill.systemReferenceCustomer;
    existingCustomerId = prefill.existingCustomerId ??
        (prefill.systemReferenceCustomer > 0
            ? prefill.systemReferenceCustomer
            : existingCustomerId);
    existingCustomerLabel = prefill.existingCustomerLabel ?? existingCustomerLabel;
    isLegalEntity = prefill.isLegalEntity || prefill.tradingName.trim().isNotEmpty;
    tradingName = prefill.tradingName;
    title = prefill.consignorInfo.title;
    salutation = prefill.consignorInfo.salutation;
    firstName = prefill.consignorInfo.firstName;
    lastName = prefill.consignorInfo.lastName;
    dateOfBirth = prefill.consignorInfo.dateOfBirth;
    nationalityIso3 = prefill.consignorInfo.nationalityIso3;
    nationalityName = prefill.consignorInfo.nationalityName;
    vatLiability = prefill.vatLiability;
    prefillVatNumber = prefill.vatNumber.trim();
    vatNumber = prefillVatNumber;
    eori = prefill.eori;
    phonePrefix = prefill.phonePrefix;
    phonePrefixOriginId = prefill.phonePrefixOriginId;
    phone = prefill.phoneNumber;
    email = prefill.emailAddress;
    street = prefill.consignorAddress.streetAddress;
    streetNumber = prefill.consignorAddress.streetNumber;
    streetAddressOptional = prefill.consignorAddress.streetAddressOptional;
    postalCode = prefill.consignorAddress.postalCode;
    city = prefill.consignorAddress.city;
    adminRegion = prefill.consignorAddress.adminRegion;
    countryIso3 = prefill.consignorAddress.countryIso3;
    countryName = prefill.consignorAddress.countryName;
    bankName = prefill.bankingDetails.bankName;
    iban = prefill.bankingDetails.accountNumber;
    correspondence = prefill.correspondence ?? correspondence;
    checkedByLeu = prefill.checkedByLeu;
    newsletterSubscribed = prefill.newsletterSubscribed;
    ancientCoinsSubscribed = prefill.ancientCoinsSubscribed;
    worldCoinsSubscribed = prefill.worldCoinsSubscribed;
    collectingArea = prefill.collectingArea;
    references = prefill.references;
    creditLimit = prefill.creditLimit;
    discount = prefill.discount;
  }

  void addFiles(List<String> paths, UploadType type) {
    final now = DateTime.now().toUtc();
    for (final path in paths) {
      final file = File(path);
      final fileName =
          file.uri.pathSegments.isEmpty ? path : file.uri.pathSegments.last;
      if (uploads.any(
        (item) => item.path == path && item.fileType == type && !item.isDeleted,
      )) {
        continue;
      }
      uploads.add(
        ContractUpload(
          localId: '${type.name}_${now.microsecondsSinceEpoch}_${path.hashCode}',
          fileName: fileName,
          fileType: type,
          path: path,
          localLastModifiedUtc: now,
        ),
      );
    }
  }

  Consignor toConsignor() {
    final consignor = Consignor.empty();
    final persistedId = localConsignorId?.trim();
    if (persistedId != null && persistedId.isNotEmpty) {
      consignor.id = persistedId;
    }
    consignor.systemReferenceConsignor = systemReferenceConsignor;
    consignor.systemReferenceCustomer = systemReferenceCustomer;
    consignor.paymentOption = PaymentOption.bankTransfer;
    consignor.existingCustomerId = existingCustomerId;
    consignor.existingCustomerLabel = existingCustomerLabel;
    consignor.isLegalEntity = isLegalEntity;
    consignor.tradingName = tradingName.trim();
    consignor.consignorInfo.title = title;
    consignor.consignorInfo.salutation = salutation;
    consignor.consignorInfo.firstName = firstName.trim();
    consignor.consignorInfo.lastName = lastName.trim();
    consignor.consignorInfo.owner = coinsOwnedByConsignor;
    consignor.consignorInfo.dateOfBirth = dateOfBirth;
    consignor.consignorInfo.nationalityIso3 = nationalityIso3;
    consignor.consignorInfo.nationalityName = nationalityName;
    consignor.vatLiability = vatLiability;
    consignor.vatNumber = vatNumber.trim();
    consignor.eori = eori.trim();
    consignor.phonePrefix = phonePrefix.trim();
    consignor.phonePrefixOriginId = phonePrefixOriginId;
    consignor.phoneNumber = phone.trim();
    consignor.emailAddress = email.trim();
    consignor.consignorAddress.streetAddress = street.trim();
    consignor.consignorAddress.streetNumber = streetNumber.trim();
    consignor.consignorAddress.streetAddressOptional = streetAddressOptional.trim();
    consignor.consignorAddress.postalCode = postalCode.trim();
    consignor.consignorAddress.city = city.trim();
    consignor.consignorAddress.adminRegion = adminRegion.trim();
    consignor.consignorAddress.countryIso3 = countryIso3;
    consignor.consignorAddress.countryName = countryName;
    consignor.bankingDetails.bankName = bankName.trim();
    consignor.bankingDetails.accountNumber = iban.trim();
    consignor.bankingDetails.isIban = true;
    consignor.bankingDetails.clearingNumber = '';
    consignor.bankingDetails.bicSwift = '';
    consignor.correspondence = correspondence;
    consignor.checkedByLeu = checkedByLeu;
    consignor.newsletterSubscribed = newsletterSubscribed;
    consignor.ancientCoinsSubscribed = ancientCoinsSubscribed;
    consignor.worldCoinsSubscribed = worldCoinsSubscribed;
    consignor.collectingArea = collectingArea.trim();
    consignor.references = references.trim();
    consignor.creditLimit = creditLimit;
    consignor.discount = discount;
    consignor.ensureGeneratedCredentials();
    return consignor;
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.current,
    required this.total,
    required this.businessStep,
  });

  final int current;
  final int total;
  final int businessStep;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step $businessStep', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: current / total),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(icon, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExistingCustomerStep extends StatelessWidget {
  const _ExistingCustomerStep({
    required this.contractOnly,
    required this.searching,
    required this.showSearch,
    required this.matches,
    required this.onFindExisting,
    required this.onSearchChanged,
    required this.onExistingSelected,
    required this.onNewConsignor,
  });

  final bool contractOnly;
  final bool searching;
  final bool showSearch;
  final List<CustomerLookupResult> matches;
  final VoidCallback onFindExisting;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<CustomerLookupResult> onExistingSelected;
  final VoidCallback onNewConsignor;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(
          contractOnly ? 'Select an existing consignor' : 'Existing or new consignor?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        _OptionCard(
          title: contractOnly ? 'Find existing consignor' : 'Existing customer',
          icon: Icons.search_rounded,
          onTap: onFindExisting,
        ),
        if (showSearch) ...[
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              labelText: 'Search existing customers',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: onSearchChanged,
          ),
        ],
        if (showSearch && matches.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Results',
            child: Column(
              children: [
                for (final match in matches)
                  ListTile(
                    title: Text(match.displayLabel),
                    subtitle: Text(match.searchSubtitle),
                    onTap: () => onExistingSelected(match),
                  ),
              ],
            ),
          ),
        ],
        if (!contractOnly) ...[
          const SizedBox(height: 18),
          _OptionCard(
            title: 'New consignor',
            icon: Icons.person_add_alt_1_outlined,
            onTap: onNewConsignor,
          ),
        ],
      ],
    );
  }
}

class _ConsignorTypeStep extends StatelessWidget {
  const _ConsignorTypeStep({
    required this.initialValue,
    required this.onSelected,
    required this.onBack,
  });

  final bool initialValue;
  final ValueChanged<bool> onSelected;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text('Legal entity or individual?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _OptionCard(
          title: 'Individual (person)',
          icon: Icons.person_outline,
          onTap: () => onSelected(false),
        ),
        const SizedBox(height: 12),
        _OptionCard(
          title: 'Company or legal entity',
          icon: Icons.business_outlined,
          onTap: () => onSelected(true),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: onBack, child: const Text('Back')),
        ),
      ],
    );
  }
}

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    required this.formKey,
    required this.draft,
    required this.titleOptions,
    required this.salutationOptions,
    required this.correspondenceOptions,
    required this.phonePrefixes,
    required this.onChanged,
    required this.onBack,
    required this.onNext,
  });

  final GlobalKey<FormState> formKey;
  final _WizardDraft draft;
  final List<_LookupOption<int>> titleOptions;
  final List<_LookupOption<int>> salutationOptions;
  final List<_LookupOption<String>> correspondenceOptions;
  final List<PhonePrefix> phonePrefixes;
  final VoidCallback onChanged;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        children: [
          Text(
            draft.isLegalEntity ? 'Company details' : 'Personal details',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          _ConsignorDetailsForm(
            draft: draft,
            titleOptions: titleOptions,
            salutationOptions: salutationOptions,
            correspondenceOptions: correspondenceOptions,
            phonePrefixes: phonePrefixes,
            onChanged: onChanged,
          ),
          const SizedBox(height: 20),
          _WizardButtons(onBack: onBack, onNext: onNext),
        ],
      ),
    );
  }
}

class _RepresentativeStep extends StatelessWidget {
  const _RepresentativeStep({
    required this.formKey,
    required this.ownerDraft,
    required this.representativeDraft,
    required this.titleOptions,
    required this.salutationOptions,
    required this.correspondenceOptions,
    required this.phonePrefixes,
    required this.onChanged,
    required this.onBack,
    required this.onNext,
  });

  final GlobalKey<FormState> formKey;
  final _WizardDraft ownerDraft;
  final _WizardDraft representativeDraft;
  final List<_LookupOption<int>> titleOptions;
  final List<_LookupOption<int>> salutationOptions;
  final List<_LookupOption<String>> correspondenceOptions;
  final List<PhonePrefix> phonePrefixes;
  final VoidCallback onChanged;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        children: [
          Text('Authorized representative', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Ownership',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('The consignor owns the coins'),
              value: ownerDraft.coinsOwnedByConsignor,
              onChanged: (value) {
                ownerDraft.coinsOwnedByConsignor = value;
                onChanged();
              },
            ),
          ),
          if (!ownerDraft.coinsOwnedByConsignor) ...[
            const SizedBox(height: 16),
            _ConsignorDetailsForm(
              draft: representativeDraft,
              titleOptions: titleOptions,
              salutationOptions: salutationOptions,
              correspondenceOptions: correspondenceOptions,
              phonePrefixes: phonePrefixes,
              onChanged: onChanged,
            ),
          ],
          const SizedBox(height: 20),
          _WizardButtons(onBack: onBack, onNext: onNext),
        ],
      ),
    );
  }
}

class _ConsignorDetailsForm extends StatelessWidget {
  const _ConsignorDetailsForm({
    required this.draft,
    required this.titleOptions,
    required this.salutationOptions,
    required this.correspondenceOptions,
    required this.phonePrefixes,
    required this.onChanged,
  });

  final _WizardDraft draft;
  final List<_LookupOption<int>> titleOptions;
  final List<_LookupOption<int>> salutationOptions;
  final List<_LookupOption<String>> correspondenceOptions;
  final List<PhonePrefix> phonePrefixes;
  final VoidCallback onChanged;

  String get _keyPrefix => draft.representativeMode ? 'representative' : 'owner';

  PhonePrefix? _selectedPhonePrefix() {
    final byOrigin = draft.phonePrefixOriginId == null
        ? null
        : phonePrefixes
            .where((item) => item.originId == draft.phonePrefixOriginId)
            .firstOrNull;
    if (byOrigin != null) return byOrigin;
    return phonePrefixes.where((item) => item.dialCode == draft.phonePrefix).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final countries = context.watch<AppState>().countries;
    return Column(
      children: [
        SectionCard(
          title: draft.isLegalEntity ? 'Company / person' : 'Person',
          child: _ResponsiveFormGrid(
            children: [
              if (!draft.representativeMode)
                _BooleanCard(
                  key: ValueKey('$_keyPrefix-field-legal-entity'),
                  title: 'Legal entity',
                  value: draft.isLegalEntity,
                  onChanged: (value) {
                    draft.isLegalEntity = value;
                    if (value &&
                        draft.prefillVatNumber.isNotEmpty &&
                        draft.vatNumber.isEmpty) {
                      draft.vatNumber = draft.prefillVatNumber;
                    }
                    onChanged();
                  },
                ),
              SearchableSelectFormField<_LookupOption<int>>(
                key: ValueKey('$_keyPrefix-field-title'),
                label: 'Title',
                items: titleOptions,
                itemLabel: (item) => item.label,
                initialValue: titleOptions
                    .where((item) => item.value == draft.title)
                    .firstOrNull,
                onChanged: (value) => draft.title = value?.value,
              ),
              SearchableSelectFormField<_LookupOption<int>>(
                key: ValueKey('$_keyPrefix-field-salutation'),
                label: 'Salutation',
                items: salutationOptions,
                itemLabel: (item) => item.label,
                initialValue: salutationOptions
                    .where((item) => item.value == draft.salutation)
                    .firstOrNull,
                onChanged: (value) => draft.salutation = value?.value,
              ),
              TextFormField(
                key: ValueKey('$_keyPrefix-field-first-name'),
                initialValue: draft.firstName,
                decoration: const InputDecoration(labelText: 'First name *'),
                validator: (value) => FormValidators.requiredText(value, 'First name'),
                onChanged: (value) => draft.firstName = value,
              ),
              TextFormField(
                key: ValueKey('$_keyPrefix-field-last-name'),
                initialValue: draft.lastName,
                decoration: const InputDecoration(labelText: 'Last name *'),
                validator: (value) => FormValidators.requiredText(value, 'Last name'),
                onChanged: (value) => draft.lastName = value,
              ),
              if (draft.isLegalEntity)
                TextFormField(
                  key: ValueKey('$_keyPrefix-field-trading-name'),
                  initialValue: draft.tradingName,
                  decoration: const InputDecoration(
                    labelText: 'Company / trading name *',
                  ),
                  validator: (value) =>
                      FormValidators.requiredText(value, 'Trading name'),
                  onChanged: (value) {
                    draft.tradingName = value;
                    if (value.trim().isNotEmpty &&
                        draft.prefillVatNumber.isNotEmpty &&
                        draft.vatNumber.isEmpty) {
                      draft.vatNumber = draft.prefillVatNumber;
                      onChanged();
                    }
                  },
                ),
              _DatePickerFormField(
                key: ValueKey(
                  '$_keyPrefix-field-date-of-birth-${draft.dateOfBirth?.toIso8601String() ?? 'empty'}',
                ),
                label: 'Date of birth *',
                value: draft.dateOfBirth,
                validator: (value) => value == null ? 'Date of birth is required' : null,
                onChanged: (value) {
                  draft.dateOfBirth = value;
                  onChanged();
                },
              ),
              CountryDropdown(
                key: ValueKey('$_keyPrefix-field-nationality'),
                label: 'Nationality *',
                value: draft.nationalityIso3,
                countries: countries,
                validator: (value) => value == null ? 'Nationality is required' : null,
                onChanged: (country) {
                  draft.nationalityIso3 = country?.iso3 ?? '';
                  draft.nationalityName = country?.name ?? '';
                  onChanged();
                },
              ),
              SearchableSelectFormField<PhonePrefix>(
                key: ValueKey(
                  '$_keyPrefix-field-phone-prefix-${draft.phonePrefixOriginId ?? draft.phonePrefix}-${phonePrefixes.length}',
                ),
                label: 'Phone prefix *',
                items: phonePrefixes,
                itemLabel: (item) => item.label,
                initialValue: _selectedPhonePrefix(),
                validator: (value) => FormValidators.phonePrefix(value?.dialCode),
                onChanged: (value) {
                  draft.phonePrefix = value?.dialCode ?? '';
                  draft.phonePrefixOriginId = value?.originId;
                },
                hintText: 'Search phone prefix',
                leading: const Icon(Icons.call_outlined),
              ),
              TextFormField(
                key: ValueKey('$_keyPrefix-field-phone'),
                initialValue: draft.phone,
                decoration: const InputDecoration(labelText: 'Telephone *'),
                validator: FormValidators.phoneLocalNumber,
                onChanged: (value) => draft.phone = value,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-()/. ]')),
                ],
              ),
              TextFormField(
                key: ValueKey('$_keyPrefix-field-email'),
                initialValue: draft.email,
                decoration: const InputDecoration(labelText: 'Email *'),
                validator: FormValidators.email,
                onChanged: (value) => draft.email = value,
                keyboardType: TextInputType.emailAddress,
              ),
              if (draft.isLegalEntity)
                TextFormField(
                  key: ValueKey('$_keyPrefix-field-eori'),
                  initialValue: draft.eori,
                  decoration: const InputDecoration(labelText: 'EORI *'),
                  validator: (value) => FormValidators.requiredText(value, 'EORI'),
                  onChanged: (value) => draft.eori = value,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Address',
          child: _ResponsiveFormGrid(
            children: [
              TextFormField(
                key: ValueKey('$_keyPrefix-field-street'),
                initialValue: draft.street,
                decoration: const InputDecoration(labelText: 'Street *'),
                validator: (value) => FormValidators.requiredText(value, 'Street'),
                onChanged: (value) => draft.street = value,
              ),
              TextFormField(
                key: ValueKey('$_keyPrefix-field-street-number'),
                initialValue: draft.streetNumber,
                decoration: const InputDecoration(labelText: 'House number *'),
                validator: (value) => FormValidators.requiredText(value, 'House number'),
                onChanged: (value) => draft.streetNumber = value,
              ),
              TextFormField(
                key: ValueKey('$_keyPrefix-field-street-address-optional'),
                initialValue: draft.streetAddressOptional,
                decoration: const InputDecoration(labelText: 'Address line 2'),
                onChanged: (value) => draft.streetAddressOptional = value,
              ),
              TextFormField(
                key: ValueKey('$_keyPrefix-field-postal-code'),
                initialValue: draft.postalCode,
                decoration: const InputDecoration(labelText: 'Postal code *'),
                validator: (value) => FormValidators.requiredText(value, 'Postal code'),
                onChanged: (value) => draft.postalCode = value,
              ),
              TextFormField(
                key: ValueKey('$_keyPrefix-field-city'),
                initialValue: draft.city,
                decoration: const InputDecoration(labelText: 'City *'),
                validator: (value) => FormValidators.requiredText(value, 'City'),
                onChanged: (value) => draft.city = value,
              ),
              TextFormField(
                key: ValueKey('$_keyPrefix-field-admin-region'),
                initialValue: draft.adminRegion,
                decoration: const InputDecoration(labelText: 'State / region'),
                onChanged: (value) => draft.adminRegion = value,
              ),
              CountryDropdown(
                key: ValueKey('$_keyPrefix-field-country'),
                label: 'Country *',
                value: draft.countryIso3,
                countries: countries,
                validator: (value) => value == null ? 'Country is required' : null,
                onChanged: (country) {
                  draft.countryIso3 = country?.iso3 ?? '';
                  draft.countryName = country?.name ?? '';
                  onChanged();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'VAT and preferences',
          child: Column(
            children: [
              _ResponsiveFormGrid(
                children: [
                  _BooleanCard(
                    key: ValueKey('$_keyPrefix-field-vat-liability'),
                    title: 'VAT obligatory',
                    value: draft.vatLiability,
                    onChanged: (value) {
                      draft.vatLiability = value;
                      onChanged();
                    },
                  ),
                  TextFormField(
                    key: ValueKey('$_keyPrefix-field-vat-number'),
                    initialValue: draft.vatNumber,
                    decoration: const InputDecoration(labelText: 'VAT number'),
                    validator: (value) => draft.vatLiability
                        ? FormValidators.requiredText(value, 'VAT number')
                        : null,
                    onChanged: (value) => draft.vatNumber = value,
                  ),
                  SearchableSelectFormField<_LookupOption<String>>(
                    key: ValueKey('$_keyPrefix-field-correspondence'),
                    label: 'Correspondence *',
                    items: correspondenceOptions,
                    itemLabel: (item) => item.label,
                    initialValue: correspondenceOptions
                        .where((item) => item.value == draft.correspondence)
                        .firstOrNull,
                    validator: (value) =>
                        value == null ? 'Correspondence is required' : null,
                    onChanged: (value) => draft.correspondence = value?.value,
                  ),
                  _BooleanCard(
                    key: ValueKey('$_keyPrefix-field-checked-by-leu'),
                    title: 'Checked by Leu',
                    value: draft.checkedByLeu,
                    onChanged: (value) {
                      draft.checkedByLeu = value;
                      onChanged();
                    },
                  ),
                  _BooleanCard(
                    key: ValueKey('$_keyPrefix-field-newsletter-subscribed'),
                    title: 'Newsletter subscribed',
                    value: draft.newsletterSubscribed,
                    onChanged: (value) {
                      draft.newsletterSubscribed = value;
                      onChanged();
                    },
                  ),
                  _BooleanCard(
                    key: ValueKey('$_keyPrefix-field-ancient-coins-subscribed'),
                    title: 'Ancient coins subscribed',
                    value: draft.ancientCoinsSubscribed,
                    onChanged: (value) {
                      draft.ancientCoinsSubscribed = value;
                      onChanged();
                    },
                  ),
                  _BooleanCard(
                    key: ValueKey('$_keyPrefix-field-world-coins-subscribed'),
                    title: 'World coins subscribed',
                    value: draft.worldCoinsSubscribed,
                    onChanged: (value) {
                      draft.worldCoinsSubscribed = value;
                      onChanged();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Bank transfer details',
          child: _ResponsiveFormGrid(
            children: [
              TextFormField(
                key: ValueKey('$_keyPrefix-field-bank-name'),
                initialValue: draft.bankName,
                decoration: const InputDecoration(labelText: 'Bank name'),
                onChanged: (value) => draft.bankName = value,
              ),
              TextFormField(
                key: ValueKey('$_keyPrefix-field-iban'),
                initialValue: draft.iban,
                decoration: const InputDecoration(labelText: 'IBAN *'),
                validator: FormValidators.iban,
                onChanged: (value) => draft.iban = value,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContractDecisionStep extends StatelessWidget {
  const _ContractDecisionStep({
    required this.draft,
    required this.saving,
    required this.onBack,
    required this.onSaveConsignorOnly,
    required this.onCreateContract,
  });

  final _WizardDraft draft;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onSaveConsignorOnly;
  final VoidCallback onCreateContract;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text('Create a contract too?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _ConsignorReview(draft: draft),
        const SizedBox(height: 20),
        OutlinedButton(onPressed: saving ? null : onBack, child: const Text('Back')),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: saving ? null : onCreateContract,
          icon: const Icon(Icons.description_outlined),
          label: const Text('Yes, create contract'),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: saving ? null : onSaveConsignorOnly,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: Text(saving ? 'Saving…' : 'No, save consignor only'),
        ),
      ],
    );
  }
}

class _AuctionStep extends StatelessWidget {
  const _AuctionStep({
    required this.formKey,
    required this.draft,
    required this.auctions,
    required this.onChanged,
    required this.onBack,
    required this.onNext,
  });

  final GlobalKey<FormState> formKey;
  final _WizardDraft draft;
  final List<AuctionOption> auctions;
  final ValueChanged<List<AuctionOption>> onChanged;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        children: [
          Text('Choose auctions', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          MultiAuctionSelectField(
            label: 'Auctions *',
            items: auctions,
            selected: draft.selectedAuctions,
            validator: MultiAuctionSelectField.requireSelection,
            onChanged: onChanged,
          ),
          const SizedBox(height: 20),
          _WizardButtons(onBack: onBack, onNext: onNext),
        ],
      ),
    );
  }
}

class _FileStep extends StatelessWidget {
  const _FileStep({
    required this.title,
    required this.files,
    required this.onAdd,
    this.onCapture,
    required this.onOpen,
    required this.onRemove,
    required this.onBack,
    required this.onNext,
  });

  final String title;
  final List<ContractUpload> files;
  final VoidCallback onAdd;
  final VoidCallback? onCapture;
  final ValueChanged<String> onOpen;
  final ValueChanged<ContractUpload> onRemove;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Files',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Add file'),
                  ),
                  if (onCapture != null)
                    OutlinedButton.icon(
                      onPressed: onCapture,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Capture'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (files.isEmpty)
                const Text('No files selected yet.')
              else
                ...files.map(
                  (file) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FileTile(upload: file, onOpen: onOpen, onRemove: onRemove),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextButton(onPressed: onNext, child: const Text('Skip for now')),
        _WizardButtons(onBack: onBack, onNext: onNext),
      ],
    );
  }
}

class _FullReviewStep extends StatelessWidget {
  const _FullReviewStep({
    required this.draft,
    required this.representative,
    required this.saving,
    required this.generatedPdfPath,
    required this.onBack,
    required this.onGeneratePdf,
    required this.onOpenPdf,
    required this.onOpenFile,
    required this.onContinue,
  });

  final _WizardDraft draft;
  final _WizardDraft? representative;
  final bool saving;
  final String? generatedPdfPath;
  final VoidCallback onBack;
  final VoidCallback onGeneratePdf;
  final VoidCallback? onOpenPdf;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text('Full review', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _ConsignorReview(draft: draft),
        if (representative != null) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Authorized representative',
            child: _ReviewLines(lines: representative!.reviewLines),
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: 'Auctions',
          child: Text(draft.selectedAuctions.map((e) => e.displayName).join(', ')),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Attachments',
          child: Column(
            children: [
              for (final file in draft.uploads)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FileTile(
                    upload: file,
                    onOpen: onOpenFile,
                    onRemove: (_) {},
                    canRemove: false,
                  ),
                ),
              if (draft.uploads.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No attachments selected.'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'PDF review copy',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: saving ? null : onGeneratePdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Generate PDF'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenPdf,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open PDF'),
              ),
              if (generatedPdfPath != null) Text(generatedPdfPath!),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(onPressed: saving ? null : onBack, child: const Text('Back')),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: saving ? null : onContinue,
          icon: const Icon(Icons.draw_outlined),
          label: const Text('Continue to signatures'),
        ),
      ],
    );
  }
}

class _SignerChoiceTile extends StatelessWidget {
  const _SignerChoiceTile({
    required this.signer,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final _LeuSigner signer;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final borderColor = selected ? palette.brand : palette.border;
    final foregroundColor = enabled ? palette.text : palette.textMuted;

    return InkWell(
      onTap: enabled ? onSelected : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(14),
          color: selected ? palette.brandSoft : palette.card,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? palette.brand : palette.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                signer.displayName,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: foregroundColor),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              height: 44,
              child: Image.asset(signer.assetPath, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignatureStep extends StatelessWidget {
  const _SignatureStep({
    required this.draft,
    required this.saving,
    required this.generatedPdfPath,
    required this.onBack,
    required this.onSignerChanged,
    required this.onSignatureChanged,
    required this.onClearSignature,
    required this.onGeneratePdf,
    required this.onOpenPdf,
    required this.onSubmit,
  });

  final _WizardDraft draft;
  final bool saving;
  final String? generatedPdfPath;
  final VoidCallback onBack;
  final ValueChanged<_LeuSigner> onSignerChanged;
  final void Function(List<List<Offset>> strokes, Size size) onSignatureChanged;
  final VoidCallback onClearSignature;
  final VoidCallback onGeneratePdf;
  final VoidCallback? onOpenPdf;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text('Sign PDF', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Who will sign the PDF?',
          child: Column(
            children: [
              for (final signer in _LeuSigner.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SignerChoiceTile(
                    signer: signer,
                    selected: draft.leuSigner == signer,
                    enabled: !saving,
                    onSelected: () => onSignerChanged(signer),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Customer signature',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The customer signs inside the box below.'),
              const SizedBox(height: 12),
              _SignaturePad(
                initialStrokes: draft.customerSignatureStrokes,
                onChanged: onSignatureChanged,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: saving ? null : onClearSignature,
                icon: const Icon(Icons.clear_rounded),
                label: const Text('Clear signature'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Signed PDF',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: saving || !draft.signatureReady ? null : onGeneratePdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Generate signed PDF'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenPdf,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open PDF'),
              ),
              if (generatedPdfPath != null) Text(generatedPdfPath!),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(onPressed: saving ? null : onBack, child: const Text('Back')),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: saving || !draft.signatureReady ? null : onSubmit,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({
    required this.initialStrokes,
    required this.onChanged,
  });

  final List<List<Offset>> initialStrokes;
  final void Function(List<List<Offset>> strokes, Size size) onChanged;

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  late List<List<Offset>> _strokes;

  @override
  void initState() {
    super.initState();
    _strokes = widget.initialStrokes
        .map((stroke) => List<Offset>.from(stroke))
        .toList(growable: true);
  }

  @override
  void didUpdateWidget(covariant _SignaturePad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStrokes.isEmpty && _strokes.isNotEmpty) {
      _strokes = <List<Offset>>[];
    }
  }

  void _notify(Size size) {
    widget.onChanged(
      _strokes.map((stroke) => List<Offset>.from(stroke)).toList(growable: false),
      size,
    );
  }

  void _startStroke(DragStartDetails details, Size size) {
    setState(() => _strokes.add(<Offset>[details.localPosition]));
    _notify(size);
  }

  void _appendStroke(DragUpdateDetails details, Size size) {
    if (_strokes.isEmpty) {
      _strokes.add(<Offset>[]);
    }
    setState(() => _strokes.last.add(details.localPosition));
    _notify(size);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 600.0;
        const height = 220.0;
        final size = Size(width, height);

        return GestureDetector(
          onPanStart: (details) => _startStroke(details, size),
          onPanUpdate: (details) => _appendStroke(details, size),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CustomPaint(
              painter: _SignaturePainter(_strokes),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}

class _ConsignorReview extends StatelessWidget {
  const _ConsignorReview({required this.draft});

  final _WizardDraft draft;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Consignor',
      child: _ReviewLines(lines: draft.reviewLines),
    );
  }
}

class _ReviewLines extends StatelessWidget {
  const _ReviewLines({required this.lines});

  final List<_ReviewLine> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    line.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(child: Text(line.value.trim().isEmpty ? '-' : line.value)),
              ],
            ),
          ),
      ],
    );
  }
}

extension _WizardDraftReview on _WizardDraft {
  String get _titleLabel => switch (title) {
        1 => 'Dr.',
        5 => 'Prof.',
        6 => 'Prof. Dr.',
        null => '',
        _ => title.toString(),
      };

  String get _salutationLabel => switch (salutation) {
        2 => 'Mr.',
        4 => 'Ms.',
        null => '',
        _ => salutation.toString(),
      };

  String get _correspondenceLabel => switch (correspondence) {
        'de' => 'German',
        'en' => 'English',
        null => '',
        _ => correspondence!,
      };

  List<_ReviewLine> get reviewLines => [
        _ReviewLine('Type', isLegalEntity ? 'Company or legal entity' : 'Individual'),
        _ReviewLine('Name', isLegalEntity ? tradingName : '$firstName $lastName'),
        _ReviewLine('Title', _titleLabel),
        _ReviewLine('Salutation', _salutationLabel),
        _ReviewLine(
          'Date of birth',
          dateOfBirth == null
              ? ''
              : '${dateOfBirth!.year.toString().padLeft(4, '0')}-${dateOfBirth!.month.toString().padLeft(2, '0')}-${dateOfBirth!.day.toString().padLeft(2, '0')}',
        ),
        _ReviewLine('Nationality', nationalityName),
        _ReviewLine('Email', email),
        _ReviewLine('Phone', '$phonePrefix $phone'),
        _ReviewLine(
          'Address',
          [
            street,
            streetNumber,
            streetAddressOptional,
            '$postalCode $city',
            adminRegion,
            countryName,
          ].where((part) => part.trim().isNotEmpty).join(', '),
        ),
        _ReviewLine('VAT number', vatNumber),
        _ReviewLine('EORI', eori),
        _ReviewLine('IBAN', iban),
        _ReviewLine('Correspondence', _correspondenceLabel),
      ];
}

class _ReviewLine {
  const _ReviewLine(this.label, this.value);
  final String label;
  final String value;
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.upload,
    required this.onOpen,
    required this.onRemove,
    this.canRemove = true,
  });

  final ContractUpload upload;
  final ValueChanged<String> onOpen;
  final ValueChanged<ContractUpload> onRemove;
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    final preview = FilePreview.fromPath(upload.path);
    final thumb = preview.isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(upload.path),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _FallbackPreview(icon: preview.icon),
            ),
          )
        : _FallbackPreview(icon: preview.icon);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          thumb,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              upload.fileName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: () => onOpen(upload.path),
            icon: const Icon(Icons.open_in_new_rounded),
            tooltip: 'Open',
          ),
          if (canRemove)
            IconButton(
              onPressed: () => onRemove(upload),
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Remove',
            ),
        ],
      ),
    );
  }
}

class _FallbackPreview extends StatelessWidget {
  const _FallbackPreview({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Icon(icon),
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
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 680
                ? 2
                : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (16 * (columns - 1))) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: children
              .map(
                (child) => SizedBox(
                  key: child.key == null ? null : ValueKey<Object?>(child.key),
                  width: width,
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
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        value: value,
        onChanged: onChanged,
      ),
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
            final selected = field.value;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final picked = await showDialog<DateTime>(
                  context: field.context,
                  builder: (context) => _MonthYearDayPickerDialog(
                    initialDate: selected ?? DateTime(1990, 1, 1),
                    firstDate: DateTime(1900, 1, 1),
                    lastDate: DateTime.now(),
                  ),
                );
                if (picked == null) return;
                field.didChange(picked);
                onChanged(picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  errorText: field.errorText,
                  prefixIcon: const Icon(Icons.calendar_month_outlined),
                ),
                child: Text(
                  selected == null
                      ? 'Select date'
                      : '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}',
                  style: selected == null
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
    final safeInitial =
        _clampDate(widget.initialDate, widget.firstDate, widget.lastDate);
    _selectedYear = safeInitial.year;
    _selectedMonth = safeInitial.month;
    _selectedDay = safeInitial.day;
  }

  DateTime _clampDate(DateTime value, DateTime min, DateTime max) {
    if (value.isBefore(min)) return min;
    if (value.isAfter(max)) return max;
    return value;
  }

  int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  List<int> get _availableYears => [
        for (var year = widget.lastDate.year; year >= widget.firstDate.year; year--)
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

    return [for (var month = startMonth; month <= endMonth; month++) month];
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

    return [for (var day = startDay; day <= endDay; day++) day];
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
      child: Text(value, style: const TextStyle(height: 1.0)),
    );
  }

  void _updateSelection({int? year, int? month, int? day}) {
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
      setState(() => _selectedDay = validDays.first);
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
                if (value != null) _updateSelection(year: value);
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
                if (value != null) _updateSelection(month: value);
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
                if (value != null) _updateSelection(day: value);
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime(_selectedYear, _selectedMonth, _selectedDay),
                    firstDate: widget.firstDate,
                    lastDate: widget.lastDate,
                    initialDatePickerMode: DatePickerMode.year,
                  );

                  if (!context.mounted) return;
                  if (picked != null) Navigator.of(context).pop(picked);
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
          onPressed: () => Navigator.of(context)
              .pop(DateTime(_selectedYear, _selectedMonth, _selectedDay)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _WizardButtons extends StatelessWidget {
  const _WizardButtons({required this.onBack, required this.onNext});

  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton(onPressed: onBack, child: const Text('Back')),
        const Spacer(),
        ElevatedButton(onPressed: onNext, child: const Text('Next')),
      ],
    );
  }
}

class _LookupOption<T> {
  const _LookupOption({required this.value, required this.label});

  final T value;
  final String label;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}