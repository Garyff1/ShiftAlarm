import 'app_enums.dart';
import 'model_parsers.dart';

class AlarmRecord {
  const AlarmRecord({
    required this.id,
    required this.scheduleId,
    required this.scheduleDate,
    required this.shiftTemplateId,
    required this.reminderRuleId,
    required this.reminderName,
    required this.shiftCode,
    required this.shiftName,
    required this.triggerAt,
    this.arrivalAt,
    this.nativeAlarmId,
    this.status = AlarmStatus.pending,
    this.soundId,
    this.soundPath,
    this.soundChecksum,
    this.isVolumeFadeInEnabled = true,
    this.isVibrationEnabled = true,
    this.isSnoozeEnabled = true,
    this.snoozeMinutes = 10,
    this.maxSnoozeCount = 3,
    this.snoozeCount = 0,
    this.parentAlarmId,
    this.registeredAt,
    this.firedAt,
    this.dismissedAt,
    this.cancelledAt,
    this.failureReason,
    this.endReason,
    this.isTemporarySchedule = false,
    this.isCoreAlarm = false,
    this.isTest = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String scheduleId;
  final DateTime scheduleDate;
  final String shiftTemplateId;
  final String reminderRuleId;
  final String reminderName;
  final String shiftCode;
  final String shiftName;
  final DateTime triggerAt;
  final DateTime? arrivalAt;
  final int? nativeAlarmId;
  final AlarmStatus status;
  final String? soundId;
  final String? soundPath;
  final String? soundChecksum;
  final bool isVolumeFadeInEnabled;
  final bool isVibrationEnabled;
  final bool isSnoozeEnabled;
  final int snoozeMinutes;
  final int maxSnoozeCount;
  final int snoozeCount;
  final String? parentAlarmId;
  final DateTime? registeredAt;
  final DateTime? firedAt;
  final DateTime? dismissedAt;
  final DateTime? cancelledAt;
  final String? failureReason;
  final AlarmEndReason? endReason;
  final bool isTemporarySchedule;
  final bool isCoreAlarm;
  final bool isTest;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get canSnooze => isSnoozeEnabled && snoozeCount < maxSnoozeCount;

  String get stableKey => '$scheduleId:$reminderRuleId';

  AlarmRecord copyWith({
    DateTime? triggerAt,
    DateTime? arrivalAt,
    bool clearArrivalAt = false,
    int? nativeAlarmId,
    AlarmStatus? status,
    String? soundId,
    String? soundPath,
    String? soundChecksum,
    bool? isVolumeFadeInEnabled,
    int? snoozeCount,
    String? parentAlarmId,
    DateTime? registeredAt,
    DateTime? firedAt,
    DateTime? dismissedAt,
    DateTime? cancelledAt,
    String? failureReason,
    bool clearFailureReason = false,
    AlarmEndReason? endReason,
    DateTime? updatedAt,
  }) => AlarmRecord(
    id: id,
    scheduleId: scheduleId,
    scheduleDate: scheduleDate,
    shiftTemplateId: shiftTemplateId,
    reminderRuleId: reminderRuleId,
    reminderName: reminderName,
    shiftCode: shiftCode,
    shiftName: shiftName,
    triggerAt: triggerAt ?? this.triggerAt,
    arrivalAt: clearArrivalAt ? null : arrivalAt ?? this.arrivalAt,
    nativeAlarmId: nativeAlarmId ?? this.nativeAlarmId,
    status: status ?? this.status,
    soundId: soundId ?? this.soundId,
    soundPath: soundPath ?? this.soundPath,
    soundChecksum: soundChecksum ?? this.soundChecksum,
    isVolumeFadeInEnabled: isVolumeFadeInEnabled ?? this.isVolumeFadeInEnabled,
    isVibrationEnabled: isVibrationEnabled,
    isSnoozeEnabled: isSnoozeEnabled,
    snoozeMinutes: snoozeMinutes,
    maxSnoozeCount: maxSnoozeCount,
    snoozeCount: snoozeCount ?? this.snoozeCount,
    parentAlarmId: parentAlarmId ?? this.parentAlarmId,
    registeredAt: registeredAt ?? this.registeredAt,
    firedAt: firedAt ?? this.firedAt,
    dismissedAt: dismissedAt ?? this.dismissedAt,
    cancelledAt: cancelledAt ?? this.cancelledAt,
    failureReason: clearFailureReason
        ? null
        : failureReason ?? this.failureReason,
    endReason: endReason ?? this.endReason,
    isTemporarySchedule: isTemporarySchedule,
    isCoreAlarm: isCoreAlarm,
    isTest: isTest,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'scheduleId': scheduleId,
    'scheduleDate': scheduleDate.millisecondsSinceEpoch,
    'shiftTemplateId': shiftTemplateId,
    'reminderRuleId': reminderRuleId,
    'reminderName': reminderName,
    'shiftCode': shiftCode,
    'shiftName': shiftName,
    'triggerAt': triggerAt.millisecondsSinceEpoch,
    'arrivalAt': arrivalAt?.millisecondsSinceEpoch,
    'nativeAlarmId': nativeAlarmId,
    'status': status.storageValue,
    'soundId': soundId,
    'soundPath': soundPath,
    'soundChecksum': soundChecksum,
    'isVolumeFadeInEnabled': isVolumeFadeInEnabled,
    'isVibrationEnabled': isVibrationEnabled,
    'isSnoozeEnabled': isSnoozeEnabled,
    'snoozeMinutes': snoozeMinutes,
    'maxSnoozeCount': maxSnoozeCount,
    'snoozeCount': snoozeCount,
    'parentAlarmId': parentAlarmId,
    'registeredAt': registeredAt?.millisecondsSinceEpoch,
    'firedAt': firedAt?.millisecondsSinceEpoch,
    'dismissedAt': dismissedAt?.millisecondsSinceEpoch,
    'cancelledAt': cancelledAt?.millisecondsSinceEpoch,
    'failureReason': failureReason,
    'endReason': endReason?.storageValue,
    'isTemporarySchedule': isTemporarySchedule,
    'isCoreAlarm': isCoreAlarm,
    'isTest': isTest,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory AlarmRecord.fromMap(Map<String, Object?> map) => AlarmRecord(
    id: map['id']?.toString() ?? '',
    scheduleId: map['scheduleId']?.toString() ?? '',
    scheduleDate: map['scheduleDate'] == null
        ? parseDateTime(map['triggerAt'])
        : parseDateTime(map['scheduleDate']),
    shiftTemplateId: map['shiftTemplateId']?.toString() ?? '',
    reminderRuleId: map['reminderRuleId']?.toString() ?? '',
    reminderName: map['reminderName']?.toString() ?? '排班提醒',
    shiftCode: map['shiftCode']?.toString() ?? '',
    shiftName: map['shiftName']?.toString() ?? '',
    triggerAt: parseDateTime(map['triggerAt']),
    arrivalAt: map['arrivalAt'] == null
        ? null
        : parseDateTime(map['arrivalAt']),
    nativeAlarmId: map['nativeAlarmId'] == null
        ? null
        : parseInt(map['nativeAlarmId']),
    status: AlarmStatus.fromStorage(map['status']),
    soundId: parseNullableString(map['soundId']),
    soundPath: parseNullableString(map['soundPath']),
    soundChecksum: parseNullableString(map['soundChecksum']),
    isVolumeFadeInEnabled: parseBool(
      map['isVolumeFadeInEnabled'],
      fallback: true,
    ),
    isVibrationEnabled: parseBool(map['isVibrationEnabled'], fallback: true),
    isSnoozeEnabled: parseBool(map['isSnoozeEnabled'], fallback: true),
    snoozeMinutes: parseInt(map['snoozeMinutes'], fallback: 10),
    maxSnoozeCount: parseInt(map['maxSnoozeCount'], fallback: 3),
    snoozeCount: parseInt(map['snoozeCount']),
    parentAlarmId: parseNullableString(map['parentAlarmId']),
    registeredAt: map['registeredAt'] == null
        ? null
        : parseDateTime(map['registeredAt']),
    firedAt: map['firedAt'] == null ? null : parseDateTime(map['firedAt']),
    dismissedAt: map['dismissedAt'] == null
        ? null
        : parseDateTime(map['dismissedAt']),
    cancelledAt: map['cancelledAt'] == null
        ? null
        : parseDateTime(map['cancelledAt']),
    failureReason: parseNullableString(map['failureReason']),
    endReason: AlarmEndReason.fromStorage(map['endReason']),
    isTemporarySchedule: parseBool(map['isTemporarySchedule']),
    isCoreAlarm: parseBool(map['isCoreAlarm']),
    isTest: parseBool(map['isTest']),
    createdAt: parseDateTime(map['createdAt']),
    updatedAt: parseDateTime(map['updatedAt']),
  );
}
