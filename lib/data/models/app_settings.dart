import 'app_enums.dart';
import 'model_parsers.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.interfaceMode = AppInterfaceMode.standard,
    this.reduceMotion = false,
    this.highContrastEnabled = false,
    this.readAloudEnabled = false,
    this.hapticFeedbackEnabled = true,
    this.weekStartDay = 1,
    this.scheduleViewMode = ScheduleViewMode.month,
    this.use24HourFormat = true,
    this.alarmGenerationDays = 14,
    this.defaultSnoozeMinutes = 10,
    this.defaultMaxSnoozeCount = 3,
    this.defaultVibrationEnabled = true,
    this.defaultFadeInEnabled = true,
    this.defaultSoundId,
    this.onboardingCompleted = false,
  });

  final AppThemeMode themeMode;
  final AppInterfaceMode interfaceMode;
  final bool reduceMotion;
  final bool highContrastEnabled;
  final bool readAloudEnabled;
  final bool hapticFeedbackEnabled;
  final int weekStartDay;
  final ScheduleViewMode scheduleViewMode;
  final bool use24HourFormat;
  final int alarmGenerationDays;
  final int defaultSnoozeMinutes;
  final int defaultMaxSnoozeCount;
  final bool defaultVibrationEnabled;
  final bool defaultFadeInEnabled;
  final String? defaultSoundId;
  final bool onboardingCompleted;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppInterfaceMode? interfaceMode,
    bool? reduceMotion,
    bool? highContrastEnabled,
    bool? readAloudEnabled,
    bool? hapticFeedbackEnabled,
    int? weekStartDay,
    ScheduleViewMode? scheduleViewMode,
    bool? use24HourFormat,
    int? alarmGenerationDays,
    int? defaultSnoozeMinutes,
    int? defaultMaxSnoozeCount,
    bool? defaultVibrationEnabled,
    bool? defaultFadeInEnabled,
    String? defaultSoundId,
    bool clearDefaultSoundId = false,
    bool? onboardingCompleted,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    interfaceMode: interfaceMode ?? this.interfaceMode,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    highContrastEnabled: highContrastEnabled ?? this.highContrastEnabled,
    readAloudEnabled: readAloudEnabled ?? this.readAloudEnabled,
    hapticFeedbackEnabled: hapticFeedbackEnabled ?? this.hapticFeedbackEnabled,
    weekStartDay: weekStartDay ?? this.weekStartDay,
    scheduleViewMode: scheduleViewMode ?? this.scheduleViewMode,
    use24HourFormat: use24HourFormat ?? this.use24HourFormat,
    alarmGenerationDays: alarmGenerationDays ?? this.alarmGenerationDays,
    defaultSnoozeMinutes: defaultSnoozeMinutes ?? this.defaultSnoozeMinutes,
    defaultMaxSnoozeCount: defaultMaxSnoozeCount ?? this.defaultMaxSnoozeCount,
    defaultVibrationEnabled:
        defaultVibrationEnabled ?? this.defaultVibrationEnabled,
    defaultFadeInEnabled: defaultFadeInEnabled ?? this.defaultFadeInEnabled,
    defaultSoundId: clearDefaultSoundId
        ? null
        : defaultSoundId ?? this.defaultSoundId,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
  );

  Map<String, Object?> toMap() => {
    'themeMode': themeMode.storageValue,
    'interfaceMode': interfaceMode.storageValue,
    'reduceMotion': reduceMotion,
    'highContrastEnabled': highContrastEnabled,
    'readAloudEnabled': readAloudEnabled,
    'hapticFeedbackEnabled': hapticFeedbackEnabled,
    'weekStartDay': weekStartDay,
    'scheduleViewMode': scheduleViewMode.storageValue,
    'use24HourFormat': use24HourFormat,
    'alarmGenerationDays': alarmGenerationDays,
    'defaultSnoozeMinutes': defaultSnoozeMinutes,
    'defaultMaxSnoozeCount': defaultMaxSnoozeCount,
    'defaultVibrationEnabled': defaultVibrationEnabled,
    'defaultFadeInEnabled': defaultFadeInEnabled,
    'defaultSoundId': defaultSoundId,
    'onboardingCompleted': onboardingCompleted,
  };

  factory AppSettings.fromMap(Map<String, Object?> map) => AppSettings(
    themeMode: AppThemeMode.fromStorage(map['themeMode']),
    interfaceMode: AppInterfaceMode.fromStorage(map['interfaceMode']),
    reduceMotion: parseBool(map['reduceMotion']),
    highContrastEnabled: parseBool(map['highContrastEnabled']),
    readAloudEnabled: parseBool(map['readAloudEnabled']),
    hapticFeedbackEnabled: parseBool(
      map['hapticFeedbackEnabled'],
      fallback: true,
    ),
    weekStartDay: parseInt(map['weekStartDay'], fallback: 1).clamp(1, 7),
    scheduleViewMode: ScheduleViewMode.fromStorage(map['scheduleViewMode']),
    use24HourFormat: parseBool(map['use24HourFormat'], fallback: true),
    alarmGenerationDays: parseInt(
      map['alarmGenerationDays'],
      fallback: 14,
    ).clamp(1, 90),
    defaultSnoozeMinutes: parseInt(
      map['defaultSnoozeMinutes'],
      fallback: 10,
    ).clamp(1, 60),
    defaultMaxSnoozeCount: parseInt(
      map['defaultMaxSnoozeCount'],
      fallback: 3,
    ).clamp(0, 10),
    defaultVibrationEnabled: parseBool(
      map['defaultVibrationEnabled'],
      fallback: true,
    ),
    defaultFadeInEnabled: parseBool(
      map['defaultFadeInEnabled'],
      fallback: true,
    ),
    defaultSoundId: parseNullableString(map['defaultSoundId']),
    onboardingCompleted: map.containsKey('interfaceMode')
        ? parseBool(map['onboardingCompleted'])
        : true,
  );
}
