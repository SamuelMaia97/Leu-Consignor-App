enum PaymentOption { bankTransfer, wise, cash, pending }

extension PaymentOptionX on PaymentOption {
  String get label => switch (this) {
        PaymentOption.bankTransfer => 'Bank transfer',
        PaymentOption.wise => 'WISE',
        PaymentOption.cash => 'Cash',
        PaymentOption.pending => 'Pending',
      };

  String get apiName => switch (this) {
        PaymentOption.bankTransfer => 'BankTransfer',
        PaymentOption.wise => 'Wise',
        PaymentOption.cash => 'Cash',
        PaymentOption.pending => 'Pending',
      };

  static PaymentOption fromAny(Object? value) {
    final raw = value?.toString().trim() ?? '';
    switch (raw.toLowerCase()) {
      case 'banktransfer':
      case 'bank_transfer':
      case 'bank transfer':
      case 'banktransfer,':
        return PaymentOption.bankTransfer;
      case 'wise':
        return PaymentOption.wise;
      case 'cash':
        return PaymentOption.cash;
      case 'pending':
      case 'wirdnochmitgeteilt':
      default:
        return PaymentOption.pending;
    }
  }
}
