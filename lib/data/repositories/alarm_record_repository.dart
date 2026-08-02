import '../models/alarm_record.dart';
import 'crud_repository.dart';
import 'stored_repository.dart';

abstract interface class AlarmRecordRepository
    implements CrudRepository<AlarmRecord> {
  Future<AlarmRecord?> getByStableKey(String stableKey);
  Future<List<AlarmRecord>> getActive();
  Future<int> nextNativeAlarmId();
}

class LocalAlarmRecordRepository extends StoredRepository<AlarmRecord>
    implements AlarmRecordRepository {
  LocalAlarmRecordRepository(super.store);
  @override
  String get collection => 'alarm_records';
  @override
  String idOf(AlarmRecord item) => item.id;
  @override
  String uniqueKeyOf(AlarmRecord item) => item.stableKey;
  @override
  Map<String, Object?> encode(AlarmRecord item) => item.toMap();
  @override
  AlarmRecord decode(Map<String, Object?> map) => AlarmRecord.fromMap(map);

  @override
  Future<AlarmRecord?> getByStableKey(String stableKey) async {
    final payload = await store.readByUniqueKey(collection, stableKey);
    if (payload == null) return null;
    return getAll().then(
      (items) => items.where((item) => item.stableKey == stableKey).firstOrNull,
    );
  }

  @override
  Future<List<AlarmRecord>> getActive() async =>
      (await getAll()).where((item) => item.status.isActive).toList();

  @override
  Future<int> nextNativeAlarmId() async {
    final used = (await getAll())
        .map((item) => item.nativeAlarmId)
        .whereType<int>()
        .toSet();
    var candidate = 10000;
    while (used.contains(candidate)) {
      candidate++;
    }
    return candidate;
  }
}
