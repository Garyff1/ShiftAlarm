import 'dart:async';
import 'dart:convert';
import 'local_data_store.dart';

class MemoryLocalDataStore implements LocalDataStore {
  MemoryLocalDataStore({Map<String, Map<String, MemoryRecord>>? seed})
    : records = seed ?? {};

  final Map<String, Map<String, MemoryRecord>> records;
  final Map<String, StreamController<void>> _controllers = {};
  bool failNextTransaction = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<String>> readAll(String collection) async {
    final result = records[collection]?.values.toList() ?? <MemoryRecord>[];
    result.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return result.map((item) => item.payload).toList();
  }

  @override
  Future<List<String>> readRange(
    String collection,
    String startKey,
    String endKey,
  ) async {
    final result = (records[collection]?.values ?? <MemoryRecord>[])
        .where(
          (item) =>
              item.uniqueKey != null &&
              item.uniqueKey!.compareTo(startKey) >= 0 &&
              item.uniqueKey!.compareTo(endKey) <= 0,
        )
        .toList();
    result.sort((a, b) => (a.uniqueKey ?? '').compareTo(b.uniqueKey ?? ''));
    return result.map((item) => item.payload).toList();
  }

  @override
  Future<String?> readById(String collection, String id) async =>
      records[collection]?[id]?.payload;

  @override
  Future<String?> readByUniqueKey(String collection, String uniqueKey) async {
    for (final record in records[collection]?.values ?? <MemoryRecord>[]) {
      if (record.uniqueKey == uniqueKey) return record.payload;
    }
    return null;
  }

  @override
  Future<void> write(
    String collection,
    String id,
    String payload, {
    String? uniqueKey,
  }) async {
    _writeWithoutNotification(collection, id, payload, uniqueKey: uniqueKey);
    _controllers[collection]?.add(null);
  }

  void _writeWithoutNotification(
    String collection,
    String id,
    String payload, {
    String? uniqueKey,
  }) {
    if (uniqueKey != null) {
      final duplicate =
          records[collection]?.entries.any(
            (entry) => entry.key != id && entry.value.uniqueKey == uniqueKey,
          ) ??
          false;
      if (duplicate) throw StateError('duplicate unique key');
    }
    (records[collection] ??= {})[id] = MemoryRecord(
      payload,
      uniqueKey,
      DateTime.now(),
    );
  }

  void seedRaw(
    String collection,
    String id,
    String payload, {
    String? uniqueKey,
  }) {
    (records[collection] ??= {})[id] = MemoryRecord(
      payload,
      uniqueKey,
      DateTime.now(),
    );
  }

  @override
  Future<void> delete(String collection, String id) async {
    records[collection]?.remove(id);
    _controllers[collection]?.add(null);
  }

  @override
  Future<void> clear(String collection) async {
    records[collection]?.clear();
    _controllers[collection]?.add(null);
  }

  @override
  Future<int> countReferences(String collection, String referenceId) async {
    var count = 0;
    for (final record in records[collection]?.values ?? <MemoryRecord>[]) {
      try {
        final map = jsonDecode(record.payload) as Map<String, dynamic>;
        if (collection == 'daily_schedules') {
          if (map['shiftTemplateId'] == referenceId ||
              map['originalShiftTemplateId'] == referenceId) {
            count++;
          }
        } else if (collection == 'schedule_change_logs') {
          if (map['newShiftTemplateId'] == referenceId ||
              map['originalShiftTemplateId'] == referenceId) {
            count++;
          }
        }
      } catch (_) {
        // Corrupt rows cannot safely be counted as a known reference.
      }
    }
    return count;
  }

  @override
  Future<T> runTransaction<T>(
    Set<String> changedCollections,
    Future<T> Function(LocalDataTransaction transaction) operation,
  ) async {
    final backup = <String, Map<String, MemoryRecord>>{
      for (final entry in records.entries)
        entry.key: Map<String, MemoryRecord>.of(entry.value),
    };
    try {
      final result = await operation(_MemoryTransaction(this));
      if (failNextTransaction) {
        failNextTransaction = false;
        throw StateError('simulated transaction failure');
      }
      for (final collection in changedCollections) {
        _controllers[collection]?.add(null);
      }
      return result;
    } catch (_) {
      records
        ..clear()
        ..addAll(backup);
      rethrow;
    }
  }

  @override
  Stream<void> watch(String collection) =>
      (_controllers[collection] ??= StreamController<void>.broadcast()).stream;
}

class _MemoryTransaction implements LocalDataTransaction {
  _MemoryTransaction(this.store);
  final MemoryLocalDataStore store;

  @override
  Future<int> countReferences(String collection, String referenceId) =>
      store.countReferences(collection, referenceId);
  @override
  Future<List<String>> readAll(String collection) => store.readAll(collection);
  @override
  Future<String?> readById(String collection, String id) =>
      store.readById(collection, id);
  @override
  Future<String?> readByUniqueKey(String collection, String uniqueKey) =>
      store.readByUniqueKey(collection, uniqueKey);
  @override
  Future<List<String>> readRange(
    String collection,
    String startKey,
    String endKey,
  ) => store.readRange(collection, startKey, endKey);

  @override
  Future<void> write(
    String collection,
    String id,
    String payload, {
    String? uniqueKey,
  }) async => store._writeWithoutNotification(
    collection,
    id,
    payload,
    uniqueKey: uniqueKey,
  );

  @override
  Future<void> delete(String collection, String id) async =>
      store.records[collection]?.remove(id);
}

class MemoryRecord {
  const MemoryRecord(this.payload, this.uniqueKey, this.updatedAt);
  final String payload;
  final String? uniqueKey;
  final DateTime updatedAt;
}
