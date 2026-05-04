class FormValidators {
  static String? requiredText(String? value, String fieldLabel) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldLabel is required';
    }
    return null;
  }

  static String? email(String? value) {
    final required = requiredText(value, 'Email');
    if (required != null) return required;

    final normalized = value!.trim();
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(normalized)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  static String? phoneLocalNumber(String? value) {
    final required = requiredText(value, 'Telephone');
    if (required != null) return required;

    final normalized = value!.trim();
    final phoneRegex = RegExp(r'^[0-9\-()/. ]+$');

    if (!phoneRegex.hasMatch(normalized)) {
      return 'Telephone contains invalid characters';
    }

    final digitCount = normalized.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digitCount < 4) {
      return 'Telephone must contain at least 4 digits';
    }

    return null;
  }

  static String? phonePrefix(String? value) {
    final required = requiredText(value, 'Phone prefix');
    if (required != null) return required;

    final normalized = value!.trim();
    if (!RegExp(r'^\+[0-9]{1,4}$').hasMatch(normalized)) {
      return 'Select a valid phone prefix';
    }

    return null;
  }

  static String? iban(String? value) {
    final normalized = (value ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (normalized.isEmpty) return 'IBAN is required';
    if (normalized.length < 15 || normalized.length > 34) {
      return 'Enter a valid IBAN';
    }
    if (!RegExp(r'^[A-Z]{2}[0-9A-Z]+$').hasMatch(normalized)) {
      return 'Enter a valid IBAN';
    }
    return null;
  }
}
