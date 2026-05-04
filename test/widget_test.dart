import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/widgets/app_empty_state.dart';

void main() {
  testWidgets('AppEmptyState renders title, message, and action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppEmptyState(
            title: 'No records',
            message: 'Create your first consignor to get started.',
            icon: Icons.inbox_outlined,
            action: Text('Create'),
          ),
        ),
      ),
    );

    expect(find.text('No records'), findsOneWidget);
    expect(find.text('Create your first consignor to get started.'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });
}
