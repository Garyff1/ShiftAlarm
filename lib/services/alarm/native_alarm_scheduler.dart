import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/alarm_record.dart';
import '../../data/models/alarm_sound.dart';
import '../../data/models/sound_ids.dart';

enum AlarmTestMode {
  standard('standard', '普通测试', '保持应用在前台，确认一分钟后能正常响铃。', 60),
  lockScreen('lock_screen', '锁屏测试', '登记后立即锁屏，确认锁屏界面和声音都能出现。', 60),
  background('background', '后台划掉测试', '登记后回到桌面，从最近任务划掉应用；不要在系统设置中“强行停止”。', 60),
  reboot('reboot', '重启恢复测试', '登记后在两分钟内重启手机，确认开机后闹钟会被恢复。', 120);

  const AlarmTestMode(
    this.storageValue,
    this.label,
    this.instruction,
    this.delaySeconds,
  );

  final String storageValue;
  final String label;
  final String instruction;
  final int delaySeconds;
}

class AlarmPermissionState {
  const AlarmPermissionState({
    required this.exactAlarm,
    required this.notifications,
    required this.fullScreenIntent,
    required this.ignoringBatteryOptimizations,
    required this.alarmVolume,
    required this.maxAlarmVolume,
  });

  const AlarmPermissionState.unavailable()
    : exactAlarm = false,
      notifications = false,
      fullScreenIntent = false,
      ignoringBatteryOptimizations = false,
      alarmVolume = 0,
      maxAlarmVolume = 0;

  final bool exactAlarm;
  final bool notifications;
  final bool fullScreenIntent;
  final bool ignoringBatteryOptimizations;
  final int alarmVolume;
  final int maxAlarmVolume;

  bool get volumeMuted => alarmVolume == 0;
  bool get volumeLow => maxAlarmVolume > 0 && alarmVolume * 4 < maxAlarmVolume;
  bool get ready => exactAlarm && notifications;

  factory AlarmPermissionState.fromMap(Map<Object?, Object?> map) =>
      AlarmPermissionState(
        exactAlarm: map['exactAlarm'] == true,
        notifications: map['notifications'] == true,
        fullScreenIntent: map['fullScreenIntent'] == true,
        ignoringBatteryOptimizations:
            map['ignoringBatteryOptimizations'] == true,
        alarmVolume: (map['alarmVolume'] as num?)?.toInt() ?? 0,
        maxAlarmVolume: (map['maxAlarmVolume'] as num?)?.toInt() ?? 0,
      );
}

class NativeScheduleResult {
  const NativeScheduleResult({
    required this.success,
    this.error,
    this.scheduleApi,
  });
  final bool success;
  final String? error;
  final String? scheduleApi;
}

class NativeAppStartupInfo {
  const NativeAppStartupInfo({
    required this.supported,
    required this.wasForceStopped,
    this.reason = -1,
    this.startType = -1,
    this.startComponent = -1,
  });

  const NativeAppStartupInfo.unsupported()
    : supported = false,
      wasForceStopped = false,
      reason = -1,
      startType = -1,
      startComponent = -1;

  final bool supported;
  final bool wasForceStopped;
  final int reason;
  final int startType;
  final int startComponent;

  factory NativeAppStartupInfo.fromMap(Map<Object?, Object?> map) =>
      NativeAppStartupInfo(
        supported: map['supported'] == true,
        wasForceStopped: map['wasForceStopped'] == true,
        reason: (map['reason'] as num?)?.toInt() ?? -1,
        startType: (map['startType'] as num?)?.toInt() ?? -1,
        startComponent: (map['startComponent'] as num?)?.toInt() ?? -1,
      );
}

class NativeDeviceInfo {
  const NativeDeviceInfo({
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    required this.sdkInt,
    required this.timezone,
  });

  const NativeDeviceInfo.unknown()
    : manufacturer = 'unknown',
      model = 'unknown',
      androidVersion = 'unknown',
      sdkInt = 0,
      timezone = 'unknown';

  final String manufacturer;
  final String model;
  final String androidVersion;
  final int sdkInt;
  final String timezone;

  factory NativeDeviceInfo.fromMap(Map<Object?, Object?> map) =>
      NativeDeviceInfo(
        manufacturer: map['manufacturer']?.toString() ?? 'unknown',
        model: map['model']?.toString() ?? 'unknown',
        androidVersion: map['androidVersion']?.toString() ?? 'unknown',
        sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
        timezone: map['timezone']?.toString() ?? 'unknown',
      );
}

