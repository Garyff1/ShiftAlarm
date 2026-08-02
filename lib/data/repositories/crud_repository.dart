abstract interface class CrudRepository<T> {
  Future<List<T>> getAll();
  Future<T?> getById(String id);
  Future<void> add(T item);
  Future<void> update(T item);
  Future<void> delete(String id);
  Stream<void> watch();
  Future<void> clearForTesting();
}
