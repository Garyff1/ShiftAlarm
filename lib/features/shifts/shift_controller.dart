import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../data/models/shift_template.dart';
import '../../data/repositories/shift_template_repository.dart';
import '../../services/alarm/alarm_sync_coordinator.dart';

class ShiftController extends ChangeNotifier {
  ShiftController(this.repository, {this.alarmSyncCoordinator});

  final ShiftTemplateRepository repository;
  final AlarmSyncCoordinator? alarmSyncCoordinator;
  List<ShiftTemplate> _items = const [];
  List<ShiftTemplate> get items => _items;
  bool isLoading = true;
  String? errorMessage;
  StreamSubscription<void>? _subscription;

  Future<void> initialize() async {
    _subscription ??= repository.watch().listen(
      (_) => load(showLoading: false),
    );
    await load();
  }

  Future<void> load({bool showLoading = true}) async {
    if (showLoading) {
      isLoading = true;
      notifyListeners();
    }
    try {
      _items = await repository.getAll();
      errorMessage = null;
    } on AppException catch (error) {
      errorMessage = error.userMessage;
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 班次加载失败: $error\n$stackTrace');
      errorMessage = '班次加载失败，请重试';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> save(ShiftTemplate item) async {
    final existing = await repository.getById(item.id);
    if (existing == null) {
      await repository.add(item);
    } else {
      await repository.update(item);
    }
    await load(showLoading: false);
    if (existing != null) {
      await alarmSyncCoordinator?.synchronizeAll();
    }
  }

  Future<void> delete(String id) async {
    final references = await repository.getReferenceSummary(id);
    if (references.isReferenced) {
      throw ValidationException(
        '该班次仍被 ${references.scheduleCount} 条排班和 ${references.changeLogCount} 条调班记录引用，请将班次设为停用',
      );
    }
    await repository.delete(id);
    await load(showLoading: false);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
