import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/screens/consignor_wizard_screen.dart';

void main() {
  testWidgets(
    'passport validity field updates from an externally supplied scan date',
    (tester) async {
      final scannedDate = DateTime(2031, 8, 17);
      DateTime? value;
      late StateSetter updateHost;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                updateHost = setState;
                return PassportValidityField(
                  label: 'Consignor Passport Valid Until',
                  value: value,
                  validationPassed: true,
                  validationResult: 'OK',
                  onChanged: (_) {},
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Select date'), findsOneWidget);

      updateHost(() => value = scannedDate);
      await tester.pump();

      expect(find.text('Select date'), findsNothing);
      expect(find.text('17-08-2031'), findsOneWidget);
    },
  );

  testWidgets('passport validity picker uses a passport-specific title',
      (tester) async {
    final date = DateTime(2031, 5, 26);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PassportValidityField(
            label: 'Consignor Passport Valid Until',
            value: date,
            validationPassed: true,
            validationResult: 'OK',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('26-05-2031'));
    await tester.pumpAndSettle();

    expect(find.text('Select passport expiry date'), findsOneWidget);
    expect(find.text('Select date of birth'), findsNothing);
  });
}
