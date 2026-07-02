import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import 'file_service.dart';
import '../models/abacus_sync.dart';
import '../models/app_settings.dart';
import '../models/auction_option.dart';
import '../models/consignor.dart';
import '../models/contract_record.dart';
import '../models/customer_lookup_result.dart';
import '../models/phone_prefix.dart';
import '../models/sync_status.dart';

class ApiService {
  ApiService(this.settings, this.token) : _dio = _createDio(settings, token);

  static const _syncRequestTimeout = Duration(minutes: 10);
  static const _contractFetchConcurrency = 4;

  final AppSettings settings;
  final String token;
  final Dio _dio;

  static Dio _createDio(AppSettings settings, String token) {
    final dio = Dio(
      BaseOptions(
        baseUrl: settings.apiBaseUrl.trim(),
        headers: token.trim().isEmpty ? {} : {'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: _syncRequestTimeout,
        sendTimeout: _syncRequestTimeout,
        responseType: ResponseType.json,
      ),
    );

    assert(() {
      final baseUri = Uri.tryParse(settings.apiBaseUrl.trim());

      final isLocalIisExpressHttps = baseUri?.scheme == 'https' &&
          (baseUri?.host == '10.0.2.2' || baseUri?.host == 'localhost') &&
          baseUri?.port == 44364;

      if (isLocalIisExpressHttps) {
        final adapter = dio.httpClientAdapter as IOHttpClientAdapter;

        adapter.createHttpClient = () {
          final client = HttpClient();

          client.badCertificateCallback =
              (X509Certificate cert, String host, int port) {
            return (host == '10.0.2.2' || host == 'localhost') && port == 44364;
          };

          return client;
        };
      }

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            debugPrint('API REQUEST: ${options.method} ${options.uri}');
            handler.next(options);
          },
          onResponse: (response, handler) {
            debugPrint(
              'API RESPONSE: ${response.statusCode} ${response.requestOptions.uri}',
            );
            handler.next(response);
          },
          onError: (error, handler) {
            debugPrint(
              'API ERROR: ${error.response?.statusCode} ${error.requestOptions.uri}',
            );
            handler.next(error);
          },
        ),
      );

      return true;
    }());

    return dio;
  }

  Future<void> validateConnection() async {
    _ensureConfigured();
    try {
      await _dio.get(_path(settings.consignorsGetAll));
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<List<PhonePrefix>> fetchPhonePrefixes() async {
    _ensureConfigured();

    try {
      final response = await _dio.get(_path(settings.originPrefixesGetAll));
      final data = response.data;
      if (data is! List) return const [];

      return data
          .whereType<Map>()
          .map((item) => PhonePrefix.fromJson(item.cast<String, dynamic>()))
          .where((item) => item.dialCode.isNotEmpty)
          .toList(growable: false);
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<List<CustomerLookupResult>> searchExistingCustomers(
    String query, {
    int take = 15,
  }) async {
    _ensureConfigured();

    if (query.trim().isEmpty) {
      return const [];
    }

    try {
      final response = await _dio.get(
        _path(settings.customersSearch),
        queryParameters: {
          'q': query.trim(),
          'take': take,
        },
      );

      final data = response.data;
      if (data is! List) return const [];

      final results = <CustomerLookupResult>[];
      for (final item in data.whereType<Map>()) {
        final parsed = await _customerLookupResultFromJson(
          item.cast<String, dynamic>(),
        );
        if (parsed.customerId > 0) {
          results.add(parsed);
        }
      }

      return results;
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<List<ContractUpload>> fetchPassportUploads(int customerId) async {
    _ensureConfigured();
    if (customerId <= 0) return const [];

    try {
      final response = await _dio.get(
        _path('/api/consignors-app/customers/$customerId/passport-uploads'),
      );

      return await _uploadsFromJson(
        customerId,
        response.data,
      );
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<ContractUpload?> fetchDossierDocumentContent({
    required int consignorId,
    required ContractUpload upload,
  }) async {
    _ensureConfigured();
    final documentId = upload.localId.trim();
    if (documentId.isEmpty) return null;

    try {
      final response = await _dio.get(
        _path(
          '/api/consignors-app/dossier-documents/'
          '${Uri.encodeComponent(documentId)}/content',
        ),
        queryParameters: {
          'fileType': upload.fileType.apiValue,
          if (upload.kind.trim().isNotEmpty) 'kind': upload.kind.trim(),
        },
      );

      final data = response.data;
      if (data is! Map) return null;

      final hydrated = await _uploadFromJson(
        consignorId: consignorId,
        json: data.cast<String, dynamic>(),
      );
      return hydrated.copyWith(fileData: '');
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<CustomerLookupResult> _customerLookupResultFromJson(
    Map<String, dynamic> json,
  ) async {
    final preview = CustomerLookupResult.fromJson(json);
    final uploads = await _uploadsFromJson(
      preview.customerId,
      json['passportUploads'] ?? json['PassportUploads'],
    );
    return CustomerLookupResult.fromJson(json, passportUploads: uploads);
  }

  Future<List<ContractUpload>> _uploadsFromJson(
    int consignorId,
    Object? value,
  ) async {
    final rows = (value as List?)
            ?.whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];
    final uploads = <ContractUpload>[];
    for (final row in rows) {
      uploads.add(
        await _uploadFromJson(
          consignorId: consignorId,
          json: row,
        ),
      );
    }
    return uploads;
  }

  /// Fetches the list of consignors that have changed on the server since
  /// [sinceUtc]. Only records with LastModifiedUtc **strictly after** [sinceUtc]
  /// are returned by the backend.
  ///
  /// Pass `null` for a full refresh (first-time sync). Otherwise pass the
  /// highest [remoteLastModifiedUtc] stored locally so only changed records are
  /// downloaded, turning “Fetching 1 of 1300” into “Fetching 1 of 10”.
  Future<RemoteSnapshot> fetchRemoteSnapshot({
    DateTime? sinceUtc,
    void Function(int current, int total, String message)? onProgress,
  }) async {
    _ensureConfigured();

    try {
      onProgress?.call(
        0,
        0,
        sinceUtc == null
            ? 'Fetching consignor report from Abacus...'
            : 'Checking Abacus for changed consignors...',
      );

      // Pass sinceUtc as a query param so the backend filters changed records only.
      final queryParameters = sinceUtc != null
          ? <String, dynamic>{
              'sinceUtc': sinceUtc.toUtc().toIso8601String(),
            }
          : null;

      final response = await _dio.get(
        _path(settings.consignorsGetAll),
        queryParameters: queryParameters,
      );
      final data = response.data;

      if (data is! List) {
        return const RemoteSnapshot();
      }

      final summaries =
          data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

      final consignors = <Consignor>[];
      final contracts = <ContractRecord>[];
      final missingReportFields = <RemoteReportFieldIssue>[];
      final total = summaries.length;

      if (total == 0) {
        onProgress?.call(0, 0, 'No changed consignors to fetch.');
        return const RemoteSnapshot();
      }

      onProgress?.call(0, total, 'Processing consignors 0 of $total...');

      for (var index = 0; index < summaries.length; index++) {
        final item = summaries[index];

        onProgress?.call(
          index,
          total,
          'Processing consignor ${index + 1} of $total...',
        );

        final fieldIssue = _reportFieldIssue(
          row: item,
          index: index,
          total: total,
        );
        if (fieldIssue != null) {
          missingReportFields.add(fieldIssue);
        }

        final details = await _remoteDetailFromReportJson(
          json: item,
          fallbackConsignorId: _reportConsignorId(item),
        );

        if (details.consignor != null) {
          consignors.add(details.consignor!);
        }

        contracts.addAll(details.contracts);

        onProgress?.call(
          index + 1,
          total,
          'Processing consignor ${index + 1} of $total...',
        );
      }

      return RemoteSnapshot(
        consignors: consignors,
        contracts: contracts,
        missingReportFields: missingReportFields,
        reportRowCount: total,
      );
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<RemoteConsignorDetail> fetchConsignorDetail(
    int consignorId, {
    String? idSource,
  }) async {
    _ensureConfigured();
    try {
      return await _fetchConsignorDetailUnchecked(consignorId);
    } on DioException catch (e) {
      final source = idSource == null ? '' : ' from $idSource';
      throw Exception(
        'Failed to fetch consignor $consignorId$source: '
        '${_friendlyDioError(e)}',
      );
    }
  }

  Future<RemoteContractFetchResult> fetchAllContracts({
    void Function(int current, int total, String message)? onProgress,
  }) async {
    _ensureConfigured();

    try {
      onProgress?.call(0, 1, 'Analyzing contracts in Abacus...');
      final response = await _dio.get(_path(settings.contractsGetAll));
      final data = response.data;
      final groups = ((data is Map
                  ? data['contracts'] ?? data['Contracts'] ?? data['value']
                  : data) as List?)
              ?.whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .toList() ??
          const <Map<String, dynamic>>[];

      final contracts = <ContractRecord>[];
      for (final groupJson in groups) {
        final consignorId = _toInt(
              groupJson['consignorId'] ??
                  groupJson['ConsignorId'] ??
                  groupJson['customerId'] ??
                  groupJson['CustomerId'] ??
                  groupJson['subjectId'] ??
                  groupJson['SubjectId'],
            ) ??
            0;
        if (consignorId <= 0) continue;

        final contract = await _contractFromGroupJson(
          consignorId: consignorId,
          json: groupJson,
        );
        contract.markRemoteSnapshot();
        contracts.add(contract);
      }

      onProgress?.call(
        1,
        1,
        'Analyzed ${contracts.length} Abacus contract${contracts.length == 1 ? '' : 's'}.',
      );

      return RemoteContractFetchResult(
        contracts: contracts,
        analyzedDocumentCount: groups.length,
      );
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<RemoteContractFetchResult> fetchContractsForConsignors(
    Iterable<int> consignorIds, {
    void Function(int current, int total, String message)? onProgress,
  }) async {
    _ensureConfigured();

    final ids = consignorIds
        .where((id) => id > 0)
        .toSet()
        .toList(growable: false)
      ..sort();
    final total = ids.length;

    if (total == 0) {
      onProgress?.call(0, 0, 'No consignors available for contract sync.');
      return const RemoteContractFetchResult();
    }

    final contracts = <ContractRecord>[];
    final skippedIds = <int>[];
    final failedMessages = <String>[];
    onProgress?.call(0, total, 'Analyzing contracts 0 of $total...');

    var completed = 0;
    for (var start = 0;
        start < ids.length;
        start += _contractFetchConcurrency) {
      final batch = ids
          .skip(start)
          .take(_contractFetchConcurrency)
          .toList(growable: false);

      final batchResults = await Future.wait(
        batch.map((consignorId) async {
          try {
            final detail = await _fetchConsignorDetailUnchecked(consignorId);
            return detail.contracts;
          } on DioException catch (e) {
            final status = e.response?.statusCode;
            if (status == 401 || status == 403) {
              rethrow;
            }

            if (status == 404) {
              skippedIds.add(consignorId);
            } else {
              failedMessages.add(
                '$consignorId: ${_friendlyDioError(e)}',
              );
            }
            return const <ContractRecord>[];
          } finally {
            completed++;
            final skippedText =
                skippedIds.isEmpty ? '' : ', skipped ${skippedIds.length}';
            final failedText = failedMessages.isEmpty
                ? ''
                : ', failed ${failedMessages.length}';
            onProgress?.call(
              completed,
              total,
              'Analyzing contracts $completed of $total$skippedText$failedText...',
            );
          }
        }),
      );

      for (final result in batchResults) {
        contracts.addAll(result);
      }
    }

    return RemoteContractFetchResult(
      contracts: contracts,
      checkedConsignorCount: total,
      skippedConsignorIds: skippedIds,
      failedMessages: failedMessages,
    );
  }

  Future<RemoteConsignorDetail> _fetchConsignorDetailUnchecked(
    int consignorId,
  ) async {
    final response = await _dio.get(
      _path(settings.consignorsGetOne).replaceAll('{id}', '$consignorId'),
    );

    if (response.data is! Map) {
      return const RemoteConsignorDetail();
    }

    return await _remoteDetailFromReportJson(
      json: (response.data as Map).cast<String, dynamic>(),
      fallbackConsignorId: consignorId,
    );
  }

  Future<RemoteConsignorDetail> _remoteDetailFromReportJson({
    required Map<String, dynamic> json,
    required int? fallbackConsignorId,
  }) async {
    final consignor = Consignor.fromJson(json);
    final canonicalId = consignor.systemReferenceCustomer > 0
        ? consignor.systemReferenceCustomer
        : fallbackConsignorId ?? consignor.systemReferenceConsignor;
    if (canonicalId > 0) {
      consignor.id = canonicalId.toString();
    }
    consignor.markRemoteSnapshot();

    final contractConsignorId =
        int.tryParse(consignor.id) ?? fallbackConsignorId ?? canonicalId;

    final contractGroups = ((json['contracts'] ?? json['Contracts']) as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];

    final contracts = <ContractRecord>[];
    for (final groupJson in contractGroups) {
      final contract = await _contractFromGroupJson(
        consignorId: contractConsignorId,
        json: groupJson,
      );
      contract.markRemoteSnapshot();
      contracts.add(contract);
    }

    return RemoteConsignorDetail(consignor: consignor, contracts: contracts);
  }

  Future<List<AuctionOption>> fetchAuctionOptions() async {
    _ensureConfigured();
    try {
      final response = await _dio.get('/api/consignors-app/auctions/dropdown');
      final data = response.data;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((item) => AuctionOption.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<PushConsignorResult> pushConsignors(
    List<Consignor> consignors, {
    Map<String, Consignor> authorizedRepresentatives = const {},
  }) async {
    if (settings.apiBaseUrl.trim().isEmpty || consignors.isEmpty) {
      return const PushConsignorResult();
    }

    try {
      final references = <String, ConsignorReference>{};
      final syncedConsignors = <String, Consignor>{};
      var pushedCount = 0;

      final toCreate = <Consignor>[];
      for (final consignor in consignors) {
        if (!consignor.hasRemoteReference) {
          toCreate.add(consignor);
          continue;
        }

        final consignorId = consignor.systemReferenceConsignor;
        if (consignorId <= 0) {
          throw Exception(
            'Consignor ${consignor.id} has a customer reference but no consignor reference for update.',
          );
        }

        final response = await _dio.put(
          _path(settings.consignorsUpdateOne)
              .replaceAll('{id}', '$consignorId'),
          data: _consignorPayload(
            consignor,
            authorizedRepresentative: authorizedRepresentatives[consignor.id],
          ),
        );

        final payload = response.data is Map
            ? (response.data as Map).cast<String, dynamic>()
            : const <String, dynamic>{};
        final reference = ConsignorReference.fromJson(payload);
        references[consignor.id] = reference;
        final currentJson =
            ((payload['consignor'] ?? payload['Consignor']) as Map?)
                ?.cast<String, dynamic>();

        if (currentJson != null) {
          final synced = Consignor.fromJson(currentJson)
            ..id = (reference.systemReferenceCustomer > 0
                    ? reference.systemReferenceCustomer
                    : reference.systemReferenceConsignor)
                .toString();
          synced.markRemoteSnapshot();
          syncedConsignors[consignor.id] = synced;
        }

        pushedCount++;
      }

      if (toCreate.isNotEmpty) {
        final response = await _dio.post(
          _path(settings.consignorsBulkUpdate),
          data: toCreate
              .map(
                (e) => _consignorPayload(
                  e,
                  authorizedRepresentative: authorizedRepresentatives[e.id],
                ),
              )
              .toList(),
        );
        final data = response.data;

        if (data is List) {
          for (var i = 0; i < data.length && i < toCreate.length; i++) {
            final item = data[i];
            if (item is Map) {
              final json = item.cast<String, dynamic>();
              final reference = ConsignorReference.fromJson(json);
              references[toCreate[i].id] = reference;
              final currentJson =
                  ((json['consignor'] ?? json['Consignor']) as Map?)
                      ?.cast<String, dynamic>();

              if (currentJson != null) {
                final synced = Consignor.fromJson(currentJson)
                  ..id = (reference.systemReferenceCustomer > 0
                          ? reference.systemReferenceCustomer
                          : reference.systemReferenceConsignor)
                      .toString();
                synced.markRemoteSnapshot();
                syncedConsignors[toCreate[i].id] = synced;
              }

              pushedCount++;
            }
          }
        }
      }

      return PushConsignorResult(
        references: references,
        pushedCount: pushedCount,
        syncedConsignors: syncedConsignors,
      );
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<List<int>> renderContractPdf(Map<String, dynamic> payload) async {
    _ensureConfigured();

    try {
      final response = await _dio.post<List<int>>(
        '/api/consignors-app/contracts/render-pdf',
        data: payload,
        options: Options(responseType: ResponseType.bytes),
      );

      final data = response.data;
      if (data == null || data.isEmpty) {
        throw Exception(
          'The contract render endpoint returned an empty response.',
        );
      }

      return data;
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<ContractRecord> createContract(
    int consignorId,
    int auctionId,
    List<ContractUpload> uploads, {
    int? abacusSubjectId,
    DateTime? signedAt,
    AbacusContractSyncEvent syncEvent = AbacusContractSyncEvent.manualSync,
    String? contractNumber,
  }) async {
    _ensureConfigured();
    try {
      final eventUtc = DateTime.now().toUtc();
      final resolvedContractNumber = contractNumber ?? auctionId.toString();
      final response = await _dio.post(
        '/api/consignors-app/consignors/$consignorId/contracts',
        data: {
          'consignorId': consignorId,
          'auctionId': auctionId,
          'signedAt': signedAt?.toUtc().toIso8601String(),
          'abacusSync': _contractSyncPayload(syncEvent),
          'files': [
            for (final upload in uploads)
              await _uploadPayload(
                upload,
                abacusMetadata: AbacusFileSyncMetadata.forUpload(
                  upload: upload,
                  consignorSubjectId: abacusSubjectId ?? consignorId,
                  contractNumber: resolvedContractNumber,
                  eventUtc: eventUtc,
                  trigger: syncEvent,
                  labelOverride: _abacusLabelForUpload(
                    upload: upload,
                    allUploads: uploads,
                    contractNumber: resolvedContractNumber,
                  ),
                ),
              ),
          ],
        },
      );

      return await _contractFromGroupJson(
        consignorId: consignorId,
        json: (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<ContractUpload> updateUpload(
    int consignorId,
    ContractUpload upload, {
    int? abacusSubjectId,
    AbacusContractSyncEvent syncEvent = AbacusContractSyncEvent.manualSync,
    String? contractNumber,
    String? documentLabel,
  }) async {
    _ensureConfigured();
    final uploadId = upload.fileId;
    if (uploadId == null || uploadId <= 0) {
      throw Exception('Upload id is required for file replacement.');
    }

    try {
      final response = await _dio.put(
        '/api/consignors-app/consignors/$consignorId/uploads/$uploadId',
        data: await _uploadPayload(
          upload,
          abacusMetadata: AbacusFileSyncMetadata.forUpload(
            upload: upload,
            consignorSubjectId: abacusSubjectId ?? consignorId,
            contractNumber: contractNumber ?? uploadId.toString(),
            eventUtc: DateTime.now().toUtc(),
            trigger: syncEvent,
            labelOverride: documentLabel,
          ),
        ),
      );

      return await _uploadFromJson(
        consignorId: consignorId,
        json: (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<void> deleteUpload(int consignorId, int uploadId) async {
    _ensureConfigured();
    try {
      await _dio.delete(
        '/api/consignors-app/consignors/$consignorId/uploads/$uploadId',
      );
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<ContractRecord> syncContract(
    int consignorId,
    int auctionId, {
    AbacusContractSyncEvent syncEvent = AbacusContractSyncEvent.manualSync,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.post(
        '/api/consignors-app/consignors/$consignorId/contracts/$auctionId/sync',
        data: {
          'abacusSync': _contractSyncPayload(syncEvent),
        },
      );
      return await _contractFromGroupJson(
        consignorId: consignorId,
        json: (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw Exception(_friendlyDioError(e));
    }
  }

  Future<ContractRecord> syncContractRecord(
    int consignorId,
    ContractRecord record, {
    int? abacusSubjectId,
    AbacusContractSyncEvent syncEvent = AbacusContractSyncEvent.manualSync,
  }) async {
    _ensureConfigured();

    final auctionId = record.auctionId;
    if (auctionId == null) {
      throw Exception('Select an auction before syncing the contract.');
    }

    final activeUploads =
        record.uploads.where((upload) => !upload.isDeleted).toList();
    if (activeUploads.isEmpty) {
      throw Exception('Add at least one file before syncing the contract.');
    }

    var workingRecord = record.copyWith(
      uploads: record.uploads.map((upload) => upload.copyWith()).toList(),
    );
    final contractNumber = _contractNumber(record);

    final pendingDeletes = workingRecord.uploads
        .where((upload) => upload.isDeleted && (upload.fileId ?? 0) > 0)
        .toList(growable: false);
    final pendingCreates = workingRecord.uploads
        .where((upload) => !upload.isDeleted && (upload.fileId ?? 0) <= 0)
        .toList(growable: false);

    var touchedRemote = false;
    final hasPendingUploadWork = pendingDeletes.isNotEmpty ||
        pendingCreates.isNotEmpty ||
        workingRecord.uploads.any((upload) {
          return (upload.fileId ?? 0) > 0 && upload.needsSync;
        });

    if (!hasPendingUploadWork &&
        syncEvent != AbacusContractSyncEvent.manualSync) {
      final refreshed = await syncContract(
        consignorId,
        auctionId,
        syncEvent: syncEvent,
      );
      refreshed.markSynced(remoteModifiedUtc: refreshed.lastModifiedUtc);
      return refreshed;
    }

    for (final upload in pendingDeletes) {
      await deleteUpload(consignorId, upload.fileId!);
      touchedRemote = true;
    }

    if (pendingDeletes.isNotEmpty) {
      workingRecord = workingRecord.copyWith(
        uploads: workingRecord.uploads
            .where((upload) => !upload.isDeleted)
            .toList(growable: false),
      );
    }

    final updatedUploads = <ContractUpload>[];
    for (final upload in workingRecord.uploads) {
      if ((upload.fileId ?? 0) > 0 && upload.needsSync) {
        final payload = upload.copyWith(
          fileData: await _readFileAsBase64(upload.path),
        );
        final serverUpload = await updateUpload(
          consignorId,
          payload,
          abacusSubjectId: abacusSubjectId,
          syncEvent: syncEvent,
          contractNumber: contractNumber,
          documentLabel: _abacusLabelForUpload(
            upload: upload,
            allUploads: workingRecord.uploads,
            contractNumber: contractNumber,
          ),
        );
        final serverUtc = serverUpload.serverLastModifiedUtc ??
            serverUpload.localLastModifiedUtc;

        updatedUploads.add(
          serverUpload.copyWith(
            path: upload.path,
            fileData: '',
            localLastModifiedUtc: serverUtc,
            serverLastModifiedUtc: serverUtc,
          ),
        );
        touchedRemote = true;
      } else {
        updatedUploads.add(upload);
      }
    }

    workingRecord = workingRecord.copyWith(uploads: updatedUploads);

    ContractRecord settledRecord;
    if (pendingCreates.isNotEmpty) {
      final createPayloads = <ContractUpload>[];
      for (final upload in pendingCreates) {
        createPayloads.add(
          upload.copyWith(fileData: await _readFileAsBase64(upload.path)),
        );
      }

      final serverContract = await createContract(
        consignorId,
        auctionId,
        createPayloads,
        abacusSubjectId: abacusSubjectId,
        signedAt: workingRecord.signedAt,
        syncEvent: syncEvent,
        contractNumber: contractNumber,
      );

      final mergedUploads = <ContractUpload>[];
      for (final serverUpload in serverContract.uploads) {
        final localMatches = workingRecord.uploads.where((local) {
          if (local.fileId != null && serverUpload.fileId != null) {
            return local.fileId == serverUpload.fileId;
          }
          return local.fileType == serverUpload.fileType &&
              local.fileName == serverUpload.fileName;
        }).toList(growable: false);

        final localMatch = localMatches.isEmpty ? null : localMatches.first;
        final serverTimestamp = serverUpload.serverLastModifiedUtc ??
            serverUpload.localLastModifiedUtc;

        mergedUploads.add(
          serverUpload.copyWith(
            path: (localMatch != null && localMatch.path.isNotEmpty)
                ? localMatch.path
                : serverUpload.path,
            fileData: '',
            localLastModifiedUtc: serverTimestamp,
            serverLastModifiedUtc: serverTimestamp,
          ),
        );
      }

      settledRecord = serverContract.copyWith(
        id: '${record.consignorId}_${serverContract.auctionId ?? auctionId}',
        consignorId: record.consignorId,
        uploads: mergedUploads,
      );
    } else if (touchedRemote) {
      final refreshed = await syncContract(
        consignorId,
        auctionId,
        syncEvent: syncEvent,
      );
      final mergedUploads = <ContractUpload>[];

      for (final serverUpload in refreshed.uploads) {
        final localMatches = workingRecord.uploads.where((local) {
          if (local.fileId != null && serverUpload.fileId != null) {
            return local.fileId == serverUpload.fileId;
          }
          return local.fileType == serverUpload.fileType &&
              local.fileName == serverUpload.fileName;
        }).toList(growable: false);

        final localMatch = localMatches.isEmpty ? null : localMatches.first;
        final serverTimestamp = serverUpload.serverLastModifiedUtc ??
            serverUpload.localLastModifiedUtc;

        mergedUploads.add(
          serverUpload.copyWith(
            path: (localMatch != null && localMatch.path.isNotEmpty)
                ? localMatch.path
                : serverUpload.path,
            fileData: '',
            localLastModifiedUtc: serverTimestamp,
            serverLastModifiedUtc: serverTimestamp,
          ),
        );
      }

      settledRecord = refreshed.copyWith(
        id: record.id,
        consignorId: record.consignorId,
        uploads: mergedUploads,
      );
    } else {
      final settledUploads = workingRecord.uploads.map((upload) {
        final serverUtc =
            upload.serverLastModifiedUtc ?? upload.localLastModifiedUtc;
        return upload.copyWith(
          fileData: '',
          localLastModifiedUtc: serverUtc,
          serverLastModifiedUtc: serverUtc,
        );
      }).toList(growable: false);

      settledRecord = workingRecord.copyWith(uploads: settledUploads);
    }

    settledRecord = settledRecord.copyWith(
      syncStatus: RecordSyncStatus.synced,
      syncErrorMessage: null,
      lastSyncedUtc: DateTime.now().toUtc(),
      remoteLastModifiedUtc:
          settledRecord.remoteLastModifiedUtc ?? settledRecord.lastModifiedUtc,
    );
    settledRecord.markSynced(
      remoteModifiedUtc:
          settledRecord.remoteLastModifiedUtc ?? settledRecord.lastModifiedUtc,
    );

    return settledRecord;
  }

  Future<ContractRecord> _contractFromGroupJson({
    required int consignorId,
    required Map<String, dynamic> json,
  }) async {
    final files = ((json['list'] ??
                json['List'] ??
                json['uploads'] ??
                json['Uploads']) as List?)
            ?.whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];

    final uploads = <ContractUpload>[];
    String pdfPath = '';
    String pdfName = 'consignor_contract.pdf';
    final resolvedSyncStatus = RecordSyncStatusX.fromAny(
      json['syncStatus'] ??
          json['SyncStatus'] ??
          json['status'] ??
          json['Status'] ??
          json['contractStatus'] ??
          json['ContractStatus'],
      hasRemoteReference: true,
      legacySynced: true,
    );

    for (final fileJson in files) {
      final upload =
          await _uploadFromJson(consignorId: consignorId, json: fileJson);
      uploads.add(upload);

      final isPdf = upload.fileName.toLowerCase().endsWith('.pdf');
      if (upload.fileType == UploadType.agreement && isPdf && pdfPath.isEmpty) {
        pdfPath = upload.path;
        pdfName = upload.fileName;
      }
    }

    final explicitContractId =
        (json['contractId'] ?? json['ContractId'])?.toString().trim();
    final fallbackContractId = pdfName.trim().isNotEmpty
        ? pdfName.replaceAll(RegExp(r'\.[^.]+$'), '')
        : '${_toInt(json['auctionId'] ?? json['AuctionId']) ?? 0}';

    final contract = ContractRecord(
      id: explicitContractId != null && explicitContractId.isNotEmpty
          ? explicitContractId
          : '${consignorId}_$fallbackContractId',
      consignorId: consignorId.toString(),
      auctionId: _toInt(json['auctionId'] ?? json['AuctionId']),
      auctionDisplayName:
          (json['auctionDisplayName'] ?? json['AuctionDisplayName'])
                  ?.toString() ??
              '',
      systemReferenceContract: _toInt(json['systemReferenceContract'] ??
              json['SystemReferenceContract']) ??
          0,
      pdfName: pdfName,
      signedAt: DateTime.tryParse(
            (json['signedAt'] ?? json['SignedAt'])?.toString() ?? '',
          ) ??
          DateTime.now(),
      lastModifiedUtc: DateTime.tryParse(
            (json['lastModifiedUtc'] ?? json['LastModifiedUtc'])?.toString() ??
                '',
          )?.toUtc() ??
          DateTime.now().toUtc(),
      pdfPath: pdfPath,
      uploads: uploads,
    );

    contract.markRemoteSnapshot();
    if (resolvedSyncStatus == RecordSyncStatus.finalized) {
      contract.syncStatus = RecordSyncStatus.finalized;
    }
    return contract;
  }

  Future<ContractUpload> _uploadFromJson({
    required int consignorId,
    required Map<String, dynamic> json,
  }) async {
    final parsed = ContractUpload.fromJson(json);

    final fileName =
        (json['fileName'] ?? json['FileName'])?.toString() ?? 'attachment';

    final fileData = (json['fileData'] ?? json['FileData'])?.toString() ?? '';

    final persistedPath = await _persistRemoteFile(
      uploadType: parsed.fileType,
      uploadId: _toInt(json['fileId'] ?? json['FileId']),
      fileName: fileName,
      base64Content: fileData,
    );

    return parsed.copyWith(
      path: persistedPath ?? parsed.path,
      fileData: fileData,
    );
  }

  Map<String, dynamic> _consignorPayload(
    Consignor consignor, {
    Consignor? authorizedRepresentative,
  }) {
    final payload = consignor.toJson();
    if (authorizedRepresentative != null) {
      payload['abacusRepresentativeLink'] = AbacusRepresentativeLinkMetadata(
        representative: authorizedRepresentative,
        trigger: 'ConsignorSync',
      ).toJson();
    }
    return payload;
  }

  Map<String, dynamic> _contractSyncPayload(AbacusContractSyncEvent event) => {
        'queueForAbacus': event != AbacusContractSyncEvent.manualSync,
        'trigger': event.apiName,
        'target': 'VendorDossier',
        'fileStoreEndpoint': '/api/file-store/v1/user',
        'documentsEndpoint': 'SubjectDocuments',
        'verifyReceipt': event.requiresDossierReceipt,
        'retry': {
          'maxAttempts': 3,
          'logBackofficeError': true,
        },
      };

  String _contractNumber(ContractRecord record) {
    final extracted = _extractContractNumber([
      record.pdfName,
      record.id,
      ...record.uploads.map((upload) => upload.fileName),
    ]);
    if (extracted != null) {
      return extracted;
    }

    if (record.systemReferenceContract > 0) {
      final year = (DateTime.now().year % 100).toString().padLeft(2, '0');
      return 'COC-$year-${record.systemReferenceContract}';
    }

    return record.id;
  }

  String? _extractContractNumber(Iterable<String> candidates) {
    final pattern =
        RegExp(r'\b(?:PROV-)?COC-\d{2}-\d+\b', caseSensitive: false);
    for (final candidate in candidates) {
      final match = pattern.firstMatch(candidate);
      if (match != null) return match.group(0)!.toUpperCase();
    }
    return null;
  }

  String? _abacusLabelForUpload({
    required ContractUpload upload,
    required List<ContractUpload> allUploads,
    required String contractNumber,
  }) {
    if (upload.isDeleted) return null;

    final baseContractNumber = _baseContractNumber(contractNumber);

    if (upload.fileType == UploadType.agreement) {
      if (!upload.fileName.toLowerCase().endsWith('.pdf')) return null;
      return contractNumber;
    }

    if (upload.fileType == UploadType.product) {
      final productUploads = allUploads
          .where(
              (item) => !item.isDeleted && item.fileType == UploadType.product)
          .toList(growable: false);
      final index = _oneBasedUploadIndex(productUploads, upload);
      return '$baseContractNumber-Product-$index';
    }

    if (upload.fileType == UploadType.passport) {
      final kind = upload.kind.trim();
      final validationReport = kind == 'NaturalPersonIdValidationReport' ||
          kind == 'RepresentativeIdValidationReport';
      if (validationReport) return null;

      final representative = kind == 'RepresentativeId';
      final passportUploads = allUploads
          .where((item) =>
              !item.isDeleted &&
              item.fileType == UploadType.passport &&
              item.kind.trim() == kind)
          .toList(growable: false);
      final prefix = representative ? 'Representative' : 'Passport';
      if (passportUploads.length <= 1) return prefix;

      final index = _oneBasedUploadIndex(passportUploads, upload);
      return '$prefix-$index';
    }

    return null;
  }

  int _oneBasedUploadIndex(
      List<ContractUpload> uploads, ContractUpload upload) {
    for (var index = 0; index < uploads.length; index++) {
      final candidate = uploads[index];
      if (identical(candidate, upload) ||
          (candidate.localId == upload.localId &&
              candidate.fileId == upload.fileId &&
              candidate.fileName == upload.fileName)) {
        return index + 1;
      }
    }
    return uploads.length + 1;
  }

  String _baseContractNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.toUpperCase().startsWith('PROV-COC-')) {
      return trimmed.substring(5);
    }
    return trimmed;
  }

  Future<Map<String, dynamic>> _uploadPayload(
    ContractUpload upload, {
    AbacusFileSyncMetadata? abacusMetadata,
  }) async {
    String? fileData =
        upload.fileData.trim().isNotEmpty ? upload.fileData : null;

    if (fileData == null && upload.path.trim().isNotEmpty) {
      final file = File(upload.path);
      if (await file.exists()) {
        fileData = base64Encode(await file.readAsBytes());
      }
    }

    final payload = {
      'localId': upload.localId,
      'fileId': upload.fileId,
      'auctionId': upload.auctionId,
      'fileType': upload.fileType.apiValue,
      'kind': upload.kind.trim().isEmpty ? null : upload.kind.trim(),
      'fileName': upload.fileName,
      'fileData': fileData ?? '',
      'signedAt': upload.signedAt?.toUtc().toIso8601String(),
      'lastModifiedUtc': upload.localLastModifiedUtc.toUtc().toIso8601String(),
    };

    if (abacusMetadata != null) {
      payload['abacusSync'] = abacusMetadata.toJson();
    }

    return payload;
  }

  Future<String?> _persistRemoteFile({
    required UploadType uploadType,
    required int? uploadId,
    required String fileName,
    required String base64Content,
  }) async {
    if (base64Content.trim().isEmpty) {
      return null;
    }

    try {
      final bytes = base64Decode(base64Content);

      final Directory targetDirectory;

      switch (uploadType) {
        case UploadType.passport:
          targetDirectory = await FileService.idPicturesDirectory();
          break;

        case UploadType.product:
          targetDirectory = await FileService.productPicturesDirectory();
          break;

        case UploadType.agreement:
          targetDirectory = await FileService.contractsDirectory();
          break;
      }

      await targetDirectory.create(recursive: true);

      final safeFileName = fileName.replaceAll(
        RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
        '_',
      );

      final persistedFileName =
          '${uploadId ?? DateTime.now().microsecondsSinceEpoch}_$safeFileName';

      final file = File(
        '${targetDirectory.path}${Platform.pathSeparator}$persistedFileName',
      );

      await file.writeAsBytes(bytes, flush: true);

      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String> _readFileAsBase64(String path) async {
    if (path.trim().isEmpty) return '';
    final file = File(path);
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  String _path(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return value.startsWith('/') ? value : '/$value';
  }

  void _ensureConfigured() {
    final baseUrl = settings.apiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw Exception('API base URL is empty.');
    }

    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme) {
      throw Exception('API base URL must include an https:// scheme.');
    }

    final localDevelopmentHost = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1' ||
        uri.host == '10.0.2.2';

    if (uri.scheme != 'https' && (kReleaseMode || !localDevelopmentHost)) {
      throw Exception('API base URL must use HTTPS.');
    }

    if (token.trim().isEmpty) {
      throw Exception(
        'No bearer token is set. Use Sign in with Microsoft or paste a valid token.',
      );
    }
  }

  int? _reportConsignorId(Map<String, dynamic> row) {
    return _toInt(
          row['systemReferenceCustomer'] ??
              row['SystemReferenceCustomer'] ??
              row['abacusSubjectId'] ??
              row['AbacusSubjectId'] ??
              row['consignorId'] ??
              row['ConsignorId'] ??
              row['customerId'] ??
              row['CustomerId'] ??
              row['systemReferenceConsignor'] ??
              row['SystemReferenceConsignor'] ??
              row['id'] ??
              row['Id'],
        ) ??
        _toInt(row['id'] ?? row['Id']);
  }

  RemoteReportFieldIssue? _reportFieldIssue({
    required Map<String, dynamic> row,
    required int index,
    required int total,
  }) {
    final missing = <String>[];

    void requireAny(String label, List<String> paths) {
      if (!paths.any((path) => _hasReportValue(row, path))) {
        missing.add(label);
      }
    }

    requireAny('Consignor subject/id', [
      'systemReferenceCustomer',
      'SystemReferenceCustomer',
      'abacusSubjectId',
      'AbacusSubjectId',
      'consignorId',
      'ConsignorId',
      'customerId',
      'CustomerId',
      'id',
      'Id',
    ]);
    requireAny('Last modified timestamp', [
      'lastModifiedUtc',
      'LastModifiedUtc',
      'remoteLastModifiedUtc',
      'RemoteLastModifiedUtc',
    ]);
    requireAny('Name', [
      'tradingName',
      'TradingName',
      'NAME',
      'VORNAME',
      'consignorInfo.firstName',
      'ConsignorInfo.FirstName',
      'firstName',
      'FirstName',
      'consignorInfo.lastName',
      'ConsignorInfo.LastName',
      'lastName',
      'LastName',
    ]);
    requireAny('Email', ['emailAddress', 'EmailAddress', 'EMAIL']);
    requireAny('Phone number', ['phoneNumber', 'PhoneNumber', 'TEL']);
    requireAny('Address street', [
      'consignorAddress.streetAddress',
      'ConsignorAddress.StreetAddress',
      'streetAddress',
      'StreetAddress',
      'STREET',
    ]);
    requireAny('Address postal code', [
      'consignorAddress.postalCode',
      'ConsignorAddress.PostalCode',
      'postalCode',
      'PostalCode',
      'PLZ',
    ]);
    requireAny('Address city', [
      'consignorAddress.city',
      'ConsignorAddress.City',
      'city',
      'City',
      'ORT',
    ]);
    requireAny('Address country', [
      'consignorAddress.country.isoCountryCode',
      'ConsignorAddress.Country.IsoCountryCode',
      'consignorAddress.country',
      'ConsignorAddress.Country',
      'country',
      'Country',
      'LAND',
    ]);
    if (_requiresBankReportFields(row)) {
      requireAny('Bank name', [
        'bankingDetails.bankName',
        'BankingDetails.BankName',
        'bankName',
        'BankName',
        'BG_NAME',
        'BG_Name',
      ]);
      requireAny('Bank account / IBAN', [
        'bankingDetails.accountNumber',
        'BankingDetails.AccountNumber',
        'accountNumber',
        'AccountNumber',
        'KONTO',
      ]);
    }
    requireAny('Payment option', ['paymentOption', 'PaymentOption']);
    requireAny('Correspondence language', [
      'correspondence',
      'Correspondence',
      'SPRACHE',
    ]);
    requireAny('Contracts', ['contracts', 'Contracts']);

    if (missing.isEmpty) {
      return null;
    }

    return RemoteReportFieldIssue(
      summaryIndex: index,
      total: total,
      consignorId: _reportConsignorId(row)?.toString(),
      missingFields: missing,
      availableFields: row.keys.map((key) => key.toString()).toList()..sort(),
    );
  }

  bool _requiresBankReportFields(Map<String, dynamic> row) {
    final countryCode = _firstReportString(row, const [
      'bankingDetails.bankCountry.isoCountryCode',
      'BankingDetails.BankCountry.IsoCountryCode',
      'bankingDetails.bankCountry',
      'BankingDetails.BankCountry',
      'BG_Land',
      'BG_LAND',
      'consignorAddress.country.isoCountryCode',
      'ConsignorAddress.Country.IsoCountryCode',
      'consignorAddress.country',
      'ConsignorAddress.Country',
      'LAND',
    ]);

    final normalized =
        countryCode?.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');

    return const {'AR', 'ARG', 'DE', 'DEU', 'CH', 'CHE'}.contains(normalized);
  }

  String? _firstReportString(Map<String, dynamic> row, List<String> paths) {
    for (final path in paths) {
      final value = _reportValue(row, path);
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is Map) {
        final iso = value['isoCountryCode'] ??
            value['IsoCountryCode'] ??
            value['countryCode'] ??
            value['CountryCode'];
        if (iso != null && iso.toString().trim().isNotEmpty) {
          return iso.toString().trim();
        }
      }
    }

    return null;
  }

  bool _hasReportValue(Map<String, dynamic> row, String path) {
    final current = _reportValue(row, path);

    if (current == null) {
      return false;
    }
    if (current is String) {
      return current.trim().isNotEmpty;
    }
    return true;
  }

  Object? _reportValue(Map<String, dynamic> row, String path) {
    if (row.containsKey(path)) {
      return row[path];
    }

    Object? current = row;
    for (final segment in path.split('.')) {
      if (current is! Map) {
        return null;
      }
      current = current[segment];
    }
    return current;
  }

  String _requestDescription(RequestOptions options) {
    return '${options.method} ${options.uri}';
  }

  String _responseBodySummary(Object? body) {
    if (body == null) {
      return 'empty';
    }

    if (body is String) {
      return _compactBodyText(body);
    }

    if (body is List<int>) {
      return '${body.length} bytes';
    }

    try {
      return _compactBodyText(jsonEncode(body));
    } catch (_) {
      return _compactBodyText(body.toString());
    }
  }

  String _compactBodyText(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) {
      return 'empty';
    }

    const maxLength = 500;
    if (compact.length <= maxLength) {
      return compact;
    }

    return '${compact.substring(0, maxLength)}...';
  }

  String _friendlyDioError(DioException e) {
    final status = e.response?.statusCode;
    final request = _requestDescription(e.requestOptions);
    final statusText = e.response?.statusMessage?.trim();
    final responseBody = _responseBodySummary(e.response?.data);

    if (status == 401 || status == 403) {
      return 'Authentication failed ($status) for $request. Sign in again or '
          'verify the token scope. Response body: $responseBody.';
    }

    if (status != null) {
      final reason =
          statusText == null || statusText.isEmpty ? '' : ' $statusText';
      return 'API request failed: $request returned HTTP $status$reason. '
          'Response body: $responseBody.';
    }

    if (e.type == DioExceptionType.connectionError) {
      if (kIsWeb) {
        return 'Browser network error for $request. This usually means CORS, '
            'certificate, DNS, or blocked browser requests. Try the Windows '
            'build first.';
      }

      return 'Network connection failed for $request. Check VPN, DNS, '
          'certificates, and whether the API host is reachable.';
    }

    if (e.type == DioExceptionType.connectionTimeout) {
      return 'Could not connect to the API in time for $request. Check URL, '
          'VPN, DNS, and certificate access.';
    }

    if (e.type == DioExceptionType.receiveTimeout) {
      return 'The API responded too slowly for $request. The endpoint is '
          'reachable, but it took too long to return data.';
    }

    if (e.type == DioExceptionType.sendTimeout) {
      return 'Uploading data to the API took too long for $request.';
    }

    return e.message ?? e.toString();
  }

  int? _toInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
}

class RemoteSnapshot {
  const RemoteSnapshot({
    this.consignors = const [],
    this.contracts = const [],
    this.missingReportFields = const [],
    this.reportRowCount = 0,
  });

  final List<Consignor> consignors;
  final List<ContractRecord> contracts;
  final List<RemoteReportFieldIssue> missingReportFields;
  final int reportRowCount;
}

class RemoteContractFetchResult {
  const RemoteContractFetchResult({
    this.contracts = const [],
    this.checkedConsignorCount = 0,
    this.analyzedDocumentCount = 0,
    this.skippedConsignorIds = const [],
    this.failedMessages = const [],
  });

  final List<ContractRecord> contracts;
  final int checkedConsignorCount;
  final int analyzedDocumentCount;
  final List<int> skippedConsignorIds;
  final List<String> failedMessages;

  int get skippedCount => skippedConsignorIds.length;
  int get failedCount => failedMessages.length;
}

class RemoteReportFieldIssue {
  const RemoteReportFieldIssue({
    required this.summaryIndex,
    required this.total,
    required this.consignorId,
    required this.missingFields,
    required this.availableFields,
  });

  final int summaryIndex;
  final int total;
  final String? consignorId;
  final List<String> missingFields;
  final List<String> availableFields;

  String get title {
    final id = consignorId == null ? '' : ' · ID $consignorId';
    return 'Row ${summaryIndex + 1} of $total$id';
  }
}

class RemoteConsignorDetail {
  const RemoteConsignorDetail({
    this.consignor,
    this.contracts = const [],
  });

  final Consignor? consignor;
  final List<ContractRecord> contracts;
}

class ConsignorReference {
  ConsignorReference({
    required this.systemReferenceConsignor,
    required this.systemReferenceCustomer,
    this.abacusSubjectId,
    this.customerAction = 'Unknown',
    this.consignorAction = 'Unknown',
  });

  final int systemReferenceConsignor;
  final int systemReferenceCustomer;
  final int? abacusSubjectId;
  final String customerAction;
  final String consignorAction;

  bool get linkedExistingCustomer =>
      customerAction.toLowerCase() == 'existing' &&
      consignorAction.toLowerCase() == 'created';

  factory ConsignorReference.fromJson(Map<String, dynamic> json) =>
      ConsignorReference(
        systemReferenceConsignor: _toIntAny(
              json['systemReferenceConsignor'] ??
                  json['SystemReferenceConsignor'],
            ) ??
            _toIntAny(json['consignorId'] ?? json['ConsignorId']) ??
            0,
        systemReferenceCustomer: _toIntAny(
              json['systemReferenceCustomer'] ??
                  json['SystemReferenceCustomer'],
            ) ??
            _toIntAny(json['customerId'] ?? json['CustomerId']) ??
            0,
        abacusSubjectId:
            _toIntAny(json['abacusSubjectId'] ?? json['AbacusSubjectId']),
        customerAction:
            (json['customerAction'] ?? json['CustomerAction'])?.toString() ??
                'Unknown',
        consignorAction:
            (json['consignorAction'] ?? json['ConsignorAction'])?.toString() ??
                'Unknown',
      );
}

class PushConsignorResult {
  const PushConsignorResult({
    this.references = const {},
    this.syncedConsignors = const {},
    this.pushedCount = 0,
  });

  final Map<String, ConsignorReference> references;
  final Map<String, Consignor> syncedConsignors;
  final int pushedCount;
}

int? _toIntAny(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');
