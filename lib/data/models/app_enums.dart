enum ShiftType {
  work('work', '工作'),
  rest('rest', '休息'),
  leave('leave', '请假'),
  other('other', '其他');

  const ShiftType(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static ShiftType fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => ShiftType.other,
  );
}

enum ReminderTimeMode {
  fixed('fixed', '固定时间'),
  beforeArrival('before_arrival', '到岗前');

  const ReminderTimeMode(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static ReminderTimeMode fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => ReminderTimeMode.beforeArrival,
  );
}

enum ScheduleStatus {
  normal('normal', '正常排班'),
  rest('rest', '休息'),
  leave('leave', '请假'),
  unconfirmed('unconfirmed', '未确认'),
  cancelled('cancelled', '已取消');

  const ScheduleStatus(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static ScheduleStatus fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => ScheduleStatus.unconfirmed,
  );
}

enum AlarmStatus {
  pending('pending', '待登记'),
  registered('registered', '已登记'),
  ringing('ringing', '正在响铃'),
  dismissed('dismissed', '已停止'),
  snoozed('snoozed', '已贪睡'),
  triggered('triggered', '已触发'),
  cancelled('cancelled', '已取消'),
  expired('expired', '已过期'),
  permissionBlocked('permission_blocked', '权限阻止'),
  failed('failed', '登记失败');

  const AlarmStatus(this.storageValue, this.label);
  final String storageValue;
  final String label;

  bool get isActive =>
      this == AlarmStatus.pending ||
      this == AlarmStatus.registered ||
      this == AlarmStatus.ringing ||
      this == AlarmStatus.snoozed ||
      this == AlarmStatus.permissionBlocked ||
      this == AlarmStatus.failed;

  static AlarmStatus fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => AlarmStatus.failed,
  );
}

enum AlarmEndReason {
  userStopped('user_stopped', '用户停止'),
  timedOut('timed_out', '未响应超时'),
  replaced('replaced', '排班变化'),
  permissionRevoked('permission_revoked', '权限被撤销'),
  testCancelled('test_cancelled', '测试已取消');

  const AlarmEndReason(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static AlarmEndReason? fromStorage(Object? value) =>
      values.where((item) => item.storageValue == value).firstOrNull;
}

enum AlarmSyncStatus {
  notRequired('not_required', '无需同步'),
  pending('pending', '等待同步'),
  synchronized('synchronized', '已同步'),
  permissionBlocked('permission_blocked', '权限不足'),
  failed('failed', '同步失败');

  const AlarmSyncStatus(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static AlarmSyncStatus fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => AlarmSyncStatus.pending,
  );
}

enum ScheduleChangeType {
  create('create', '首次排班'),
  replace('replace', '更换班次'),
  swap('swap', '交换班次'),
  markRest('mark_rest', '标记休息'),
  markLeave('mark_leave', '标记请假'),
  updateReminders('update_reminders', '修改当天提醒'),
  restore('restore', '恢复原排班'),
  delete('delete', '删除排班'),
  copy('copy', '复制排班');

  const ScheduleChangeType(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static ScheduleChangeType fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => ScheduleChangeType.replace,
  );
}

enum AppThemeMode {
  system('system', '跟随系统'),
  light('light', '浅色'),
  dark('dark', '深色');

  const AppThemeMode(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static AppThemeMode fromStorage(Object? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => AppThemeMode.system,
  );
}
