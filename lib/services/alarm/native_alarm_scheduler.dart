import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/alarm_record.dart';
import '../../data/models/alarm_sound.dart';
import '../../data/models/sound_ids.dart';

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
  const NativeScheduleResult({required this.success, this.error});
  final bool success;
  final String? error;
}

abstract interface class NativeAlarmScheduler {
  Future<AlarmPermissionState> getPermissionState();
  Future<NativeScheduleResult> schedule(AlarmRecord record);
  Future<void> cancel(int nativeAlarmId);
  Future<void> replaceDirectBootSnapshots(Iterable<AlarmRecord> records);
  Future<List<Map<String, Object?>>> consumeNativeEvents();
  Future<void> openExactAlarmSettings();
  Future<bool> requestNotificationPermission();
  Future<void> openNotificationSettings();
  Future<void> openFullScreenIntentSettings();
  Future<void> openAlarmVolumeSettings();
  Future<void> openBatterySettings();
  Future<NativeScheduleResult> scheduleTestAlarm({
    required int delaySeconds,
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
    AlarmSound? sound,
    bool fadeIn = true,
  }) async {
    final value = await _channel
        .invokeMapMethod<Object?, Object?>('scheduleTestAlarm', {
          'delaySeconds': delaySeconds,
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
  List<AlarmRecord> snapshots = const [];
  bool failScheduling = false;
  bool testAlarmScheduled = false;

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
    AlarmSound? sound,
    bool fadeIn = true,
  }) async {
    testAlarmScheduled = permissions.exactAlarm;
    return NativeScheduleResult(
      success: testAlarmScheduled,
      error: testAlarmScheduled ? null : 'exact_alarm_permission_denied',
    );
  }

  @override
  Future<void> cancelTestAlarm() async => testAlarmScheduled = false;
}
