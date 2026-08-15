import 'model_parsers.dart';

enum AlarmLifecycleStage {
  planned('planned', '已生成计划'),
  scheduled('scheduled', '已提交系统'),
  receiverReceived('receiver_received', '系统已经触发'),
  ringServiceStarted('ring_service_started', '响铃服务已启动'),
  audioPrepared('audio_prepared', '声音已准备'),
  audioStarted('audio_started', '声音开始播放'),
  dismissed('dismissed', '用户已停止'),
  snoozed('snoozed', '用户已贪睡'),
  timeout('timeout', '响铃超时'),
  playbackFailed('playback_failed', '声音播放失败'),
  serviceFailed('service_failed', '响铃服务失败'),
  cancelled('cancelled', '闹钟已取消'),
  appWasForceStopped('app_was_force_stopped', '检测到强行停止'),
  forceStopRecovered('force_stop_recovered', '强行停止后已恢复'),
  directBootRestored('direct_boot_restored', '重启闹钟已恢复'),
  timeRecalculated('time_recalculated', '系统时间变化后已重算'),
  timezoneRecalculated('timezone_recalculated', '时区变化后已重算'),
  diagnosticFailure('diagnostic_failure', '检测到异常');

  const AlarmLifecycleStage(this.storageValue, this.label);
  final String storageValue;
  final String label;

  bool get isSuccessfulDelivery =>
      this == receiverReceived ||
      this == ringServiceStarted ||
      this == audioPrepared ||
      this == audioStarted ||
      this == dismissed ||
      this == snoozed ||
      this == timeout;

  bool get isTerminal =>
      this == dismissed ||
      this == snoozed ||
      this == timeout ||
      this == playbackFailed ||
      this == serviceFailed ||
      this == cancelled ||
      this == diagnosticFailure;

  static AlarmLifecycleStage fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => AlarmLifecycleStage.diagnosticFailure,
  );
}

enum AlarmFailureCategory {
  systemNotTriggered('system_not_triggered', '系统没有触发闹钟'),
  exactAlarmPermissionMissing('exact_alarm_permission_missing', '精确闹钟权限未开启'),
  appForceStopped('app_force_stopped', '应用曾被强行停止'),
  receiverFailure('receiver_failure', '系统广播接收失败'),
  foregroundServiceFailure('foreground_service_failure', '响铃服务启动失败'),
  notificationFailure('notification_failure', '响铃通知创建失败'),
  audioInitializationFailure('audio_initialization_failure', '声音初始化失败'),
  audioPlaybackFailure('audio_playback_failure', '声音播放失败'),
  customSoundUnavailable('custom_sound_unavailable', '自定义铃声不可用'),
  directBootRestoreFailure('direct_boot_restore_failure', '重启恢复失败'),
  timeChanged('time_changed', '系统时间发生变化'),
  timezoneChanged('timezone_changed', '系统时区发生变化'),
  scheduleOutdated('schedule_outdated', '排班计划已经变化'),
  unknown('unknown', '暂时无法确定原因');

  const AlarmFailureCategory(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static AlarmFailureCategory? fromStorage(Object? value) {
    if (value == null) return null;
    return values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AlarmFailureCategory.unknown,
    );
  }
}

class AlarmLifecycleEvent {
  const AlarmLifecycleEvent({
    required this.id,
    required this.alarmId,
    required this.stage,
    required this.occurredAt,
    this.scheduleId,
    this.nativeAlarmId,
    this.plannedTriggerAt,
    this.failureCategory,
    this.source = 'flutter',
    this.isTest = false,
    this.details = const {},
  });

  final String id;
  final String alarmId;
  final String? scheduleId;
  final int? nativeAlarmId;
  final AlarmLifecycleStage stage;
  final DateTime occurredAt;
  final DateTime? plannedTriggerAt;
  final AlarmFailureCategory? failureCategory;
  final String source;
  final bool isTest;
  final Map<String, Object?> details;

  Map<String, Object?> toMap() => {
    'id': id,
    'alarmId': alarmId,
    'scheduleId': scheduleId,
    'nativeAlarmId': nativeAlarmId,
    'stage': stage.storageValue,
    'occurredAt': occurredAt.millisecondsSinceEpoch,
    'plannedTriggerAt': plannedTriggerAt?.millisecondsSinceEpoch,
    'failureCategory': failureCategory?.storageValue,
    'source': source,
    'isTest': isTest,
    'details': details,
  };

  factory AlarmLifecycleEvent.fromMap(Map<String, Object?> map) {
    final rawDetails = map['details'];
    return AlarmLifecycleEvent(
      id: parseString(map['id']),
      alarmId: parseString(map['alarmId'], fallback: 'unknown'),
      scheduleId: parseNullableString(map['scheduleId']),
      nativeAlarmId: map['nativeAlarmId'] == null
          ? null
          : parseInt(map['nativeAlarmId']),
      stage: AlarmLifecycleStage.fromStorage(map['stage']),
      occurredAt: parseDateTime(map['occurredAt']),
      plannedTriggerAt: parseNullableDateTime(map['plannedTriggerAt']),
      failureCategory: AlarmFailureCategory.fromStorage(map['failureCategory']),
      source: parseString(map['source'], fallback: 'flutter'),
      isTest: parseBool(map['isTest']),
      details: rawDetails is Map
          ? rawDetails.map((key, value) => MapEntry(key.toString(), value))
          : const {},
    );
  }
}
