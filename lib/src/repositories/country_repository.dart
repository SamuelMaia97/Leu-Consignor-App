import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/country.dart';

class CountryRepository {
  Future<List<Country>> loadCountries() async {
    final jsonString = await rootBundle.loadString('assets/data/countries.json');
    final list = (json.decode(jsonString) as List).cast<Map<String, dynamic>>();
    return list.map(Country.fromJson).toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}
