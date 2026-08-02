import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import 'local_data_store.dart';

class SqliteLocalDataStore implements LocalDataStore {
  SqliteLocalDataStore({DatabaseFactory? factory, this.databasePath})
    : _factory = factory ?? databaseFactory;

  final DatabaseFactory _factory;
  final String? databasePath;
  Database? _database;
  final Map<String, StreamController<void>> _controllers = {};

  static const scheduleCollection = 'daily_schedules';
  static const changeLogCollection = 'schedule_change_logs';
  static const alarmCollection = 'alarm_records';
  static const soundCollection = 'alarm_sounds';
  static const allowedCollections = {
    'shift_templates',
    scheduleCollection,
    alarmCollection,
    soundCollection,
    changeLogCollection,
  };

  @visibleForTesting
  Database get databaseForTesting => _db;

  @override
  Future<void> initialize() async {
    if (_database != null) return;
    try {
      final root = databasePath == null ? await getDatabasesPath() : null;
      final path = databasePath ?? p.join(root!, AppConstants.databaseName);
      _database = await _factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: AppConstants.databaseVersion,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) async {
            await _createVersionOne(db);
            await _createVersionTwo(db);
            await _createVersionThree(db);
            await _createVersionFour(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) await _migrateVersionOneToTwo(db);
            if (oldVersion < 3) await _migrateVersionTwoToThree(db);
            if (oldVersion < 4) await _migrateVersionThreeToFour(db);
          },
        ),
      );
    } catch (error, stackTrace) {
      _log('数据库初始化或迁移失败', error, stackTrace);
      throw StorageException('本地数据升级失败，原数据未被清空，请重新打开应用', cause: error);
    }
  }

  static Future<void> _createVersionOne(DatabaseExecutor db) async {
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
    await db.execute('''
      CREATE UNIQUE INDEX records_unique_key
      ON records(collection, unique_key)
      WHERE unique_key IS NOT NULL
    ''');
    await db.execute(
      'CREATE INDEX records_updated_at ON records(collection, updated_at)',
    );
  }

  static Future<void> _createVersionTwo(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_schedules (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        shift_template_id TEXT NOT NULL,
        original_shift_template_id TEXT,
        payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS daily_schedules_date_unique ON daily_schedules(date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS daily_schedules_shift_template_id ON daily_schedules(shift_template_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS daily_schedules_original_shift_template_id ON daily_schedules(original_shift_template_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schedule_change_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        original_shift_template_id TEXT,
        new_shift_template_id TEXT,
        created_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS schedule_change_logs_date ON schedule_change_logs(date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS schedule_change_logs_created_at ON schedule_change_logs(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS schedule_change_logs_original_shift ON schedule_change_logs(original_shift_template_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS schedule_change_logs_new_shift ON schedule_change_logs(new_shift_template_id)',
    );
  }

  static Future<void> _createVersionThree(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alarm_records (
        id TEXT PRIMARY KEY,
        stable_key TEXT NOT NULL,
        schedule_id TEXT NOT NULL,
        trigger_at INTEGER NOT NULL,
        native_alarm_id INTEGER,
        sound_id TEXT,
        status TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS alarm_records_stable_key ON alarm_records(stable_key)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS alarm_records_native_id ON alarm_records(native_alarm_id) WHERE native_alarm_id IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS alarm_records_schedule_id ON alarm_records(schedule_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS alarm_records_trigger_at ON alarm_records(trigger_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS alarm_records_status ON alarm_records(status)',
    );
  }

  static Future<void> _createVersionFour(DatabaseExecutor db) async {
    final alarmColumns = await db.rawQuery('PRAGMA table_info(alarm_records)');
    if (!alarmColumns.any((row) => row['name'] == 'sound_id')) {
      await db.execute('ALTER TABLE alarm_records ADD COLUMN sound_id TEXT');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS alarm_records_sound_id ON alarm_records(sound_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alarm_sounds (
        id TEXT PRIMARY KEY,
        checksum TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_available INTEGER NOT NULL DEFAULT 1,
        payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS alarm_sounds_checksum ON alarm_sounds(checksum)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS alarm_sounds_is_default ON alarm_sounds(is_default)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS alarm_sounds_is_available ON alarm_sounds(is_available)',
    );
  }

  static Future<void> _migrateVersionThreeToFour(DatabaseExecutor db) async {
    await _createVersionFour(db);
    final oldRows = await db.query(
      'records',
      where: 'collection = ?',
      whereArgs: [soundCollection],
    );
    for (final row in oldRows) {
      final id = row['id'] as String;
      try {
        final payload = row['payload'] as String;
        final map = jsonDecode(payload) as Map<String, dynamic>;
        await _writeSound(db, id, payload, map);
        await db.delete(
          'records',
          where: 'collection = ? AND id = ?',
          whereArgs: [soundCollection, id],
        );
      } catch (error, stackTrace) {
        debugPrint(
          '[ShiftAlarm] v4 迁移跳过损坏记录 $soundCollection/$id: $error\n$stackTrace',
        );
      }
    }
  }

  static Future<void> _migrateVersionTwoToThree(DatabaseExecutor db) async {
    await _createVersionThree(db);
    final oldRows = await db.query(
      'records',
      where: 'collection = ?',
      whereArgs: [alarmCollection],
    );
    for (final row in oldRows) {
      final id = row['id'] as String;
      try {
        final payload = row['payload'] as String;
        final map = jsonDecode(payload) as Map<String, dynamic>;
        await _writeAlarm(db, id, payload, map, row['unique_key'] as String?);
        await db.delete(
          'records',
          where: 'collection = ? AND id = ?',
          whereArgs: [alarmCollection, id],
        );
      } catch (error, stackTrace) {
        debugPrint(
          '[ShiftAlarm] v3 迁移跳过损坏记录 $alarmCollection/$id: $error\n$stackTrace',
        );
      }
    }
  }

  static Future<void> _migrateVersionOneToTwo(DatabaseExecutor db) async {
    await _createVersionTwo(db);
    final oldRows = await db.query(
      'records',
      where: 'collection IN (?, ?)',
      whereArgs: [scheduleCollection, changeLogCollection],
    );
    for (final row in oldRows) {
      final collection = row['collection'] as String;
      final id = row['id'] as String;
      try {
        final payload = row['payload'] as String;
        final map = jsonDecode(payload) as Map<String, dynamic>;
        if (collection == scheduleCollection) {
          await _writeSchedule(
            db,
            id,
            payload,
            map,
            row['unique_key'] as String?,
          );
        } else {
          await _writeChangeLog(db, id, payload, map);
        }
        await db.delete(
          'records',
          where: 'collection = ? AND id = ?',
          whereArgs: [collection, id],
        );
      } catch (error, stackTrace) {
        debugPrint(
          '[ShiftAlarm] v2 迁移跳过损坏记录 $collection/$id: $error\n$stackTrace',
        );
      }
    }
  }

  static String _dateKeyFromMap(Map<String, dynamic> map, {String? fallback}) {
    final explicit = map['dateKey'];
    if (explicit is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(explicit)) {
      return explicit;
    }
    if (fallback != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(fallback)) {
      return fallback;
    }
    final value = map['date'];
    DateTime date;
    if (value is int) {
      date = DateTime.fromMillisecondsSinceEpoch(value);
    } else {
      date =
          DateTime.tryParse(value?.toString() ?? '') ??
          (throw const FormatException('invalid date'));
    }
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Database get _db {
    final database = _database;
    if (database == null) throw const StorageException('本地数据尚未初始化');
    return database;
  }

  void _validateCollection(String collection) {
    if (!allowedCollections.contains(collection)) {
      throw StorageException('不支持的数据类型：$collection');
    }
  }

  static Future<List<String>> _readAll(
    DatabaseExecutor db,
    String collection,
  ) async {
    if (collection == scheduleCollection) {
      final rows = await db.query(
        scheduleCollection,
        columns: ['payload'],
        orderBy: 'date ASC',
      );
      return rows.map((row) => row['payload'] as String).toList();
    }
    if (collection == changeLogCollection) {
      final rows = await db.query(
        changeLogCollection,
        columns: ['payload'],
        orderBy: 'created_at DESC',
      );
      return rows.map((row) => row['payload'] as String).toList();
    }
    if (collection == alarmCollection) {
      final rows = await db.query(
        alarmCollection,
        columns: ['payload'],
        orderBy: 'trigger_at ASC',
      );
      return rows.map((row) => row['payload'] as String).toList();
    }
    if (collection == soundCollection) {
      final rows = await db.query(
        soundCollection,
        columns: ['payload'],
        orderBy: 'is_default DESC, updated_at DESC',
      );
      return rows.map((row) => row['payload'] as String).toList();
    }
    final rows = await db.query(
      'records',
      columns: ['payload'],
      where: 'collection = ?',
      whereArgs: [collection],
      orderBy: 'updated_at ASC',
    );
    return rows.map((row) => row['payload'] as String).toList();
  }

  @override
  Future<List<String>> readAll(String collection) async {
    _validateCollection(collection);
    try {
      return await _readAll(_db, collection);
    } catch (error, stackTrace) {
      _log('读取 $collection 失败', error, stackTrace);
      throw StorageException('读取本地数据失败，请重试', cause: error);
    }
  }

  static Future<List<String>> _readRange(
    DatabaseExecutor db,
    String collection,
    String startKey,
    String endKey,
  ) async {
    if (collection != scheduleCollection && collection != changeLogCollection) {
      return _readAll(db, collection);
    }
    final rows = await db.query(
      collection,
      columns: ['payload'],
      where: 'date >= ? AND date <= ?',
      whereArgs: [startKey, endKey],
      orderBy: collection == scheduleCollection
          ? 'date ASC'
          : 'created_at DESC',
    );
    return rows.map((row) => row['payload'] as String).toList();
  }

  @override
  Future<List<String>> readRange(
    String collection,
    String startKey,
    String endKey,
  ) async {
    _validateCollection(collection);
    return _readRange(_db, collection, startKey, endKey);
  }

  static Future<String?> _readById(
    DatabaseExecutor db,
    String collection,
    String id,
  ) async {
    final table =
        collection == scheduleCollection ||
            collection == changeLogCollection ||
            collection == alarmCollection ||
            collection == soundCollection
        ? collection
        : 'records';
    final rows = await db.query(
      table,
      columns: ['payload'],
      where: table == 'records' ? 'collection = ? AND id = ?' : 'id = ?',
      whereArgs: table == 'records' ? [collection, id] : [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['payload'] as String;
  }

  @override
  Future<String?> readById(String collection, String id) async {
    _validateCollection(collection);
    return _readById(_db, collection, id);
  }

  static Future<String?> _readByUniqueKey(
    DatabaseExecutor db,
    String collection,
    String uniqueKey,
  ) async {
    if (collection == scheduleCollection) {
      final rows = await db.query(
        scheduleCollection,
        columns: ['payload'],
        where: 'date = ?',
        whereArgs: [uniqueKey],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['payload'] as String;
    }
    if (collection == alarmCollection) {
      final rows = await db.query(
        alarmCollection,
        columns: ['payload'],
        where: 'stable_key = ?',
        whereArgs: [uniqueKey],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['payload'] as String;
    }
    if (collection == soundCollection) {
      final rows = await db.query(
        soundCollection,
        columns: ['payload'],
        where: 'checksum = ?',
        whereArgs: [uniqueKey],
        orderBy: 'updated_at DESC',
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['payload'] as String;
    }
    final rows = await db.query(
      'records',
      columns: ['payload'],
      where: 'collection = ? AND unique_key = ?',
      whereArgs: [collection, uniqueKey],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['payload'] as String;
  }

  @override
  Future<String?> readByUniqueKey(String collection, String uniqueKey) async {
    _validateCollection(collection);
    return _readByUniqueKey(_db, collection, uniqueKey);
  }

  static Future<void> _writeSchedule(
    DatabaseExecutor db,
    String id,
    String payload,
    Map<String, dynamic> map,
    String? uniqueKey,
  ) async {
    final values = <String, Object?>{
      'id': id,
      'date': _dateKeyFromMap(map, fallback: uniqueKey),
      'shift_template_id': map['shiftTemplateId']?.toString() ?? '',
      'original_shift_template_id': map['originalShiftTemplateId']?.toString(),
      'payload': payload,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    final updated = await db.update(
      scheduleCollection,
      values,
      where: 'id = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (updated == 0) {
      await db.insert(
        scheduleCollection,
        values,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  static Future<void> _writeChangeLog(
    DatabaseExecutor db,
    String id,
    String payload,
    Map<String, dynamic> map,
  ) async {
    final values = <String, Object?>{
      'id': id,
      'date': _dateKeyFromMap(map),
      'original_shift_template_id': map['originalShiftTemplateId']?.toString(),
      'new_shift_template_id': map['newShiftTemplateId']?.toString(),
      'created_at': map['createdAt'] is int
          ? map['createdAt']
          : DateTime.now().millisecondsSinceEpoch,
      'payload': payload,
    };
    final updated = await db.update(
      changeLogCollection,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) {
      await db.insert(
        changeLogCollection,
        values,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  static Future<void> _writeAlarm(
    DatabaseExecutor db,
    String id,
    String payload,
    Map<String, dynamic> map,
    String? uniqueKey,
  ) async {
    final stableKey =
        uniqueKey ??
        '${map['scheduleId'] ?? ''}:${map['reminderRuleId'] ?? ''}';
    final values = <String, Object?>{
      'id': id,
      'stable_key': stableKey,
      'schedule_id': map['scheduleId']?.toString() ?? '',
      'trigger_at': map['triggerAt'] is int
          ? map['triggerAt']
          : DateTime.now().millisecondsSinceEpoch,
      'native_alarm_id': map['nativeAlarmId'],
      'sound_id': map['soundId']?.toString(),
      'status': map['status']?.toString() ?? 'failed',
      'payload': payload,
      'updated_at': map['updatedAt'] is int
          ? map['updatedAt']
          : DateTime.now().millisecondsSinceEpoch,
    };
    final updated = await db.update(
      alarmCollection,
      values,
      where: 'id = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (updated == 0) {
      await db.insert(
        alarmCollection,
        values,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  static Future<void> _writeSound(
    DatabaseExecutor db,
    String id,
    String payload,
    Map<String, dynamic> map,
  ) async {
    final values = <String, Object?>{
      'id': id,
      'checksum': map['checksum']?.toString() ?? '',
      'is_default': map['isDefault'] == true ? 1 : 0,
      'is_available': map['isAvailable'] == false ? 0 : 1,
      'payload': payload,
      'updated_at': map['updatedAt'] is int
          ? map['updatedAt']
          : DateTime.now().millisecondsSinceEpoch,
    };
    final updated = await db.update(
      soundCollection,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) {
      await db.insert(
        soundCollection,
        values,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  static Future<void> _write(
    DatabaseExecutor db,
    String collection,
    String id,
    String payload, {
    String? uniqueKey,
  }) async {
    if (collection == scheduleCollection ||
        collection == changeLogCollection ||
        collection == alarmCollection ||
        collection == soundCollection) {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('record is not an object');
      }
      if (collection == scheduleCollection) {
        await _writeSchedule(db, id, payload, decoded, uniqueKey);
      } else if (collection == changeLogCollection) {
        await _writeChangeLog(db, id, payload, decoded);
      } else if (collection == soundCollection) {
        await _writeSound(db, id, payload, decoded);
      } else {
        await _writeAlarm(db, id, payload, decoded, uniqueKey);
      }
      return;
    }
    final values = {
      'collection': collection,
      'id': id,
      'unique_key': uniqueKey,
      'payload': payload,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    final updated = await db.update(
      'records',
      values,
      where: 'collection = ? AND id = ?',
      whereArgs: [collection, id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (updated == 0) {
      await db.insert(
        'records',
        values,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  @override
  Future<void> write(
    String collection,
    String id,
    String payload, {
    String? uniqueKey,
  }) async {
    _validateCollection(collection);
    try {
      await _db.transaction(
        (txn) => _write(txn, collection, id, payload, uniqueKey: uniqueKey),
      );
      _controllers[collection]?.add(null);
    } catch (error, stackTrace) {
      _log('写入 $collection 失败', error, stackTrace);
      throw StorageException('保存本地数据失败，请重试', cause: error);
    }
  }

  static Future<void> _delete(
    DatabaseExecutor db,
    String collection,
    String id,
  ) async {
    final table =
        collection == scheduleCollection ||
            collection == changeLogCollection ||
            collection == alarmCollection ||
            collection == soundCollection
        ? collection
        : 'records';
    await db.delete(
      table,
      where: table == 'records' ? 'collection = ? AND id = ?' : 'id = ?',
      whereArgs: table == 'records' ? [collection, id] : [id],
    );
  }

  @override
  Future<void> delete(String collection, String id) async {
    _validateCollection(collection);
    await _delete(_db, collection, id);
    _controllers[collection]?.add(null);
  }

  @override
  Future<void> clear(String collection) async {
    _validateCollection(collection);
    final table =
        collection == scheduleCollection ||
            collection == changeLogCollection ||
            collection == alarmCollection ||
            collection == soundCollection
        ? collection
        : 'records';
    await _db.delete(
      table,
      where: table == 'records' ? 'collection = ?' : null,
      whereArgs: table == 'records' ? [collection] : null,
    );
    _controllers[collection]?.add(null);
  }

  static Future<int> _countReferences(
    DatabaseExecutor db,
    String collection,
    String referenceId,
  ) async {
    if (collection == scheduleCollection) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM daily_schedules WHERE shift_template_id = ? OR original_shift_template_id = ?',
        [referenceId, referenceId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }
    if (collection == changeLogCollection) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM schedule_change_logs WHERE new_shift_template_id = ? OR original_shift_template_id = ?',
        [referenceId, referenceId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }
    return 0;
  }

  @override
  Future<int> countReferences(String collection, String referenceId) async {
    _validateCollection(collection);
    return _countReferences(_db, collection, referenceId);
  }

  @override
  Future<T> runTransaction<T>(
    Set<String> changedCollections,
    Future<T> Function(LocalDataTransaction transaction) operation,
  ) async {
    try {
      final result = await _db.transaction(
        (txn) => operation(_SqliteTransaction(txn)),
      );
      for (final collection in changedCollections) {
        _controllers[collection]?.add(null);
      }
      return result;
    } catch (error, stackTrace) {
      _log('数据库事务已回滚', error, stackTrace);
      throw StorageException('排班操作失败，所有修改已回滚', cause: error);
    }
  }

  @override
  Stream<void> watch(String collection) {
    _validateCollection(collection);
    return (_controllers[collection] ??= StreamController<void>.broadcast())
        .stream;
  }

  void _log(String message, Object error, StackTrace stackTrace) {
    debugPrint('[ShiftAlarm] $message: $error\n$stackTrace');
  }
}

class _SqliteTransaction implements LocalDataTransaction {
  _SqliteTransaction(this.transaction);
  final Transaction transaction;

  @override
  Future<int> countReferences(String collection, String referenceId) =>
      SqliteLocalDataStore._countReferences(
        transaction,
        collection,
        referenceId,
      );
  @override
  Future<void> delete(String collection, String id) =>
      SqliteLocalDataStore._delete(transaction, collection, id);
  @override
  Future<List<String>> readAll(String collection) =>
      SqliteLocalDataStore._readAll(transaction, collection);
  @override
  Future<String?> readById(String collection, String id) =>
      SqliteLocalDataStore._readById(transaction, collection, id);
  @override
  Future<String?> readByUniqueKey(String collection, String uniqueKey) =>
      SqliteLocalDataStore._readByUniqueKey(transaction, collection, uniqueKey);
  @override
  Future<List<String>> readRange(
    String collection,
    String startKey,
    String endKey,
  ) => SqliteLocalDataStore._readRange(
    transaction,
    collection,
    startKey,
    endKey,
  );
  @override
  Future<void> write(
    String collection,
    String id,
    String payload, {
    String? uniqueKey,
  }) => SqliteLocalDataStore._write(
    transaction,
    collection,
    id,
    payload,
    uniqueKey: uniqueKey,
  );
}
