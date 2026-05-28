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
    this.checkedByLeu = true,
    this.ancientCoinsSubscribed = false,
    this.worldCoinsSubscribed = false,
    this.newsletterSubscribed = true,
    this.collectingArea = '',
    this.correspondence,
    this.references = '',
    this.creditLimit = 0,
    this.discount,
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
  bool checkedByLeu;
  bool ancientCoinsSubscribed;
  bool worldCoinsSubscribed;
  bool newsletterSubscribed;
  String collectingArea;
  String? correspondence;
  String references;
  double creditLimit;
  double? discount;
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

    final hasRemoteReference = systemReferenceConsignor > 0;

    final rawPhoneNumber =
        _toString(json['phoneNumber'] ?? json['PhoneNumber']);
    final parsedPhone = PhoneNumberParser.parse(rawPhoneNumber);
    final explicitPhonePrefix = _toString(
      json['phonePrefix'] ??
          json['PhonePrefix'] ??
          json['phoneCountryPrefix'] ??
          json['PhoneCountryPrefix'],
    );
    final explicitPhonePrefixOriginId = _toInt(
      json['phonePrefixOriginId'] ??
          json['PhonePrefixOriginId'] ??
          json['phonePrefixId'] ??
          json['PhonePrefixId'],
    );
    final legacyIsLegalEntity =
        _toBool(json['isLegalEntity'] ?? json['IsLegalEntity']) ?? false;
    final legacyIsSoleProprietor =
        _toBool(json['isSoleProprietor'] ?? json['IsSoleProprietor']) ?? false;
    final resolvedConsignorType = legacyIsSoleProprietor
        ? ConsignorType.soleProprietor
        : ConsignorTypeX.fromAny(
            json['consignorType'] ??
                json['ConsignorType'] ??
                json['partyType'] ??
                json['PartyType'],
            legacyIsLegalEntity: legacyIsLegalEntity,
          );

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
      existingCustomerId: _toInt(
        json['existingCustomerId'] ?? json['ExistingCustomerId'],
      ),
      existingCustomerLabel: _toNullableString(
        json['existingCustomerLabel'] ?? json['ExistingCustomerLabel'],
      ),
      consignorType: resolvedConsignorType,
      tradingName: _toString(json['tradingName'] ?? json['TradingName']),
      consignorInfo: Person.fromJson(
        ((json['consignorInfo'] ?? json['ConsignorInfo']) as Map?)
                ?.cast<String, dynamic>() ??
            {},
      ),
      vatLiability:
          (json['vatLiability'] ?? json['VatLiability']) as bool? ?? false,
      vatNumber: _toString(json['vatNumber'] ?? json['VatNumber']),
      phonePrefix: explicitPhonePrefix.isNotEmpty
          ? explicitPhonePrefix
          : parsedPhone.prefix,
      phonePrefixOriginId: explicitPhonePrefixOriginId,
      phoneNumber: explicitPhonePrefix.isNotEmpty
          ? _stripExplicitPrefix(rawPhoneNumber, explicitPhonePrefix)
          : parsedPhone.localNumber,
      emailAddress: _toString(json['emailAddress'] ?? json['EmailAddress']),
      consignorAddress: Address.fromJson(
        ((json['consignorAddress'] ??
                    json['ConsignorAddress'] ??
                    json['consignorAddress'] ??
                    json['ConsignorAddress']) as Map?)
                ?.cast<String, dynamic>() ??
            {},
      ),
      bankingDetails: BankingDetails.fromJson(
        ((json['bankingDetails'] ??
                    json['BankingDetails'] ??
                    json['bankingDetailsDto'] ??
                    json['BankingDetailsDto']) as Map?)
                ?.cast<String, dynamic>() ??
            {},
      ),
      paymentOption: PaymentOptionX.fromAny(
          json['paymentOption'] ?? json['PaymentOption']),
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
    if (text == 'true') return true;
    if (text == 'false') return false;
    return null;
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
