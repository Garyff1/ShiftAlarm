import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/app_settings.dart';
import 'package:shift_alarm/data/models/alarm_record.dart';
import 'package:shift_alarm/data/models/alarm_sound.dart';
import 'package:shift_alarm/data/models/clock_time.dart';
import 'package:shift_alarm/data/models/daily_schedule.dart';
import 'package:shift_alarm/data/models/shift_template.dart';
import 'package:shift_alarm/data/repositories/app_settings_repository.dart';
import 'package:shift_alarm/data/repositories/alarm_record_repository.dart';
import 'package:shift_alarm/data/repositories/alarm_sound_repository.dart';
import 'package:shift_alarm/data/repositories/daily_schedule_repository.dart';
import 'package:shift_alarm/data/repositories/shift_template_repository.dart';
import 'package:shift_alarm/data/storage/sqlite_local_data_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late DatabaseFactory factory;
  late ShiftTemplate legacyShift;
  late DailySchedule legacySchedule;

  setUp(() async {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'shift_alarm_migration_',
    );
    databasePath =
        '${temporaryDirectory.path}${Platform.pathSeparator}shift_alarm.db';
    final now = DateTime(2026, 8, 1);
    legacyShift = ShiftTemplate(
      id: 'legacy_shift',
      code: 'A1',
      name: '旧早班',
      type: ShiftType.work,
      colorValue: 0xFF526AA0,
      arrivalTime: const ClockTime(hour: 8, minute: 0),
      createdAt: now,
      updatedAt: now,
    );
    legacySchedule = DailySchedule(
      id: 'legacy_schedule',
      date: DateTime(2026, 8, 10),
      shiftTemplateId: legacyShift.id,
      originalShiftTemplateId: legacyShift.id,
      createdAt: now,
      updatedAt: now,
    );
    final database = await factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE records (
              collection TEXT NOT NULL,
              id TEXT NOT NULL,
              unique_key TEXT,
              payload TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (collection, id)
            )
          ''');
          await db.execute(
            'CREATE UNIQUE INDEX records_unique_key ON records(collection, unique_key) WHERE unique_key IS NOT NULL',
          );
          await db.insert('records', {
            'collection': 'shift_templates',
            'id': legacyShift.id,
            'unique_key': legacyShift.code,
            'payload': jsonEncode(legacyShift.toMap()),
            'updated_at': now.millisecondsSinceEpoch,
          });
          await db.insert('records', {
            'collection': 'daily_schedules',
            'id': legacySchedule.id,
            'unique_key': legacySchedule.dateKey,
            'payload': jsonEncode(legacySchedule.toMap()),
            'updated_at': now.millisecondsSinceEpoch,
          });
        },
      ),
    );
    await database.close();
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('v1 升级到 v2 后原班次数据仍存在', () async {
    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    final shifts = await LocalShiftTemplateRepository(store).getAll();
    expect(shifts.single.code, 'A1');
    expect(await store.databaseForTesting.getVersion(), 4);
    await store.databaseForTesting.close();
  });

  test('v1 通用记录中的排班迁移到新表', () async {
    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    final migrated = await LocalDailyScheduleRepository(
      store,
    ).getByDate(DateTime(2026, 8, 10));
    expect(migrated?.shiftTemplateId, legacyShift.id);
    final remaining = await store.databaseForTesting.query(
      'records',
      where: 'collection = ?',
      whereArgs: ['daily_schedules'],
    );
    expect(remaining, isEmpty);
    await store.databaseForTesting.close();
  });

  test('v2 创建日期唯一索引和查询索引', () async {
    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    final indexes = await store.databaseForTesting.rawQuery(
      'PRAGMA index_list(daily_schedules)',
    );
    final names = indexes.map((row) => row['name']).toSet();
    expect(names, contains('daily_schedules_date_unique'));
    expect(names, contains('daily_schedules_shift_template_id'));
    await store.databaseForTesting.close();
  });

  test('损坏的 v1 排班记录会被保留且不阻断其他记录迁移', () async {
    final legacyDatabase = await factory.openDatabase(databasePath);
    await legacyDatabase.insert('records', {
      'collection': 'daily_schedules',
      'id': 'broken_schedule',
      'unique_key': '2026-08-12',
      'payload': '{broken json',
      'updated_at': DateTime(2026, 8, 1).millisecondsSinceEpoch,
    });
    await legacyDatabase.close();

    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    expect(
      await LocalDailyScheduleRepository(
        store,
      ).getByDate(DateTime(2026, 8, 10)),
      isNotNull,
    );
    final retained = await store.databaseForTesting.query(
      'records',
      where: 'collection = ? AND id = ?',
      whereArgs: ['daily_schedules', 'broken_schedule'],
    );
    expect(retained, hasLength(1));
    await store.databaseForTesting.close();
  });

  test('升级后可以新增排班且数据库层阻止重复日期', () async {
    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    final repository = LocalDailyScheduleRepository(store);
    await repository.setShift(DateTime(2026, 8, 11), legacyShift);
    final row = (await store.databaseForTesting.query(
      'daily_schedules',
      where: 'date = ?',
      whereArgs: ['2026-08-11'],
    )).single;
    expect(
      () => store.databaseForTesting.insert('daily_schedules', {
        ...row,
        'id': 'duplicate',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await store.databaseForTesting.close();
  });

  test('数据库迁移不会影响 SharedPreferences 设置', () async {
    SharedPreferences.setMockInitialValues({
      'app_settings_v1': jsonEncode(
        const AppSettings(themeMode: AppThemeMode.dark).toMap(),
      ),
    });
    final settingsRepository = SharedPreferencesAppSettingsRepository(
      await SharedPreferences.getInstance(),
    );
    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    expect((await settingsRepository.load()).themeMode, AppThemeMode.dark);
    await store.databaseForTesting.close();
  });

  test('v2 通用 AlarmRecord 升级到 v3 专用表且数据完整', () async {
    final versionTwo = await factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(version: 2, onUpgrade: (_, _, _) async {}),
    );
    final now = DateTime(2026, 8, 1, 12);
    final legacyAlarm = AlarmRecord(
      id: 'legacy_alarm',
      scheduleId: legacySchedule.id,
      scheduleDate: legacySchedule.date,
      shiftTemplateId: legacyShift.id,
      reminderRuleId: 'wake',
      reminderName: '起床',
      shiftCode: legacyShift.code,
      shiftName: legacyShift.name,
      triggerAt: DateTime(2026, 8, 10, 6),
      nativeAlarmId: 10000,
      status: AlarmStatus.registered,
      createdAt: now,
      updatedAt: now,
    );
    await versionTwo.insert('records', {
      'collection': 'alarm_records',
      'id': legacyAlarm.id,
      'unique_key': legacyAlarm.stableKey,
      'payload': jsonEncode(legacyAlarm.toMap()),
      'updated_at': now.millisecondsSinceEpoch,
    });
    await versionTwo.close();

    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    final restored = await LocalAlarmRecordRepository(
      store,
    ).getById(legacyAlarm.id);
    expect(restored?.nativeAlarmId, 10000);
    expect(restored?.status, AlarmStatus.registered);
    expect(restored?.stableKey, legacyAlarm.stableKey);
    final oldRows = await store.databaseForTesting.query(
      'records',
      where: 'collection = ?',
      whereArgs: ['alarm_records'],
    );
    expect(oldRows, isEmpty);
    await store.databaseForTesting.close();
  });

  test('v3 为稳定键、原生 ID、排班、时间和状态建立索引', () async {
    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    final indexes = await store.databaseForTesting.rawQuery(
      'PRAGMA index_list(alarm_records)',
    );
    final names = indexes.map((row) => row['name']).toSet();
    expect(names, contains('alarm_records_stable_key'));
    expect(names, contains('alarm_records_native_id'));
    expect(names, contains('alarm_records_schedule_id'));
    expect(names, contains('alarm_records_trigger_at'));
    expect(names, contains('alarm_records_status'));
    await store.databaseForTesting.close();
  });

  test('v4 创建独立铃声表和三个查询索引', () async {
    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    final tables = await store.databaseForTesting.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(tables.map((row) => row['name']), contains('alarm_sounds'));
    final indexes = await store.databaseForTesting.rawQuery(
      'PRAGMA index_list(alarm_sounds)',
    );
    final names = indexes.map((row) => row['name']).toSet();
    expect(names, contains('alarm_sounds_checksum'));
    expect(names, contains('alarm_sounds_is_default'));
    expect(names, contains('alarm_sounds_is_available'));
    await store.databaseForTesting.close();
  });

  test('v4 alarm_records 增加 sound_id 和查询索引', () async {
    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    final columns = await store.databaseForTesting.rawQuery(
      'PRAGMA table_info(alarm_records)',
    );
    expect(columns.map((row) => row['name']), contains('sound_id'));
    final indexes = await store.databaseForTesting.rawQuery(
      'PRAGMA index_list(alarm_records)',
    );
    expect(
      indexes.map((row) => row['name']),
      contains('alarm_records_sound_id'),
    );
    await store.databaseForTesting.close();
  });

  test('v4 铃声记录可保存并按校验值读取', () async {
    final store = SqliteLocalDataStore(
      factory: factory,
      databasePath: databasePath,
    );
    await store.initialize();
    final sounds = LocalAlarmSoundRepository(store);
    final now = DateTime(2026, 8, 2);
    await sounds.add(
      AlarmSound(
        id: 'sound-1',
        displayName: '迁移铃声',
        internalPath: '/files/sound-1.mp3',
        sourceName: 'sound.mp3',
        mimeType: 'audio/mpeg',
        format: 'mp3',
        fileSize: 1024,
        durationMilliseconds: 3000,
        checksum: 'sha256-value',
        importedAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect((await sounds.findByChecksum('sha256-value'))?.id, 'sound-1');
    await store.databaseForTesting.close();
  });
}
