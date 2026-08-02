abstract interface class LocalDataTransaction {
  Future<List<String>> readAll(String collection);
  Future<List<String>> readRange(
    String collection,
    String startKey,
    String endKey,
  );
  Future<String?> readById(String collection, String id);
  Future<String?> readByUniqueKey(String collection, String uniqueKey);
  Future<void> write(
    String collection,
    String id,
    String payload, {
    String? uniqueKey,
  });
  Future<void> delete(String collection, String id);
  Future<int> countReferences(String collection, String referenceId);
}

abstract interface class LocalDataStore implements LocalDataTransaction {
  Future<void> initialize();
  Future<void> clear(String collection);
  Stream<void> watch(String collection);

  /// Executes all operations atomically and emits collection changes only after commit.
  Future<T> runTransaction<T>(
    Set<String> changedCollections,
    Future<T> Function(LocalDataTransaction transaction) operation,
  );
}
