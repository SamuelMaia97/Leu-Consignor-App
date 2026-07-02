import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/services/api_service.dart';
import 'package:leu_consignor_app/src/widgets/sync_report_dialog.dart';

void main() {
  testWidgets('Sync report dialog renders a long missing-field report',
      (tester) async {
    final issues = List.generate(
      80,
      (index) => RemoteReportFieldIssue(
        summaryIndex: index,
        total: 80,
        consignorId: '${120000 + index}',
        missingFields: const ['Bank name', 'Bank account / IBAN'],
        availableFields: const [
          'ConsignorId',
          'EmailAddress',
          'LastModifiedUtc',
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => showSyncReportDialog(context, issues),
                child: const Text('Open report'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Abacus report fields'), findsOneWidget);
    expect(
      find.text('80 report rows had fields missing from /get-all.'),
      findsOneWidget,
    );
    expect(find.textContaining('ID 120000'), findsOneWidget);
  });
}
