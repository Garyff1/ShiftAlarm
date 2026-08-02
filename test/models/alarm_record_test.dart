import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/data/models/alarm_record.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/services/alarm/native_alarm_scheduler.dart';

AlarmRecord record({
  AlarmStatus status = AlarmStatus.pending,
  int snoozeCount = 0,
  int maxSnoozeCount = 3,
  bool snoozeEnabled = true,
  String? failureReason,
}) {
  final now = DateTime(2026, 8, 1, 12);
  return AlarmRecord(
    id: 'alarm-1',
    scheduleId: 'schedule-1',
    scheduleDate: DateTime(2026, 8, 2),
    shiftTemplateId: 'shift-1',
    reminderRuleId: 'wake',
    reminderName: '起床',
    shiftCode: 'A1',
    shiftName: '早班',
    triggerAt: DateTime(2026, 8, 2, 6),
    arrivalAt: DateTime(2026, 8, 2, 8),
    nativeAlarmId: 10000,
    status: status,
    soundId: 'system',
    isSnoozeEnabled: snoozeEnabled,
    snoozeMinutes: 8,
    maxSnoozeCount: maxSnoozeCount,
    snoozeCount: snoozeCount,
    failureReason: failureReason,
    isTemporarySchedule: true,
    isCoreAlarm: true,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('稳定键由排班 ID 与提醒规则 ID 组成', () {
    expect(record().stableKey, 'schedule-1:wake');
  });

  test('未达到最大次数时允许贪睡', () {
    expect(record(snoozeCount: 2, maxSnoozeCount: 3).canSnooze, isTrue);
  });

  test('达到最大次数后禁止继续贪睡', () {
    expect(record(snoozeCount: 3, maxSnoozeCount: 3).canSnooze, isFalse);
  });

  test('提醒关闭贪睡后始终禁止贪睡', () {
    expect(record(snoozeEnabled: false).canSnooze, isFalse);
  });

  test('AlarmRecord v3 字段可完整序列化恢复', () {
    final restored = AlarmRecord.fromMap(
      record(status: AlarmStatus.ringing).toMap(),
    );
    expect(restored.toMap(), record(status: AlarmStatus.ringing).toMap());
  });

  test('未知闹钟状态恢复为登记失败', () {
    final map = record().toMap()..['status'] = 'future_unknown';
    expect(AlarmRecord.fromMap(map).status, AlarmStatus.failed);
  });

  test('copyWith 可清除旧失败原因并保留稳定 ID', () {
    final updated = record(
      failureReason: '旧错误',
    ).copyWith(status: AlarmStatus.registered, clearFailureReason: true);
    expect(updated.failureReason, isNull);
    expect(updated.nativeAlarmId, 10000);
    expect(updated.stableKey, 'schedule-1:wake');
  });

  test('只有可恢复状态会计入活动闹钟', () {
    expect(AlarmStatus.registered.isActive, isTrue);
    expect(AlarmStatus.permissionBlocked.isActive, isTrue);
    expect(AlarmStatus.cancelled.isActive, isFalse);
    expect(AlarmStatus.dismissed.isActive, isFalse);
  });

  test('原生载荷包含本地时间、稳定 ID 和 15 分钟上限', () {
    final payload = nativePayloadFor(record());
    expect(payload['nativeAlarmId'], 10000);
    expect(payload['triggerYear'], 2026);
    expect(payload['triggerMonth'], 8);
    expect(payload['triggerDay'], 2);
    expect(payload['triggerHour'], 6);
    expect(payload['maxRingingMinutes'], 15);
  });

  test('权限状态正确判断静音、低音量与总体就绪', () {
    const ready = AlarmPermissionState(
      exactAlarm: true,
      notifications: true,
      fullScreenIntent: false,
      ignoringBatteryOptimizations: false,
      alarmVolume: 2,
      maxAlarmVolume: 10,
    );
    expect(ready.ready, isTrue);
    expect(ready.volumeMuted, isFalse);
    expect(ready.volumeLow, isTrue);
    const muted = AlarmPermissionState.unavailable();
    expect(muted.volumeMuted, isTrue);
    expect(muted.ready, isFalse);
  });
}
