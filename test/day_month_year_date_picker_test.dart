import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/widgets/day_month_year_date_picker.dart';

void main() {
  test('formats display dates as dd-MM-yyyy', () {
    expect(formatDayMonthYear(DateTime.utc(1988, 2, 3)), '03-02-1988');
  });

  testWidgets('presents date controls in day, month, year order',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DayMonthYearDatePickerDialog(
          title: 'Select date of birth',
          initialDate: DateTime(1988, 2, 3),
          firstDate: DateTime(1900, 1, 1),
          lastDate: DateTime(2026, 12, 31),
        ),
      ),
    );

    expect(
      find.text('Choose day, month, and year directly.'),
      findsOneWidget,
    );

    final dayTop = tester.getTopLeft(find.text('Day')).dy;
    final monthTop = tester.getTopLeft(find.text('Month')).dy;
    final yearTop = tester.getTopLeft(find.text('Year')).dy;

    expect(dayTop, lessThan(monthTop));
    expect(monthTop, lessThan(yearTop));
    expect(find.text('03'), findsOneWidget);
    expect(find.text('02 - February'), findsOneWidget);
    expect(find.text('1988'), findsOneWidget);
  });
}
