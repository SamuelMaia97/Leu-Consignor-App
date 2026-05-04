class Country {
  const Country({
    required this.name,
    required this.iso3,
    this.iso2 = '',
    this.nameDe = '',
  });

  final String name;
  final String iso3;
  final String iso2;
  final String nameDe;

  factory Country.fromJson(Map<String, dynamic> json) => Country(
        name: (json['name'] ?? json['countryName']) as String? ?? '',
        iso3: (json['iso3'] ?? json['origin_iso'] ?? json['isoCountryCode3']) as String? ?? '',
        iso2: (json['iso2'] ?? json['origin_short'] ?? json['isoCountryCode2']) as String? ?? '',
        nameDe: (json['nameDe'] ?? json['countryNameDe']) as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'iso3': iso3,
        'iso2': iso2,
        'nameDe': nameDe,
      };

  bool matchesCode(String code) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    return iso3.toUpperCase() == normalized || iso2.toUpperCase() == normalized;
  }

  @override
  String toString() => name;
}
