import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/daily_schedule.dart';
import '../models/schedule_change_log.dart';
import 'crud_repository.dart';
import 'stored_repository.dart';

abstract interface class ScheduleChangeLogRepository
    implements CrudRepository<ScheduleChangeLog> {
  Future<List<ScheduleChangeLog>> getByDateRange(DateTime start, DateTime end);
  Future<List<ScheduleChangeLog>> getRecent({int limit = 100});
  Future<int> countShiftReferences(String shiftTemplateId);
}

class LocalScheduleChangeLogRepository
    extends StoredRepository<ScheduleChangeLog>
    implements ScheduleChangeLogRepository {
  LocalScheduleChangeLogRepository(super.store);
  @override
  String get collection => 'schedule_change_logs';
  @override
  String idOf(ScheduleChangeLog item) => item.id;
  @override
  Map<String, Object?> encode(ScheduleChangeLog item) => item.toMap();
  @override
  ScheduleChangeLog decode(Map<String, Object?> map) =>
      ScheduleChangeLog.fromMap(map);

  @override
  Future<List<ScheduleChangeLog>> getByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final payloads = await store.readRange(
      collection,
      DailySchedule.dateKeyOf(start),
      DailySchedule.dateKeyOf(end),
    );
    final result = <ScheduleChangeLog>[];
    for (final payload in payloads) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          result.add(ScheduleChangeLog.fromMap(decoded));
        }
      } catch (error, stackTrace) {
        debugPrint('[ShiftAlarm] 已跳过损坏的调班日志: $error\n$stackTrace');
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<List<ScheduleChangeLog>> getRecent({int limit = 100}) async {
    final all = await getAll();
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all.take(limit).toList();
  }

  @override
  Future<int> countShiftReferences(String shiftTemplateId) =>
      store.countReferences(collection, shiftTemplateId);
}
