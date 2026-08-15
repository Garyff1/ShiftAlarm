import '../../data/models/alarm_lifecycle_event.dart';
import '../../data/models/alarm_record.dart';
import '../../data/models/app_enums.dart';
import 'native_alarm_scheduler.dart';

enum AlarmDiagnosticState { ready, normal, needsAttention, failed }

class AlarmDiagnosticSummary {
  const AlarmDiagnosticSummary({
    required this.alarm,
    required this.events,
    required this.state,
    required this.headline,
    required this.conclusion,
    this.failureCategory,
  });

  final AlarmRecord alarm;
  final List<AlarmLifecycleEvent> events;
  final AlarmDiagnosticState state;
  final String headline;
  final String conclusion;
  final AlarmFailureCategory? failureCategory;

  AlarmLifecycleEvent? eventFor(AlarmLifecycleStage stage) =>
      events.where((item) => item.stage == stage).lastOrNull;
}

class AlarmDiagnosticService {
  const AlarmDiagnosticService();

  List<AlarmDiagnosticSummary> build({
    required Iterable<AlarmRecord> alarms,
    required Iterable<AlarmLifecycleEvent> events,
    required AlarmPermissionState permissions,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final grouped = <String, List<AlarmLifecycleEvent>>{};
    for (final event in events) {
      grouped.putIfAbsent(event.alarmId, () => []).add(event);
    }
    final result =
        alarms
            .where((item) => !item.isTest)
            .map(
              (alarm) => _summarize(
                alarm,
                grouped[alarm.id] ?? const [],
                permissions,
                clock,
              ),
            )
            .toList()
          ..sort((a, b) => b.alarm.triggerAt.compareTo(a.alarm.triggerAt));
    return result;
  }

  AlarmDiagnosticSummary _summarize(
    AlarmRecord alarm,
    List<AlarmLifecycleEvent> rawEvents,
    AlarmPermissionState permissions,
    DateTime now,
  ) {
    final events = List<AlarmLifecycleEvent>.of(rawEvents)
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final failure = events
        .where((item) => item.failureCategory != null)
        .lastOrNull;
    final audioStarted = events.any(
      (item) => item.stage == AlarmLifecycleStage.audioStarted,
    );
    final receiverReceived = events.any(
      (item) => item.stage == AlarmLifecycleStage.receiverReceived,
    );
    final serviceStarted = events.any(
      (item) => item.stage == AlarmLifecycleStage.ringServiceStarted,
    );
    final scheduled = events.any(
      (item) => item.stage == AlarmLifecycleStage.scheduled,
    );
    final afterDeliveryWindow = now.isAfter(
      alarm.triggerAt.add(const Duration(minutes: 2)),
    );

    if (audioStarted) {
      return AlarmDiagnosticSummary(
        alarm: alarm,
        events: events,
        state: AlarmDiagnosticState.normal,
        headline: '已正常响铃',
        conclusion: '系统已经触发闹钟，ShiftAlarm 响铃服务和声音播放均已启动。',
        failureCategory:
            failure?.failureCategory ==
                AlarmFailureCategory.customSoundUnavailable
            ? failure?.failureCategory
            : null,
      );
    }

    if (!permissions.exactAlarm && alarm.status.isActive) {
      return AlarmDiagnosticSummary(
        alarm: alarm,
        events: events,
        state: AlarmDiagnosticState.failed,
        headline: '需要开启闹钟权限',
        conclusion: '系统当前不允许 ShiftAlarm 提交精确闹钟。',
        failureCategory: AlarmFailureCategory.exactAlarmPermissionMissing,
      );
    }

    if (afterDeliveryWindow) {
      final category =
          failure?.failureCategory ??
          (!scheduled
              ? AlarmFailureCategory.scheduleOutdated
              : !receiverReceived
              ? AlarmFailureCategory.systemNotTriggered
              : !serviceStarted
              ? AlarmFailureCategory.foregroundServiceFailure
              : AlarmFailureCategory.audioPlaybackFailure);
      final conclusion = switch (category) {
        AlarmFailureCategory.systemNotTriggered => '系统没有把这次闹钟事件交给 ShiftAlarm。',
        AlarmFailureCategory.foregroundServiceFailure =>
          '系统已经触发闹钟，但响铃服务没有成功启动。',
        AlarmFailureCategory.notificationFailure => '响铃服务已经收到请求，但系统通知创建失败。',
        AlarmFailureCategory.audioInitializationFailure ||
        AlarmFailureCategory.audioPlaybackFailure => '闹钟已经触发，但声音没有确认开始播放。',
        AlarmFailureCategory.appForceStopped =>
          'ShiftAlarm 曾被强行停止，系统可能移除了这次闹钟。',
        AlarmFailureCategory.exactAlarmPermissionMissing => '闹钟触发前精确闹钟权限不可用。',
        _ => '这次闹钟没有形成完整的响铃确认链路。',
      };
      return AlarmDiagnosticSummary(
        alarm: alarm,
        events: events,
        state: AlarmDiagnosticState.failed,
        headline: '未确认响铃',
        conclusion: conclusion,
        failureCategory: category,
      );
    }

    if (failure != null &&
        failure.failureCategory !=
            AlarmFailureCategory.customSoundUnavailable) {
      return AlarmDiagnosticSummary(
        alarm: alarm,
        events: events,
        state: AlarmDiagnosticState.needsAttention,
        headline: '需要处理',
        conclusion: failure.failureCategory!.label,
        failureCategory: failure.failureCategory,
      );
    }

    return AlarmDiagnosticSummary(
      alarm: alarm,
      events: events,
      state: AlarmDiagnosticState.ready,
      headline: alarm.status == AlarmStatus.registered ? '等待响铃' : '正在准备',
      conclusion: scheduled
          ? 'ShiftAlarm 已向系统提交这次闹钟，等待到达计划时间。'
          : 'ShiftAlarm 正在准备并提交这次闹钟。',
    );
  }
}
