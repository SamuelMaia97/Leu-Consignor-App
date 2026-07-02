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
        'dateOfBirth': dateOfBirth?.toUtc().toIso8601String(),
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
    return DateTime.tryParse(value.toString());
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
