import 'form_validators.dart';

class BankingRules {
  const BankingRules._();

  static bool requiresIbanOnly({
    required String countryIso3,
    required String countryName,
  }) {
    final iso = countryIso3.trim().toUpperCase();
    final name = countryName.trim().toLowerCase();

    return iso == 'CHE' ||
        iso == 'CH' ||
        iso == 'AUT' ||
        iso == 'AT' ||
        iso == 'DEU' ||
        iso == 'DE' ||
        name == 'switzerland' ||
        name == 'schweiz' ||
        name == 'suisse' ||
        name == 'austria' ||
        name == 'osterreich' ||
        name == 'oesterreich' ||
        name == 'germany' ||
        name == 'german' ||
        name == 'deutschland';
  }

  static String accountLabel({
    required bool bankTransfer,
    required bool requiresIbanOnly,
  }) {
    if (!bankTransfer) return 'IBAN / Account No';
    return requiresIbanOnly ? 'IBAN *' : 'IBAN / Account No *';
  }

  static String? validateAccount({
    required String? value,
    required bool bankTransfer,
    required bool requiresIbanOnly,
  }) {
    if (!bankTransfer) return null;
    return requiresIbanOnly
        ? FormValidators.iban(value)
        : FormValidators.ibanOrAccountNumber(value);
  }
}
