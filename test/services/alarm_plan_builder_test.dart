import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/clock_time.dart';
import 'package:shift_alarm/data/models/daily_schedule.dart';
import 'package:shift_alarm/data/models/reminder_rule.dart';
import 'package:shift_alarm/data/models/shift_template.dart';
import 'package:shift_alarm/services/alarm/alarm_plan_builder.dart';

ReminderRule relativeRule(
  String id,
  int minutes, {
  bool enabled = true,
  bool snooze = true,
  int snoozeMinutes = 10,
  int maxSnooze = 3,
}) => ReminderRule(
  id: id,
  name: id,
  timeMode: ReminderTimeMode.beforeArrival,
  minutesBeforeArrival: minutes,
  isEnabled: enabled,
  isSnoozeEnabled: snooze,
  snoozeMinutes: snoozeMinutes,
  maxSnoozeCount: maxSnooze,
);

ReminderRule fixedRule(String id, int hour, int minute) => ReminderRule(
  id: id,
  name: id,
  timeMode: ReminderTimeMode.fixed,
  fixedTime: ClockTime(hour: hour, minute: minute),
);

ShiftTemplate shift({
  ShiftType type = ShiftType.work,
  ClockTime? arrival = const ClockTime(hour: 8, minute: 0),
  int dayOffset = 0,
  List<ReminderRule>? rules,
}) {
  final now = DateTime(2026, 8, 1);
  return ShiftTemplate(
    id: 'shift-a',
    code: 'A1',
    name: '早班',
    type: type,
    colorValue: 0xFF456789,
    arrivalTime: arrival,
    arrivalDayOffset: dayOffset,
    reminderRules: rules ?? [relativeRule('起床', 120)],
    createdAt: now,
    updatedAt: now,
  );
}

DailySchedule schedule({
  DateTime? date,
  bool paused = false,
  bool temporary = false,
  List<ReminderRule> overrides = const [],
}) {
  final now = DateTime(2026, 8, 1);
  return DailySchedule(
    id: 'schedule-a',
    date: date ?? DateTime(2026, 8, 2),
    shiftTemplateId: 'shift-a',
    originalShiftTemplateId: 'shift-a',
    isAllRemindersPaused: paused,
    isTemporaryChanged: temporary,
    reminderOverrides: overrides,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  const builder = AlarmPlanBuilder();
  final beforeAll = DateTime(2026, 8, 1);

  test('工作排班为每条有效提醒生成 AlarmRecord', () {
    final template = shift(
      rules: [
        relativeRule('起床', 120),
        relativeRule('出发', 60),
        relativeRule('即将到岗', 20),
      ],
    );
    final result = builder.build(
      schedules: [schedule()],
      templates: {template.id: template},
      now: beforeAll,
    );
    expect(result, hasLength(3));
  });

  test('生成结果按真实触发时间排序', () {
    final template = shift(
      rules: [relativeRule('即将到岗', 20), relativeRule('起床', 120)],
    );
    final result = builder.build(
      schedules: [schedule()],
      templates: {template.id: template},
      now: beforeAll,
    );
    expect(result.map((item) => item.reminderRuleId), ['起床', '即将到岗']);
  });

  test('固定提醒使用排班日期的固定时刻', () {
    final template = shift(rules: [fixedRule('固定', 6, 35)]);
    final result = builder.build(
      schedules: [schedule()],
      templates: {template.id: template},
      now: beforeAll,
    );
    expect(result.single.triggerAt, DateTime(2026, 8, 2, 6, 35));
  });

  test('相对提醒按到岗时间向前计算', () {
    final template = shift(rules: [relativeRule('出发', 75)]);
    final result = builder.build(
      schedules: [schedule()],
      templates: {template.id: template},
      now: beforeAll,
    );
    expect(result.single.triggerAt, DateTime(2026, 8, 2, 6, 45));
  });

  test('凌晨到岗的提醒可以落在前一自然日', () {
    final template = shift(
      arrival: const ClockTime(hour: 1, minute: 0),
      rules: [relativeRule('起床', 120)],
    );
    final result = builder.build(
      schedules: [schedule()],
      templates: {template.id: template},
      now: beforeAll,
    );
    expect(result.single.triggerAt, DateTime(2026, 8, 1, 23));
  });

  test('次日到岗按下一自然日计算相对提醒', () {
    final template = shift(
      arrival: const ClockTime(hour: 1, minute: 0),
      dayOffset: 1,
      rules: [relativeRule('出发', 120)],
    );
    final result = builder.build(
      schedules: [schedule()],
      templates: {template.id: template},
      now: beforeAll,
    );
    expect(result.single.triggerAt, DateTime(2026, 8, 2, 23));
    expect(result.single.arrivalAt, DateTime(2026, 8, 3, 1));
  });

  test('已经过期的提醒不会补响', () {
    final template = shift(rules: [relativeRule('起床', 120)]);
    final result = builder.build(
      schedules: [schedule()],
      templates: {template.id: template},
      now: DateTime(2026, 8, 2, 6, 1),
    );
    expect(result, isEmpty);
  });

  test('触发时间恰好等于当前时刻也会被过滤', () {
    final template = shift(rules: [relativeRule('起床', 120)]);
    final result = builder.build(
      schedules: [schedule()],
      templates: {template.id: template},
      now: DateTime(2026, 8, 2, 6),
    );
    expect(result, isEmpty);
  });

  test('休息班不生成闹钟', () {
    final template = shift(
      type: ShiftType.rest,
      arrival: null,
      rules: const [],
    );
    expect(
      builder.build(
        schedules: [schedule()],
        templates: {template.id: template},
        now: beforeAll,
      ),
      isEmpty,
    );
  });

  test('请假班不生成闹钟', () {
    final template = shift(
      type: ShiftType.leave,
      arrival: null,
      rules: const [],
    );
    expect(
      builder.build(
        schedules: [schedule()],
        templates: {template.id: template},
        now: beforeAll,
      ),
      isEmpty,
    );
  });

  test('暂停全部提醒的排班不生成闹钟', () {
    final template = shift();
    expect(
      builder.build(
        schedules: [schedule(paused: true)],
        templates: {template.id: template},
        now: beforeAll,
      ),
      isEmpty,
    );
  });

  test('当天提醒覆盖会替代模板提醒', () {
    final template = shift(rules: [relativeRule('模板提醒', 120)]);
    final result = builder.build(
      schedules: [
        schedule(overrides: [relativeRule('当天提醒', 30)]),
      ],
      templates: {template.id: template},
      now: beforeAll,
    );
    expect(result.single.reminderRuleId, '当天提醒');
    expect(result.single.triggerAt, DateTime(2026, 8, 2, 7, 30));
  });

  test('找不到班次模板时安全跳过孤立排班', () {
    expect(
      builder.build(
        schedules: [schedule()],
        templates: const {},
        now: beforeAll,
      ),
      isEmpty,
    );
  });

  test('贪睡、振动和临时调班配置完整传入记录', () {
    final template = shift(
      rules: [
        relativeRule('起床', 120, snooze: true, snoozeMinutes: 7, maxSnooze: 2),
      ],
    );
    final record = builder
        .build(
          schedules: [schedule(temporary: true)],
          templates: {template.id: template},
          now: beforeAll,
        )
        .single;
    expect(record.isSnoozeEnabled, isTrue);
    expect(record.snoozeMinutes, 7);
    expect(record.maxSnoozeCount, 2);
    expect(record.isTemporarySchedule, isTrue);
    expect(record.isCoreAlarm, isTrue);
  });
}
