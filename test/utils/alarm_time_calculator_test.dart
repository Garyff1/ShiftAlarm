import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/core/utils/alarm_time_calculator.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/clock_time.dart';
import 'package:shift_alarm/data/models/reminder_rule.dart';

ReminderRule relative(String id, int minutes, {int order = 0}) => ReminderRule(
  id: id,
  name: id,
  timeMode: ReminderTimeMode.beforeArrival,
  minutesBeforeArrival: minutes,
  sortOrder: order,
);

void main() {
  final date = DateTime(2026, 8, 10);

  test('到岗前 120 分钟', () {
    final result = AlarmTimeCalculator.calculate(
      scheduleDate: date,
      arrivalTime: const ClockTime(hour: 8, minute: 0),
      arrivalDayOffset: 0,
      rule: relative('起床', 120),
    );
    expect(result, DateTime(2026, 8, 10, 6));
  });

  test('提醒时间可以跨越零点', () {
    final result = AlarmTimeCalculator.calculate(
      scheduleDate: date,
      arrivalTime: const ClockTime(hour: 1, minute: 0),
      arrivalDayOffset: 0,
      rule: relative('出发', 120),
    );
    expect(result, DateTime(2026, 8, 9, 23));
  });

  test('次日到岗按下一自然日计算', () {
    final result = AlarmTimeCalculator.calculate(
      scheduleDate: date,
      arrivalTime: const ClockTime(hour: 1, minute: 0),
      arrivalDayOffset: 1,
      rule: relative('出发', 120),
    );
    expect(result, DateTime(2026, 8, 10, 23));
  });

  test('固定时间使用排班当天', () {
    const rule = ReminderRule(
      id: 'fixed',
      name: '固定提醒',
      timeMode: ReminderTimeMode.fixed,
      fixedTime: ClockTime(hour: 7, minute: 30),
    );
    final result = AlarmTimeCalculator.calculate(
      scheduleDate: date,
      arrivalTime: null,
      arrivalDayOffset: 1,
      rule: rule,
    );
    expect(result, DateTime(2026, 8, 10, 7, 30));
  });

  test('多条提醒按实际触发时间排序', () {
    final result = AlarmTimeCalculator.calculateAndSort(
      scheduleDate: date,
      arrivalTime: const ClockTime(hour: 8, minute: 0),
      arrivalDayOffset: 0,
      rules: [
        relative('即将到岗', 20, order: 2),
        relative('起床', 120),
        relative('出发', 60, order: 1),
      ],
    );
    expect(result.map((entry) => entry.key.id), ['起床', '出发', '即将到岗']);
  });

  test('已停用提醒会被过滤', () {
    const disabled = ReminderRule(
      id: 'disabled',
      name: '已停用',
      isEnabled: false,
      timeMode: ReminderTimeMode.beforeArrival,
      minutesBeforeArrival: 30,
    );
    final result = AlarmTimeCalculator.calculateAndSort(
      scheduleDate: date,
      arrivalTime: const ClockTime(hour: 8, minute: 0),
      arrivalDayOffset: 0,
      rules: [disabled, relative('enabled', 60)],
    );
    expect(result.map((entry) => entry.key.id), ['enabled']);
  });
}
