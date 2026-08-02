import '../../data/models/alarm_sound.dart';
import '../../data/models/sound_ids.dart';

class ResolvedAlarmSound {
  const ResolvedAlarmSound.system()
    : id = SoundIds.system,
      path = null,
      checksum = null,
      isSystem = true;

  ResolvedAlarmSound.custom(AlarmSound sound)
    : id = sound.id,
      path = sound.internalPath,
      checksum = sound.checksum,
      isSystem = false;

  final String id;
  final String? path;
  final String? checksum;
  final bool isSystem;
}

abstract final class SoundResolver {
  static ResolvedAlarmSound resolve({
    required String? reminderSoundId,
    required String? shiftSoundId,
    required String? appDefaultSoundId,
    required Iterable<AlarmSound> sounds,
  }) {
    final byId = {for (final sound in sounds) sound.id: sound};
    for (final id in [reminderSoundId, shiftSoundId, appDefaultSoundId]) {
      if (id == null || id.isEmpty) continue;
      if (id == SoundIds.system) return const ResolvedAlarmSound.system();
      final sound = byId[id];
      if (sound != null &&
          sound.isAvailable &&
          sound.internalPath.isNotEmpty &&
          sound.checksum.isNotEmpty) {
        return ResolvedAlarmSound.custom(sound);
      }
    }
    return const ResolvedAlarmSound.system();
  }
}
