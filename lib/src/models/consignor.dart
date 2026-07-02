import 'dart:math';

import '../domain/consignor_type.dart';
import '../utils/phone_number_parser.dart';
import 'address.dart';
import 'banking_details.dart';
import 'payment_option.dart';
import 'person.dart';
import 'sync_status.dart';

class Consignor {
  Consignor({
    required this.id,
    this.systemReferenceConsignor = 0,
    this.systemReferenceCustomer = 0,
    this.abacusSubjectId,
    this.existingCustomerId,
    this.existingCustomerLabel,
    bool isLegalEntity = false,
    ConsignorType? consignorType,
    this.tradingName = '',
    Person? consignorInfo,
    this.vatLiability = false,
    this.vatNumber = '',
    this.phonePrefix = '',
    this.phonePrefixOriginId,
    this.phoneNumber = '',
    this.emailAddress = '',
    Address? consignorAddress,
    BankingDetails? bankingDetails,
    this.paymentOption = PaymentOption.bankTransfer,
    this.passportValidUntil,
    this.checkedByLeu = true,
    this.ancientCoinsSubscribed = false,
    this.worldCoinsSubscribed = false,
    this.newsletterSubscribed = true,
    this.collectingArea = '',
    this.correspondence,
    this.references = '',
    this.creditLimit = 0,
    this.discount,
    this.consignmentFeeFloorAuction,
    this.consignmentFeeWebAuction,
    this.eori = '',
    this.username = '',
    this.password = '',
    DateTime? lastModifiedUtc,
    this.syncStatus = RecordSyncStatus.draft,
    this.syncErrorMessage,
    this.lastSyncedUtc,
    this.remoteLastModifiedUtc,
    this.lastEditedByUsername,
    this.lastEditedAtUtc,
  })  : consignorType = consignorType ??
            (isLegalEntity
                ? ConsignorType.legalEntity
                : ConsignorType.naturalPerson),
        consignorInfo = consignorInfo ?? Person(),
        consignorAddress = consignorAddress ?? Address(),
        bankingDetails = bankingDetails ?? BankingDetails(),
        lastModifiedUtc = lastModifiedUtc ?? DateTime.now().toUtc();

  String id;
  int systemReferenceConsignor;
  int systemReferenceCustomer;
  int? abacusSubjectId;
  int? existingCustomerId;
  String? existingCustomerLabel;
  ConsignorType consignorType;
  String tradingName;
  Person consignorInfo;
  bool vatLiability;
  String vatNumber;
  String phonePrefix;
  int? phonePrefixOriginId;
  String phoneNumber;
  String emailAddress;
  Address consignorAddress;
  BankingDetails bankingDetails;
  PaymentOption paymentOption;
  DateTime? passportValidUntil;
  bool checkedByLeu;
  bool ancientCoinsSubscribed;
  bool worldCoinsSubscribed;
  bool newsletterSubscribed;
  String collectingArea;
  String? correspondence;
  String references;
  double creditLimit;
  double? discount;
  double? consignmentFeeFloorAuction;
  double? consignmentFeeWebAuction;
  String eori;
  String username;
  String password;
  DateTime lastModifiedUtc;
  RecordSyncStatus syncStatus;
  String? syncErrorMessage;
  DateTime? lastSyncedUtc;
  DateTime? remoteLastModifiedUtc;
  String? lastEditedByUsername;
  DateTime? lastEditedAtUtc;

  bool get hasRemoteReference => systemReferenceConsignor > 0;

  bool get isLegalEntity => consignorType == ConsignorType.legalEntity;

  set isLegalEntity(bool value) {
    consignorType =
        value ? ConsignorType.legalEntity : ConsignorType.naturalPerson;
  }

  bool get isSoleProprietor => consignorType == ConsignorType.soleProprietor;

  set isSoleProprietor(bool value) {
    consignorType =
        value ? ConsignorType.soleProprietor : ConsignorType.naturalPerson;
  }

  bool get usesTradingName => isLegalEntity || isSoleProprietor;

  bool get linksExistingCustomer =>
      existingCustomerId != null && systemReferenceConsignor <= 0;

