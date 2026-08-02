import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/data/models/alarm_record.dart';
import 'package:shift_alarm/data/models/alarm_sound.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/clock_time.dart';
import 'package:shift_alarm/data/models/reminder_rule.dart';
import 'package:shift_alarm/data/models/shift_template.dart';
import 'package:shift_alarm/data/repositories/alarm_record_repository.dart';
import 'package:shift_alarm/data/repositories/alarm_sound_repository.dart';
import 'package:shift_alarm/data/repositories/shift_template_repository.dart';
import 'package:shift_alarm/data/storage/memory_local_data_store.dart';

AlarmSound _sound(String id, {String? checksum}) => AlarmSound(
  id: id,
  displayName: '铃声 $id',
  internalPath: '/files/$id.mp3',
  sourceName: '$id.mp3',
  mimeType: 'audio/mpeg',
  format: 'mp3',
  fileSize: 1024,
  durationMilliseconds: 5000,
  checksum: checksum ?? 'checksum-$id',
  importedAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ShiftTemplate _shift({String? shiftSound, String? reminderSound}) =>
    ShiftTemplate(
      id: 'shift-1',
      code: 'A1',
      name: '早班',
      type: ShiftType.work,
      colorValue: 0xFF3157C8,
      arrivalTime: const ClockTime(hour: 8, minute: 0),
      defaultSoundId: shiftSound,
      reminderRules: [
        ReminderRule(
          id: 'rule-1',
          name: '起床',
          timeMode: ReminderTimeMode.beforeArrival,
          minutesBeforeArrival: 60,
          soundId: reminderSound,
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

AlarmRecord _alarm(String soundId) => AlarmRecord(
  id: 'alarm-1',
  scheduleId: 'schedule-1',
  scheduleDate: DateTime(2035, 1, 1),
  shiftTemplateId: 'shift-1',
  reminderRuleId: 'rule-1',
  reminderName: '起床',
  shiftCode: 'A1',
  shiftName: '早班',
  triggerAt: DateTime(2035, 1, 1, 7),
  soundId: soundId,
  soundPath: '/files/$soundId.mp3',
  soundChecksum: 'checksum-$soundId',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  late MemoryLocalDataStore store;
  late LocalAlarmSoundRepository sounds;
  late LocalShiftTemplateRepository shifts;
  late LocalAlarmRecordRepository alarms;

  setUp(() async {
    store = MemoryLocalDataStore();
    await store.initialize();
    sounds = LocalAlarmSoundRepository(store);
    shifts = LocalShiftTemplateRepository(store);
    alarms = LocalAlarmRecordRepository(store);
  });

  test('新增后可按 ID 读取铃声', () async {
    await sounds.add(_sound('one'));
    expect((await sounds.getById('one'))?.displayName, '铃声 one');
  });

  test('可按 SHA-256 校验值找到已导入铃声', () async {
    await sounds.add(_sound('one', checksum: 'same-checksum'));
    expect((await sounds.findByChecksum('same-checksum'))?.id, 'one');
  });

  test('空校验值不会匹配任何铃声', () async {
    await sounds.add(_sound('one'));
    expect(await sounds.findByChecksum(''), isNull);
  });

  test('引用统计识别班次默认铃声及名称', () async {
    await shifts.add(_shift(shiftSound: 'one'));
    final usage = await sounds.getReferenceSummary('one');
    expect(usage.shiftCount, 1);
    expect(usage.shiftNames, ['A1 早班']);
  });

  test('引用统计识别单条提醒铃声及位置', () async {
    await shifts.add(_shift(reminderSound: 'one'));
    final usage = await sounds.getReferenceSummary('one');
    expect(usage.reminderCount, 1);
    expect(usage.reminderNames, ['A1 · 起床']);
  });

  test('引用统计只计入未来闹钟并给出标签', () async {
    await alarms.add(_alarm('one'));
    final usage = await sounds.getReferenceSummary('one');
    expect(usage.futureAlarmCount, 1);
    expect(usage.futureAlarmLabels.single, contains('A1 · 起床'));
  });

  test('重命名仅更新铃声记录', () async {
    final sound = _sound('one');
    await sounds.add(sound);
    await sounds.update(sound.copyWith(displayName: '新名称'));
    final restored = await sounds.getById('one');
    expect(restored?.displayName, '新名称');
    expect(restored?.internalPath, sound.internalPath);
  });

  test('删除未引用铃声不会影响其他铃声', () async {
    await sounds.add(_sound('one'));
    await sounds.add(_sound('two'));
    await sounds.delete('one');
    expect(await sounds.getById('one'), isNull);
    expect(await sounds.getById('two'), isNotNull);
  });

  test('替换删除在同一事务更新班次、提醒和未来闹钟', () async {
    await sounds.add(_sound('one'));
    await shifts.add(_shift(shiftSound: 'one', reminderSound: 'one'));
    await alarms.add(_alarm('one'));

    final summary = await sounds.replaceReferencesAndDelete('one', 'system');

    expect(summary.shiftCount, 1);
    expect(summary.reminderCount, 1);
    expect(summary.futureAlarmCount, 1);
    expect(await sounds.getById('one'), isNull);
    final shift = await shifts.getById('shift-1');
    expect(shift?.defaultSoundId, 'system');
    expect(shift?.reminderRules.single.soundId, 'system');
    final alarm = await alarms.getById('alarm-1');
    expect(alarm?.soundId, 'system');
    expect(alarm?.soundPath, isNull);
  });

  test('替换事务失败时铃声和全部引用保持原样', () async {
    await sounds.add(_sound('one'));
    await shifts.add(_shift(shiftSound: 'one'));
    store.failNextTransaction = true;
    await expectLater(
      sounds.replaceReferencesAndDelete('one', 'system'),
      throwsStateError,
    );
    expect(await sounds.getById('one'), isNotNull);
    expect((await shifts.getById('shift-1'))?.defaultSoundId, 'one');
  });

  test('删除应用默认铃声时原子转移默认标志', () async {
    await sounds.add(_sound('one').copyWith(isDefault: true));
    await sounds.add(_sound('two'));

    await sounds.replaceReferencesAndDelete(
      'one',
      'two',
      transferDefault: true,
    );

    expect(await sounds.getById('one'), isNull);
    expect((await sounds.getById('two'))?.isDefault, isTrue);
  });
}
