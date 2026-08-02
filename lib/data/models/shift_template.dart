import 'app_enums.dart';
import 'clock_time.dart';
import 'model_parsers.dart';
import 'reminder_rule.dart';

class ShiftTemplate {
  const ShiftTemplate({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.aliases = const [],
    required this.colorValue,
    this.arrivalTime,
    this.arrivalDayOffset = 0,
    this.reminderRules = const [],
    this.defaultSoundId,
    this.note = '',
    this.isEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String code;
  final String name;
  final ShiftType type;
  final List<String> aliases;
  final int colorValue;
  final ClockTime? arrivalTime;
  final int arrivalDayOffset;
  final List<ReminderRule> reminderRules;
  final String? defaultSoundId;
  final String note;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  ShiftTemplate copyWith({
    String? id,
    String? code,
    String? name,
    ShiftType? type,
    List<String>? aliases,
    int? colorValue,
    ClockTime? arrivalTime,
    bool clearArrivalTime = false,
    int? arrivalDayOffset,
    List<ReminderRule>? reminderRules,
    String? defaultSoundId,
    bool clearDefaultSoundId = false,
    String? note,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ShiftTemplate(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    type: type ?? this.type,
    aliases: aliases ?? this.aliases,
    colorValue: colorValue ?? this.colorValue,
    arrivalTime: clearArrivalTime ? null : arrivalTime ?? this.arrivalTime,
    arrivalDayOffset: arrivalDayOffset ?? this.arrivalDayOffset,
    reminderRules: reminderRules ?? this.reminderRules,
    defaultSoundId: clearDefaultSoundId
        ? null
        : defaultSoundId ?? this.defaultSoundId,
    note: note ?? this.note,
    isEnabled: isEnabled ?? this.isEnabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'type': type.storageValue,
    'aliases': aliases,
    'colorValue': colorValue,
    'arrivalTime': arrivalTime?.toMap(),
    'arrivalDayOffset': arrivalDayOffset,
    'reminderRules': reminderRules.map((rule) => rule.toMap()).toList(),
    'defaultSoundId': defaultSoundId,
    'note': note,
    'isEnabled': isEnabled,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory ShiftTemplate.fromMap(Map<String, Object?> map) {
    final rawAliases = map['aliases'];
    final rawRules = map['reminderRules'];
    return ShiftTemplate(
      id: map['id']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      type: ShiftType.fromStorage(map['type']),
      aliases: rawAliases is List
          ? rawAliases
                .map((item) => item.toString())
                .where((item) => item.isNotEmpty)
                .toList()
          : const [],
      colorValue: parseInt(map['colorValue'], fallback: 0xFF4F6BED),
      arrivalTime: ClockTime.fromMap(map['arrivalTime']),
      arrivalDayOffset: parseInt(map['arrivalDayOffset']).clamp(0, 1),
      reminderRules: rawRules is List
          ? rawRules
                .whereType<Map>()
                .map(
                  (item) => ReminderRule.fromMap(item.cast<String, Object?>()),
                )
                .toList()
          : const [],
      defaultSoundId: parseNullableString(map['defaultSoundId']),
      note: map['note']?.toString() ?? '',
      isEnabled: parseBool(map['isEnabled'], fallback: true),
      createdAt: parseDateTime(map['createdAt']),
      updatedAt: parseDateTime(map['updatedAt']),
    );
  }
}
