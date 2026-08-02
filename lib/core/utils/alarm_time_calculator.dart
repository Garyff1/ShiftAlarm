import '../../data/models/clock_time.dart';
import '../../data/models/reminder_rule.dart';
import '../../data/models/app_enums.dart';

abstract final class AlarmTimeCalculator {
  static DateTime? calculate({
    required DateTime scheduleDate,
    required ClockTime? arrivalTime,
    required int arrivalDayOffset,
    required ReminderRule rule,
  }) {
    if (!rule.isEnabled) return null;
    final baseDate = DateTime(
      scheduleDate.year,
      scheduleDate.month,
      scheduleDate.day,
    );
    if (rule.timeMode == ReminderTimeMode.fixed) {
      final time = rule.fixedTime;
      if (time == null) return null;
      return DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        time.hour,
        time.minute,
      );
    }
    final time = arrivalTime;
    final minutes = rule.minutesBeforeArrival;
    if (time == null || minutes == null || minutes < 0) return null;
    final arrivalDate = baseDate.add(Duration(days: arrivalDayOffset));
    return DateTime(
      arrivalDate.year,
      arrivalDate.month,
      arrivalDate.day,
      time.hour,
      time.minute,
    ).subtract(Duration(minutes: minutes));
  }

  static List<MapEntry<ReminderRule, DateTime>> calculateAndSort({
    required DateTime scheduleDate,
    required ClockTime? arrivalTime,
    required int arrivalDayOffset,
    required Iterable<ReminderRule> rules,
  }) {
    final result = <MapEntry<ReminderRule, DateTime>>[];
    for (final rule in rules) {
      final trigger = calculate(
        scheduleDate: scheduleDate,
        arrivalTime: arrivalTime,
        arrivalDayOffset: arrivalDayOffset,
        rule: rule,
      );
      if (trigger != null) result.add(MapEntry(rule, trigger));
    }
    result.sort((a, b) {
      final byTime = a.value.compareTo(b.value);
      return byTime != 0 ? byTime : a.key.sortOrder.compareTo(b.key.sortOrder);
    });
    return result;
  }
}
