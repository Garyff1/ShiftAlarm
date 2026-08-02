import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/data/models/alarm_record.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/clock_time.dart';
import 'package:shift_alarm/data/models/reminder_rule.dart';
import 'package:shift_alarm/data/models/shift_template.dart';
import 'package:shift_alarm/data/repositories/alarm_record_repository.dart';
import 'package:shift_alarm/data/repositories/daily_schedule_repository.dart';
import 'package:shift_alarm/data/repositories/shift_template_repository.dart';
import 'package:shift_alarm/data/storage/memory_local_data_store.dart';
import 'package:shift_alarm/services/alarm/alarm_sync_coordinator.dart';
import 'package:shift_alarm/services/alarm/native_alarm_scheduler.dart';

class AlarmHarness {
  AlarmHarness({AlarmPermissionState? permissions})
    : store = MemoryLocalDataStore(),
      native = MemoryNativeAlarmScheduler(permissions: permissions) {
    schedules = LocalDailyScheduleRepository(store);
    shifts = LocalShiftTemplateRepository(store);
    alarms = LocalAlarmRecordRepository(store);
    coordinator = AlarmSyncCoordinator(
      scheduleRepository: schedules,
      shiftRepository: shifts,
      alarmRepository: alarms,
      nativeScheduler: native,
    );
  }

  final MemoryLocalDataStore store;
  final MemoryNativeAlarmScheduler native;
  late final LocalDailyScheduleRepository schedules;
  late final LocalShiftTemplateRepository shifts;
  late final LocalAlarmRecordRepository alarms;
  late final AlarmSyncCoordinator coordinator;

  final now = DateTime(2026, 8, 1, 0, 0);
  final date = DateTime(2026, 8, 2);

  ShiftTemplate work({
    String id = 'shift-a',
    String code = 'A1',
    int arrivalHour = 8,
    List<ReminderRule>? rules,
  }) => ShiftTemplate(
    id: id,
    code: code,
    name: '$code 班',
    type: ShiftType.work,
    colorValue: 0xFF336699,
    arrivalTime: ClockTime(hour: arrivalHour, minute: 0),
    reminderRules:
        rules ??
        const [
          ReminderRule(
            id: 'wake',
            name: '起床',
            timeMode: ReminderTimeMode.beforeArrival,
            minutesBeforeArrival: 120,
          ),
        ],
    createdAt: now,
    updatedAt: now,
  );

  ShiftTemplate rest() => ShiftTemplate(
    id: 'shift-off',
    code: 'OFF',
    name: '休息',
    type: ShiftType.rest,
    colorValue: 0xFF888888,
    createdAt: now,
    updatedAt: now,
  );

  Future<ShiftTemplate> seedWork({List<ReminderRule>? rules}) async {
    final template = work(rules: rules);
    await shifts.add(template);
    await schedules.setShift(date, template);
    return template;
  }
}

const denied = AlarmPermissionState(
  exactAlarm: false,
  notifications: true,
  fullScreenIntent: true,
  ignoringBatteryOptimizations: true,
  alarmVolume: 5,
  maxAlarmVolume: 10,
);

