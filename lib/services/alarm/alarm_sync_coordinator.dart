import 'dart:async';
import '../../data/models/alarm_record.dart';
import '../../data/models/alarm_lifecycle_event.dart';
import '../../data/models/app_enums.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/daily_schedule.dart';
import '../../data/repositories/alarm_record_repository.dart';
import '../../data/repositories/alarm_lifecycle_repository.dart';
import '../../data/repositories/alarm_sound_repository.dart';
import '../../data/repositories/daily_schedule_repository.dart';
import '../../data/repositories/shift_template_repository.dart';
import '../../core/utils/id_generator.dart';
import 'alarm_plan_builder.dart';
import 'alarm_service.dart';
import 'native_alarm_scheduler.dart';

class AlarmSyncResult {
  const AlarmSyncResult({
    this.registered = 0,
    this.cancelled = 0,
    this.unchanged = 0,
    this.failed = 0,
    this.permissionBlocked = 0,
  });
  final int registered;
  final int cancelled;
  final int unchanged;
  final int failed;
  final int permissionBlocked;

  bool get successful => failed == 0 && permissionBlocked == 0;
}

class AlarmSyncCoordinator implements ScheduleAlarmSyncCoordinator {
  AlarmSyncCoordinator({
    required this.scheduleRepository,
    required this.shiftRepository,
    required this.alarmRepository,
    required this.nativeScheduler,
    this.soundRepository,
    this.loadSettings,
    this.lifecycleRepository,
    this.planBuilder = const AlarmPlanBuilder(),
    this.generationDays = 30,
  });

  final DailyScheduleRepository scheduleRepository;
  final ShiftTemplateRepository shiftRepository;
  final AlarmRecordRepository alarmRepository;
  final NativeAlarmScheduler nativeScheduler;
  final AlarmSoundRepository? soundRepository;
  final Future<AppSettings> Function()? loadSettings;
  final AlarmLifecycleRepository? lifecycleRepository;
  final AlarmPlanBuilder planBuilder;
  final int generationDays;
  Future<void>? _activeSync;

  @override
  Future<void> markPending(Iterable<DateTime> dates) async {
    try {
      await synchronizeDates(dates);
    } catch (_) {
      final schedules = await Future.wait(
        dates.map(scheduleRepository.getByDate),
      );
      await scheduleRepository.setAlarmSyncStatus(
        schedules.whereType<DailySchedule>().map((item) => item.id),
        AlarmSyncStatus.failed,
      );
    }
  }

  Future<AlarmSyncResult> synchronizeAll({
    DateTime? now,
    bool forceReschedule = false,
  }) async {
    final clock = now ?? DateTime.now();
    final schedules = await scheduleRepository.getFuture(
      from: clock,
      days: generationDays,
    );
    return _serialize(
      () => _synchronize(
        schedules: schedules,
        scopeDates: null,
        now: clock,
        forceReschedule: forceReschedule,
      ),
    );
  }

  Future<AlarmSyncResult> synchronizeDates(
    Iterable<DateTime> dates, {
    DateTime? now,
  }) async {
    final normalized = dates.map(DailySchedule.normalizeDate).toSet();
    final schedules = (await Future.wait(
      normalized.map(scheduleRepository.getByDate),
    )).whereType<DailySchedule>().toList();
    return _serialize(
      () => _synchronize(
        schedules: schedules,
        scopeDates: normalized,
        now: now ?? DateTime.now(),
        forceReschedule: false,
      ),
    );
  }

  Future<AlarmSyncResult> _serialize(
    Future<AlarmSyncResult> Function() operation,
  ) async {
    while (_activeSync != null) {
      await _activeSync;
    }
    final completer = Completer<void>();
    _activeSync = completer.future;
    try {
      return await operation();
    } finally {
      completer.complete();
      _activeSync = null;
    }
  }

