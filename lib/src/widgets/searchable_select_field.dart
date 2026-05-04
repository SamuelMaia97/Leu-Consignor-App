import 'package:flutter/material.dart';

class SearchableSelectFormField<T> extends FormField<T> {
  SearchableSelectFormField({
    super.key,
    required String label,
    required List<T> items,
    required String Function(T item) itemLabel,
    required ValueChanged<T?> onChanged,
    super.initialValue,
    String? hintText,
    super.validator,
    bool enabled = true,
    bool allowClear = true,
    Widget? leading,
  }) : super(
          builder: (field) {
            Future<void> openPicker() async {
              if (!enabled) return;

              final picked = await showModalBottomSheet<T?>(
                context: field.context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (sheetContext) {
                  var query = '';

                  return StatefulBuilder(
                    builder: (context, setSheetState) {
                      final filtered = items.where((item) {
                        final labelValue = itemLabel(item).toLowerCase();
                        return labelValue.contains(query.toLowerCase());
                      }).toList(growable: false);

                      return SafeArea(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 12,
                            bottom:
                                MediaQuery.of(context).viewInsets.bottom + 16,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                autofocus: true,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  labelText: label,
                                  hintText: hintText ?? 'Search',
                                ),
                                onChanged: (value) =>
                                    setSheetState(() => query = value),
                              ),
                              const SizedBox(height: 12),
                              Flexible(
                                child: filtered.isEmpty
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(24),
                                          child: Text('No matching results.'),
                                        ),
                                      )
                                    : ListView.separated(
                                        shrinkWrap: true,
                                        itemBuilder: (context, index) {
                                          final item = filtered[index];
                                          return ListTile(
                                            title: Text(itemLabel(item)),
                                            onTap: () => Navigator.of(
                                              sheetContext,
                                            ).pop(item),
                                          );
                                        },
                                        separatorBuilder: (_, __) =>
                                            const Divider(height: 1),
                                        itemCount: filtered.length,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );

              if (picked == null) return;
              field.didChange(picked);
              onChanged(picked);
            }

            final selected = field.value;
            final selectedLabel = selected == null ? '' : itemLabel(selected);
            final textStyle = Theme.of(field.context).textTheme.bodyLarge;

            return InkWell(
              onTap: openPicker,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                isEmpty: selectedLabel.isEmpty,
                decoration: InputDecoration(
                  labelText: label,
                  errorText: field.errorText,
                  prefixIcon: leading,
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  suffixIcon: enabled
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (allowClear && selected != null)
                              IconButton(
                                onPressed: () {
                                  field.didChange(null);
                                  onChanged(null);
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                            const Icon(Icons.keyboard_arrow_down_rounded),
                            const SizedBox(width: 8),
                          ],
                        )
                      : null,
                ),
                child: selectedLabel.isEmpty
                    ? const SizedBox(height: 24)
                    : Text(selectedLabel, style: textStyle),
              ),
            );
          },
        );
}