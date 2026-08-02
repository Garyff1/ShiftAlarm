import 'app_enums.dart';
import 'clock_time.dart';
import 'model_parsers.dart';

class ReminderRule {
  const ReminderRule({
    required this.id,
    required this.name,
    required this.timeMode,
    this.fixedTime,
    this.minutesBeforeArrival,
    this.soundId,
    this.isVibrationEnabled = true,
    this.isSnoozeEnabled = true,
    this.snoozeMinutes = 10,
    this.maxSnoozeCount = 3,
    this.isVolumeFadeInEnabled = true,
    this.isFullScreenEnabled = false,
    this.isEnabled = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final ReminderTimeMode timeMode;
  final ClockTime? fixedTime;
  final int? minutesBeforeArrival;
  final String? soundId;
  final bool isVibrationEnabled;
  final bool isSnoozeEnabled;
  final int snoozeMinutes;
  final int maxSnoozeCount;
  final bool isVolumeFadeInEnabled;
  final bool isFullScreenEnabled;
  final bool isEnabled;
  final int sortOrder;

  ReminderRule copyWith({
    String? id,
    String? name,
    ReminderTimeMode? timeMode,
    ClockTime? fixedTime,
    bool clearFixedTime = false,
    int? minutesBeforeArrival,
    bool clearMinutesBeforeArrival = false,
    String? soundId,
    bool clearSoundId = false,
    bool? isVibrationEnabled,
    bool? isSnoozeEnabled,
    int? snoozeMinutes,
    int? maxSnoozeCount,
    bool? isVolumeFadeInEnabled,
    bool? isFullScreenEnabled,
    bool? isEnabled,
    int? sortOrder,
  }) => ReminderRule(
    id: id ?? this.id,
    name: name ?? this.name,
    timeMode: timeMode ?? this.timeMode,
    fixedTime: clearFixedTime ? null : fixedTime ?? this.fixedTime,
    minutesBeforeArrival: clearMinutesBeforeArrival
        ? null
        : minutesBeforeArrival ?? this.minutesBeforeArrival,
    soundId: clearSoundId ? null : soundId ?? this.soundId,
    isVibrationEnabled: isVibrationEnabled ?? this.isVibrationEnabled,
    isSnoozeEnabled: isSnoozeEnabled ?? this.isSnoozeEnabled,
    snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    maxSnoozeCount: maxSnoozeCount ?? this.maxSnoozeCount,
    isVolumeFadeInEnabled: isVolumeFadeInEnabled ?? this.isVolumeFadeInEnabled,
    isFullScreenEnabled: isFullScreenEnabled ?? this.isFullScreenEnabled,
    isEnabled: isEnabled ?? this.isEnabled,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'timeMode': timeMode.storageValue,
    'fixedTime': fixedTime?.toMap(),
    'minutesBeforeArrival': minutesBeforeArrival,
    'soundId': soundId,
    'isVibrationEnabled': isVibrationEnabled,
    'isSnoozeEnabled': isSnoozeEnabled,
    'snoozeMinutes': snoozeMinutes,
    'maxSnoozeCount': maxSnoozeCount,
    'isVolumeFadeInEnabled': isVolumeFadeInEnabled,
    'isFullScreenEnabled': isFullScreenEnabled,
    'isEnabled': isEnabled,
    'sortOrder': sortOrder,
  };

  factory ReminderRule.fromMap(Map<String, Object?> map) => ReminderRule(
    id: map['id']?.toString() ?? '',
    name: map['name']?.toString() ?? '',
    timeMode: ReminderTimeMode.fromStorage(map['timeMode']),
    fixedTime: ClockTime.fromMap(map['fixedTime']),
    minutesBeforeArrival: map['minutesBeforeArrival'] == null
        ? null
        : parseInt(map['minutesBeforeArrival']),
    soundId: parseNullableString(map['soundId']),
    isVibrationEnabled: parseBool(map['isVibrationEnabled'], fallback: true),
    isSnoozeEnabled: parseBool(map['isSnoozeEnabled'], fallback: true),
    snoozeMinutes: parseInt(map['snoozeMinutes'], fallback: 10),
    maxSnoozeCount: parseInt(map['maxSnoozeCount'], fallback: 3),
    isVolumeFadeInEnabled: parseBool(
      map['isVolumeFadeInEnabled'],
      fallback: true,
    ),
    isFullScreenEnabled: parseBool(map['isFullScreenEnabled']),
    isEnabled: parseBool(map['isEnabled'], fallback: true),
    sortOrder: parseInt(map['sortOrder']),
  );
}
