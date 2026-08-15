import '../../core/constants/app_constants.dart';
import '../models/alarm_lifecycle_event.dart';
import 'stored_repository.dart';

abstract interface class AlarmLifecycleRepository {
  Future<List<AlarmLifecycleEvent>> getAll();
  Future<List<AlarmLifecycleEvent>> getForAlarm(String alarmId);
  Future<void> append(AlarmLifecycleEvent event);
  Future<void> appendAll(Iterable<AlarmLifecycleEvent> events);
  Future<void> prune({DateTime? now});
  Stream<void> watch();
}

class LocalAlarmLifecycleRepository
    extends StoredRepository<AlarmLifecycleEvent>
    implements AlarmLifecycleRepository {
  LocalAlarmLifecycleRepository(super.store);

  @override
  String get collection => 'alarm_lifecycle_events';
  @override
  String idOf(AlarmLifecycleEvent item) => item.id;
  @override
  Map<String, Object?> encode(AlarmLifecycleEvent item) => item.toMap();
  @override
  AlarmLifecycleEvent decode(Map<String, Object?> map) =>
      AlarmLifecycleEvent.fromMap(map);

  @override
  Future<List<AlarmLifecycleEvent>> getForAlarm(String alarmId) async =>
      (await getAll()).where((item) => item.alarmId == alarmId).toList()
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  @override
  Future<void> append(AlarmLifecycleEvent event) async {
    await add(event);
    await prune();
  }

  @override
  Future<void> appendAll(Iterable<AlarmLifecycleEvent> events) async {
    for (final event in events) {
      await add(event);
    }
    await prune();
  }

  @override
  Future<void> prune({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(
      const Duration(days: AppConstants.lifecycleRetentionDays),
    );
    final all = (await getAll())
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final retainedIds = all
        .where((item) => !item.occurredAt.isBefore(cutoff))
        .take(AppConstants.lifecycleMaxEvents)
        .map((item) => item.id)
        .toSet();
    for (final event in all) {
      if (!retainedIds.contains(event.id)) await delete(event.id);
    }
  }
}
