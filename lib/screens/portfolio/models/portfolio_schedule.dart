import 'package:flutter/material.dart';

const portfolioScheduleDays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class PortfolioSchedule {
  const PortfolioSchedule({
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  final String day;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  bool get hasValidRange => _minutes(endTime) > _minutes(startTime);

  String get formatted =>
      '$day ${formatTime(startTime)} - ${formatTime(endTime)}';

  static String formatTime(TimeOfDay value) {
    final hour = value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  static PortfolioSchedule? tryParse(String value) {
    final match = RegExp(
      r'^\s*(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s+'
      r'(\d{1,2}):(\d{2})\s*(AM|PM)\s*-\s*'
      r'(\d{1,2}):(\d{2})\s*(AM|PM)\s*$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;

    final start = _parseTime(match.group(2), match.group(3), match.group(4));
    final end = _parseTime(match.group(5), match.group(6), match.group(7));
    if (start == null || end == null) return null;

    final matchedDay = match.group(1)!;
    final day = portfolioScheduleDays.firstWhere(
      (candidate) => candidate.toLowerCase() == matchedDay.toLowerCase(),
    );
    final schedule = PortfolioSchedule(
      day: day,
      startTime: start,
      endTime: end,
    );
    return schedule.hasValidRange ? schedule : null;
  }

  static String displayValue(String storedValue) {
    final trimmed = storedValue.trim();
    return tryParse(trimmed)?.formatted ?? trimmed;
  }

  static TimeOfDay? _parseTime(
    String? hourValue,
    String? minuteValue,
    String? period,
  ) {
    final hour = int.tryParse(hourValue ?? '');
    final minute = int.tryParse(minuteValue ?? '');
    if (hour == null ||
        minute == null ||
        hour < 1 ||
        hour > 12 ||
        minute > 59) {
      return null;
    }

    var hour24 = hour % 12;
    if (period?.toUpperCase() == 'PM') hour24 += 12;
    return TimeOfDay(hour: hour24, minute: minute);
  }

  static int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;
}
