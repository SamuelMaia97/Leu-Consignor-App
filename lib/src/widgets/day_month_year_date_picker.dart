import 'package:flutter/material.dart';

import 'searchable_select_field.dart';

String formatDayMonthYear(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.year.toString().padLeft(4, '0')}';
}

class DayMonthYearDatePickerDialog extends StatefulWidget {
  const DayMonthYearDatePickerDialog({
    super.key,
    required this.title,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final String title;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<DayMonthYearDatePickerDialog> createState() =>
      _DayMonthYearDatePickerDialogState();
}

class _DayMonthYearDatePickerDialogState
    extends State<DayMonthYearDatePickerDialog> {
  static const List<String> _monthLabels = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  @override
  void initState() {
    super.initState();
    final safeInitial = _clampDate(
      widget.initialDate,
      widget.firstDate,
      widget.lastDate,
    );
    _selectedYear = safeInitial.year;
    _selectedMonth = safeInitial.month;
    _selectedDay = safeInitial.day;
  }

  DateTime _clampDate(DateTime value, DateTime min, DateTime max) {
    if (value.isBefore(min)) return min;
    if (value.isAfter(max)) return max;
    return value;
  }

  int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  List<int> get _availableYears => [
        for (var year = widget.lastDate.year;
            year >= widget.firstDate.year;
            year--)
          year,
      ];

  List<int> get _availableMonths {
    var startMonth = 1;
    var endMonth = 12;

    if (_selectedYear == widget.firstDate.year) {
      startMonth = widget.firstDate.month;
    }
    if (_selectedYear == widget.lastDate.year) {
      endMonth = widget.lastDate.month;
    }

    return [for (var month = startMonth; month <= endMonth; month++) month];
  }

  List<int> get _availableDays {
    var startDay = 1;
    var endDay = _daysInMonth(_selectedYear, _selectedMonth);

    if (_selectedYear == widget.firstDate.year &&
        _selectedMonth == widget.firstDate.month) {
      startDay = widget.firstDate.day;
    }

    if (_selectedYear == widget.lastDate.year &&
        _selectedMonth == widget.lastDate.month) {
      endDay = widget.lastDate.day;
    }

    return [for (var day = startDay; day <= endDay; day++) day];
  }

  void _updateSelection({int? year, int? month, int? day}) {
    final nextYear = year ?? _selectedYear;
    final nextMonth = month ?? _selectedMonth;
    final maxDay = _daysInMonth(nextYear, nextMonth);
    final desiredDay = day ?? _selectedDay;
    final nextDay = desiredDay > maxDay ? maxDay : desiredDay;

    setState(() {
      _selectedYear = nextYear;
      _selectedMonth = nextMonth;
      _selectedDay = nextDay;
    });

    final validMonths = _availableMonths;
    if (!validMonths.contains(_selectedMonth)) {
      setState(() {
        _selectedMonth = validMonths.first;
        _selectedDay =
            _selectedDay > _daysInMonth(_selectedYear, _selectedMonth)
                ? _daysInMonth(_selectedYear, _selectedMonth)
                : _selectedDay;
      });
    }

    final validDays = _availableDays;
    if (!validDays.contains(_selectedDay)) {
      setState(() => _selectedDay = validDays.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = _availableYears;
    final months = _availableMonths;
    final days = _availableDays;

    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Choose day, month, and year directly.'),
            ),
            const SizedBox(height: 16),
            SearchableSelectFormField<int>(
              key: ValueKey(
                'dob-day-$_selectedYear-$_selectedMonth-$_selectedDay',
              ),
              label: 'Day',
              items: days,
              itemLabel: (day) => day.toString().padLeft(2, '0'),
              initialValue: _selectedDay,
              allowClear: false,
              hintText: 'Search day',
              onChanged: (value) {
                if (value != null) _updateSelection(day: value);
              },
            ),
            const SizedBox(height: 12),
            SearchableSelectFormField<int>(
              key: ValueKey('dob-month-$_selectedYear-$_selectedMonth'),
              label: 'Month',
              items: months,
              itemLabel: (month) =>
                  '${month.toString().padLeft(2, '0')} - ${_monthLabels[month - 1]}',
              initialValue: _selectedMonth,
              allowClear: false,
              hintText: 'Search month',
              onChanged: (value) {
                if (value != null) _updateSelection(month: value);
              },
            ),
            const SizedBox(height: 12),
            SearchableSelectFormField<int>(
              key: ValueKey('dob-year-$_selectedYear'),
              label: 'Year',
              items: years,
              itemLabel: (year) => year.toString(),
              initialValue: _selectedYear,
              allowClear: false,
              hintText: 'Search year',
              onChanged: (value) {
                if (value != null) _updateSelection(year: value);
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime(_selectedYear, _selectedMonth, _selectedDay),
                    firstDate: widget.firstDate,
                    lastDate: widget.lastDate,
                    initialDatePickerMode: DatePickerMode.day,
                    initialEntryMode: DatePickerEntryMode.calendarOnly,
                    locale: const Locale('en', 'GB'),
                  );

                  if (!context.mounted) return;
                  if (picked != null) Navigator.of(context).pop(picked);
                },
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Use calendar view instead'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context)
              .pop(DateTime(_selectedYear, _selectedMonth, _selectedDay)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
