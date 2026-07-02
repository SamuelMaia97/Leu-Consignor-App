import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/auction_option.dart';
import 'package:leu_consignor_app/src/widgets/multi_auction_select_field.dart';

void main() {
  const auctions = [
    AuctionOption(
        auctionId: 1,
        auctionNumber: 1,
        auctionType: 1,
        displayName: 'Auction 1'),
    AuctionOption(
        auctionId: 2,
        auctionNumber: 2,
        auctionType: 1,
        displayName: 'Auction 2'),
  ];

  testWidgets('tapping the field opens the bottom sheet', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MultiAuctionSelectField(
                label: 'Auctions',
                items: auctions,
                selected: const [],
                onChanged: (_) {}))));

    await tester.tap(find.text('Auctions'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets(
      'selecting two auctions and tapping Done calls onChanged with both',
      (tester) async {
    var selected = <AuctionOption>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MultiAuctionSelectField(
                label: 'Auctions',
                items: auctions,
                selected: const [],
                onChanged: (value) => selected = value))));

    await tester.tap(find.text('Auctions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auction 1'));
    await tester.tap(find.text('Auction 2'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(selected.map((e) => e.auctionId), [2, 1]);
  });

  testWidgets('orders dropdown options from most recent to oldest',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MultiAuctionSelectField(
                label: 'Auctions',
                items: auctions,
                selected: const [],
                onChanged: (_) {}))));

    await tester.tap(find.text('Auctions'));
    await tester.pumpAndSettle();

    final auction2Top = tester.getTopLeft(find.text('Auction 2').last).dy;
    final auction1Top = tester.getTopLeft(find.text('Auction 1').last).dy;

    expect(auction2Top, lessThan(auction1Top));
  });

  testWidgets('tapping chip delete removes that auction', (tester) async {
    var selected = List<AuctionOption>.from(auctions);
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      return Scaffold(
          body: MultiAuctionSelectField(
              label: 'Auctions',
              items: auctions,
              selected: selected,
              onChanged: (value) => setState(() => selected = value)));
    })));

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();

    expect(selected.map((e) => e.auctionId), [1]);
  });

  test('validator returns an error when no auction is selected', () {
    expect(MultiAuctionSelectField.requireSelection(const []), isNotNull);
  });

  test('validator passes when at least one auction is selected', () {
    expect(MultiAuctionSelectField.requireSelection([auctions.first]), isNull);
  });
}
