abstract final class AppConstants {
  static const appName = 'ShiftAlarm';
  static const appSubtitle = '排班闹钟';
  static const version = '1.0.0+6';
  static const databaseName = 'shift_alarm.db';
  static const databaseVersion = 5;
  static const lifecycleRetentionDays = 30;
  static const lifecycleMaxEvents = 1000;
  static const alarmChannel = 'com.shiftalarm.app/alarm';
  static const maxAlarmRingingMinutes = 15;
  static const maxSoundFileBytes = 50 * 1024 * 1024;
  static const soundFadeInSeconds = 30;
}
