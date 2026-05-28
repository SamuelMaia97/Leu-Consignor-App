enum ConsignorType {
  naturalPerson,
  soleProprietor,
  legalEntity,
}

extension ConsignorTypeX on ConsignorType {
  String get apiName => switch (this) {
        ConsignorType.naturalPerson => 'NaturalPerson',
        ConsignorType.soleProprietor => 'SoleProprietor',
        ConsignorType.legalEntity => 'LegalEntity',
      };

  String get label => switch (this) {
        ConsignorType.naturalPerson => 'Natural person',
        ConsignorType.soleProprietor => 'Sole proprietor',
        ConsignorType.legalEntity => 'Legal entity',
      };

  static ConsignorType fromAny(Object? value,
      {bool legacyIsLegalEntity = false}) {
    final raw = value?.toString().trim().toLowerCase() ?? '';
    switch (raw) {
      case 'soleproprietor':
      case 'sole_proprietor':
      case 'sole proprietor':
      case 'einzelfirma':
      case 'inhaber einzelunternehmen':
        return ConsignorType.soleProprietor;
      case 'legalentity':
      case 'legal_entity':
      case 'legal entity':
      case 'company':
      case 'juristische person':
      case 'jur. person':
        return ConsignorType.legalEntity;
      case 'naturalperson':
      case 'natural_person':
      case 'natural person':
      case 'individual':
      case 'privatperson':
      case 'natuerliche person':
      case 'natürliche person':
        return ConsignorType.naturalPerson;
      default:
        return legacyIsLegalEntity
            ? ConsignorType.legalEntity
            : ConsignorType.naturalPerson;
    }
  }
}
