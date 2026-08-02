abstract final class IdGenerator {
  static int _counter = 0;

  static String create(String prefix) {
    _counter = (_counter + 1) % 100000;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }
}
