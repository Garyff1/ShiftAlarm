import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../services/alarm/alarm_service.dart';
import '../models/app_enums.dart';
import '../models/daily_schedule.dart';
import '../models/schedule_change_log.dart';
import '../models/shift_template.dart';
import '../storage/local_data_store.dart';
import 'crud_repository.dart';
import 'schedule_operation_models.dart';
import 'stored_repository.dart';

abstract interface class DailyScheduleRepository
    implements CrudRepository<DailySchedule> {
  Future<DailySchedule?> getByDate(DateTime date);
  Future<List<DailySchedule>> getByDateRange(DateTime start, DateTime end);
  Future<List<DailySchedule>> getByMonth(DateTime month);
  Future<DailySchedule?> getToday([DateTime? now]);
  Future<DailySchedule?> getTomorrow([DateTime? now]);
  Future<List<DailySchedule>> getFuture({DateTime? from, int days = 90});
  Future<int> countShiftReferences(String shiftTemplateId);
  Future<ShiftReferenceSummary> getShiftReferenceSummary(
    String shiftTemplateId,
  );
  Future<bool> isShiftReferenced(String shiftTemplateId);
  Future<void> saveOrReplace(DailySchedule schedule);
  Future<DailySchedule> setShift(
    DateTime date,
    ShiftTemplate shift, {
    String reason = '',
    Map<String, ShiftTemplate> templates = const {},
  });
  Future<DailySchedule> restoreOriginal(
    DateTime date, {
    required Map<String, ShiftTemplate> templates,
  });
  Future<void> deleteByDate(
    DateTime date, {
    Map<String, ShiftTemplate> templates = const {},
  });
  Future<BatchScheduleResult> batchSet(
    Iterable<DateTime> dates,
    ShiftTemplate shift, {
    required bool overwriteExisting,
    String reason = '批量排班',
    Map<String, ShiftTemplate> templates = const {},
  });
  Future<int> batchDelete(
    Iterable<DateTime> dates, {
    Map<String, ShiftTemplate> templates = const {},
  });
  Future<void> swapDates(
    DateTime first,
    DateTime second, {
    required Map<String, ShiftTemplate> templates,
    String reason = '两天班次交换',
  });
  Future<DailySchedule> copyToDate(
    DailySchedule source,
    DateTime target,
    ShiftTemplate shift, {
    required bool overwriteExisting,
    bool copyNote = false,
  });
  Future<void> updateNote(DateTime date, String note);
  Future<void> setRemindersPaused(DateTime date, bool paused);
  Future<void> setAlarmSyncStatus(
    Iterable<String> scheduleIds,
    AlarmSyncStatus status, {
    DateTime? synchronizedAt,
  });
}

