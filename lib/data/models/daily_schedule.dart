import 'app_enums.dart';
import 'model_parsers.dart';
import 'reminder_rule.dart';

class DailySchedule {
  const DailySchedule({
    required this.id,
    required this.date,
    required this.shiftTemplateId,
    this.originalShiftTemplateId,
    this.status = ScheduleStatus.normal,
    this.isTemporaryChanged = false,
    this.reminderOverrides = const [],
    this.isAllRemindersPaused = false,
    this.alarmSyncStatus = AlarmSyncStatus.pending,
    this.lastAlarmSyncAt,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime date;
  final String shiftTemplateId;
  final String? originalShiftTemplateId;
  final ScheduleStatus status;
  final bool isTemporaryChanged;
  final List<ReminderRule> reminderOverrides;
  final bool isAllRemindersPaused;
  final AlarmSyncStatus alarmSyncStatus;
  final DateTime? lastAlarmSyncAt;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get dateKey => dateKeyOf(date);

  static DateTime normalizeDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String dateKeyOf(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  DailySchedule copyWith({
    String? id,
    DateTime? date,
    String? shiftTemplateId,
    String? originalShiftTemplateId,
    bool clearOriginalShiftTemplateId = false,
    ScheduleStatus? status,
    bool? isTemporaryChanged,
    List<ReminderRule>? reminderOverrides,
    bool? isAllRemindersPaused,
    AlarmSyncStatus? alarmSyncStatus,
    DateTime? lastAlarmSyncAt,
    bool clearLastAlarmSyncAt = false,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DailySchedule(
    id: id ?? this.id,
    date: date == null ? this.date : normalizeDate(date),
    shiftTemplateId: shiftTemplateId ?? this.shiftTemplateId,
    originalShiftTemplateId: clearOriginalShiftTemplateId
        ? null
        : originalShiftTemplateId ?? this.originalShiftTemplateId,
    status: status ?? this.status,
    isTemporaryChanged: isTemporaryChanged ?? this.isTemporaryChanged,
    reminderOverrides: reminderOverrides ?? this.reminderOverrides,
    isAllRemindersPaused: isAllRemindersPaused ?? this.isAllRemindersPaused,
    alarmSyncStatus: alarmSyncStatus ?? this.alarmSyncStatus,
    lastAlarmSyncAt: clearLastAlarmSyncAt
        ? null
        : lastAlarmSyncAt ?? this.lastAlarmSyncAt,
    note: note ?? this.note,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'date': normalizeDate(date).millisecondsSinceEpoch,
    'dateKey': dateKey,
    'shiftTemplateId': shiftTemplateId,
    'originalShiftTemplateId': originalShiftTemplateId,
    'status': status.storageValue,
    'isTemporaryChanged': isTemporaryChanged,
    'reminderOverrides': reminderOverrides.map((item) => item.toMap()).toList(),
    'isAllRemindersPaused': isAllRemindersPaused,
    'alarmSyncStatus': alarmSyncStatus.storageValue,
    'lastAlarmSyncAt': lastAlarmSyncAt?.millisecondsSinceEpoch,
    'note': note,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory DailySchedule.fromMap(Map<String, Object?> map) {
    final overrides = map['reminderOverrides'];
    final rawDate = map['dateKey'] is String
        ? DateTime.tryParse(map['dateKey']! as String)
        : null;
    final parsedDate = rawDate ?? parseDateTime(map['date']);
    return DailySchedule(
      id: map['id']?.toString() ?? '',
      date: normalizeDate(parsedDate),
      shiftTemplateId: map['shiftTemplateId']?.toString() ?? '',
      originalShiftTemplateId: parseNullableString(
        map['originalShiftTemplateId'],
      ),
      status: ScheduleStatus.fromStorage(map['status']),
      isTemporaryChanged: parseBool(map['isTemporaryChanged']),
      reminderOverrides: overrides is List
          ? overrides
                .whereType<Map>()
                .map(
                  (item) => ReminderRule.fromMap(item.cast<String, Object?>()),
                )
                .toList()
          : const [],
      isAllRemindersPaused: parseBool(map['isAllRemindersPaused']),
      alarmSyncStatus: AlarmSyncStatus.fromStorage(map['alarmSyncStatus']),
      lastAlarmSyncAt: map['lastAlarmSyncAt'] == null
          ? null
          : parseDateTime(map['lastAlarmSyncAt']),
      note: map['note']?.toString() ?? '',
      createdAt: parseDateTime(map['createdAt']),
      updatedAt: parseDateTime(map['updatedAt']),
    );
  }
}
