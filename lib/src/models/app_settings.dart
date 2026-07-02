class AppSettings {
  static const defaultContractsGetAll = '/api/consignors-app/contracts/get-all';
  static const legacyFilesGetAll = '/api/consignors-app/files/get-all';

  const AppSettings({
    this.apiBaseUrl = '',
    this.consignorsGetAll = '/api/consignors-app/consignors/get-all',
    this.consignorsGetOne = '/api/consignors-app/consignors/get/{id}',
    this.consignorsUpdateOne = '/api/consignors-app/consignors/update/{id}',
    this.consignorsBulkUpdate = '/api/consignors-app/consignors/bulk-create',
    this.contractsGetAll = defaultContractsGetAll,
    this.contractsGetOne = '/api/consignors-app/files/get/{id}',
    this.contractsUpdateOne = '/api/consignors-app/files/update/{id}',
    this.contractsBulkUpdate = '/api/consignors-app/files/bulk-create',
    this.originPrefixesGetAll = '/api/consignors-app/origins/prefixes',
    this.customersSearch = '/api/consignors-app/customers/search',
    this.oauthClientId = '624093e0-ab94-4eef-9ab1-af1641767586',
    this.oauthTenantId = 'cd78fc46-542b-4310-a4e6-9b30e28d2ba1',
    this.oauthScope =
        'api://205427fe-d62e-41ba-a5a3-6666c6f37784/access_as_user',
    this.oauthRedirectUri = 'http://localhost',
    this.lastSyncCompletedUtc,
  });

  final String apiBaseUrl;
  final String consignorsGetAll;
  final String consignorsGetOne;
  final String consignorsUpdateOne;
  final String consignorsBulkUpdate;
  final String contractsGetAll;
  final String contractsGetOne;
  final String contractsUpdateOne;
  final String contractsBulkUpdate;
  final String originPrefixesGetAll;
  final String customersSearch;
  final String oauthClientId;
  final String oauthTenantId;
  final String oauthScope;
  final String oauthRedirectUri;
  final DateTime? lastSyncCompletedUtc;

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        apiBaseUrl: json['apiBaseUrl'] as String? ?? '',
        consignorsGetAll: json['consignorsGetAll'] as String? ??
            '/api/consignors-app/consignors/get-all',
        consignorsGetOne: json['consignorsGetOne'] as String? ??
            '/api/consignors-app/consignors/get/{id}',
        consignorsUpdateOne: json['consignorsUpdateOne'] as String? ??
            '/api/consignors-app/consignors/update/{id}',
        consignorsBulkUpdate: json['consignorsBulkUpdate'] as String? ??
            '/api/consignors-app/consignors/bulk-create',
        contractsGetAll: _migrateContractsGetAll(json['contractsGetAll']),
        contractsGetOne: json['contractsGetOne'] as String? ??
            '/api/consignors-app/files/get/{id}',
        contractsUpdateOne: json['contractsUpdateOne'] as String? ??
            '/api/consignors-app/files/update/{id}',
        contractsBulkUpdate: json['contractsBulkUpdate'] as String? ??
            '/api/consignors-app/files/bulk-create',
        originPrefixesGetAll: json['originPrefixesGetAll'] as String? ??
            '/api/consignors-app/origins/prefixes',
        customersSearch: json['customersSearch'] as String? ??
            '/api/consignors-app/customers/search',
        oauthClientId: json['oauthClientId'] as String? ??
            '624093e0-ab94-4eef-9ab1-af1641767586',
        oauthTenantId: json['oauthTenantId'] as String? ??
            'cd78fc46-542b-4310-a4e6-9b30e28d2ba1',
        oauthScope: json['oauthScope'] as String? ??
            'api://205427fe-d62e-41ba-a5a3-6666c6f37784/access_as_user',
        oauthRedirectUri:
            json['oauthRedirectUri'] as String? ?? 'http://localhost',
        lastSyncCompletedUtc: DateTime.tryParse(
          json['lastSyncCompletedUtc']?.toString() ?? '',
        ),
      );

  static String _migrateContractsGetAll(Object? value) {
    final text = value?.toString().trim();
    if (text == null ||
        text.isEmpty ||
        text.toLowerCase() == legacyFilesGetAll.toLowerCase()) {
      return defaultContractsGetAll;
    }

    return text;
  }

  Map<String, dynamic> toJson() => {
        'apiBaseUrl': apiBaseUrl,
        'consignorsGetAll': consignorsGetAll,
        'consignorsGetOne': consignorsGetOne,
        'consignorsUpdateOne': consignorsUpdateOne,
        'consignorsBulkUpdate': consignorsBulkUpdate,
        'contractsGetAll': contractsGetAll,
        'contractsGetOne': contractsGetOne,
        'contractsUpdateOne': contractsUpdateOne,
        'contractsBulkUpdate': contractsBulkUpdate,
        'originPrefixesGetAll': originPrefixesGetAll,
        'customersSearch': customersSearch,
        'oauthClientId': oauthClientId,
        'oauthTenantId': oauthTenantId,
        'oauthScope': oauthScope,
        'oauthRedirectUri': oauthRedirectUri,
        'lastSyncCompletedUtc': lastSyncCompletedUtc?.toUtc().toIso8601String(),
      };

  AppSettings copyWith({
    String? apiBaseUrl,
    String? consignorsGetAll,
    String? consignorsGetOne,
    String? consignorsUpdateOne,
    String? consignorsBulkUpdate,
    String? contractsGetAll,
    String? contractsGetOne,
    String? contractsUpdateOne,
    String? contractsBulkUpdate,
    String? originPrefixesGetAll,
    String? customersSearch,
    String? oauthClientId,
    String? oauthTenantId,
    String? oauthScope,
    String? oauthRedirectUri,
    DateTime? lastSyncCompletedUtc,
  }) =>
      AppSettings(
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        consignorsGetAll: consignorsGetAll ?? this.consignorsGetAll,
        consignorsGetOne: consignorsGetOne ?? this.consignorsGetOne,
        consignorsUpdateOne: consignorsUpdateOne ?? this.consignorsUpdateOne,
        consignorsBulkUpdate: consignorsBulkUpdate ?? this.consignorsBulkUpdate,
        contractsGetAll: contractsGetAll ?? this.contractsGetAll,
        contractsGetOne: contractsGetOne ?? this.contractsGetOne,
        contractsUpdateOne: contractsUpdateOne ?? this.contractsUpdateOne,
        contractsBulkUpdate: contractsBulkUpdate ?? this.contractsBulkUpdate,
        originPrefixesGetAll: originPrefixesGetAll ?? this.originPrefixesGetAll,
        customersSearch: customersSearch ?? this.customersSearch,
        oauthClientId: oauthClientId ?? this.oauthClientId,
        oauthTenantId: oauthTenantId ?? this.oauthTenantId,
        oauthScope: oauthScope ?? this.oauthScope,
        oauthRedirectUri: oauthRedirectUri ?? this.oauthRedirectUri,
        lastSyncCompletedUtc: lastSyncCompletedUtc ?? this.lastSyncCompletedUtc,
      );
}
