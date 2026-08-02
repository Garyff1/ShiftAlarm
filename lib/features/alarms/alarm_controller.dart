import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/alarm_record.dart';
import '../../data/models/alarm_sound.dart';
import '../../data/models/app_enums.dart';
import '../../data/repositories/alarm_record_repository.dart';
import '../../services/alarm/alarm_sync_coordinator.dart';
import '../../services/alarm/native_alarm_scheduler.dart';

class AlarmController extends ChangeNotifier {
  AlarmController({
    required this.coordinator,
    required this.repository,
    required this.nativeScheduler,
  });

  final AlarmSyncCoordinator coordinator;
  final AlarmRecordRepository repository;
  final NativeAlarmScheduler nativeScheduler;
  AlarmPermissionState permissions = const AlarmPermissionState.unavailable();
  List<AlarmRecord> records = const [];
  bool isLoading = true;
  bool isSyncing = false;
  String? errorMessage;
  AlarmSyncResult? lastSyncResult;
  DateTime? testTriggerAt;
  String testStatus = '未测试';
  Timer? _testTimer;
  StreamSubscription<void>? _recordSubscription;

  AlarmRecord? get nextRegistered => records
      .where(
        (item) =>
            item.status == AlarmStatus.registered &&
            item.triggerAt.isAfter(DateTime.now()),
      )
      .firstOrNull;

  List<AlarmRecord> get formalRecords =>
      records.where((item) => !item.isTest).toList();

  int? get testRemainingSeconds {
    final trigger = testTriggerAt;
    if (trigger == null) return null;
    return trigger.difference(DateTime.now()).inSeconds.clamp(0, 3600);
  }

  String get overallStatus {
    if (!permissions.exactAlarm) return '闹钟尚未生效';
    if (!permissions.notifications || !permissions.fullScreenIntent) {
      return '部分功能受限';
    }
    if (permissions.volumeMuted) return '闹钟音量已静音';
    return '所有权限正常';
  }

  Future<void> initialize() async {
    _recordSubscription ??= repository.watch().listen((_) => loadRecords());
    await refreshPermissions();
    await _reconcileEvents();
    await synchronize(showLoading: false);
    isLoading = false;
    notifyListeners();
  }

  Future<void> handleResume() async {
    await refreshPermissions();
    await _reconcileEvents();
    await synchronize(showLoading: false);
  }

  Future<void> refreshPermissions() async {
    try {
      permissions = await nativeScheduler.getPermissionState();
      errorMessage = null;
    } catch (error) {
      errorMessage = '权限状态读取失败：$error';
    }
    notifyListeners();
  }

  Future<void> loadRecords() async {
    records = await repository.getAll();
    records = records.reversed.toList()
      ..sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
    notifyListeners();
  }

  Future<AlarmSyncResult?> synchronize({bool showLoading = true}) async {
    if (isSyncing) return lastSyncResult;
    isSyncing = true;
    if (showLoading) notifyListeners();
    try {
      lastSyncResult = await coordinator.synchronizeAll();
      await loadRecords();
      errorMessage = null;
      return lastSyncResult;
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 闹钟同步失败: $error\n$stackTrace');
      errorMessage = '闹钟同步失败，请重试';
      return null;
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _reconcileEvents() async {
    final testEvents = await coordinator.reconcileNativeEvents();
    for (final event in testEvents) {
      final status = event['status']?.toString();
      testStatus = switch (status) {
        'ringing' => '测试闹钟已触发',
        'snoozed' => '测试闹钟已贪睡',
        'dismissed' => '测试通过',
        'triggered' => '测试闹钟未响应',
        'recovered' => '系统已恢复闹钟',
        _ => testStatus,
      };
      if (status == 'dismissed' || status == 'triggered') {
        testTriggerAt = null;
        _testTimer?.cancel();
      }
    }
    await loadRecords();
  }

  Future<bool> startTestAlarm({
    int delaySeconds = 60,
    AlarmSound? sound,
  }) async {
    await refreshPermissions();
    if (!permissions.exactAlarm) {
      testStatus = '精确闹钟权限未开启';
      notifyListeners();
      return false;
    }
    final result = await nativeScheduler.scheduleTestAlarm(
      delaySeconds: delaySeconds,
      sound: sound,
    );
    if (!result.success) {
      testStatus = '测试登记失败：${result.error ?? '未知错误'}';
      notifyListeners();
      return false;
    }
    testTriggerAt = DateTime.now().add(Duration(seconds: delaySeconds));
    testStatus = '测试闹钟等待触发';
    _testTimer?.cancel();
    _testTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
      if (testRemainingSeconds == 0) _testTimer?.cancel();
    });
    notifyListeners();
    return true;
  }

  Future<void> cancelTestAlarm() async {
    await nativeScheduler.cancelTestAlarm();
    _testTimer?.cancel();
    testTriggerAt = null;
    testStatus = '测试已取消';
    notifyListeners();
  }

  Future<void> openExactAlarmSettings() =>
      nativeScheduler.openExactAlarmSettings();
  Future<bool> requestNotificationPermission() async {
    final granted = await nativeScheduler.requestNotificationPermission();
    await refreshPermissions();
    return granted;
  }

  Future<void> openNotificationSettings() =>
      nativeScheduler.openNotificationSettings();
  Future<void> openFullScreenIntentSettings() =>
      nativeScheduler.openFullScreenIntentSettings();
  Future<void> openAlarmVolumeSettings() =>
      nativeScheduler.openAlarmVolumeSettings();
  Future<void> openBatterySettings() => nativeScheduler.openBatterySettings();

  @override
  void dispose() {
    _recordSubscription?.cancel();
    _testTimer?.cancel();
    super.dispose();
  }
}