  bool get synced =>
      syncStatus == RecordSyncStatus.synced ||
      syncStatus == RecordSyncStatus.finalized;

  bool get needsSync => syncStatus.needsSync;

  String get fullPhoneNumber => PhoneNumberParser.combine(
        prefix: phonePrefix,
        localNumber: phoneNumber,
      );

  factory Consignor.empty() {
    final credentials = _GeneratedCredentials.create();

    return Consignor(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      checkedByLeu: true,
      ancientCoinsSubscribed: false,
      worldCoinsSubscribed: false,
      newsletterSubscribed: true,
      collectingArea: '',
      correspondence: 'en',
      references: '',
      creditLimit: 0,
      discount: null,
      consignmentFeeFloorAuction: null,
      consignmentFeeWebAuction: null,
      eori: '',
      username: credentials.username,
      password: credentials.password,
      paymentOption: PaymentOption.bankTransfer,
      syncStatus: RecordSyncStatus.draft,
    );
  }

  factory Consignor.fromJson(Map<String, dynamic> json) {
    final systemReferenceCustomer = _toInt(
          json['systemReferenceCustomer'] ??
              json['SystemReferenceCustomer'] ??
              json['customerId'] ??
              json['CustomerId'],
        ) ??
        0;

    final systemReferenceConsignor = _toInt(
          json['systemReferenceConsignor'] ??
              json['SystemReferenceConsignor'] ??
              json['consignorId'] ??
              json['ConsignorId'],
        ) ??
        0;

    final abacusSubjectId = _toInt(
      json['abacusSubjectId'] ?? json['AbacusSubjectId'],
    );

    final hasRemoteReference = systemReferenceConsignor > 0;

    final contactPersonJson = _firstMap(json, const [
      'contactPerson',
      'ContactPerson',
      'contact',
      'Contact',
      'primaryContact',
      'PrimaryContact',
      'contactPersonDto',
      'ContactPersonDto',
      'authorizedContact',
      'AuthorizedContact',
    ]);
    final nestedPersonJson = _firstMap(json, const [
      'consignorInfo',
      'ConsignorInfo',
      'person',
      'Person',
    ]);
    final personJson = _mergeNonEmptyMaps([
      _personFieldsFromRoot(json),
      contactPersonJson,
      nestedPersonJson,
    ]);
    final tradingName = _resolveTradingName(json, contactPersonJson);
    final contactPhoneNumber = contactPersonJson == null
        ? null
        : _firstNonEmptyValue(contactPersonJson, const [
            'phoneNumber',
            'PhoneNumber',
            'phone',
            'Phone',
            'TEL',
            'Tel',
          ]);
    final rawPhoneNumber = _toString(
      contactPhoneNumber ??
          _firstNonEmptyValue(json, const [
            'phoneNumber',
            'PhoneNumber',
            'phone',
            'Phone',
            'TEL',
            'Tel',
          ]),
    );
    final parsedPhone = PhoneNumberParser.parse(rawPhoneNumber);
    final contactPhonePrefix = contactPersonJson == null
        ? null
        : _firstNonEmptyValue(contactPersonJson, const [
            'phonePrefix',
            'PhonePrefix',
            'phoneCountryPrefix',
            'PhoneCountryPrefix',
          ]);
    final explicitPhonePrefix = _toString(
      contactPhonePrefix ??
          _firstNonEmptyValue(json, const [
            'phonePrefix',
            'PhonePrefix',
            'phoneCountryPrefix',
            'PhoneCountryPrefix',
          ]),
    );
    final explicitPhonePrefixOriginId = _toInt(
      json['phonePrefixOriginId'] ??
          json['PhonePrefixOriginId'] ??
          json['phonePrefixId'] ??
          json['PhonePrefixId'],
    );
    final rawConsignorType = json['consignorType'] ??
        json['ConsignorType'] ??
        json['partyType'] ??
        json['PartyType'] ??
        json['customerType'] ??
        json['CustomerType'];
    final legacyIsLegalEntity =
        _toBool(json['isLegalEntity'] ?? json['IsLegalEntity']) ?? false;
    final legacyIsSoleProprietor =
        _toBool(json['isSoleProprietor'] ?? json['IsSoleProprietor']) ?? false;
    var resolvedConsignorType = legacyIsSoleProprietor
        ? ConsignorType.soleProprietor
        : ConsignorTypeX.fromAny(
            rawConsignorType,
            legacyIsLegalEntity: legacyIsLegalEntity,
          );
    final hasExplicitConsignorType = rawConsignorType != null ||
        legacyIsLegalEntity ||
        legacyIsSoleProprietor;
    if (!hasExplicitConsignorType &&
        tradingName.trim().isNotEmpty &&
        (contactPersonJson != null || !_personHasName(personJson))) {
      resolvedConsignorType = ConsignorType.legalEntity;
    }
    final addressJson = _firstMap(json, const [
          'consignorAddress',
          'ConsignorAddress',
          'address',
          'Address',
          'customerAddress',
          'CustomerAddress',
        ]) ??
        json;
    final bankingJson = _firstMap(json, const [
          'bankingDetails',
          'BankingDetails',
          'bankingDetailsDto',
          'BankingDetailsDto',
          'bankDetails',
          'BankDetails',
          'paymentDetails',
          'PaymentDetails',
        ]) ??
        json;

    return Consignor(
      id: (json['id'] ??
              json['Id'] ??
              json['systemReferenceCustomer'] ??
              json['SystemReferenceCustomer'] ??
              json['systemReferenceConsignor'] ??
              json['SystemReferenceConsignor'] ??
              DateTime.now().microsecondsSinceEpoch)
          .toString(),
      systemReferenceConsignor: systemReferenceConsignor,
      systemReferenceCustomer: systemReferenceCustomer,
      abacusSubjectId: abacusSubjectId,
      existingCustomerId: _toInt(
        json['existingCustomerId'] ?? json['ExistingCustomerId'],
      ),
      existingCustomerLabel: _toNullableString(
        json['existingCustomerLabel'] ?? json['ExistingCustomerLabel'],
      ),
      consignorType: resolvedConsignorType,
      tradingName: tradingName,
      consignorInfo: Person.fromJson(personJson),
      vatLiability:
          _toBool(json['vatLiability'] ?? json['VatLiability']) ?? false,
      vatNumber: _toString(
        _firstNonEmptyValue(json, const [
          'vatNumber',
          'VatNumber',
          'VAT',
          'MWST',
        ]),
      ),
      phonePrefix: explicitPhonePrefix.isNotEmpty
          ? explicitPhonePrefix
          : parsedPhone.prefix,
      phonePrefixOriginId: explicitPhonePrefixOriginId,
      phoneNumber: explicitPhonePrefix.isNotEmpty
          ? _stripExplicitPrefix(rawPhoneNumber, explicitPhonePrefix)
          : parsedPhone.localNumber,
      emailAddress: _toString(_contactEmail(contactPersonJson) ??
          _firstNonEmptyValue(json, const [
            'emailAddress',
            'EmailAddress',
            'email',
            'Email',
            'EMAIL',
          ])),
      consignorAddress: Address.fromJson(addressJson),
      bankingDetails: BankingDetails.fromJson(bankingJson),
      paymentOption: PaymentOptionX.fromAny(
          json['paymentOption'] ?? json['PaymentOption']),
      passportValidUntil: DateTime.tryParse(
        (json['passportValidUntil'] ??
                    json['PassportValidUntil'] ??
                    json['passportDate'] ??
                    json['PassportDate'])
                ?.toString() ??
            '',
      ),
      checkedByLeu:
          (json['checkedByLeu'] ?? json['CheckedByLeu']) as bool? ?? true,
      ancientCoinsSubscribed: (json['ancientCoinsSubscribed'] ??
              json['AncientCoinsSubscribed']) as bool? ??
          false,
      worldCoinsSubscribed: (json['worldCoinsSubscribed'] ??
              json['WorldCoinsSubscribed']) as bool? ??
          false,
      newsletterSubscribed: (json['newsletterSubscribed'] ??
              json['NewsletterSubscribed']) as bool? ??
          true,
      collectingArea:
          _toString(json['collectingArea'] ?? json['CollectingArea']),
      correspondence: _normalizeCorrespondence(
        json['correspondence'] ?? json['Correspondence'],
      ),
      references: _toString(json['references'] ?? json['References']),
      creditLimit: _toDouble(json['creditLimit'] ?? json['CreditLimit']) ?? 0,
      discount: _toDouble(json['discount'] ?? json['Discount']),
      consignmentFeeFloorAuction: _toDouble(
        json['consignmentFeeFloorAuction'] ??
            json['ConsignmentFeeFloorAuction'] ??
            json['consignorPrintedTerms'] ??
            json['ConsignorPrintedTerms'],
      ),
      consignmentFeeWebAuction: _toDouble(
        json['consignmentFeeWebAuction'] ??
            json['ConsignmentFeeWebAuction'] ??
            json['consignorElectronicTerms'] ??
            json['ConsignorElectronicTerms'],
      ),
      eori: _toString(json['eori'] ?? json['Eori'] ?? json['EORI']),
      username: _toString(json['username'] ?? json['Username']),
      password: _toString(json['password'] ?? json['Password']),
      lastModifiedUtc: DateTime.tryParse(
            (json['lastModifiedUtc'] ?? json['LastModifiedUtc'])?.toString() ??
                '',
          )?.toUtc() ??
          DateTime.now().toUtc(),
      syncStatus: RecordSyncStatusX.fromAny(
        json['syncStatus'] ?? json['SyncStatus'],
        hasRemoteReference: hasRemoteReference,
        legacySynced: (json['synced'] ?? json['Synced']) as bool?,
      ),
      syncErrorMessage: _toNullableString(
        json['syncErrorMessage'] ?? json['SyncErrorMessage'],
      ),
      lastSyncedUtc: DateTime.tryParse(
        (json['lastSyncedUtc'] ?? json['LastSyncedUtc'])?.toString() ?? '',
      )?.toUtc(),
      remoteLastModifiedUtc: DateTime.tryParse(
        (json['remoteLastModifiedUtc'] ?? json['RemoteLastModifiedUtc'])
                ?.toString() ??
            '',
      )?.toUtc(),
      lastEditedByUsername: _toNullableString(
        json['lastEditedByUsername'] ?? json['LastEditedByUsername'],
      ),
      lastEditedAtUtc: DateTime.tryParse(
        (json['lastEditedAtUtc'] ?? json['LastEditedAtUtc'])?.toString() ?? '',
      )?.toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'systemReferenceConsignor': systemReferenceConsignor,
        'systemReferenceCustomer': systemReferenceCustomer,
        'abacusSubjectId': abacusSubjectId,
        'existingCustomerId': existingCustomerId,
        'existingCustomerLabel': existingCustomerLabel,
        'isLegalEntity': isLegalEntity,
        'isSoleProprietor': isSoleProprietor,
        'consignorType': consignorType.apiName,
        'tradingName': tradingName.trim().isEmpty ? null : tradingName.trim(),
        'consignorInfo': consignorInfo.toJson(),
        'vatLiability': vatLiability,
        'vatNumber': vatNumber.trim().isEmpty ? null : vatNumber.trim(),
        'phonePrefix': phonePrefix.trim().isEmpty ? null : phonePrefix.trim(),
        'phonePrefixOriginId': phonePrefixOriginId,
        'phoneNumber': fullPhoneNumber.trim(),
        'emailAddress': emailAddress.trim(),
        'consignorAddress': consignorAddress.toJson(),
        'bankingDetails': bankingDetails.toJson(),
        'bankingDetailsDto': bankingDetails.toJson(),
        'paymentOption': paymentOption.apiName,
        'passportValidUntil': passportValidUntil?.toUtc().toIso8601String(),
        'checkedByLeu': checkedByLeu,
        'ancientCoinsSubscribed': ancientCoinsSubscribed,
        'worldCoinsSubscribed': worldCoinsSubscribed,
        'newsletterSubscribed': newsletterSubscribed,
        'collectingArea':
            collectingArea.trim().isEmpty ? null : collectingArea.trim(),
        'correspondence': _normalizeCorrespondence(correspondence),
        'references': references.trim().isEmpty ? null : references.trim(),
        'creditLimit': creditLimit,
        'discount': discount,
        'consignmentFeeFloorAuction': consignmentFeeFloorAuction,
        'consignmentFeeWebAuction': consignmentFeeWebAuction,
        'eori': eori.trim().isEmpty ? null : eori.trim(),
        'username': username.trim().isEmpty ? null : username.trim(),
        'password': password.trim().isEmpty ? null : password.trim(),
        'lastModifiedUtc': lastModifiedUtc.toUtc().toIso8601String(),
        'syncStatus': syncStatus.name,
        'syncErrorMessage': syncErrorMessage,
        'lastSyncedUtc': lastSyncedUtc?.toUtc().toIso8601String(),
        'remoteLastModifiedUtc':
            remoteLastModifiedUtc?.toUtc().toIso8601String(),
        'lastEditedByUsername': lastEditedByUsername,
        'lastEditedAtUtc': lastEditedAtUtc?.toUtc().toIso8601String(),
        'synced': synced,
      };

  String get displayName {
    if ((isLegalEntity || isSoleProprietor) && tradingName.trim().isNotEmpty) {
      return tradingName.trim();
    }
    return consignorInfo.fullName;
  }

  void clearExistingCustomerSelection() {
    existingCustomerId = null;
    existingCustomerLabel = null;
  }

  void ensureGeneratedCredentials() {
    if (username.trim().isNotEmpty && password.trim().isNotEmpty) {
      return;
    }

    final credentials = _GeneratedCredentials.create();
    username = credentials.username;
    password = credentials.password;
  }

  void markDraft([String? editorUsername]) {
    _markEdited(editorUsername);
    syncErrorMessage = null;
    syncStatus = RecordSyncStatus.draft;
  }

  void markReadyForSync([String? editorUsername]) {
    _markEdited(editorUsername);
    syncErrorMessage = null;
    syncStatus = RecordSyncStatus.pendingSync;
  }

  void markLocalChange([String? editorUsername]) {
    _markEdited(editorUsername);
    syncErrorMessage = null;
    syncStatus = hasRemoteReference
        ? RecordSyncStatus.pendingSync
        : RecordSyncStatus.draft;
  }

  void _markEdited(String? editorUsername) {
    final nowUtc = DateTime.now().toUtc();
    lastModifiedUtc = nowUtc;
    lastEditedAtUtc = nowUtc;
    final normalized = editorUsername?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      lastEditedByUsername = normalized;
    }
  }

