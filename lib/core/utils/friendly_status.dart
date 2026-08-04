import '../../data/models/app_enums.dart';

abstract final class FriendlyStatus {
  static String alarm(AlarmStatus status) => switch (status) {
    AlarmStatus.registered => '闹钟已经设置',
    AlarmStatus.pending => '正在设置闹钟',
    AlarmStatus.permissionBlocked => '需要开启权限',
    AlarmStatus.failed => '闹钟设置失败',
    AlarmStatus.ringing => '闹钟正在响',
    AlarmStatus.triggered ||
    AlarmStatus.dismissed ||
    AlarmStatus.expired => '闹钟已经响过',
    AlarmStatus.snoozed => '已开启贪睡',
    AlarmStatus.cancelled => '本次闹钟已取消',
  };

  static String sync(AlarmSyncStatus status) => switch (status) {
    AlarmSyncStatus.notRequired => '当天没有工作闹钟',
    AlarmSyncStatus.pending => '正在设置闹钟',
    AlarmSyncStatus.synchronized => '闹钟已经设置',
    AlarmSyncStatus.permissionBlocked => '需要开启权限',
    AlarmSyncStatus.failed => '闹钟设置失败',
  };
}
