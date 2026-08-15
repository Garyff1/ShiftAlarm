import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../data/models/alarm_lifecycle_event.dart';
import '../../data/models/alarm_record.dart';
import 'alarm_sync_coordinator.dart';
import 'native_alarm_scheduler.dart';

class DiagnosticReport {
  const DiagnosticReport({required this.json, required this.summary});
  final String json;
  final String summary;
}

class DiagnosticReportService {
  const DiagnosticReportService();

  static const _safeDetailKeys = {
    'scheduleApi',
    'exactAlarmPermission',
    'timezone',
    'timezoneOffsetMinutes',
    'systemTime',
    'forceReschedule',
    'audioFocus',
    'soundType',
    'fallback',
    'reason',
    'errorType',
    'action',
    'restoredCount',
    'registered',
    'cancelled',
    'failed',
    'snoozeCount',
    'inferred',
    'startReason',
    'startType',
    'startComponent',
  };

  DiagnosticReport build({
    required NativeDeviceInfo device,
    required NativeAppStartupInfo startup,
    required AlarmPermissionState permissions,
    required Iterable<AlarmRecord> alarms,
    required Iterable<AlarmLifecycleEvent> lifecycleEvents,
    AlarmSyncResult? lastSync,
    DateTime? lastSyncAt,
    DateTime? generatedAt,
  }) {
    final clock = generatedAt ?? DateTime.now();
    final alarmList = alarms.where((item) => !item.isTest).toList();
    final events = lifecycleEvents.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final statusCounts = <String, int>{};
    for (final alarm in alarmList) {
      statusCounts.update(
        alarm.status.storageValue,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final failures = events
        .where((item) => item.failureCategory != null)
        .take(100)
        .toList();
    final report = <String, Object?>{
      'schema': 'shiftalarm-diagnostic-v1',
      'generatedAt': clock.toIso8601String(),
      'app': {
        'name': AppConstants.appName,
        'version': AppConstants.version,
        'package': 'com.shiftalarm.app',
      },
      'device': {
        'manufacturer': device.manufacturer,
        'model': device.model,
        'androidVersion': device.androidVersion,
        'api': device.sdkInt,
        'timezone': device.timezone,
      },
      'permissions': {
        'exactAlarm': permissions.exactAlarm,
        'notifications': permissions.notifications,
        'fullScreenIntent': permissions.fullScreenIntent,
        'ignoringBatteryOptimizations':
            permissions.ignoringBatteryOptimizations,
        'alarmVolume': permissions.alarmVolume,
        'maxAlarmVolume': permissions.maxAlarmVolume,
      },
      'startup': {
        'forceStopDetectionSupported': startup.supported,
        'wasForceStopped': startup.wasForceStopped,
        'reason': startup.reason,
        'startType': startup.startType,
        'startComponent': startup.startComponent,
      },
      'alarmSync': {
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'registered': lastSync?.registered,
        'cancelled': lastSync?.cancelled,
        'unchanged': lastSync?.unchanged,
        'failed': lastSync?.failed,
        'permissionBlocked': lastSync?.permissionBlocked,
      },
      'alarmRecords': {
        'submittedFutureCount': alarmList
            .where(
              (item) =>
                  item.triggerAt.isAfter(clock) &&
                  (item.status.isActive ||
                      item.status.storageValue == 'registered'),
            )
            .length,
        'statusCounts': statusCounts,
      },
      'recentFailures': failures
          .map(
            (item) => {
              'stage': item.stage.storageValue,
              'category': item.failureCategory?.storageValue,
              'occurredAt': item.occurredAt.toIso8601String(),
              'nativeAlarmId': item.nativeAlarmId,
            },
          )
          .toList(),
      'lifecycleEvents': events.take(500).map(_safeEvent).toList(),
      'privacy': {
        'containsUserName': false,
        'containsCompanyName': false,
        'containsFullSchedule': false,
        'containsAudioFile': false,
        'containsInternalFilePath': false,
        'containsTokenOrKeystore': false,
      },
    };
    const encoder = JsonEncoder.withIndent('  ');
    final summary = StringBuffer()
      ..writeln('ShiftAlarm 脱敏诊断报告')
      ..writeln('生成时间：${clock.toIso8601String()}')
      ..writeln('App：${AppConstants.version}')
      ..writeln(
        '设备：${device.manufacturer} ${device.model} / Android ${device.androidVersion} / API ${device.sdkInt}',
      )
      ..writeln('时区：${device.timezone}')
      ..writeln(
        '权限：精确闹钟 ${_yesNo(permissions.exactAlarm)}，通知 ${_yesNo(permissions.notifications)}，锁屏全屏 ${_yesNo(permissions.fullScreenIntent)}',
      )
      ..writeln(
        '电池优化：${permissions.ignoringBatteryOptimizations ? '不受限制' : '可能受限'}',
      )
      ..writeln('检测到强行停止：${_yesNo(startup.wasForceStopped)}')
      ..writeln(
        '未来已提交记录：${alarmList.where((item) => item.triggerAt.isAfter(clock) && item.status.isActive).length}',
      )
      ..writeln('最近异常数：${failures.length}')
      ..writeln('生命周期事件数（导出上限500）：${events.take(500).length}')
      ..writeln()
      ..writeln('本报告不包含姓名、公司、完整班表、私人音频、PIN、密钥、Token 或内部完整路径。');
    return DiagnosticReport(json: encoder.convert(report), summary: '$summary');
  }

  Map<String, Object?> _safeEvent(AlarmLifecycleEvent event) => {
    'alarmId': event.alarmId == 'system' ? 'system' : _opaque(event.alarmId),
    'nativeAlarmId': event.nativeAlarmId,
    'stage': event.stage.storageValue,
    'occurredAt': event.occurredAt.toIso8601String(),
    'plannedTriggerAt': event.plannedTriggerAt?.toIso8601String(),
    'failureCategory': event.failureCategory?.storageValue,
    'source': event.source,
    'isTest': event.isTest,
    'details': {
      for (final entry in event.details.entries)
        if (_safeDetailKeys.contains(entry.key)) entry.key: entry.value,
    },
  };

  String _opaque(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 'alarm_${hash.toRadixString(16)}';
  }

  static String _yesNo(bool value) => value ? '是' : '否';
}
