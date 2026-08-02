import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/core/errors/app_exception.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/clock_time.dart';
import 'package:shift_alarm/data/models/shift_template.dart';
import 'package:shift_alarm/data/repositories/shift_template_repository.dart';
import 'package:shift_alarm/data/storage/memory_local_data_store.dart';

ShiftTemplate shift({
  required String id,
  required String code,
  String name = '早班',
  bool enabled = true,
}) {
  final time = DateTime(2026, 8, 1, 8);
  return ShiftTemplate(
    id: id,
    code: code,
    name: name,
    type: ShiftType.work,
    colorValue: 0xFF526AA0,
    arrivalTime: const ClockTime(hour: 8, minute: 0),
    isEnabled: enabled,
    createdAt: time,
    updatedAt: time,
  );
}

void main() {
  late MemoryLocalDataStore store;
  late LocalShiftTemplateRepository repository;

  setUp(() async {
    store = MemoryLocalDataStore();
    await store.initialize();
    repository = LocalShiftTemplateRepository(store);
  });

  test('新增班次', () async {
    await repository.add(shift(id: '1', code: 'A1'));
    expect((await repository.getAll()).single.code, 'A1');
  });

  test('修改班次', () async {
    final original = shift(id: '1', code: 'A1');
    await repository.add(original);
    await repository.update(original.copyWith(name: '新早班'));
    expect((await repository.getById('1'))?.name, '新早班');
  });

  test('删除班次', () async {
    await repository.add(shift(id: '1', code: 'A1'));
    await repository.delete('1');
    expect(await repository.getAll(), isEmpty);
  });

  test('重复代码不区分大小写并被拦截', () async {
    await repository.add(shift(id: '1', code: 'A1'));
    expect(
      () => repository.add(shift(id: '2', code: 'a1')),
      throwsA(isA<DuplicateShiftCodeException>()),
    );
  });

  test('重新创建 Repository 后数据仍可读取', () async {
    await repository.add(shift(id: '1', code: 'A1'));
    final reopened = LocalShiftTemplateRepository(store);
    expect((await reopened.getAll()).single.id, '1');
  });

  test('仅查询启用班次', () async {
    await repository.add(shift(id: '1', code: 'A1'));
    await repository.add(shift(id: '2', code: 'B1', enabled: false));
    expect((await repository.getEnabled()).map((item) => item.code), ['A1']);
  });

  test('损坏记录不会导致整个列表失败', () async {
    await repository.add(shift(id: '1', code: 'A1'));
    store.seedRaw('shift_templates', 'broken', '{broken json');
    final result = await repository.getAll();
    expect(result.map((item) => item.code), ['A1']);
  });
}