abstract interface class NativeAlarmScheduler {
  Future<AlarmPermissionState> getPermissionState();
  Future<NativeScheduleResult> schedule(AlarmRecord record);
  Future<void> cancel(int nativeAlarmId);
  Future<void> replaceDirectBootSnapshots(Iterable<AlarmRecord> records);
  Future<List<Map<String, Object?>>> consumeNativeEvents();
  Future<List<Map<String, Object?>>> consumeLifecycleEvents();
  Future<NativeAppStartupInfo> getStartupInfo();
  Future<NativeDeviceInfo> getDeviceInfo();
  Future<bool> shareDiagnosticReport({
    required String json,
    required String summary,
  });
  Future<void> openExactAlarmSettings();
  Future<bool> requestNotificationPermission();
  Future<void> openNotificationSettings();
  Future<void> openFullScreenIntentSettings();
  Future<void> openAlarmVolumeSettings();
  Future<void> openBatterySettings();
  Future<NativeScheduleResult> scheduleTestAlarm({
    required int delaySeconds,
    AlarmTestMode mode = AlarmTestMode.standard,
    AlarmSound? sound,
    bool fadeIn = true,
  });
  Future<void> cancelTestAlarm();
}

Map<String, Object?> nativePayloadFor(AlarmRecord record) => {
  'id': record.id,
  'scheduleId': record.scheduleId,
  'nativeAlarmId': record.nativeAlarmId,
  'triggerAt': record.triggerAt.millisecondsSinceEpoch,
  'triggerYear': record.triggerAt.year,
  'triggerMonth': record.triggerAt.month,
  'triggerDay': record.triggerAt.day,
  'triggerHour': record.triggerAt.hour,
  'triggerMinute': record.triggerAt.minute,
  'reminderName': record.reminderName,
  'shiftCode': record.shiftCode,
  'shiftName': record.shiftName,
  'arrivalAt': record.arrivalAt?.millisecondsSinceEpoch,
  'isTemporary': record.isTemporarySchedule,
  'isCore': record.isCoreAlarm,
  'isTest': record.isTest,
  'vibration': record.isVibrationEnabled,
  'snoozeEnabled': record.isSnoozeEnabled,
  'snoozeMinutes': record.snoozeMinutes,
  'maxSnoozeCount': record.maxSnoozeCount,
  'snoozeCount': record.snoozeCount,
  'maxRingingMinutes': AppConstants.maxAlarmRingingMinutes,
  'soundId': record.soundId ?? SoundIds.system,
  'soundPath': record.soundPath,
  'soundChecksum': record.soundChecksum,
  'fadeIn': record.isVolumeFadeInEnabled,
};

class MethodChannelNativeAlarmScheduler implements NativeAlarmScheduler {
  const MethodChannelNativeAlarmScheduler();
  static const _channel = MethodChannel(AppConstants.alarmChannel);

  @override
  Future<AlarmPermissionState> getPermissionState() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'getPermissionState',
    );
    return AlarmPermissionState.fromMap(map ?? const {});
  }

  @override
  Future<NativeScheduleResult> schedule(AlarmRecord record) async {
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'scheduleAlarm',
        nativePayloadFor(record),
      );
      return NativeScheduleResult(
        success: value?['success'] == true,
        error: value?['error']?.toString(),
        scheduleApi: value?['scheduleApi']?.toString(),
      );
    } on PlatformException catch (error) {
      return NativeScheduleResult(success: false, error: error.message);
    }
  }

  @override
  Future<void> cancel(int nativeAlarmId) => _channel.invokeMethod<void>(
    'cancelAlarm',
    {'nativeAlarmId': nativeAlarmId},
  );

  @override
  Future<void> replaceDirectBootSnapshots(Iterable<AlarmRecord> records) =>
      _channel.invokeMethod<void>(
        'replaceSnapshots',
        records.map(nativePayloadFor).toList(),
      );

  @override
  Future<List<Map<String, Object?>>> consumeNativeEvents() async {
    final values = await _channel.invokeListMethod<Object?>('consumeEvents');
    return (values ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList();
  }

  @override
  Future<List<Map<String, Object?>>> consumeLifecycleEvents() async {
    final values = await _channel.invokeListMethod<Object?>(
      'consumeLifecycleEvents',
    );
    return (values ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList();
  }

  @override
  Future<NativeAppStartupInfo> getStartupInfo() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getStartupInfo',
    );
    return NativeAppStartupInfo.fromMap(value ?? const {});
  }

  @override
  Future<NativeDeviceInfo> getDeviceInfo() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getDeviceInfo',
    );
    return NativeDeviceInfo.fromMap(value ?? const {});
  }

  @override
  Future<bool> shareDiagnosticReport({
    required String json,
    required String summary,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'shareDiagnosticReport',
      {'json': json, 'summary': summary},
    );
    return value?['success'] == true;
  }

  @override
  Future<void> openExactAlarmSettings() =>
      _channel.invokeMethod<void>('openExactAlarmSettings');
  @override
  Future<bool> requestNotificationPermission() async =>
      await _channel.invokeMethod<bool>('requestNotificationPermission') ??
      false;
  @override
  Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');
  @override
  Future<void> openFullScreenIntentSettings() =>
      _channel.invokeMethod<void>('openFullScreenIntentSettings');
  @override
  Future<void> openAlarmVolumeSettings() =>
      _channel.invokeMethod<void>('openAlarmVolumeSettings');
  @override
  Future<void> openBatterySettings() =>
      _channel.invokeMethod<void>('openBatterySettings');

  @override
  Future<NativeScheduleResult> scheduleTestAlarm({
    required int delaySeconds,
    AlarmTestMode mode = AlarmTestMode.standard,
    AlarmSound? sound,
    bool fadeIn = true,
  }) async {
    final value = await _channel
        .invokeMapMethod<Object?, Object?>('scheduleTestAlarm', {
          'delaySeconds': delaySeconds,
          'testMode': mode.storageValue,
          'soundId': sound?.id ?? SoundIds.system,
          'soundPath': sound?.internalPath,
          'soundChecksum': sound?.checksum,
          'fadeIn': fadeIn,
        });
    return NativeScheduleResult(
      success: value?['success'] == true,
      error: value?['error']?.toString(),
    );
  }

  @override
  Future<void> cancelTestAlarm() =>
      _channel.invokeMethod<void>('cancelTestAlarm');
}