  Future<AlarmSyncResult> _synchronize({
    required List<DailySchedule> schedules,
    required Set<DateTime>? scopeDates,
    required DateTime now,
    required bool forceReschedule,
  }) async {
    final shifts = await shiftRepository.getAll();
    final sounds = await soundRepository?.getAll() ?? const [];
    final settings = await loadSettings?.call() ?? const AppSettings();
    final templates = {for (final shift in shifts) shift.id: shift};
    final desired = planBuilder.build(
      schedules: schedules,
      templates: templates,
      appSettings: settings,
      sounds: sounds,
      now: now,
    );
    final existing = await alarmRepository.getAll();
    final scopedExisting = scopeDates == null
        ? existing.where((item) => item.status.isActive).toList()
        : existing
              .where(
                (item) =>
                    item.status.isActive &&
                    scopeDates.contains(
                      DailySchedule.normalizeDate(item.scheduleDate),
                    ),
              )
              .toList();
    final existingByKey = {for (final item in existing) item.stableKey: item};
    final desiredKeys = desired.map((item) => item.stableKey).toSet();
    var registered = 0;
    var cancelled = 0;
    var unchanged = 0;
    var failed = 0;
    var permissionBlocked = 0;

    for (final stale in scopedExisting.where(
      (item) => !desiredKeys.contains(item.stableKey),
    )) {
      if (stale.nativeAlarmId != null) {
        await nativeScheduler.cancel(stale.nativeAlarmId!);
      }
      await alarmRepository.update(
        stale.copyWith(
          status: AlarmStatus.cancelled,
          cancelledAt: now,
          endReason: AlarmEndReason.replaced,
        ),
      );
      await _appendLifecycle(
        alarmId: stale.id,
        scheduleId: stale.scheduleId,
        nativeAlarmId: stale.nativeAlarmId,
        stage: AlarmLifecycleStage.cancelled,
        occurredAt: now,
        plannedTriggerAt: stale.triggerAt,
        failureCategory: AlarmFailureCategory.scheduleOutdated,
        details: const {'reason': 'schedule_changed'},
      );
      cancelled++;
    }

    final permissions = await nativeScheduler.getPermissionState();
    var nextId = await alarmRepository.nextNativeAlarmId();
    for (final plan in desired) {
      final old = existingByKey[plan.stableKey];
      final nativeId = old?.nativeAlarmId ?? nextId++;
      final candidate = _materialize(plan, old, nativeId, now);
      await _appendLifecycle(
        alarmId: candidate.id,
        scheduleId: candidate.scheduleId,
        nativeAlarmId: candidate.nativeAlarmId,
        stage: AlarmLifecycleStage.planned,
        occurredAt: now,
        plannedTriggerAt: candidate.triggerAt,
        details: {
          'shiftCode': candidate.shiftCode,
          'reminderName': candidate.reminderName,
          'timezone': now.timeZoneName,
        },
      );
      final unchangedRegistration =
          old?.status == AlarmStatus.registered &&
          old?.triggerAt == candidate.triggerAt &&
          old?.shiftTemplateId == candidate.shiftTemplateId &&
          old?.reminderName == candidate.reminderName &&
          old?.soundId == candidate.soundId &&
          old?.soundPath == candidate.soundPath &&
          old?.soundChecksum == candidate.soundChecksum &&
          old?.isVolumeFadeInEnabled == candidate.isVolumeFadeInEnabled;
      if (unchangedRegistration && permissions.exactAlarm && !forceReschedule) {
        unchanged++;
        continue;
      }
      if (old?.nativeAlarmId != null && old!.status.isActive) {
        await nativeScheduler.cancel(old.nativeAlarmId!);
        cancelled++;
      }
      if (!permissions.exactAlarm) {
        await alarmRepository.update(
          candidate.copyWith(
            status: AlarmStatus.permissionBlocked,
            failureReason: '精确闹钟权限未开启',
          ),
        );
        await _appendLifecycle(
          alarmId: candidate.id,
          scheduleId: candidate.scheduleId,
          nativeAlarmId: candidate.nativeAlarmId,
          stage: AlarmLifecycleStage.diagnosticFailure,
          occurredAt: now,
          plannedTriggerAt: candidate.triggerAt,
          failureCategory: AlarmFailureCategory.exactAlarmPermissionMissing,
          details: const {'exactAlarmPermission': false},
        );
        permissionBlocked++;
        continue;
      }
      final result = await nativeScheduler.schedule(candidate);
      if (result.success) {
        await alarmRepository.update(
          candidate.copyWith(
            status: AlarmStatus.registered,
            registeredAt: now,
            clearFailureReason: true,
          ),
        );
        await _appendLifecycle(
          alarmId: candidate.id,
          scheduleId: candidate.scheduleId,
          nativeAlarmId: candidate.nativeAlarmId,
          stage: AlarmLifecycleStage.scheduled,
          occurredAt: now,
          plannedTriggerAt: candidate.triggerAt,
          details: {
            'scheduleApi':
                result.scheduleApi ??
                (candidate.isCoreAlarm
                    ? 'setAlarmClock'
                    : 'setExactAndAllowWhileIdle'),
            'exactAlarmPermission': permissions.exactAlarm,
            'timezone': now.timeZoneName,
            'timezoneOffsetMinutes': now.timeZoneOffset.inMinutes,
            'systemTime': now.millisecondsSinceEpoch,
            'forceReschedule': forceReschedule,
          },
        );
        registered++;
      } else {
        await alarmRepository.update(
          candidate.copyWith(
            status: AlarmStatus.failed,
            failureReason: result.error ?? '系统闹钟登记失败',
          ),
        );
        await _appendLifecycle(
          alarmId: candidate.id,
          scheduleId: candidate.scheduleId,
          nativeAlarmId: candidate.nativeAlarmId,
          stage: AlarmLifecycleStage.diagnosticFailure,
          occurredAt: now,
          plannedTriggerAt: candidate.triggerAt,
          failureCategory: result.error == 'exact_alarm_permission_denied'
              ? AlarmFailureCategory.exactAlarmPermissionMissing
              : AlarmFailureCategory.unknown,
          details: {'reason': result.error ?? 'native_schedule_failed'},
        );
        failed++;
      }
    }

    final scheduleStatus = !permissions.exactAlarm
        ? AlarmSyncStatus.permissionBlocked
        : failed > 0
        ? AlarmSyncStatus.failed
        : AlarmSyncStatus.synchronized;
    await scheduleRepository.setAlarmSyncStatus(
      schedules.map((item) => item.id),
      scheduleStatus,
      synchronizedAt: scheduleStatus == AlarmSyncStatus.synchronized
          ? now
          : null,
    );
    await _refreshSnapshots();
    return AlarmSyncResult(
      registered: registered,
      cancelled: cancelled,
      unchanged: unchanged,
      failed: failed,
      permissionBlocked: permissionBlocked,
    );
  }

