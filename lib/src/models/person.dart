class Person {
  Person({
    this.title,
    this.salutation,
    this.firstName = '',
    this.lastName = '',
    this.owner = true,
    this.dateOfBirth,
    this.nationalityIso3 = '',
    this.nationalityName = '',
  });

  int? title;
  int? salutation;
  String firstName;
  String lastName;
  bool owner;
  DateTime? dateOfBirth;
  String nationalityIso3;
  String nationalityName;

  factory Person.fromJson(Map<String, dynamic> json) {
    var firstName = _toString(
      _firstValue(json, const [
        'firstName',
        'FirstName',
        'firstname',
        'Firstname',
        'first_name',
        'VORNAME',
        'Vorname',
      ]),
    );
    var lastName = _toString(
      _firstValue(json, const [
        'lastName',
        'LastName',
        'lastname',
        'Lastname',
        'last_name',
        'NACHNAME',
        'Nachname',
        'NAME',
        'Name',
      ]),
    );

    if (firstName.trim().isEmpty && lastName.trim().isEmpty) {
      final fullName = _toString(
        _firstValue(json, const [
          'fullName',
          'FullName',
          'displayName',
          'DisplayName',
          'contactName',
          'ContactName',
        ]),
      ).trim();
      if (fullName.isNotEmpty) {
        final parts = fullName.split(RegExp(r'\s+'));
        firstName = parts.first;
        lastName = parts.length > 1 ? parts.skip(1).join(' ') : '';
      }
    }

    return Person(
      title: _toInt(
        _firstValue(json, const [
          'title',
          'Title',
          'TitleId',
          'titleId',
          'TITEL',
        ]),
      ),
      salutation: _toInt(
        _firstValue(json, const [
          'salutation',
          'Salutation',
          'SalutationId',
          'salutationId',
          'ANREDE',
        ]),
      ),
      firstName: firstName,
      lastName: lastName,
      owner: _toBool(_firstValue(json, const ['owner', 'Owner'])) ?? true,
      dateOfBirth: _parseDate(
        _firstValue(json, const [
          'dateOfBirth',
          'DateOfBirth',
          'birthDate',
          'BirthDate',
          'GEBDAT',
        ]),
      ),
      nationalityIso3: _countryIso(
        _firstValue(json, const [
          'nationality',
          'Nationality',
          'nationalityCountry',
          'NationalityCountry',
        ]),
      ),
      nationalityName: _countryName(
        _firstValue(json, const [
          'nationality',
          'Nationality',
          'nationalityCountry',
          'NationalityCountry',
        ]),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'titleId': title,
        'salutationId': salutation,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'owner': owner,
        'dateOfBirth': _formatDateOnly(dateOfBirth),
        'nationality':
            nationalityIso3.trim().isEmpty && nationalityName.trim().isEmpty
                ? null
                : {
                    'isoCountryCode': nationalityIso3,
                    'countryName': nationalityName,
                  },
      };

  String get fullName =>
      [firstName, lastName].where((value) => value.trim().isNotEmpty).join(' ');

  static int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static String _toString(Object? value) => value?.toString() ?? '';

  static bool? _toBool(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase().trim();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return null;
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) {
      return DateTime.utc(value.year, value.month, value.day);
    }

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    // Customer dates are calendar dates. Preserve the date written by the
    // source instead of allowing an offset conversion to move it a day.
    final isoDate =
        RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:$|[T\s])').firstMatch(text);
    if (isoDate != null) {
      return _validUtcDate(
        int.tryParse(isoDate.group(1)!),
        int.tryParse(isoDate.group(2)!),
        int.tryParse(isoDate.group(3)!),
      );
    }

    final european =
        RegExp(r'^(\d{1,2})[.\/-](\d{1,2})[.\/-](\d{4})$').firstMatch(text);
    if (european != null) {
      return _validUtcDate(
        int.tryParse(european.group(3)!),
        int.tryParse(european.group(2)!),
        int.tryParse(european.group(1)!),
      );
    }

    final parsed = DateTime.tryParse(text);
    return parsed == null
        ? null
        : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  static DateTime? _validUtcDate(int? year, int? month, int? day) {
    if (year == null || month == null || day == null) {
      return null;
    }
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static String? _formatDateOnly(DateTime? value) {
    if (value == null) return null;
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _countryIso(Object? value) {
    if (value is Map) {
      return (value['isoCountryCode'] ?? value['IsoCountryCode'])?.toString() ??
          '';
    }
    return '';
  }

  static String _countryName(Object? value) {
    if (value is Map) {
      return (value['countryName'] ?? value['CountryName'])?.toString() ?? '';
    }
    return '';
  }

  static Object? _firstValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      return value;
    }
    return null;
  }
}
