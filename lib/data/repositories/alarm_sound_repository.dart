import 'dart:convert';
import '../models/alarm_record.dart';
import '../models/alarm_sound.dart';
import '../models/shift_template.dart';
import 'crud_repository.dart';
import 'stored_repository.dart';

abstract interface class AlarmSoundRepository
    implements CrudRepository<AlarmSound> {
  Future<AlarmSound?> findByChecksum(String checksum);
  Future<SoundReferenceSummary> getReferenceSummary(String soundId);
  Future<SoundReferenceSummary> replaceReferencesAndDelete(
    String soundId,
    String replacementId, {
    bool transferDefault = false,
  });
}

class SoundReferenceSummary {
  const SoundReferenceSummary({
    this.shiftCount = 0,
    this.reminderCount = 0,
    this.futureAlarmCount = 0,
    this.isAppDefault = false,
    this.shiftNames = const [],
    this.reminderNames = const [],
    this.futureAlarmLabels = const [],
  });

  final int shiftCount;
  final int reminderCount;
  final int futureAlarmCount;
  final bool isAppDefault;
  final List<String> shiftNames;
  final List<String> reminderNames;
  final List<String> futureAlarmLabels;
  int get total => shiftCount + reminderCount + futureAlarmCount;
  bool get isReferenced => total > 0 || isAppDefault;

  SoundReferenceSummary copyWith({bool? isAppDefault}) => SoundReferenceSummary(
    shiftCount: shiftCount,
    reminderCount: reminderCount,
    futureAlarmCount: futureAlarmCount,
    isAppDefault: isAppDefault ?? this.isAppDefault,
    shiftNames: shiftNames,
    reminderNames: reminderNames,
    futureAlarmLabels: futureAlarmLabels,
  );
}

class LocalAlarmSoundRepository extends StoredRepository<AlarmSound>
    implements AlarmSoundRepository {
  LocalAlarmSoundRepository(super.store);
  @override
  String get collection => 'alarm_sounds';
  @override
  String idOf(AlarmSound item) => item.id;
  @override
  Map<String, Object?> encode(AlarmSound item) => item.toMap();
  @override
  AlarmSound decode(Map<String, Object?> map) => AlarmSound.fromMap(map);

  @override
  Future<AlarmSound?> findByChecksum(String checksum) async {
    if (checksum.isEmpty) return null;
    final payload = await store.readByUniqueKey(collection, checksum);
    if (payload != null) {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic>
          ? AlarmSound.fromMap(decoded)
          : null;
    }
    for (final sound in await getAll()) {
      if (sound.checksum == checksum) return sound;
    }
    return null;
  }

  @override
  Future<SoundReferenceSummary> getReferenceSummary(String soundId) async {
    final shifts = await store.readAll('shift_templates');
    var shiftCount = 0;
    var reminderCount = 0;
    final shiftNames = <String>[];
    final reminderNames = <String>[];
    for (final payload in shifts) {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) continue;
      final shift = ShiftTemplate.fromMap(decoded);
      if (shift.defaultSoundId == soundId) {
        shiftCount++;
        shiftNames.add('${shift.code} ${shift.name}');
      }
      for (final rule in shift.reminderRules.where(
        (rule) => rule.soundId == soundId,
      )) {
        reminderCount++;
        reminderNames.add('${shift.code} · ${rule.name}');
      }
    }
    final now = DateTime.now();
    final alarms = await store.readAll('alarm_records');
    var futureAlarmCount = 0;
    final futureAlarmLabels = <String>[];
    for (final payload in alarms) {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) continue;
      final alarm = AlarmRecord.fromMap(decoded);
      if (alarm.soundId == soundId && alarm.triggerAt.isAfter(now)) {
        futureAlarmCount++;
        futureAlarmLabels.add(
          '${alarm.shiftCode} · ${alarm.reminderName} · ${alarm.triggerAt.month}/${alarm.triggerAt.day} ${alarm.triggerAt.hour.toString().padLeft(2, '0')}:${alarm.triggerAt.minute.toString().padLeft(2, '0')}',
        );
      }
    }
    return SoundReferenceSummary(
      shiftCount: shiftCount,
      reminderCount: reminderCount,
      futureAlarmCount: futureAlarmCount,
      shiftNames: shiftNames,
      reminderNames: reminderNames,
      futureAlarmLabels: futureAlarmLabels,
    );
  }

  @override
  Future<SoundReferenceSummary> replaceReferencesAndDelete(
    String soundId,
    String replacementId, {
    bool transferDefault = false,
  }) => store.runTransaction({'shift_templates', 'alarm_records', collection}, (
    transaction,
  ) async {
    var shiftCount = 0;
    var reminderCount = 0;
    var futureAlarmCount = 0;
    for (final payload in await transaction.readAll('shift_templates')) {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) continue;
      final shift = ShiftTemplate.fromMap(decoded);
      final shiftMatched = shift.defaultSoundId == soundId;
      var shiftReminderMatches = 0;
      final rules = shift.reminderRules.map((rule) {
        if (rule.soundId != soundId) return rule;
        reminderCount++;
        shiftReminderMatches++;
        return rule.copyWith(soundId: replacementId);
      }).toList();
      if (!shiftMatched && shiftReminderMatches == 0) continue;
      if (shiftMatched) shiftCount++;
      final updated = shift.copyWith(
        defaultSoundId: shiftMatched ? replacementId : shift.defaultSoundId,
        reminderRules: rules,
        updatedAt: DateTime.now(),
      );
      await transaction.write(
        'shift_templates',
        updated.id,
        jsonEncode(updated.toMap()),
      );
    }
    final now = DateTime.now();
    for (final payload in await transaction.readAll('alarm_records')) {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) continue;
      final alarm = AlarmRecord.fromMap(decoded);
      if (alarm.soundId != soundId) continue;
      if (alarm.triggerAt.isAfter(now)) futureAlarmCount++;
      final map = Map<String, dynamic>.of(decoded)
        ..['soundId'] = replacementId
        ..['soundPath'] = null
        ..['soundChecksum'] = null
        ..['updatedAt'] = now.millisecondsSinceEpoch;
      await transaction.write(
        'alarm_records',
        alarm.id,
        jsonEncode(map),
        uniqueKey: alarm.stableKey,
      );
    }
    if (transferDefault && replacementId != 'system') {
      final replacementPayload = await transaction.readById(
        collection,
        replacementId,
      );
      if (replacementPayload == null) {
        throw StateError('替代铃声不存在');
      }
      final decoded = jsonDecode(replacementPayload);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('替代铃声记录损坏');
      }
      final replacement = AlarmSound.fromMap(
        decoded,
      ).copyWith(isDefault: true, updatedAt: now);
      await transaction.write(
        collection,
        replacement.id,
        jsonEncode(replacement.toMap()),
        uniqueKey: replacement.checksum,
      );
    }
    await transaction.delete(collection, soundId);
    return SoundReferenceSummary(
      shiftCount: shiftCount,
      reminderCount: reminderCount,
      futureAlarmCount: futureAlarmCount,
    );
  });
}
