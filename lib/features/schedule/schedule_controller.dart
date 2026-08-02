import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../data/models/daily_schedule.dart';
import '../../data/models/schedule_change_log.dart';
import '../../data/models/shift_template.dart';
import '../../data/repositories/daily_schedule_repository.dart';
import '../../data/repositories/schedule_change_log_repository.dart';
import '../../data/repositories/schedule_operation_models.dart';
import '../../data/repositories/shift_template_repository.dart';

class ScheduleController extends ChangeNotifier {
  ScheduleController({
    required this.repository,
    required this.changeLogRepository,
    required this.shiftRepository,
  });

  final DailyScheduleRepository repository;
  final ScheduleChangeLogRepository changeLogRepository;
  final ShiftTemplateRepository shiftRepository;
  final List<StreamSubscription<void>> _subscriptions = [];

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime get selectedMonth => _selectedMonth;
  Map<String, DailySchedule> schedules = const {};
  Map<String, ShiftTemplate> templates = const {};
  List<ScheduleChangeLog> changeLogs = const [];
  DailySchedule? todaySchedule;
  DailySchedule? tomorrowSchedule;
  bool isLoading = true;
  bool isOperating = false;
  String? errorMessage;
  bool batchMode = false;
  final Set<String> selectedDateKeys = {};

  ShiftTemplate? shiftFor(DailySchedule? schedule) =>
      schedule == null ? null : templates[schedule.shiftTemplateId];

  ShiftTemplate? originalShiftFor(DailySchedule? schedule) =>
      schedule == null ? null : templates[schedule.originalShiftTemplateId];

  DailySchedule? scheduleFor(DateTime date) =>
      schedules[DailySchedule.dateKeyOf(date)];

  List<ShiftTemplate> get enabledTemplates =>
      templates.values.where((item) => item.isEnabled).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<void> initialize() async {
    _subscriptions.add(
      repository.watch().listen((_) => refresh(showLoading: false)),
    );
    _subscriptions.add(changeLogRepository.watch().listen((_) => loadLogs()));
    _subscriptions.add(
      shiftRepository.watch().listen((_) => refresh(showLoading: false)),
    );
    await refresh();
  }

  Future<void> refresh({bool showLoading = true}) async {
    if (showLoading) {
      isLoading = true;
      notifyListeners();
    }
    try {
      final allTemplates = await shiftRepository.getAll();
      templates = {for (final item in allTemplates) item.id: item};
      final monthSchedules = await repository.getByMonth(_selectedMonth);
      schedules = {for (final item in monthSchedules) item.dateKey: item};
      todaySchedule = await repository.getToday();
      tomorrowSchedule = await repository.getTomorrow();
      await loadLogs(notify: false);
      errorMessage = null;
    } on AppException catch (error) {
      errorMessage = error.userMessage;
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 排班刷新失败: $error\n$stackTrace');
      errorMessage = '排班加载失败，请重试';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadLogs({bool notify = true}) async {
    changeLogs = await changeLogRepository.getByDateRange(
      DateTime(_selectedMonth.year, _selectedMonth.month),
      DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0),
    );
    if (notify) notifyListeners();
  }

  Future<void> changeMonth(int offset) async {
    _selectedMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + offset,
    );
    clearSelection();
    await refresh();
  }

  Future<void> selectMonth(DateTime month) async {
    _selectedMonth = DateTime(month.year, month.month);
    clearSelection();
    await refresh();
  }

  Future<void> goToToday() async {
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    clearSelection();
    await refresh();
  }

  Future<void> refreshForClockChange({
    required DateTime previous,
    required DateTime current,
  }) async {
    final wasViewingCurrentMonth =
        _selectedMonth.year == previous.year &&
        _selectedMonth.month == previous.month;
    final monthChanged =
        current.year != previous.year || current.month != previous.month;
    if (wasViewingCurrentMonth && monthChanged) {
      _selectedMonth = DateTime(current.year, current.month);
      clearSelection();
    }
    await refresh(showLoading: false);
  }

  Future<T?> _operate<T>(Future<T> Function() action) async {
    if (isOperating) return null;
    isOperating = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await action();
      await refresh(showLoading: false);
      return result;
    } on AppException catch (error) {
      errorMessage = error.userMessage;
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 排班操作失败: $error\n$stackTrace');
      errorMessage = '排班操作失败，请重试';
      rethrow;
    } finally {
      isOperating = false;
      notifyListeners();
    }
  }

  Future<DailySchedule?> setShift(
    DateTime date,
    ShiftTemplate shift, {
    String reason = '',
  }) => _operate(
    () =>
        repository.setShift(date, shift, reason: reason, templates: templates),
  );

  Future<DailySchedule?> restore(DateTime date) =>
      _operate(() => repository.restoreOriginal(date, templates: templates));

  Future<void> deleteDate(DateTime date) async {
    await _operate(() => repository.deleteByDate(date, templates: templates));
  }

  Future<BatchScheduleResult?> applyBatch(
    ShiftTemplate shift, {
    required bool overwriteExisting,
  }) async {
    final dates = selectedDateKeys.map(DateTime.parse).toList();
    final result = await _operate(
      () => repository.batchSet(
        dates,
        shift,
        overwriteExisting: overwriteExisting,
        templates: templates,
      ),
    );
    clearSelection();
    return result;
  }

  Future<void> clearBatch() async {
    final dates = selectedDateKeys.map(DateTime.parse).toList();
    await _operate(() => repository.batchDelete(dates, templates: templates));
    clearSelection();
  }

  Future<void> swap(DateTime first, DateTime second) async {
    await _operate(
      () => repository.swapDates(first, second, templates: templates),
    );
  }

  Future<void> updateNote(DateTime date, String note) async {
    await _operate(() => repository.updateNote(date, note));
  }

  Future<void> setRemindersPaused(DateTime date, bool paused) async {
    await _operate(() => repository.setRemindersPaused(date, paused));
  }

  Future<DailySchedule?> copyTo(
    DailySchedule source,
    DateTime target, {
    required bool overwriteExisting,
    bool copyNote = false,
  }) {
    final shift = templates[source.shiftTemplateId];
    if (shift == null) throw const ValidationException('当前班次数据缺失，无法复制');
    return _operate(
      () => repository.copyToDate(
        source,
        target,
        shift,
        overwriteExisting: overwriteExisting,
        copyNote: copyNote,
      ),
    );
  }

  void enterBatch(DateTime initialDate) {
    batchMode = true;
    selectedDateKeys
      ..clear()
      ..add(DailySchedule.dateKeyOf(initialDate));
    notifyListeners();
  }

  void toggleDate(DateTime date) {
    final key = DailySchedule.dateKeyOf(date);
    if (!selectedDateKeys.remove(key)) selectedDateKeys.add(key);
    if (selectedDateKeys.isEmpty) batchMode = false;
    notifyListeners();
  }

  void clearSelection() {
    batchMode = false;
    selectedDateKeys.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
