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

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        title: _toInt(json['title'] ?? json['TitleId'] ?? json['titleId']),
        salutation: _toInt(
          json['salutation'] ?? json['SalutationId'] ?? json['salutationId'],
        ),
        firstName: _toString(json['firstName'] ?? json['FirstName']),
        lastName: _toString(json['lastName'] ?? json['LastName']),
        owner: (json['owner'] ?? json['Owner']) as bool? ?? true,
        dateOfBirth: _parseDate(json['dateOfBirth'] ?? json['DateOfBirth']),
        nationalityIso3: _countryIso(json['nationality'] ?? json['Nationality']),
        nationalityName: _countryName(json['nationality'] ?? json['Nationality']),
      );

  Map<String, dynamic> toJson() => {
        'titleId': title,
        'salutationId': salutation,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'owner': owner,
        'dateOfBirth': dateOfBirth?.toUtc().toIso8601String(),
        'nationality': nationalityIso3.trim().isEmpty && nationalityName.trim().isEmpty
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

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String _countryIso(Object? value) {
    if (value is Map) {
      return (value['isoCountryCode'] ?? value['IsoCountryCode'])?.toString() ?? '';
    }
    return '';
  }

  static String _countryName(Object? value) {
    if (value is Map) {
      return (value['countryName'] ?? value['CountryName'])?.toString() ?? '';
    }
    return '';
  }
}