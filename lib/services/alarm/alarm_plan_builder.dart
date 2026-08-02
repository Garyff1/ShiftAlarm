import '../../core/utils/alarm_time_calculator.dart';
import '../../data/models/alarm_record.dart';
import '../../data/models/alarm_sound.dart';
import '../../data/models/app_enums.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/daily_schedule.dart';
import '../../data/models/shift_template.dart';
import '../sounds/sound_resolver.dart';

class AlarmPlanBuilder {
  const AlarmPlanBuilder();

  List<AlarmRecord> build({
    required Iterable<DailySchedule> schedules,
    required Map<String, ShiftTemplate> templates,
    AppSettings appSettings = const AppSettings(),
    Iterable<AlarmSound> sounds = const [],
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final result = <AlarmRecord>[];
    for (final schedule in schedules) {
      final shift = templates[schedule.shiftTemplateId];
      if (shift == null ||
          shift.type != ShiftType.work ||
          schedule.isAllRemindersPaused) {
        continue;
      }
      final rules = schedule.reminderOverrides.isEmpty
          ? shift.reminderRules
          : schedule.reminderOverrides;
      final calculated = AlarmTimeCalculator.calculateAndSort(
        scheduleDate: schedule.date,
        arrivalTime: shift.arrivalTime,
        arrivalDayOffset: shift.arrivalDayOffset,
        rules: rules,
      ).where((item) => item.value.isAfter(clock)).toList();
      final arrival = shift.arrivalTime == null
          ? null
          : DateTime(
              schedule.date.year,
              schedule.date.month,
              schedule.date.day + shift.arrivalDayOffset,
              shift.arrivalTime!.hour,
              shift.arrivalTime!.minute,
            );
      for (var index = 0; index < calculated.length; index++) {
        final entry = calculated[index];
        final rule = entry.key;
        final createdAt = clock;
        final sound = SoundResolver.resolve(
          reminderSoundId: rule.soundId,
          shiftSoundId: shift.defaultSoundId,
          appDefaultSoundId: appSettings.defaultSoundId,
          sounds: sounds,
        );
        result.add(
          AlarmRecord(
            id: 'alarm_${schedule.id}_${rule.id}',
            scheduleId: schedule.id,
            scheduleDate: schedule.date,
            shiftTemplateId: shift.id,
            reminderRuleId: rule.id,
            reminderName: rule.name,
            shiftCode: shift.code,
            shiftName: shift.name,
            triggerAt: entry.value,
            arrivalAt: arrival,
            soundId: sound.id,
            soundPath: sound.path,
            soundChecksum: sound.checksum,
            isVolumeFadeInEnabled: rule.isVolumeFadeInEnabled,
            isVibrationEnabled: rule.isVibrationEnabled,
            isSnoozeEnabled: rule.isSnoozeEnabled,
            snoozeMinutes: rule.snoozeMinutes,
            maxSnoozeCount: rule.maxSnoozeCount,
            isTemporarySchedule: schedule.isTemporaryChanged,
            isCoreAlarm: index == 0 || rule.name.contains('起床'),
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
      }
    }
    result.sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
    return result;
  }
}
