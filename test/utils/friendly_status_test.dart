import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/core/utils/friendly_status.dart';
import 'package:shift_alarm/data/models/app_enums.dart';

void main() {
  final alarmCases = <AlarmStatus, String>{
    AlarmStatus.pending: '正在设置闹钟',
    AlarmStatus.registered: '闹钟已经设置',
    AlarmStatus.ringing: '闹钟正在响',
    AlarmStatus.dismissed: '闹钟已经响过',
    AlarmStatus.snoozed: '已开启贪睡',
    AlarmStatus.triggered: '闹钟已经响过',
    AlarmStatus.cancelled: '本次闹钟已取消',
    AlarmStatus.expired: '闹钟已经响过',
    AlarmStatus.permissionBlocked: '需要开启权限',
    AlarmStatus.failed: '闹钟设置失败',
  };

  for (final entry in alarmCases.entries) {
    test('${entry.key.name} 显示为普通中文', () {
      expect(FriendlyStatus.alarm(entry.key), entry.value);
      expect(FriendlyStatus.alarm(entry.key), isNot(contains('_')));
    });
  }

  final syncCases = <AlarmSyncStatus, String>{
    AlarmSyncStatus.notRequired: '当天没有工作闹钟',
    AlarmSyncStatus.pending: '正在设置闹钟',
    AlarmSyncStatus.synchronized: '闹钟已经设置',
    AlarmSyncStatus.permissionBlocked: '需要开启权限',
    AlarmSyncStatus.failed: '闹钟设置失败',
  };

  for (final entry in syncCases.entries) {
    test('${entry.key.name} 同步状态显示为普通中文', () {
      expect(FriendlyStatus.sync(entry.key), entry.value);
      expect(FriendlyStatus.sync(entry.key), isNot(contains('_')));
    });
  }
}
