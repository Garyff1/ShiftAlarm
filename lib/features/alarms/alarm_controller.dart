import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/alarm_record.dart';
import '../../data/models/alarm_lifecycle_event.dart';
import '../../data/models/alarm_sound.dart';
import '../../data/models/app_enums.dart';
import '../../data/repositories/alarm_record_repository.dart';
import '../../data/repositories/alarm_lifecycle_repository.dart';
import '../../core/utils/id_generator.dart';
import '../../services/alarm/alarm_diagnostic_service.dart';
import '../../services/alarm/diagnostic_report_service.dart';
import '../../services/alarm/alarm_sync_coordinator.dart';
import '../../services/alarm/native_alarm_scheduler.dart';

class AlarmController extends ChangeNotifier {
  AlarmController({
    required this.coordinator,
    required this.repository,
    required this.nativeScheduler,
    this.lifecycleRepository,
    this.diagnosticService = const AlarmDiagnosticService(),
    this.reportService = const DiagnosticReportService(),
  });

  final AlarmSyncCoordinator coordinator;
  final AlarmRecordRepository repository;
  final NativeAlarmScheduler nativeScheduler;
  final AlarmLifecycleRepository? lifecycleRepository;
  final AlarmDiagnosticService diagnosticService;
  final DiagnosticReportService reportService;
  AlarmPermissionState permissions = const AlarmPermissionState.unavailable();
  List<AlarmRecord> records = const [];
  bool isLoading = true;
  bool isSyncing = false;
  String? errorMessage;
  AlarmSyncResult? lastSyncResult;
  DateTime? lastSyncAt;
  List<AlarmLifecycleEvent> lifecycleEvents = const [];
  NativeAppStartupInfo startupInfo = const NativeAppStartupInfo.unsupported();
  bool forceStopRecoveredThisLaunch = false;
  String? forceStopRecoveryMessage;
  bool _startupChecked = false;
  bool isExportingDiagnostics = false;
  DateTime? testTriggerAt;
  String testStatus = '未测试';
  AlarmTestMode? activeTestMode;
  Timer? _testTimer;
  StreamSubscription<void>? _recordSubscription;
  StreamSubscription<void>? _lifecycleSubscription;

  AlarmRecord? get nextRegistered => records
      .where(
        (item) =>
            item.status == AlarmStatus.registered &&
            item.triggerAt.isAfter(DateTime.now()),
      )
      .firstOrNull;

  List<AlarmRecord> get formalRecords =>
      records.where((item) => !item.isTest).toList();

  int get submittedFutureCount => formalRecords
      .where(
        (item) =>
            item.triggerAt.isAfter(DateTime.now()) && item.status.isActive,
      )
      .length;

  bool get hasHealthIssue =>
      !permissions.exactAlarm ||
      !permissions.notifications ||
      !permissions.fullScreenIntent ||
      permissions.volumeMuted ||
      lastSyncResult?.successful == false ||
      latestCustomSoundFailure != null ||
      latestCompletedDiagnostic?.state == AlarmDiagnosticState.failed;

  String get healthHeadline => hasHealthIssue ? '需要处理' : '一切正常';
  String get healthDescription => hasHealthIssue
      ? '有一项设置或最近一次响铃结果需要检查'
      : 'ShiftAlarm 已提交 $submittedFutureCount 个未来闹钟，最近一次同步成功';

  List<AlarmDiagnosticSummary> get diagnosticSummaries =>
      diagnosticService.build(
        alarms: formalRecords,
        events: lifecycleEvents,
        permissions: permissions,
      );

  AlarmDiagnosticSummary? get latestCompletedDiagnostic => diagnosticSummaries
      .where((item) => item.alarm.triggerAt.isBefore(DateTime.now()))
      .firstOrNull;

  AlarmLifecycleEvent? get latestDirectBootEvent => lifecycleEvents
      .where((item) => item.stage == AlarmLifecycleStage.directBootRestored)
      .firstOrNull;

  AlarmLifecycleEvent? get latestTimezoneEvent => lifecycleEvents
      .where(
        (item) =>
            item.stage == AlarmLifecycleStage.timezoneRecalculated ||
            item.stage == AlarmLifecycleStage.timeRecalculated,
      )
      .firstOrNull;

  AlarmLifecycleEvent? get latestForceStopEvent => lifecycleEvents
      .where((item) => item.stage == AlarmLifecycleStage.appWasForceStopped)
      .firstOrNull;

