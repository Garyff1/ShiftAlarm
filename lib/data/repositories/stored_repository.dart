import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../storage/local_data_store.dart';
import 'crud_repository.dart';

abstract class StoredRepository<T> implements CrudRepository<T> {
  StoredRepository(this.store);

  final LocalDataStore store;
  String get collection;
  String idOf(T item);
  Map<String, Object?> encode(T item);
  T decode(Map<String, Object?> map);
  String? uniqueKeyOf(T item) => null;

  @override
  Future<List<T>> getAll() async {
    final payloads = await store.readAll(collection);
    final result = <T>[];
    for (final payload in payloads) {
      try {
        final value = jsonDecode(payload);
        if (value is! Map<String, dynamic>) {
          throw const FormatException('record is not an object');
        }
        result.add(decode(value));
      } catch (error, stackTrace) {
        debugPrint('[ShiftAlarm] 已跳过损坏的 $collection 记录: $error\n$stackTrace');
      }
    }
    return result;
  }

  @override
  Future<T?> getById(String id) async {
    final payload = await store.readById(collection, id);
    if (payload == null) return null;
    try {
      final value = jsonDecode(payload);
      if (value is! Map<String, dynamic>) {
        throw const FormatException('record is not an object');
      }
      return decode(value);
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] $collection/$id 数据损坏: $error\n$stackTrace');
      return null;
    }
  }

  @override
  Future<void> add(T item) => _save(item);

  @override
  Future<void> update(T item) => _save(item);

  Future<void> _save(T item) async {
    try {
      await store.write(
        collection,
        idOf(item),
        jsonEncode(encode(item)),
        uniqueKey: uniqueKeyOf(item),
      );
    } on AppException {
      rethrow;
    } catch (error) {
      throw StorageException('保存数据失败，请重试', cause: error);
    }
  }

  @override
  Future<void> delete(String id) => store.delete(collection, id);

  @override
  Stream<void> watch() => store.watch(collection);

  @override
  Future<void> clearForTesting() => store.clear(collection);
}