class MemoryNativeAlarmScheduler implements NativeAlarmScheduler {
  MemoryNativeAlarmScheduler({AlarmPermissionState? permissions})
    : permissions =
          permissions ??
          const AlarmPermissionState(
            exactAlarm: true,
            notifications: true,
            fullScreenIntent: true,
            ignoringBatteryOptimizations: true,
            alarmVolume: 5,
            maxAlarmVolume: 10,
          );

  AlarmPermissionState permissions;
  final Map<int, AlarmRecord> scheduled = {};
  final List<Map<String, Object?>> events = [];
  final List<Map<String, Object?>> lifecycleEvents = [];
  List<AlarmRecord> snapshots = const [];
  bool failScheduling = false;
  bool testAlarmScheduled = false;
  AlarmTestMode? scheduledTestMode;
  NativeAppStartupInfo startupInfo = const NativeAppStartupInfo.unsupported();
  NativeDeviceInfo deviceInfo = const NativeDeviceInfo.unknown();
  bool diagnosticReportShared = false;

  @override
  Future<AlarmPermissionState> getPermissionState() async => permissions;
  @override
  Future<NativeScheduleResult> schedule(AlarmRecord record) async {
    if (!permissions.exactAlarm) {
      return const NativeScheduleResult(
        success: false,
        error: 'exact_alarm_permission_denied',
      );
    }
    if (failScheduling) {
      return const NativeScheduleResult(success: false, error: 'simulated');
    }
    scheduled[record.nativeAlarmId!] = record;
    return const NativeScheduleResult(success: true);
  }

  @override
  Future<void> cancel(int nativeAlarmId) async =>
      scheduled.remove(nativeAlarmId);
  @override
  Future<void> replaceDirectBootSnapshots(Iterable<AlarmRecord> records) async {
    snapshots = records.toList();
  }

  @override
  Future<List<Map<String, Object?>>> consumeNativeEvents() async {
    final result = List<Map<String, Object?>>.of(events);
    events.clear();
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> consumeLifecycleEvents() async {
    final result = List<Map<String, Object?>>.of(lifecycleEvents);
    lifecycleEvents.clear();
    return result;
  }

  @override
  Future<NativeAppStartupInfo> getStartupInfo() async => startupInfo;
  @override
  Future<NativeDeviceInfo> getDeviceInfo() async => deviceInfo;
  @override
  Future<bool> shareDiagnosticReport({
    required String json,
    required String summary,
  }) async {
    diagnosticReportShared = true;
    return true;
  }

  @override
  Future<void> openAlarmVolumeSettings() async {}
  @override
  Future<void> openBatterySettings() async {}
  @override
  Future<void> openExactAlarmSettings() async {}
  @override
  Future<void> openFullScreenIntentSettings() async {}
  @override
  Future<void> openNotificationSettings() async {}
  @override
  Future<bool> requestNotificationPermission() async =>
      permissions.notifications;
  @override
  Future<NativeScheduleResult> scheduleTestAlarm({
    required int delaySeconds,
    AlarmTestMode mode = AlarmTestMode.standard,
    AlarmSound? sound,
    bool fadeIn = true,
  }) async {
    testAlarmScheduled = permissions.exactAlarm;
    scheduledTestMode = testAlarmScheduled ? mode : null;
    return NativeScheduleResult(
      success: testAlarmScheduled,
      error: testAlarmScheduled ? null : 'exact_alarm_permission_denied',
    );
  }

  @override
  Future<void> cancelTestAlarm() async {
    testAlarmScheduled = false;
    scheduledTestMode = null;
  }
}
