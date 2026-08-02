import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/clock_time.dart';
import 'package:shift_alarm/data/models/reminder_rule.dart';
import 'package:shift_alarm/data/models/shift_template.dart';

void main() {
  final createdAt = DateTime(2026, 8, 1, 12, 30);
  final reminder = ReminderRule(
    id: 'reminder_1',
    name: '起床',
    timeMode: ReminderTimeMode.beforeArrival,
    minutesBeforeArrival: 120,
    sortOrder: 0,
  );

  test('ShiftTemplate 可完整序列化并恢复', () {
    final original = ShiftTemplate(
      id: 'shift_1',
      code: 'A1',
      name: '早班',
      type: ShiftType.work,
      aliases: const ['早', 'A'],
      colorValue: 0xFF526AA0,
      arrivalTime: const ClockTime(hour: 8, minute: 0),
      arrivalDayOffset: 1,
      reminderRules: [reminder],
      note: '测试',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final restored = ShiftTemplate.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.code, 'A1');
    expect(restored.aliases, ['早', 'A']);
    expect(restored.arrivalTime, const ClockTime(hour: 8, minute: 0));
    expect(restored.arrivalDayOffset, 1);
    expect(restored.reminderRules.single.name, '起床');
    expect(restored.createdAt, createdAt);
  });

  test('ReminderRule 可完整序列化并恢复', () {
    final original = reminder.copyWith(
      timeMode: ReminderTimeMode.fixed,
      fixedTime: const ClockTime(hour: 6, minute: 45),
      clearMinutesBeforeArrival: true,
      isVibrationEnabled: false,
      snoozeMinutes: 15,
      maxSnoozeCount: 2,
    );
    final restored = ReminderRule.fromMap(original.toMap());

    expect(restored.timeMode, ReminderTimeMode.fixed);
    expect(restored.fixedTime, const ClockTime(hour: 6, minute: 45));
    expect(restored.minutesBeforeArrival, isNull);
    expect(restored.snoozeMinutes, 15);
    expect(restored.maxSnoozeCount, 2);
  });

  test('未知枚举值恢复为安全默认值', () {
    expect(ShiftType.fromStorage('future_type'), ShiftType.other);
    expect(
      ReminderTimeMode.fromStorage('future_mode'),
      ReminderTimeMode.beforeArrival,
    );
    expect(
      ScheduleStatus.fromStorage('future_status'),
      ScheduleStatus.unconfirmed,
    );
    expect(AlarmStatus.fromStorage('future_alarm'), AlarmStatus.failed);
    expect(AppThemeMode.fromStorage('future_theme'), AppThemeMode.system);
  });

  test('跨天字段保存并恢复', () {
    final map = <String, Object?>{
      'id': 'shift_2',
      'code': 'N',
      'name': '夜班',
      'type': 'work',
      'colorValue': 0xFF526AA0,
      'arrivalTime': {'hour': 1, 'minute': 15},
      'arrivalDayOffset': 1,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': createdAt.millisecondsSinceEpoch,
    };

    final restored = ShiftTemplate.fromMap(map);
    expect(restored.arrivalDayOffset, 1);
    expect(restored.arrivalTime, const ClockTime(hour: 1, minute: 15));
  });

  test('缺少别名和提醒字段时使用空列表', () {
    final restored = ShiftTemplate.fromMap({
      'id': 'shift_3',
      'code': 'OFF',
      'name': '休息',
      'type': 'rest',
      'colorValue': 0xFF526AA0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': createdAt.millisecondsSinceEpoch,
    });

    expect(restored.aliases, isEmpty);
    expect(restored.reminderRules, isEmpty);
  });
}
