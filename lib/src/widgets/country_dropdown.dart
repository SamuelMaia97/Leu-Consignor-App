import 'package:flutter/material.dart';

import '../models/country.dart';
import 'searchable_select_field.dart';

class CountryDropdown extends StatelessWidget {
  const CountryDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.countries,
    required this.onChanged,
    this.validator,
    this.enabled = true,
    this.hintText,
  });

  final String label;
  final String value;
  final List<Country> countries;
  final ValueChanged<Country?> onChanged;
  final String? Function(Country?)? validator;
  final bool enabled;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final selected = countries.where((country) => country.matchesCode(value)).cast<Country?>().firstOrNull;

    return SearchableSelectFormField<Country>(
      label: label,
      items: countries,
      itemLabel: (item) => item.name,
      initialValue: selected,
      hintText: hintText ?? 'Search $label',
      validator: validator,
      enabled: enabled,
      onChanged: onChanged,
      leading: const Icon(Icons.public_outlined),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