  void markSynced({DateTime? remoteModifiedUtc}) {
    syncStatus = RecordSyncStatus.synced;
    syncErrorMessage = null;
    lastSyncedUtc = DateTime.now().toUtc();
    remoteLastModifiedUtc = remoteModifiedUtc ?? lastModifiedUtc;
  }

  void markRemoteSnapshot() {
    syncStatus = RecordSyncStatus.synced;
    syncErrorMessage = null;
    lastSyncedUtc = DateTime.now().toUtc();
    remoteLastModifiedUtc = lastModifiedUtc;
  }

  void markSyncFailed(String message) {
    syncStatus = RecordSyncStatus.syncFailed;
    syncErrorMessage = message.trim();
  }

  static int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static bool? _toBool(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase().trim();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return null;
  }

  static Map<String, dynamic>? _firstMap(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value is Map) {
        return value.cast<String, dynamic>();
      }
    }
    return null;
  }

  static Object? _firstNonEmptyValue(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      return value;
    }
    return null;
  }

  static Map<String, dynamic> _mergeNonEmptyMaps(
    Iterable<Map<String, dynamic>?> maps,
  ) {
    final merged = <String, dynamic>{};
    for (final map in maps) {
      if (map == null) continue;
      for (final entry in map.entries) {
        final value = entry.value;
        if (value == null) continue;
        if (value is String && value.trim().isEmpty) continue;
        merged[entry.key] = value;
      }
    }
    return merged;
  }

  static Map<String, dynamic> _personFieldsFromRoot(
    Map<String, dynamic> json,
  ) {
    const aliases = {
      'firstName': [
        'firstName',
        'FirstName',
        'firstname',
        'Firstname',
        'VORNAME',
        'Vorname',
      ],
      'lastName': [
        'lastName',
        'LastName',
        'lastname',
        'Lastname',
        'NACHNAME',
        'Nachname',
        'NAME',
        'Name',
      ],
      'fullName': [
        'personName',
        'PersonName',
        'contactName',
        'ContactName',
      ],
      'title': ['title', 'Title', 'TitleId', 'titleId'],
      'salutation': ['salutation', 'Salutation', 'SalutationId'],
      'dateOfBirth': ['dateOfBirth', 'DateOfBirth', 'birthDate', 'GEBDAT'],
      'nationality': ['nationality', 'Nationality'],
    };

    final mapped = <String, dynamic>{};
    for (final entry in aliases.entries) {
      final value = _firstNonEmptyValue(json, entry.value);
      if (value != null) {
        mapped[entry.key] = value;
      }
    }

    return mapped;
  }

  static bool _personHasName(Map<String, dynamic> json) {
    return _toString(_firstNonEmptyValue(json, const [
          'firstName',
          'FirstName',
          'VORNAME',
        ])).trim().isNotEmpty ||
        _toString(_firstNonEmptyValue(json, const [
          'lastName',
          'LastName',
          'NAME',
        ])).trim().isNotEmpty ||
        _toString(_firstNonEmptyValue(json, const [
          'fullName',
          'FullName',
          'displayName',
          'DisplayName',
        ])).trim().isNotEmpty;
  }

  static String _resolveTradingName(
    Map<String, dynamic> json,
    Map<String, dynamic>? contactPersonJson,
  ) {
    final explicit = _toString(
      _firstNonEmptyValue(json, const [
        'tradingName',
        'TradingName',
        'companyName',
        'CompanyName',
        'legalName',
        'LegalName',
        'firma',
        'Firma',
      ]),
    );
    if (explicit.trim().isNotEmpty) return explicit;

    final abacusName = _toString(
      _firstNonEmptyValue(json, const ['NAME', 'Name', 'name']),
    );
    final looksLikeCompany = contactPersonJson != null ||
        (_toBool(json['isLegalEntity'] ?? json['IsLegalEntity']) ?? false) ||
        _toString(
          _firstNonEmptyValue(json, const [
            'companyId',
            'CompanyId',
            'contactPersonId',
            'ContactPersonId',
          ]),
        ).trim().isNotEmpty;

    return looksLikeCompany ? abacusName : '';
  }

  static Object? _contactEmail(Map<String, dynamic>? contactPersonJson) {
    if (contactPersonJson == null) return null;
    return _firstNonEmptyValue(contactPersonJson, const [
      'emailAddress',
      'EmailAddress',
      'email',
      'Email',
      'EMAIL',
    ]);
  }

  static String _stripExplicitPrefix(
      String rawPhoneNumber, String explicitPrefix) {
    final trimmedRaw = rawPhoneNumber.trim();
    final trimmedPrefix = explicitPrefix.trim();
    if (trimmedRaw.isEmpty || trimmedPrefix.isEmpty) {
      return trimmedRaw;
    }

    if (trimmedRaw.startsWith(trimmedPrefix)) {
      return trimmedRaw.substring(trimmedPrefix.length).trim();
    }

    final parsed = PhoneNumberParser.parse(trimmedRaw);
    if (parsed.prefix == trimmedPrefix && parsed.localNumber.isNotEmpty) {
      return parsed.localNumber;
    }

    return trimmedRaw;
  }

  static String _toString(Object? value) => value?.toString() ?? '';

  static String? _toNullableString(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static String? _normalizeCorrespondence(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;

    switch (text.toLowerCase()) {
      case 'de':
      case 'german':
      case 'deutsch':
        return 'de';
      case 'en':
      case 'english':
        return 'en';
      default:
        return text.toLowerCase();
    }
  }
}

class _GeneratedCredentials {
  const _GeneratedCredentials({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  static _GeneratedCredentials create() {
    final random = Random.secure();
    final suffix = 1000 + random.nextInt(9000);
    final username = 'ConsignorApp$suffix';

    return _GeneratedCredentials(
      username: username,
      password: username,
    );
  }
}