void main() {
  test('首次同步登记系统闹钟并写入 Direct Boot 快照', () async {
    final h = AlarmHarness();
    await h.seedWork();
    final result = await h.coordinator.synchronizeAll(now: h.now);
    final saved = (await h.alarms.getAll()).single;
    expect(result.registered, 1);
    expect(saved.status, AlarmStatus.registered);
    expect(saved.nativeAlarmId, 10000);
    expect(h.native.scheduled.keys, [10000]);
    expect(h.native.snapshots.single.id, saved.id);
  });

  test('同一批排班重复同步保持幂等且不新增 ID', () async {
    final h = AlarmHarness();
    await h.seedWork();
    await h.coordinator.synchronizeAll(now: h.now);
    final second = await h.coordinator.synchronizeAll(now: h.now);
    expect(second.unchanged, 1);
    expect(second.registered, 0);
    expect(h.native.scheduled, hasLength(1));
    expect((await h.alarms.getAll()).single.nativeAlarmId, 10000);
  });

  test('班次时间变化时替换原闹钟但沿用稳定原生 ID', () async {
    final h = AlarmHarness();
    final original = await h.seedWork();
    await h.coordinator.synchronizeAll(now: h.now);
    await h.shifts.update(
      original.copyWith(
        arrivalTime: const ClockTime(hour: 9, minute: 0),
        updatedAt: h.now.add(const Duration(minutes: 1)),
      ),
    );
    final result = await h.coordinator.synchronizeDates([h.date], now: h.now);
    final saved = (await h.alarms.getAll()).single;
    expect(result.cancelled, 1);
    expect(result.registered, 1);
    expect(saved.nativeAlarmId, 10000);
    expect(saved.triggerAt, DateTime(2026, 8, 2, 7));
    expect(h.native.scheduled, hasLength(1));
  });

  test('精确闹钟权限关闭时写入权限阻断而不调用系统登记', () async {
    final h = AlarmHarness(permissions: denied);
    await h.seedWork();
    final result = await h.coordinator.synchronizeAll(now: h.now);
    final saved = (await h.alarms.getAll()).single;
    expect(result.permissionBlocked, 1);
    expect(result.successful, isFalse);
    expect(saved.status, AlarmStatus.permissionBlocked);
    expect(saved.failureReason, contains('权限'));
    expect(h.native.scheduled, isEmpty);
    expect(h.native.snapshots, isEmpty);
  });

  test('权限恢复后自动登记先前被阻断的同一条记录', () async {
    final h = AlarmHarness(permissions: denied);
    await h.seedWork();
    await h.coordinator.synchronizeAll(now: h.now);
    h.native.permissions = const AlarmPermissionState(
      exactAlarm: true,
      notifications: true,
      fullScreenIntent: true,
      ignoringBatteryOptimizations: true,
      alarmVolume: 5,
      maxAlarmVolume: 10,
    );
    final result = await h.coordinator.synchronizeAll(now: h.now);
    final saved = (await h.alarms.getAll()).single;
    expect(result.registered, 1);
    expect(saved.status, AlarmStatus.registered);
    expect(saved.nativeAlarmId, 10000);
    expect(saved.failureReason, isNull);
  });

  test('原生登记失败会保留失败原因并不写恢复快照', () async {
    final h = AlarmHarness();
    h.native.failScheduling = true;
    await h.seedWork();
    final result = await h.coordinator.synchronizeAll(now: h.now);
    final saved = (await h.alarms.getAll()).single;
    expect(result.failed, 1);
    expect(saved.status, AlarmStatus.failed);
    expect(saved.failureReason, 'simulated');
    expect(h.native.snapshots, isEmpty);
  });

  test('删除排班后取消旧系统闹钟并结束记录', () async {
    final h = AlarmHarness();
    await h.seedWork();
    await h.coordinator.synchronizeAll(now: h.now);
    await h.schedules.deleteByDate(h.date);
    final result = await h.coordinator.synchronizeDates([h.date], now: h.now);
    final saved = (await h.alarms.getAll()).single;
    expect(result.cancelled, 1);
    expect(saved.status, AlarmStatus.cancelled);
    expect(saved.endReason, AlarmEndReason.replaced);
    expect(h.native.scheduled, isEmpty);
  });

  test('标记休息会取消原工作提醒且不生成新提醒', () async {
    final h = AlarmHarness();
    await h.seedWork();
    await h.coordinator.synchronizeAll(now: h.now);
    final off = h.rest();
    await h.shifts.add(off);
    await h.schedules.setShift(h.date, off);
    final result = await h.coordinator.synchronizeDates([h.date], now: h.now);
    expect(result.cancelled, 1);
    expect(result.registered, 0);
    expect(h.native.scheduled, isEmpty);
  });

  test('暂停当天全部提醒会取消已有系统闹钟', () async {
    final h = AlarmHarness();
    await h.seedWork();
    await h.coordinator.synchronizeAll(now: h.now);
    await h.schedules.setRemindersPaused(h.date, true);
    final result = await h.coordinator.synchronizeDates([h.date], now: h.now);
    expect(result.cancelled, 1);
    expect(h.native.scheduled, isEmpty);
  });

  test('多条提醒分配互不冲突的持久化原生 ID', () async {
    final h = AlarmHarness();
    await h.seedWork(
      rules: const [
        ReminderRule(
          id: 'wake',
          name: '起床',
          timeMode: ReminderTimeMode.beforeArrival,
          minutesBeforeArrival: 120,
        ),
        ReminderRule(
          id: 'leave',
          name: '出发',
          timeMode: ReminderTimeMode.beforeArrival,
          minutesBeforeArrival: 60,
        ),
        ReminderRule(
          id: 'near',
          name: '即将到岗',
          timeMode: ReminderTimeMode.beforeArrival,
          minutesBeforeArrival: 20,
        ),
      ],
    );
    await h.coordinator.synchronizeAll(now: h.now);
    final ids = (await h.alarms.getAll())
        .map((item) => item.nativeAlarmId)
        .toSet();
    expect(ids, {10000, 10001, 10002});
    expect(h.native.scheduled, hasLength(3));
  });

  test('原生 ringing 事件回写触发时间并移出恢复快照', () async {
    final h = AlarmHarness();
    await h.seedWork();
    await h.coordinator.synchronizeAll(now: h.now);
    final alarm = (await h.alarms.getAll()).single;
    final firedAt = DateTime(2026, 8, 2, 6);
    h.native.events.add({
      'id': alarm.id,
      'status': 'ringing',
      'at': firedAt.millisecondsSinceEpoch,
    });
    await h.coordinator.reconcileNativeEvents();
    final saved = (await h.alarms.getAll()).single;
    expect(saved.status, AlarmStatus.ringing);
    expect(saved.firedAt, firedAt);
    expect(h.native.snapshots, isEmpty);
  });

  test('原生停止事件回写已停止和用户停止原因', () async {
    final h = AlarmHarness();
    await h.seedWork();
    await h.coordinator.synchronizeAll(now: h.now);
    final alarm = (await h.alarms.getAll()).single;
    final dismissedAt = DateTime(2026, 8, 2, 6, 1);
    h.native.events.add({
      'id': alarm.id,
      'status': 'dismissed',
      'at': dismissedAt.millisecondsSinceEpoch,
    });
    await h.coordinator.reconcileNativeEvents();
    final saved = (await h.alarms.getAll()).single;
    expect(saved.status, AlarmStatus.dismissed);
    expect(saved.dismissedAt, dismissedAt);
    expect(saved.endReason, AlarmEndReason.userStopped);
  });

  test('原生贪睡事件更新触发时间并保留重启恢复快照', () async {
    final h = AlarmHarness();
    await h.seedWork();
    await h.coordinator.synchronizeAll(now: h.now);
    final alarm = (await h.alarms.getAll()).single;
    final snoozeAt = DateTime(2026, 8, 2, 6, 10);
    h.native.events.add({
      'id': alarm.id,
      'status': 'snoozed',
      'at': DateTime(2026, 8, 2, 6).millisecondsSinceEpoch,
      'triggerAt': snoozeAt.millisecondsSinceEpoch,
      'snoozeCount': 1,
    });
    await h.coordinator.reconcileNativeEvents();
    final saved = (await h.alarms.getAll()).single;
    expect(saved.status, AlarmStatus.snoozed);
    expect(saved.triggerAt, snoozeAt);
    expect(saved.snoozeCount, 1);
    expect(h.native.snapshots.single.id, alarm.id);
  });

  test('测试闹钟事件单独返回且不会混入正式记录', () async {
    final h = AlarmHarness();
    h.native.events.add({
      'id': 'test-alarm',
      'status': 'dismissed',
      'isTest': true,
      'at': h.now.millisecondsSinceEpoch,
    });
    final events = await h.coordinator.reconcileNativeEvents();
    expect(events, hasLength(1));
    expect(events.single['isTest'], isTrue);
    expect(await h.alarms.getAll(), isEmpty);
  });

  test('原生 ID 从现有占用值之后继续分配', () async {
    final h = AlarmHarness();
    final old = AlarmRecord(
      id: 'old',
      scheduleId: 'old-schedule',
      scheduleDate: DateTime(2026, 7, 1),
      shiftTemplateId: 'old-shift',
      reminderRuleId: 'old-rule',
      reminderName: '旧提醒',
      shiftCode: 'OLD',
      shiftName: '旧班',
      triggerAt: DateTime(2026, 7, 1, 6),
      nativeAlarmId: 10000,
      status: AlarmStatus.cancelled,
      createdAt: h.now,
      updatedAt: h.now,
    );
    await h.alarms.add(old);
    await h.seedWork();
    await h.coordinator.synchronizeAll(now: h.now);
    final current = (await h.alarms.getAll()).singleWhere(
      (item) => item.scheduleId != 'old-schedule',
    );
    expect(current.nativeAlarmId, 10001);
  });

  test('并发同步被串行化且最终只有一条系统登记', () async {
    final h = AlarmHarness();
    await h.seedWork();
    final results = await Future.wait([
      h.coordinator.synchronizeAll(now: h.now),
      h.coordinator.synchronizeAll(now: h.now),
    ]);
    expect(results.map((item) => item.registered).reduce((a, b) => a + b), 1);
    expect(results.map((item) => item.unchanged).reduce((a, b) => a + b), 1);
    expect(h.native.scheduled, hasLength(1));
  });
}