  AlarmRecord _materialize(
    AlarmRecord plan,
    AlarmRecord? old,
    int nativeAlarmId,
    DateTime now,
  ) => AlarmRecord(
    id: old?.id ?? plan.id,
    scheduleId: plan.scheduleId,
    scheduleDate: plan.scheduleDate,
    shiftTemplateId: plan.shiftTemplateId,
    reminderRuleId: plan.reminderRuleId,
    reminderName: plan.reminderName,
    shiftCode: plan.shiftCode,
    shiftName: plan.shiftName,
    triggerAt: plan.triggerAt,
    arrivalAt: plan.arrivalAt,
    nativeAlarmId: nativeAlarmId,
    status: AlarmStatus.pending,
    soundId: plan.soundId,
    soundPath: plan.soundPath,
    soundChecksum: plan.soundChecksum,
    isVolumeFadeInEnabled: plan.isVolumeFadeInEnabled,
    isVibrationEnabled: plan.isVibrationEnabled,
    isSnoozeEnabled: plan.isSnoozeEnabled,
    snoozeMinutes: plan.snoozeMinutes,
    maxSnoozeCount: plan.maxSnoozeCount,
    isTemporarySchedule: plan.isTemporarySchedule,
    isCoreAlarm: plan.isCoreAlarm,
    createdAt: old?.createdAt ?? now,
    updatedAt: now,
  );

  Future<void> _refreshSnapshots() async {
    final active = (await alarmRepository.getAll())
        .where(
          (item) =>
              item.status == AlarmStatus.registered ||
              item.status == AlarmStatus.snoozed,
        )
        .toList();
    await nativeScheduler.replaceDirectBootSnapshots(active);
  }

  Future<List<Map<String, Object?>>> reconcileNativeEvents() async {
    final lifecycleValues = await nativeScheduler.consumeLifecycleEvents();
    final lifecycleEvents = <AlarmLifecycleEvent>[];
    for (final value in lifecycleValues) {
      try {
        lifecycleEvents.add(AlarmLifecycleEvent.fromMap(value));
      } catch (_) {
        // A malformed native diagnostic event must never block alarm recovery.
      }
    }
    await lifecycleRepository?.appendAll(lifecycleEvents);
    final events = await nativeScheduler.consumeNativeEvents();
    final testEvents = <Map<String, Object?>>[];
    for (final event in events) {
      if (event['isTest'] == true) {
        testEvents.add(event);
        continue;
      }
      final id = event['id']?.toString();
      if (id == null) continue;
      final record = await alarmRepository.getById(id);
      if (record == null) continue;
      final status = AlarmStatus.fromStorage(event['status']);
      final at = DateTime.fromMillisecondsSinceEpoch(
        (event['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      );
      await alarmRepository.update(
        record.copyWith(
          status: status,
          triggerAt: event['triggerAt'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (event['triggerAt'] as num).toInt(),
                ),
          snoozeCount: (event['snoozeCount'] as num?)?.toInt(),
          firedAt: status == AlarmStatus.ringing ? at : null,
          dismissedAt: status == AlarmStatus.dismissed ? at : null,
          endReason: status == AlarmStatus.dismissed
              ? AlarmEndReason.userStopped
              : status == AlarmStatus.triggered
              ? AlarmEndReason.timedOut
              : null,
        ),
      );
    }
    await _refreshSnapshots();
    return testEvents;
  }

  Future<void> _appendLifecycle({
    required String alarmId,
    required AlarmLifecycleStage stage,
    required DateTime occurredAt,
    String? scheduleId,
    int? nativeAlarmId,
    DateTime? plannedTriggerAt,
    AlarmFailureCategory? failureCategory,
    bool isTest = false,
    Map<String, Object?> details = const {},
  }) async {
    final repository = lifecycleRepository;
    if (repository == null) return;
    await repository.append(
      AlarmLifecycleEvent(
        id: IdGenerator.create('alarm_event'),
        alarmId: alarmId,
        scheduleId: scheduleId,
        nativeAlarmId: nativeAlarmId,
        stage: stage,
        occurredAt: occurredAt,
        plannedTriggerAt: plannedTriggerAt,
        failureCategory: failureCategory,
        isTest: isTest,
        details: details,
      ),
    );
  }
}
