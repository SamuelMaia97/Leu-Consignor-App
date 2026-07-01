import 'package:flutter/material.dart';

import '../models/auction_option.dart';

class MultiAuctionSelectField extends FormField<List<AuctionOption>> {
  MultiAuctionSelectField({
    super.key,
    required String label,
    required List<AuctionOption> items,
    required List<AuctionOption> selected,
    required ValueChanged<List<AuctionOption>> onChanged,
    String? hintText,
    String Function(AuctionOption auction)? itemLabel,
    super.validator,
    bool enabled = true,
  }) : super(
          initialValue: selected,
          builder: (field) {
            String labelFor(AuctionOption auction) =>
                itemLabel?.call(auction) ?? auction.displayName;
            final sortedItems = items.toList(growable: false)
              ..sort(MultiAuctionSelectField._compareAuctions);

            Future<void> openPicker() async {
              if (!enabled) return;

              final picked = await showModalBottomSheet<List<AuctionOption>>(
                context: field.context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (sheetContext) {
                  var query = '';
                  final selectedIds = <int>{
                    for (final item in field.value ?? selected) item.auctionId,
                  };

                  return StatefulBuilder(
                    builder: (context, setSheetState) {
                      final filtered = sortedItems.where((item) {
                        return labelFor(item)
                            .toLowerCase()
                            .contains(query.toLowerCase());
                      }).toList(growable: false);

                      List<AuctionOption> buildSelection() => sortedItems
                          .where((item) => selectedIds.contains(item.auctionId))
                          .toList(growable: false);

                      void submitSingleMatch() {
                        if (filtered.length != 1) return;
                        setSheetState(() {
                          selectedIds.add(filtered.single.auctionId);
                        });
                      }

                      return SafeArea(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 12,
                            bottom:
                                MediaQuery.of(context).viewInsets.bottom + 16,
                          ),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.78,
                            child: Column(
                              children: [
                                TextField(
                                  autofocus: true,
                                  decoration: InputDecoration(
                                    prefixIcon:
                                        const Icon(Icons.search_rounded),
                                    labelText: label,
                                    hintText: hintText ?? 'Search auctions',
                                  ),
                                  onChanged: (value) =>
                                      setSheetState(() => query = value),
                                  onSubmitted: (_) => submitSingleMatch(),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: filtered.isEmpty
                                      ? const Center(
                                          child: Text('No matching results.'),
                                        )
                                      : ListView.separated(
                                          itemBuilder: (context, index) {
                                            final item = filtered[index];
                                            final checked = selectedIds
                                                .contains(item.auctionId);
                                            return CheckboxListTile(
                                              value: checked,
                                              title: Text(labelFor(item)),
                                              controlAffinity:
                                                  ListTileControlAffinity
                                                      .leading,
                                              onChanged: (value) {
                                                setSheetState(() {
                                                  if (value ?? false) {
                                                    selectedIds
                                                        .add(item.auctionId);
                                                  } else {
                                                    selectedIds.remove(
                                                      item.auctionId,
                                                    );
                                                  }
                                                });
                                              },
                                            );
                                          },
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1),
                                          itemCount: filtered.length,
                                        ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () => Navigator.of(sheetContext)
                                        .pop(buildSelection()),
                                    child: const Text('Done'),
                                  ),
                                ),
                              ],
                            ),
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

            void removeAuction(AuctionOption auction) {
              final next = (field.value ?? selected)
                  .where((item) => item.auctionId != auction.auctionId)
                  .toList(growable: false);
              field.didChange(next);
              onChanged(next);
            }

            final value = (field.value ?? const <AuctionOption>[])
                .toList(growable: false)
              ..sort(MultiAuctionSelectField._compareAuctions);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: openPicker,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    isEmpty: value.isEmpty,
                    decoration: InputDecoration(
                      labelText: label,
                      errorText: field.errorText,
                      prefixIcon: const Icon(Icons.gavel_outlined),
                      suffixIcon: enabled
                          ? const Icon(Icons.keyboard_arrow_down_rounded)
                          : null,
                    ),
                    child: value.isEmpty
                        ? const SizedBox(height: 24)
                        : Text(
                            '${value.length} auction${value.length == 1 ? '' : 's'} selected',
                          ),
                  ),
                ),
                if (value.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: value
                        .map(
                          (auction) => FilterChip(
                            label: Text(labelFor(auction)),
                            labelStyle: TextStyle(
                              color:
                                  Theme.of(field.context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            backgroundColor:
                                Theme.of(field.context).colorScheme.surface,
                            side: BorderSide(
                              color: Theme.of(field.context).dividerColor,
                            ),
                            onSelected:
                                enabled ? (_) => removeAuction(auction) : null,
                            deleteIcon:
                                const Icon(Icons.close_rounded, size: 18),
                            onDeleted:
                                enabled ? () => removeAuction(auction) : null,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ],
            );
          },
        );

  static String? requireSelection(List<AuctionOption>? value) {
    return value == null || value.isEmpty
        ? 'Select at least one auction'
        : null;
  }

  static int _compareAuctions(AuctionOption a, AuctionOption b) {
    final byNumber = _sortNumber(a).compareTo(_sortNumber(b));
    if (byNumber != 0) return byNumber;
    return a.auctionId.compareTo(b.auctionId);
  }

  static int _sortNumber(AuctionOption auction) {
    if (auction.auctionNumber > 0) return auction.auctionNumber;
    final match = RegExp(r'\b(\d+)\b').firstMatch(auction.displayName);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? auction.auctionId;
    }
    return auction.auctionId;
  }
}
