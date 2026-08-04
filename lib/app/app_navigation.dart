import 'package:flutter/foundation.dart';

class AppNavigationController extends ChangeNotifier {
  int _index = 0;
  int get index => _index;

  void select(int index) {
    if (index == _index || index < 0 || index > 4) return;
    _index = index;
    notifyListeners();
  }

  void ensureWithin(int maximumIndex) {
    if (_index <= maximumIndex) return;
    _index = 0;
    notifyListeners();
  }
}
