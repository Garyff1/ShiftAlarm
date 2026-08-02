import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/core/errors/app_exception.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/clock_time.dart';
import 'package:shift_alarm/data/models/daily_schedule.dart';
import 'package:shift_alarm/data/models/shift_template.dart';
import 'package:shift_alarm/data/repositories/daily_schedule_repository.dart';
import 'package:shift_alarm/data/repositories/schedule_change_log_repository.dart';
import 'package:shift_alarm/data/repositories/shift_template_repository.dart';
import 'package:shift_alarm/data/storage/memory_local_data_store.dart';

ShiftTemplate template(
  String id,
  String code, {
  ShiftType type = ShiftType.work,
}) {
  final now = DateTime(2026, 8, 1);
  return ShiftTemplate(
    id: id,
    code: code,
    name: '$code 班',
    type: type,
    colorValue: 0xFF526AA0,
    arrivalTime: type == ShiftType.work
        ? const ClockTime(hour: 8, minute: 0)
        : null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late MemoryLocalDataStore store;
  late LocalDailyScheduleRepository repository;
  late LocalScheduleChangeLogRepository logs;
  late ShiftTemplate a1;
  late ShiftTemplate b1;
  late ShiftTemplate off;
  late Map<String, ShiftTemplate> templates;

  setUp(() async {
    store = MemoryLocalDataStore();
    await store.initialize();
    repository = LocalDailyScheduleRepository(store);
    logs = LocalScheduleChangeLogRepository(store);
    a1 = template('a1', 'A1');
    b1 = template('b1', 'B1');
    off = template('off', 'OFF', type: ShiftType.rest);
    templates = {a1.id: a1, b1.id: b1, off.id: off};
  });

  test('日期始终规范化为自然日零点', () async {
    final saved = await repository.setShift(DateTime(2026, 8, 10, 23, 59), a1);
    expect(saved.date, DateTime(2026, 8, 10));
    expect(saved.dateKey, '2026-08-10');
  });

  test('首次排班保存当前与原始班次且不标记临时调整', () async {
    final saved = await repository.setShift(DateTime(2026, 8, 10), a1);
    expect(saved.shiftTemplateId, a1.id);
    expect(saved.originalShiftTemplateId, a1.id);
    expect(saved.isTemporaryChanged, isFalse);
    expect(saved.alarmSyncStatus, AlarmSyncStatus.pending);
  });

  test('同一天再次设置执行更新且只有一条记录', () async {
    final date = DateTime(2026, 8, 10);
    await repository.setShift(date, a1);
    await repository.setShift(date, b1, templates: templates);
    expect(await repository.getAll(), hasLength(1));
    expect((await repository.getByDate(date))?.shiftTemplateId, b1.id);
  });

  test('直接新增重复日期受到唯一键保护', () async {
    final now = DateTime(2026, 8, 1);
    final first = DailySchedule(
      id: '1',
      date: now,
      shiftTemplateId: a1.id,
      createdAt: now,
      updatedAt: now,
    );
    final second = DailySchedule(
      id: '2',
      date: now,
      shiftTemplateId: b1.id,
      createdAt: now,
      updatedAt: now,
    );
    await repository.add(first);
    expect(() => repository.add(second), throwsA(isA<ValidationException>()));
  });

  test('查询月份只返回指定月份数据', () async {
    await repository.setShift(DateTime(2026, 8, 1), a1);
    await repository.setShift(DateTime(2026, 8, 31), a1);
    await repository.setShift(DateTime(2026, 9, 1), b1);
    expect(await repository.getByMonth(DateTime(2026, 8)), hasLength(2));
  });

  test('反向日期范围自动纠正', () async {
    await repository.setShift(DateTime(2026, 8, 5), a1);
    expect(
      await repository.getByDateRange(
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 1),
      ),
      hasLength(1),
    );
  });

  test('查询今天和明天', () async {
    final today = DateTime(2026, 8, 10);
    await repository.setShift(today, a1);
    await repository.setShift(today.add(const Duration(days: 1)), b1);
    expect((await repository.getToday(today))?.shiftTemplateId, a1.id);
    expect((await repository.getTomorrow(today))?.shiftTemplateId, b1.id);
  });

  test('删除排班并原子写入日志', () async {
    final date = DateTime(2026, 8, 10);
    await repository.setShift(date, a1);
    await repository.deleteByDate(date, templates: templates);
    expect(await repository.getByDate(date), isNull);
    expect((await logs.getAll()).single.changeType, ScheduleChangeType.delete);
  });

  test('临时调班保留最初原始班次并写入快照', () async {
    final date = DateTime(2026, 8, 10);
    await repository.setShift(date, a1);
    final changed = await repository.setShift(
      date,
      b1,
      reason: '临时安排',
      templates: templates,
    );
    expect(changed.originalShiftTemplateId, a1.id);
    expect(changed.isTemporaryChanged, isTrue);
    final log = (await logs.getAll()).single;
    expect(log.originalShiftCode, 'A1');
    expect(log.newShiftCode, 'B1');
    expect(log.reason, '临时安排');
  });

  test('连续临时调班不改变最初原始班次', () async {
    final c2 = template('c2', 'C2');
    templates[c2.id] = c2;
    final date = DateTime(2026, 8, 10);
    await repository.setShift(date, a1);
    await repository.setShift(date, b1, templates: templates);
    final changedAgain = await repository.setShift(
      date,
      c2,
      templates: templates,
    );
    expect(changedAgain.originalShiftTemplateId, a1.id);
    expect(await logs.getAll(), hasLength(2));
  });

  test('恢复原排班关闭临时标记并写入恢复日志', () async {
    final date = DateTime(2026, 8, 10);
    await repository.setShift(date, a1);
    await repository.setShift(date, b1, templates: templates);
    final restored = await repository.restoreOriginal(
      date,
      templates: templates,
    );
    expect(restored.shiftTemplateId, a1.id);
    expect(restored.isTemporaryChanged, isFalse);
    expect((await logs.getAll()).last.changeType, ScheduleChangeType.restore);
  });

  test('原始班次缺失时恢复失败且保留当前排班', () async {
    final date = DateTime(2026, 8, 10);
    await repository.setShift(date, a1);
    await repository.setShift(date, b1, templates: templates);
    expect(
      () => repository.restoreOriginal(date, templates: {b1.id: b1}),
      throwsA(isA<ValidationException>()),
    );
    expect((await repository.getByDate(date))?.shiftTemplateId, b1.id);
  });

  test('批量设置 60 天不产生重复日期', () async {
    final dates = [
      for (var i = 0; i < 60; i++) DateTime(2026, 8, 1).add(Duration(days: i)),
    ];
    final result = await repository.batchSet(
      dates,
      a1,
      overwriteExisting: true,
      templates: templates,
    );
    expect(result.savedCount, 60);
    expect(
      (await repository.getAll()).map((item) => item.dateKey).toSet(),
      hasLength(60),
    );
  });

  test('连续创建 90 天排班后日期仍唯一', () async {
    final start = DateTime(2026, 1, 1);
    for (var index = 0; index < 90; index++) {
      await repository.setShift(start.add(Duration(days: index)), a1);
    }
    final all = await repository.getAll();
    expect(all, hasLength(90));
    expect(all.map((item) => item.dateKey).toSet(), hasLength(90));
  });

  test('快速修改同一天 20 次只保留一条排班', () async {
    final date = DateTime(2026, 8, 10);
    for (var index = 0; index < 20; index++) {
      await repository.setShift(
        date,
        index.isEven ? a1 : b1,
        templates: templates,
      );
    }
    final saved = await repository.getAll();
    expect(saved, hasLength(1));
    expect(saved.single.shiftTemplateId, b1.id);
    expect(saved.single.originalShiftTemplateId, a1.id);
    expect(await logs.getAll(), hasLength(19));
  });

  test('批量设置可跳过已有排班', () async {
    final dates = [DateTime(2026, 8, 1), DateTime(2026, 8, 2)];
    await repository.setShift(dates.first, b1);
    final result = await repository.batchSet(
      dates,
      a1,
      overwriteExisting: false,
      templates: templates,
    );
    expect(result.savedCount, 1);
    expect(result.skippedCount, 1);
    expect((await repository.getByDate(dates.first))?.shiftTemplateId, b1.id);
  });

  test('两天班次交换并保存两条关联日志', () async {
    final first = DateTime(2026, 8, 10);
    final second = DateTime(2026, 8, 11);
    await repository.setShift(first, a1);
    await repository.setShift(second, b1);
    await repository.swapDates(first, second, templates: templates);
    expect((await repository.getByDate(first))?.shiftTemplateId, b1.id);
    expect((await repository.getByDate(second))?.shiftTemplateId, a1.id);
    expect((await repository.getByDate(first))?.isTemporaryChanged, isTrue);
    final swapLogs = await logs.getAll();
    expect(swapLogs, hasLength(2));
    expect(swapLogs.first.batchOperationId, swapLogs.last.batchOperationId);
  });

  test('连续交换班次 20 次保持数据完整且无重复日期', () async {
    final first = DateTime(2026, 8, 10);
    final second = DateTime(2026, 8, 11);
    await repository.setShift(first, a1);
    await repository.setShift(second, b1);
    for (var index = 0; index < 20; index++) {
      await repository.swapDates(first, second, templates: templates);
    }
    final all = await repository.getAll();
    expect(all, hasLength(2));
    expect(all.map((item) => item.dateKey).toSet(), hasLength(2));
    expect((await repository.getByDate(first))?.shiftTemplateId, a1.id);
    expect((await repository.getByDate(second))?.shiftTemplateId, b1.id);
    expect(await logs.getAll(), hasLength(40));
  });

  test('交换同一天或两个空日期会被拒绝', () async {
    final date = DateTime(2026, 8, 10);
    expect(
      () => repository.swapDates(date, date, templates: templates),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => repository.swapDates(
        date,
        date.add(const Duration(days: 1)),
        templates: templates,
      ),
      throwsA(isA<AppException>()),
    );
  });

  test('交换事务失败时两天数据和日志整体回滚', () async {
    final first = DateTime(2026, 8, 10);
    final second = DateTime(2026, 8, 11);
    await repository.setShift(first, a1);
    await repository.setShift(second, b1);
    store.failNextTransaction = true;
    expect(
      () => repository.swapDates(first, second, templates: templates),
      throwsA(isA<AppException>()),
    );
    expect((await repository.getByDate(first))?.shiftTemplateId, a1.id);
    expect((await repository.getByDate(second))?.shiftTemplateId, b1.id);
    expect(await logs.getAll(), isEmpty);
  });

  test('班次引用统计包含排班和调班日志并阻止删除', () async {
    final shiftStore = LocalShiftTemplateRepository(
      store,
      referenceChecker: repository.getShiftReferenceSummary,
    );
    await shiftStore.add(a1);
    await shiftStore.add(b1);
    final date = DateTime(2026, 8, 10);
    await repository.setShift(date, a1);
    await repository.setShift(date, b1, templates: templates);
    final summary = await repository.getShiftReferenceSummary(a1.id);
    expect(summary.scheduleCount, 1);
    expect(summary.changeLogCount, 1);
    expect(await shiftStore.canDelete(a1.id), isFalse);
  });

  test('当天备注和暂停提醒状态可持久化', () async {
    final date = DateTime(2026, 8, 10);
    await repository.setShift(date, a1);
    await repository.updateNote(date, '临时会议');
    await repository.setRemindersPaused(date, true);
    final saved = await repository.getByDate(date);
    expect(saved?.note, '临时会议');
    expect(saved?.isAllRemindersPaused, isTrue);
  });
}
