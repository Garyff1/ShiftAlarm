import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/data/models/alarm_lifecycle_event.dart';
import 'package:shift_alarm/data/models/alarm_record.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/repositories/alarm_lifecycle_repository.dart';
import 'package:shift_alarm/data/storage/memory_local_data_store.dart';
import 'package:shift_alarm/services/alarm/alarm_diagnostic_service.dart';
import 'package:shift_alarm/services/alarm/diagnostic_report_service.dart';
import 'package:shift_alarm/services/alarm/native_alarm_scheduler.dart';

const readyPermissions = AlarmPermissionState(
  exactAlarm: true,
  notifications: true,
  fullScreenIntent: true,
  ignoringBatteryOptimizations: true,
  alarmVolume: 5,
  maxAlarmVolume: 10,
);

AlarmRecord alarm(DateTime triggerAt) => AlarmRecord(
  id: 'private-alarm-id',
  scheduleId: 'private-schedule-id',
  scheduleDate: DateTime(triggerAt.year, triggerAt.month, triggerAt.day),
  shiftTemplateId: 'shift-a',
  reminderRuleId: 'wake',
  reminderName: '私人起床提醒',
  shiftCode: 'A1',
  shiftName: '秘密公司早班',
  triggerAt: triggerAt,
  nativeAlarmId: 10001,
  status: AlarmStatus.registered,
  soundPath: r'C:\Users\person\private-alarm.mp3',
  createdAt: triggerAt.subtract(const Duration(days: 1)),
  updatedAt: triggerAt.subtract(const Duration(days: 1)),
);

AlarmLifecycleEvent event(
  String id,
  AlarmLifecycleStage stage,
  DateTime at, {
  AlarmFailureCategory? failure,
  Map<String, Object?> details = const {},
}) => AlarmLifecycleEvent(
  id: id,
  alarmId: 'private-alarm-id',
  nativeAlarmId: 10001,
  stage: stage,
  occurredAt: at,
  failureCategory: failure,
  details: details,
);

void main() {
  test('生命周期模型可完整序列化且未知值安全降级', () {
    final original = event(
      'event-1',
      AlarmLifecycleStage.audioStarted,
      DateTime(2026, 8, 15, 8),
      details: const {'soundType': 'system'},
    );
    final restored = AlarmLifecycleEvent.fromMap(original.toMap());
    expect(restored.stage, AlarmLifecycleStage.audioStarted);
    expect(restored.details['soundType'], 'system');
    expect(
      AlarmLifecycleEvent.fromMap({
        ...original.toMap(),
        'stage': 'future_stage',
        'failureCategory': 'future_failure',
      }).failureCategory,
      AlarmFailureCategory.unknown,
    );
  });

  test('生命周期仓库按 30 天和最多 1000 条执行保留策略', () async {
    final store = MemoryLocalDataStore();
    await store.initialize();
    final repository = LocalAlarmLifecycleRepository(store);
    final now = DateTime(2026, 8, 15, 12);
    await repository.appendAll([
      event('expired', AlarmLifecycleStage.planned, DateTime(2026, 7, 1)),
      for (var index = 0; index < 1002; index++)
        event(
          'current-$index',
          AlarmLifecycleStage.scheduled,
          now.subtract(Duration(minutes: index)),
        ),
    ]);
    await repository.prune(now: now);
    final retained = await repository.getAll();
    expect(retained, hasLength(1000));
    expect(retained.any((item) => item.id == 'expired'), isFalse);
    expect(retained.any((item) => item.id == 'current-1001'), isFalse);
  });

  test('诊断能区分系统未触发、服务未启动和正常响铃', () {
    final trigger = DateTime(2026, 8, 15, 8);
    const service = AlarmDiagnosticService();

    final systemMissing = service
        .build(
          alarms: [alarm(trigger)],
          events: [event('scheduled', AlarmLifecycleStage.scheduled, trigger)],
          permissions: readyPermissions,
          now: trigger.add(const Duration(minutes: 3)),
        )
        .single;
    expect(
      systemMissing.failureCategory,
      AlarmFailureCategory.systemNotTriggered,
    );

    final serviceMissing = service
        .build(
          alarms: [alarm(trigger)],
          events: [
            event('scheduled', AlarmLifecycleStage.scheduled, trigger),
            event('receiver', AlarmLifecycleStage.receiverReceived, trigger),
          ],
          permissions: readyPermissions,
          now: trigger.add(const Duration(minutes: 3)),
        )
        .single;
    expect(
      serviceMissing.failureCategory,
      AlarmFailureCategory.foregroundServiceFailure,
    );

    final normal = service
        .build(
          alarms: [alarm(trigger)],
          events: [event('audio', AlarmLifecycleStage.audioStarted, trigger)],
          permissions: readyPermissions,
          now: trigger.add(const Duration(minutes: 3)),
        )
        .single;
    expect(normal.state, AlarmDiagnosticState.normal);
  });

  test('诊断报告散列 ID 并过滤名称、音频路径和未授权详情', () {
    final trigger = DateTime(2026, 8, 16, 8);
    final report = const DiagnosticReportService().build(
      device: const NativeDeviceInfo(
        manufacturer: 'Google',
        model: 'Pixel',
        androidVersion: '16',
        sdkInt: 36,
        timezone: 'Asia/Shanghai',
      ),
      startup: const NativeAppStartupInfo(
        supported: true,
        wasForceStopped: true,
      ),
      permissions: readyPermissions,
      alarms: [alarm(trigger)],
      lifecycleEvents: [
        event(
          'event',
          AlarmLifecycleStage.scheduled,
          trigger.subtract(const Duration(minutes: 1)),
          details: const {
            'scheduleApi': 'setAlarmClock',
            'path': r'C:\Users\person\private-alarm.mp3',
            'secret': 'token-value',
          },
        ),
      ],
      generatedAt: DateTime(2026, 8, 15),
    );
    final decoded = jsonDecode(report.json) as Map<String, dynamic>;
    final exported = report.json;
    expect(exported, isNot(contains('private-alarm-id')));
    expect(exported, isNot(contains('私人起床提醒')));
    expect(exported, isNot(contains('秘密公司早班')));
    expect(exported, isNot(contains('private-alarm.mp3')));
    expect(exported, isNot(contains('token-value')));
    expect(decoded['privacy']['containsInternalFilePath'], isFalse);
  });
}