class LocalDailyScheduleRepository extends StoredRepository<DailySchedule>
    implements DailyScheduleRepository {
  LocalDailyScheduleRepository(
    super.store, {
    this.syncCoordinator = const PendingOnlyScheduleAlarmSyncCoordinator(),
  });

  final ScheduleAlarmSyncCoordinator syncCoordinator;

  Future<T> _runTransaction<T>(
    Set<String> changedCollections,
    Future<T> Function(LocalDataTransaction transaction) operation,
  ) async {
    try {
      return await store.runTransaction(changedCollections, operation);
    } on AppException {
      rethrow;
    } catch (error) {
      throw StorageException('排班数据保存失败，请重试', cause: error);
    }
  }

  @override
  String get collection => 'daily_schedules';
  static const changeLogCollection = 'schedule_change_logs';
  @override
  String idOf(DailySchedule item) => item.id;
  @override
  Map<String, Object?> encode(DailySchedule item) => item.toMap();
  @override
  DailySchedule decode(Map<String, Object?> map) => DailySchedule.fromMap(map);
  @override
  String uniqueKeyOf(DailySchedule item) => item.dateKey;

  ScheduleStatus _statusFor(ShiftTemplate shift) => switch (shift.type) {
    ShiftType.rest => ScheduleStatus.rest,
    ShiftType.leave => ScheduleStatus.leave,
    _ => ScheduleStatus.normal,
  };

  DailySchedule? _decodePayload(String? payload) {
    if (payload == null) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return DailySchedule.fromMap(decoded);
      }
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 排班数据损坏: $error\n$stackTrace');
    }
    return null;
  }

  Future<void> _writeSchedule(
    LocalDataTransaction transaction,
    DailySchedule schedule,
  ) => transaction.write(
    collection,
    schedule.id,
    jsonEncode(schedule.toMap()),
    uniqueKey: schedule.dateKey,
  );
  Future<void> _writeLog(
    LocalDataTransaction transaction,
    ScheduleChangeLog log,
  ) => transaction.write(changeLogCollection, log.id, jsonEncode(log.toMap()));

  ScheduleChangeLog _log({
    required DateTime date,
    required ShiftTemplate? oldShift,
    required ShiftTemplate? newShift,
    DateTime? relatedDate,
    String? batchOperationId,
    required ScheduleChangeType type,
    required String reason,
  }) => ScheduleChangeLog(
    id: IdGenerator.create('change'),
    date: DailySchedule.normalizeDate(date),
    originalShiftTemplateId: oldShift?.id,
    newShiftTemplateId: newShift?.id,
    relatedDate: relatedDate == null
        ? null
        : DailySchedule.normalizeDate(relatedDate),
    batchOperationId: batchOperationId,
    originalShiftCode: oldShift?.code,
    originalShiftName: oldShift?.name,
    newShiftCode: newShift?.code,
    newShiftName: newShift?.name,
    changeType: type,
    reason: reason,
    createdAt: DateTime.now(),
  );

  @override
  Future<DailySchedule?> getByDate(DateTime date) async => _decodePayload(
    await store.readByUniqueKey(collection, DailySchedule.dateKeyOf(date)),
  );

  @override
  Future<List<DailySchedule>> getByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    var from = DailySchedule.normalizeDate(start);
    var to = DailySchedule.normalizeDate(end);
    if (from.isAfter(to)) (from, to) = (to, from);
    final payloads = await store.readRange(
      collection,
      DailySchedule.dateKeyOf(from),
      DailySchedule.dateKeyOf(to),
    );
    final result = payloads
        .map(_decodePayload)
        .whereType<DailySchedule>()
        .toList();
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  @override
  Future<List<DailySchedule>> getByMonth(DateTime month) => getByDateRange(
    DateTime(month.year, month.month),
    DateTime(month.year, month.month + 1, 0),
  );

  @override
  Future<DailySchedule?> getToday([DateTime? now]) =>
      getByDate(now ?? DateTime.now());

  @override
  Future<DailySchedule?> getTomorrow([DateTime? now]) {
    final today = DailySchedule.normalizeDate(now ?? DateTime.now());
    return getByDate(today.add(const Duration(days: 1)));
  }

  @override
  Future<List<DailySchedule>> getFuture({DateTime? from, int days = 90}) {
    final start = DailySchedule.normalizeDate(from ?? DateTime.now());
    return getByDateRange(start, start.add(Duration(days: days)));
  }

  @override
  Future<int> countShiftReferences(String shiftTemplateId) =>
      store.countReferences(collection, shiftTemplateId);

  @override
  Future<ShiftReferenceSummary> getShiftReferenceSummary(
    String shiftTemplateId,
  ) async => ShiftReferenceSummary(
    scheduleCount: await store.countReferences(collection, shiftTemplateId),
    changeLogCount: await store.countReferences(
      changeLogCollection,
      shiftTemplateId,
    ),
  );

  @override
  Future<bool> isShiftReferenced(String shiftTemplateId) async =>
      (await getShiftReferenceSummary(shiftTemplateId)).isReferenced;

  @override
  Future<void> saveOrReplace(DailySchedule schedule) async {
    final normalized = schedule.copyWith(
      date: schedule.date,
      alarmSyncStatus: AlarmSyncStatus.pending,
      clearLastAlarmSyncAt: true,
      updatedAt: DateTime.now(),
    );
    await _runTransaction({collection}, (transaction) async {
      final existing = _decodePayload(
        await transaction.readByUniqueKey(collection, normalized.dateKey),
      );
      if (existing != null && existing.id != normalized.id) {
        await transaction.delete(collection, existing.id);
      }
      await _writeSchedule(transaction, normalized);
    });
    await syncCoordinator.markPending([normalized.date]);
  }

  @override
  Future<void> add(DailySchedule item) async {
    if (await hasDuplicateDate(item.date)) {
      throw const ValidationException('该日期已有排班');
    }
    await super.add(item);
  }

  Future<bool> hasDuplicateDate(DateTime date, {String? excludingId}) async {
    final existing = await getByDate(date);
    return existing != null && existing.id != excludingId;
  }

  @override
  Future<DailySchedule> setShift(
    DateTime date,
    ShiftTemplate shift, {
    String reason = '',
    Map<String, ShiftTemplate> templates = const {},
  }) async {
    final normalizedDate = DailySchedule.normalizeDate(date);
    late DailySchedule result;
    await _runTransaction({collection, changeLogCollection}, (
      transaction,
    ) async {
      final existing = _decodePayload(
        await transaction.readByUniqueKey(
          collection,
          DailySchedule.dateKeyOf(normalizedDate),
        ),
      );
      final now = DateTime.now();
      if (existing == null) {
        result = DailySchedule(
          id: IdGenerator.create('schedule'),
          date: normalizedDate,
          shiftTemplateId: shift.id,
          originalShiftTemplateId: shift.id,
          status: _statusFor(shift),
          alarmSyncStatus: AlarmSyncStatus.pending,
          createdAt: now,
          updatedAt: now,
        );
      } else if (existing.shiftTemplateId == shift.id) {
        result = existing.copyWith(
          status: _statusFor(shift),
          alarmSyncStatus: AlarmSyncStatus.pending,
          clearLastAlarmSyncAt: true,
          updatedAt: now,
        );
      } else {
        result = existing.copyWith(
          shiftTemplateId: shift.id,
          originalShiftTemplateId:
              existing.originalShiftTemplateId ?? existing.shiftTemplateId,
          status: _statusFor(shift),
          isTemporaryChanged: true,
          alarmSyncStatus: AlarmSyncStatus.pending,
          clearLastAlarmSyncAt: true,
          updatedAt: now,
        );
        final oldSnapshot =
            templates[existing.shiftTemplateId] ??
            ShiftTemplate(
              id: existing.shiftTemplateId,
              code: existing.shiftTemplateId,
              name: '原班次',
              type: ShiftType.other,
              colorValue: 0,
              createdAt: existing.createdAt,
              updatedAt: existing.updatedAt,
            );
        await _writeLog(
          transaction,
          _log(
            date: normalizedDate,
            oldShift: oldSnapshot,
            newShift: shift,
            type: shift.type == ShiftType.rest
                ? ScheduleChangeType.markRest
                : shift.type == ShiftType.leave
                ? ScheduleChangeType.markLeave
                : ScheduleChangeType.replace,
            reason: reason,
          ),
        );
      }
      await _writeSchedule(transaction, result);
    });
    await syncCoordinator.markPending([normalizedDate]);
    return result;
  }

  @override
  Future<DailySchedule> restoreOriginal(
    DateTime date, {
    required Map<String, ShiftTemplate> templates,
  }) async {
    final normalized = DailySchedule.normalizeDate(date);
    late DailySchedule restored;
    await _runTransaction({collection, changeLogCollection}, (
      transaction,
    ) async {
      final existing = _decodePayload(
        await transaction.readByUniqueKey(
          collection,
          DailySchedule.dateKeyOf(normalized),
        ),
      );
      if (existing == null) throw const ValidationException('该日期没有排班');
      final originalId = existing.originalShiftTemplateId;
      if (!existing.isTemporaryChanged || originalId == null) {
        throw const ValidationException('该日期没有可恢复的原排班');
      }
      final originalShift = templates[originalId];
      if (originalShift == null) {
        throw const ValidationException('原班次数据缺失，请重新选择班次');
      }
      final currentShift = templates[existing.shiftTemplateId];
      restored = existing.copyWith(
        shiftTemplateId: originalId,
        status: _statusFor(originalShift),
        isTemporaryChanged: false,
        alarmSyncStatus: AlarmSyncStatus.pending,
        clearLastAlarmSyncAt: true,
        updatedAt: DateTime.now(),
      );
      await _writeSchedule(transaction, restored);
      await _writeLog(
        transaction,
        _log(
          date: normalized,
          oldShift: currentShift,
          newShift: originalShift,
          type: ScheduleChangeType.restore,
          reason: '恢复原排班',
        ),
      );
    });
    await syncCoordinator.markPending([normalized]);
    return restored;
  }

  @override
  Future<void> deleteByDate(
    DateTime date, {
    Map<String, ShiftTemplate> templates = const {},
  }) async {
    final normalized = DailySchedule.normalizeDate(date);
    await _runTransaction({collection, changeLogCollection}, (
      transaction,
    ) async {
      final existing = _decodePayload(
        await transaction.readByUniqueKey(
          collection,
          DailySchedule.dateKeyOf(normalized),
        ),
      );
      if (existing == null) return;
      await transaction.delete(collection, existing.id);
      await _writeLog(
        transaction,
        _log(
          date: normalized,
          oldShift: templates[existing.shiftTemplateId],
          newShift: null,
          type: ScheduleChangeType.delete,
          reason: '删除当天排班',
        ),
      );
    });
    await syncCoordinator.markPending([normalized]);
  }

  @override
  Future<BatchScheduleResult> batchSet(
    Iterable<DateTime> dates,
    ShiftTemplate shift, {
    required bool overwriteExisting,
    String reason = '批量排班',
    Map<String, ShiftTemplate> templates = const {},
  }) async {
    final normalizedDates = <String, DateTime>{
      for (final date in dates)
        DailySchedule.dateKeyOf(date): DailySchedule.normalizeDate(date),
    }.values.toList()..sort();
    if (normalizedDates.isEmpty) {
      return const BatchScheduleResult(savedCount: 0, skippedCount: 0);
    }
    var saved = 0;
    var skipped = 0;
    final batchId = IdGenerator.create('batch');
    await _runTransaction({collection, changeLogCollection}, (
      transaction,
    ) async {
      for (final date in normalizedDates) {
        final existing = _decodePayload(
          await transaction.readByUniqueKey(
            collection,
            DailySchedule.dateKeyOf(date),
          ),
        );
        if (existing != null && !overwriteExisting) {
          skipped++;
          continue;
        }
        final now = DateTime.now();
        final schedule = existing == null
            ? DailySchedule(
                id: IdGenerator.create('schedule'),
                date: date,
                shiftTemplateId: shift.id,
                originalShiftTemplateId: shift.id,
                status: _statusFor(shift),
                alarmSyncStatus: AlarmSyncStatus.pending,
                createdAt: now,
                updatedAt: now,
              )
            : existing.copyWith(
                shiftTemplateId: shift.id,
                originalShiftTemplateId:
                    existing.originalShiftTemplateId ??
                    existing.shiftTemplateId,
                status: _statusFor(shift),
                isTemporaryChanged:
                    existing.isTemporaryChanged ||
                    existing.shiftTemplateId != shift.id,
                alarmSyncStatus: AlarmSyncStatus.pending,
                clearLastAlarmSyncAt: true,
                updatedAt: now,
              );
        await _writeSchedule(transaction, schedule);
        if (existing != null && existing.shiftTemplateId != shift.id) {
          await _writeLog(
            transaction,
            _log(
              date: date,
              oldShift: templates[existing.shiftTemplateId],
              newShift: shift,
              batchOperationId: batchId,
              type: ScheduleChangeType.replace,
              reason: reason,
            ),
          );
        }
        saved++;
      }
    });
    await syncCoordinator.markPending(normalizedDates);
    return BatchScheduleResult(savedCount: saved, skippedCount: skipped);
  }

  @override
  Future<int> batchDelete(
    Iterable<DateTime> dates, {
    Map<String, ShiftTemplate> templates = const {},
  }) async {
    final normalizedDates = <String, DateTime>{
      for (final date in dates)
        DailySchedule.dateKeyOf(date): DailySchedule.normalizeDate(date),
    }.values.toList();
    var deleted = 0;
    final batchId = IdGenerator.create('batch_delete');
    await _runTransaction({collection, changeLogCollection}, (
      transaction,
    ) async {
      for (final date in normalizedDates) {
        final existing = _decodePayload(
          await transaction.readByUniqueKey(
            collection,
            DailySchedule.dateKeyOf(date),
          ),
        );
        if (existing == null) continue;
        await transaction.delete(collection, existing.id);
        await _writeLog(
          transaction,
          _log(
            date: date,
            oldShift: templates[existing.shiftTemplateId],
            newShift: null,
            batchOperationId: batchId,
            type: ScheduleChangeType.delete,
            reason: '批量清除排班',
          ),
        );
        deleted++;
      }
    });
    await syncCoordinator.markPending(normalizedDates);
    return deleted;
  }

  @override
  Future<void> swapDates(
    DateTime first,
    DateTime second, {
    required Map<String, ShiftTemplate> templates,
    String reason = '两天班次交换',
  }) async {
    final firstDate = DailySchedule.normalizeDate(first);
    final secondDate = DailySchedule.normalizeDate(second);
    if (firstDate == secondDate) throw const ValidationException('不能交换同一天');
    final batchId = IdGenerator.create('swap');
    await _runTransaction({collection, changeLogCollection}, (
      transaction,
    ) async {
      final firstSchedule = _decodePayload(
        await transaction.readByUniqueKey(
          collection,
          DailySchedule.dateKeyOf(firstDate),
        ),
      );
      final secondSchedule = _decodePayload(
        await transaction.readByUniqueKey(
          collection,
          DailySchedule.dateKeyOf(secondDate),
        ),
      );
      if (firstSchedule == null && secondSchedule == null) {
        throw const ValidationException('两个日期都未排班，无法交换');
      }
      final now = DateTime.now();
      if (firstSchedule != null && secondSchedule != null) {
        final firstIncoming = templates[secondSchedule.shiftTemplateId];
        final secondIncoming = templates[firstSchedule.shiftTemplateId];
        if (firstIncoming == null || secondIncoming == null) {
          throw const ValidationException('交换所需的班次数据缺失');
        }
        final updatedFirst = firstSchedule.copyWith(
          shiftTemplateId: secondSchedule.shiftTemplateId,
          originalShiftTemplateId:
              firstSchedule.originalShiftTemplateId ??
              firstSchedule.shiftTemplateId,
          status: _statusFor(firstIncoming),
          isTemporaryChanged: true,
          alarmSyncStatus: AlarmSyncStatus.pending,
          clearLastAlarmSyncAt: true,
          updatedAt: now,
        );
        final updatedSecond = secondSchedule.copyWith(
          shiftTemplateId: firstSchedule.shiftTemplateId,
          originalShiftTemplateId:
              secondSchedule.originalShiftTemplateId ??
              secondSchedule.shiftTemplateId,
          status: _statusFor(secondIncoming),
          isTemporaryChanged: true,
          alarmSyncStatus: AlarmSyncStatus.pending,
          clearLastAlarmSyncAt: true,
          updatedAt: now,
        );
        await _writeSchedule(transaction, updatedFirst);
        await _writeSchedule(transaction, updatedSecond);
        await _writeLog(
          transaction,
          _log(
            date: firstDate,
            relatedDate: secondDate,
            oldShift: templates[firstSchedule.shiftTemplateId],
            newShift: firstIncoming,
            batchOperationId: batchId,
            type: ScheduleChangeType.swap,
            reason: reason,
          ),
        );
        await _writeLog(
          transaction,
          _log(
            date: secondDate,
            relatedDate: firstDate,
            oldShift: templates[secondSchedule.shiftTemplateId],
            newShift: secondIncoming,
            batchOperationId: batchId,
            type: ScheduleChangeType.swap,
            reason: reason,
          ),
        );
      } else {
        final source = firstSchedule ?? secondSchedule!;
        final sourceDate = firstSchedule == null ? secondDate : firstDate;
        final targetDate = firstSchedule == null ? firstDate : secondDate;
        await transaction.delete(collection, source.id);
        final moved = source.copyWith(
          id: IdGenerator.create('schedule'),
          date: targetDate,
          originalShiftTemplateId:
              source.originalShiftTemplateId ?? source.shiftTemplateId,
          isTemporaryChanged: true,
          alarmSyncStatus: AlarmSyncStatus.pending,
          clearLastAlarmSyncAt: true,
          createdAt: now,
          updatedAt: now,
        );
        await _writeSchedule(transaction, moved);
        await _writeLog(
          transaction,
          _log(
            date: targetDate,
            relatedDate: sourceDate,
            oldShift: null,
            newShift: templates[source.shiftTemplateId],
            batchOperationId: batchId,
            type: ScheduleChangeType.swap,
            reason: '$reason（移动到空日期）',
          ),
        );
      }
    });
    await syncCoordinator.markPending([firstDate, secondDate]);
  }

  @override
  Future<DailySchedule> copyToDate(
    DailySchedule source,
    DateTime target,
    ShiftTemplate shift, {
    required bool overwriteExisting,
    bool copyNote = false,
  }) async {
    final targetDate = DailySchedule.normalizeDate(target);
    final existing = await getByDate(targetDate);
    if (existing != null && !overwriteExisting) {
      throw const ValidationException('目标日期已有排班');
    }
    await batchSet(
      [targetDate],
      shift,
      overwriteExisting: overwriteExisting,
      reason: '复制排班',
      templates: {shift.id: shift},
    );
    if (copyNote && source.note.isNotEmpty) {
      await updateNote(targetDate, source.note);
    }
    return (await getByDate(targetDate))!;
  }

  @override
  Future<void> updateNote(DateTime date, String note) async {
    final existing = await getByDate(date);
    if (existing == null) throw const ValidationException('该日期没有排班');
    await saveOrReplace(
      existing.copyWith(note: note.trim(), updatedAt: DateTime.now()),
    );
  }

  @override
  Future<void> setRemindersPaused(DateTime date, bool paused) async {
    final existing = await getByDate(date);
    if (existing == null) throw const ValidationException('该日期没有排班');
    await saveOrReplace(
      existing.copyWith(
        isAllRemindersPaused: paused,
        alarmSyncStatus: AlarmSyncStatus.pending,
        clearLastAlarmSyncAt: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> setAlarmSyncStatus(
    Iterable<String> scheduleIds,
    AlarmSyncStatus status, {
    DateTime? synchronizedAt,
  }) async {
    final ids = scheduleIds.toSet();
    if (ids.isEmpty) return;
    await _runTransaction({collection}, (transaction) async {
      for (final id in ids) {
        final existing = _decodePayload(
          await transaction.readById(collection, id),
        );
        if (existing == null) continue;
        await _writeSchedule(
          transaction,
          existing.copyWith(
            alarmSyncStatus: status,
            lastAlarmSyncAt: synchronizedAt,
            clearLastAlarmSyncAt: synchronizedAt == null,
            updatedAt: DateTime.now(),
          ),
        );
      }
    });
  }
}