  AlarmLifecycleEvent? get latestCustomSoundFailure => lifecycleEvents
      .where(
        (item) =>
            item.failureCategory == AlarmFailureCategory.customSoundUnavailable,
      )
      .firstOrNull;

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
    _lifecycleSubscription ??= lifecycleRepository?.watch().listen(
      (_) => loadLifecycleEvents(),
    );
    await _checkStartupInfo();
    await refreshPermissions();
    await _reconcileEvents();
    await loadRecords();
    await loadLifecycleEvents();
    await _recordUnconfirmedDeliveries();
    // Android 15/API 35 introduced a reliable force-stop startup signal. On
    // older releases we cannot distinguish a force stop from another cold
    // start, so re-register with stable PendingIntent IDs. The operation is
    // idempotent and prevents a stale local `registered` row from suppressing
    // recovery after the system removed its PendingIntent.
    final forceReschedule =
        startupInfo.wasForceStopped || !startupInfo.supported;
    final result = await synchronize(
      showLoading: false,
      forceReschedule: forceReschedule,
    );
    if (startupInfo.wasForceStopped && result != null) {
      await _appendSystemLifecycle(
        AlarmLifecycleStage.forceStopRecovered,
        details: {
          'registered': result.registered,
          'cancelled': result.cancelled,
          'failed': result.failed,
        },
      );
      forceStopRecoveredThisLaunch = result.failed == 0;
      forceStopRecoveryMessage = result.failed == 0
          ? 'ShiftAlarm 曾被“强行停止”，系统可能移除了之前设置的闹钟。未来闹钟已重新恢复。'
          : '检测到 ShiftAlarm 曾被“强行停止”，部分未来闹钟恢复失败，请打开闹钟健康中心处理。';
    }
    await loadLifecycleEvents();
    isLoading = false;
    notifyListeners();
  }

  Future<void> handleResume() async {
    await refreshPermissions();
    await _reconcileEvents();
    await loadRecords();
    await loadLifecycleEvents();
    await _recordUnconfirmedDeliveries();
    await synchronize(showLoading: false);
  }

  Future<void> _checkStartupInfo() async {
    if (_startupChecked) return;
    _startupChecked = true;
    try {
      startupInfo = await nativeScheduler.getStartupInfo();
      if (startupInfo.wasForceStopped) {
        await _appendSystemLifecycle(
          AlarmLifecycleStage.appWasForceStopped,
          failureCategory: AlarmFailureCategory.appForceStopped,
          details: {
            'startReason': startupInfo.reason,
            'startType': startupInfo.startType,
            'startComponent': startupInfo.startComponent,
          },
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 启动原因读取失败: $error\n$stackTrace');
    }
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

  Future<void> loadLifecycleEvents() async {
    final lifecycle = lifecycleRepository;
    if (lifecycle == null) return;
    lifecycleEvents = (await lifecycle.getAll())
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    notifyListeners();
  }

  Future<AlarmSyncResult?> synchronize({
    bool showLoading = true,
    bool forceReschedule = false,
  }) async {
    if (isSyncing) return lastSyncResult;
    isSyncing = true;
    if (showLoading) notifyListeners();
    try {
      lastSyncResult = await coordinator.synchronizeAll(
        forceReschedule: forceReschedule,
      );
      lastSyncAt = DateTime.now();
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

  Future<void> _recordUnconfirmedDeliveries() async {
    final lifecycle = lifecycleRepository;
    if (lifecycle == null) return;
    final existingFailureAlarmIds = lifecycleEvents
        .where((item) => item.stage == AlarmLifecycleStage.diagnosticFailure)
        .map((item) => item.alarmId)
        .toSet();
    final failures = diagnosticSummaries.where(
      (item) =>
          item.state == AlarmDiagnosticState.failed &&
          item.failureCategory != null &&
          !existingFailureAlarmIds.contains(item.alarm.id),
    );
    final inferred = failures.map(
      (summary) => AlarmLifecycleEvent(
        id: IdGenerator.create('alarm_event'),
        alarmId: summary.alarm.id,
        scheduleId: summary.alarm.scheduleId,
        nativeAlarmId: summary.alarm.nativeAlarmId,
        stage: AlarmLifecycleStage.diagnosticFailure,
        occurredAt: DateTime.now(),
        plannedTriggerAt: summary.alarm.triggerAt,
        failureCategory: summary.failureCategory,
        details: const {'inferred': true},
      ),
    );
    if (inferred.isNotEmpty) {
      await lifecycle.appendAll(inferred);
      await loadLifecycleEvents();
    }
  }

  Future<AlarmSyncResult?> runHealthCheck() async {
    await refreshPermissions();
    await _reconcileEvents();
    await loadLifecycleEvents();
    await _recordUnconfirmedDeliveries();
    return synchronize(showLoading: true);
  }

  Future<bool> exportDiagnosticReport() async {
    if (isExportingDiagnostics) return false;
    isExportingDiagnostics = true;
    notifyListeners();
    try {
      await _reconcileEvents();
      await loadLifecycleEvents();
      final device = await nativeScheduler.getDeviceInfo();
      final report = reportService.build(
        device: device,
        startup: startupInfo,
        permissions: permissions,
        alarms: records,
        lifecycleEvents: lifecycleEvents,
        lastSync: lastSyncResult,
        lastSyncAt: lastSyncAt,
      );
      return await nativeScheduler.shareDiagnosticReport(
        json: report.json,
        summary: report.summary,
      );
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 诊断报告导出失败: $error\n$stackTrace');
      errorMessage = '诊断报告导出失败，请重试';
      return false;
    } finally {
      isExportingDiagnostics = false;
      notifyListeners();
    }
  }

  Future<void> _appendSystemLifecycle(
    AlarmLifecycleStage stage, {
    AlarmFailureCategory? failureCategory,
    Map<String, Object?> details = const {},
  }) async {
    await lifecycleRepository?.append(
      AlarmLifecycleEvent(
        id: IdGenerator.create('alarm_event'),
        alarmId: 'system',
        stage: stage,
        occurredAt: DateTime.now(),
        failureCategory: failureCategory,
        details: details,
      ),
    );
  }

  Future<bool> startTestAlarm({
    int delaySeconds = 60,
    AlarmTestMode mode = AlarmTestMode.standard,
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
      mode: mode,
      sound: sound,
    );
    if (!result.success) {
      testStatus = '测试登记失败：${result.error ?? '未知错误'}';
      notifyListeners();
      return false;
    }
    testTriggerAt = DateTime.now().add(Duration(seconds: delaySeconds));
    activeTestMode = mode;
    testStatus = '${mode.label}闹钟等待触发';
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
    activeTestMode = null;
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
    _lifecycleSubscription?.cancel();
    _testTimer?.cancel();
    super.dispose();
  }
}
