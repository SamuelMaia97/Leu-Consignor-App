enum ActivityEventType {
  consignorSaved,
  contractCreated,
  contractUpdated,
  pdfGenerated,
  passportDownloaded,
  syncStarted,
  syncSucceeded,
  syncFailed,
  connectionSucceeded,
  connectionFailed,
  warning,
}

extension ActivityEventTypeX on ActivityEventType {
  static ActivityEventType fromAny(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return ActivityEventType.warning;

    for (final type in ActivityEventType.values) {
      if (type.name == text) return type;
    }

    return ActivityEventType.warning;
  }
}

class ActivityEvent {
  ActivityEvent({
    required this.id,
    required this.type,
    required this.title,
    this.description = '',
    this.relatedConsignorId,
    this.relatedContractId,
    DateTime? occurredAtUtc,
  }) : occurredAtUtc = occurredAtUtc ?? DateTime.now().toUtc();

  final String id;
  final ActivityEventType type;
  final String title;
  final String description;
  final String? relatedConsignorId;
  final String? relatedContractId;
  final DateTime occurredAtUtc;

  factory ActivityEvent.create({
    required ActivityEventType type,
    required String title,
    String description = '',
    String? relatedConsignorId,
    String? relatedContractId,
  }) {
    final now = DateTime.now().toUtc();
    return ActivityEvent(
      id: '${now.microsecondsSinceEpoch}_${type.name}',
      type: type,
      title: title,
      description: description,
      relatedConsignorId: relatedConsignorId,
      relatedContractId: relatedContractId,
      occurredAtUtc: now,
    );
  }

  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    return ActivityEvent(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      type: ActivityEventTypeX.fromAny(json['type'] ?? json['Type']),
      title: (json['title'] ?? json['Title'] ?? '').toString(),
      description:
          (json['description'] ?? json['Description'] ?? '').toString(),
      relatedConsignorId:
          (json['relatedConsignorId'] ?? json['RelatedConsignorId'])
              ?.toString(),
      relatedContractId:
          (json['relatedContractId'] ?? json['RelatedContractId'])?.toString(),
      occurredAtUtc: DateTime.tryParse(
            (json['occurredAtUtc'] ?? json['OccurredAtUtc'])?.toString() ?? '',
          )?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'description': description.trim().isEmpty ? null : description.trim(),
        'relatedConsignorId': relatedConsignorId,
        'relatedContractId': relatedContractId,
        'occurredAtUtc': occurredAtUtc.toUtc().toIso8601String(),
      };
}
