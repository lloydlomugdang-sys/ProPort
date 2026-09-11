import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_schedule.dart';
import 'package:proport_app/screens/portfolio/widgets/portfolio_schedule_picker.dart';

void main() {
  test('formats a selected day and time range consistently', () {
    const schedule = PortfolioSchedule(
      day: 'Monday',
      startTime: TimeOfDay(hour: 8, minute: 0),
      endTime: TimeOfDay(hour: 10, minute: 0),
    );

    expect(schedule.hasValidRange, isTrue);
    expect(schedule.formatted, 'Monday 8:00 AM - 10:00 AM');
  });

  test('parses current and older compact GradPort schedule strings', () {
    final current = PortfolioSchedule.tryParse('Monday 8:00 AM - 10:00 AM');
    final compact = PortfolioSchedule.tryParse('tuesday 1:05pm-2:30PM');

    expect(current?.formatted, 'Monday 8:00 AM - 10:00 AM');
    expect(compact?.formatted, 'Tuesday 1:05 PM - 2:30 PM');
  });

  test(
    'rejects invalid ranges and preserves unknown legacy text for display',
    () {
      const invalid = PortfolioSchedule(
        day: 'Friday',
        startTime: TimeOfDay(hour: 14, minute: 0),
        endTime: TimeOfDay(hour: 13, minute: 59),
      );

      expect(invalid.hasValidRange, isFalse);
      expect(
        PortfolioSchedule.tryParse('Old alternating laboratory schedule'),
        isNull,
      );
      expect(
        PortfolioSchedule.displayValue(
          '  Old alternating laboratory schedule  ',
        ),
        'Old alternating laboratory schedule',
      );
    },
  );

  testWidgets('picker collects a day, start time, and end time', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _ScheduleHarness()));

    await tester.tap(find.byKey(const Key('schedule-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wednesday').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('schedule-start-time')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('schedule-end-time')));
    await tester.pump();

    expect(find.text('Wednesday 9:00 AM - 11:00 AM'), findsOneWidget);
  });
}

class _ScheduleHarness extends StatefulWidget {
  const _ScheduleHarness();

  @override
  State<_ScheduleHarness> createState() => _ScheduleHarnessState();
}

class _ScheduleHarnessState extends State<_ScheduleHarness> {
  String? day;
  TimeOfDay? start;
  TimeOfDay? end;

  @override
  Widget build(BuildContext context) {
    final schedule = day == null || start == null || end == null
        ? null
        : PortfolioSchedule(day: day!, startTime: start!, endTime: end!);
    return Scaffold(
      body: Column(
        children: [
          PortfolioSchedulePicker(
            day: day,
            startTime: start,
            endTime: end,
            onDayChanged: (value) => setState(() => day = value),
            onStartTimeChanged: (value) => setState(() => start = value),
            onEndTimeChanged: (value) => setState(() => end = value),
            timePicker: (_, initialTime) async => initialTime.hour == 8
                ? const TimeOfDay(hour: 9, minute: 0)
                : const TimeOfDay(hour: 11, minute: 0),
          ),
          if (schedule != null) Text(schedule.formatted),
        ],
      ),
    );
  }
}
