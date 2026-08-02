import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift_alarm/data/models/alarm_record.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/repositories/alarm_record_repository.dart';
import 'package:shift_alarm/data/repositories/daily_schedule_repository.dart';
import 'package:shift_alarm/data/repositories/shift_template_repository.dart';
import 'package:shift_alarm/data/storage/memory_local_data_store.dart';
import 'package:shift_alarm/features/alarms/alarm_controller.dart';
import 'package:shift_alarm/features/alarms/alarm_records_page.dart';
import 'package:shift_alarm/features/alarms/permission_center_page.dart';
import 'package:shift_alarm/services/alarm/alarm_sync_coordinator.dart';
import 'package:shift_alarm/services/alarm/native_alarm_scheduler.dart';

class AlarmWidgetHarness {
  AlarmWidgetHarness(this.permissions)
    : store = MemoryLocalDataStore(),
      native = MemoryNativeAlarmScheduler(permissions: permissions) {
    alarms = LocalAlarmRecordRepository(store);
    coordinator = AlarmSyncCoordinator(
      scheduleRepository: LocalDailyScheduleRepository(store),
      shiftRepository: LocalShiftTemplateRepository(store),
      alarmRepository: alarms,
      nativeScheduler: native,
    );
    controller = AlarmController(
      coordinator: coordinator,
      repository: alarms,
      nativeScheduler: native,
    );
  }

  final AlarmPermissionState permissions;
  final MemoryLocalDataStore store;
  final MemoryNativeAlarmScheduler native;
  late final LocalAlarmRecordRepository alarms;
  late final AlarmSyncCoordinator coordinator;
  late final AlarmController controller;

  Future<void> initialize() => controller.initialize();

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AlarmController>.value(
        value: controller,
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: brightness,
            ),
          ),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AlarmRecord record({
    AlarmStatus status = AlarmStatus.registered,
    String? failureReason,
    int snoozeCount = 0,
  }) {
    final now = DateTime(2026, 8, 1);
    return AlarmRecord(
      id: 'alarm-widget',
      scheduleId: 'schedule-widget',
      scheduleDate: DateTime(2026, 8, 2),
      shiftTemplateId: 'shift-widget',
      reminderRuleId: 'wake-widget',
      reminderName: '起床提醒',
      shiftCode: 'A1',
      shiftName: '早班',
      triggerAt: DateTime(2026, 8, 2, 6),
      nativeAlarmId: 10000,
      status: status,
      failureReason: failureReason,
      snoozeCount: snoozeCount,
      maxSnoozeCount: 3,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  }
}

const allGranted = AlarmPermissionState(
  exactAlarm: true,
  notifications: true,
  fullScreenIntent: true,
  ignoringBatteryOptimizations: true,
  alarmVolume: 5,
  maxAlarmVolume: 10,
);

void main() {
  testWidgets('权限中心展示全部正常状态', (tester) async {
    final h = AlarmWidgetHarness(allGranted);
    await h.initialize();
    await h.pump(tester, const PermissionCenterPage());
    expect(find.text('权限中心'), findsOneWidget);
    expect(find.text('所有权限正常'), findsOneWidget);
    expect(find.text('精确闹钟'), findsOneWidget);
    expect(find.text('锁屏全屏提醒'), findsOneWidget);
    expect(find.text('正常 · 5/10'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('精确闹钟权限关闭时显示尚未生效', (tester) async {
    final h = AlarmWidgetHarness(
      const AlarmPermissionState(
        exactAlarm: false,
        notifications: true,
        fullScreenIntent: true,
        ignoringBatteryOptimizations: true,
        alarmVolume: 5,
        maxAlarmVolume: 10,
      ),
    );
    await h.initialize();
    await h.pump(tester, const PermissionCenterPage());
    expect(find.text('闹钟尚未生效'), findsOneWidget);
    expect(find.text('未开启'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('全屏提醒受限时总体状态不会误报全部正常', (tester) async {
    final h = AlarmWidgetHarness(
      const AlarmPermissionState(
        exactAlarm: true,
        notifications: true,
        fullScreenIntent: false,
        ignoringBatteryOptimizations: true,
        alarmVolume: 5,
        maxAlarmVolume: 10,
      ),
    );
    await h.initialize();
    await h.pump(tester, const PermissionCenterPage());
    expect(find.text('部分功能受限'), findsOneWidget);
    expect(find.text('受限'), findsOneWidget);
    expect(find.text('所有权限正常'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('一分钟测试闹钟可登记并取消', (tester) async {
    final h = AlarmWidgetHarness(allGranted);
    await h.initialize();
    await h.pump(tester, const PermissionCenterPage());
    await tester.scrollUntilVisible(
      find.text('一分钟后测试'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('一分钟后测试'));
    await tester.pump();
    expect(h.native.testAlarmScheduled, isTrue);
    expect(find.textContaining('测试闹钟等待触发'), findsOneWidget);
    expect(find.text('取消测试闹钟'), findsOneWidget);
    await tester.tap(find.text('取消测试闹钟'));
    await tester.pump();
    expect(h.native.testAlarmScheduled, isFalse);
    expect(find.text('测试已取消'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('权限不足时测试按钮先显示用途解释', (tester) async {
    final h = AlarmWidgetHarness(
      const AlarmPermissionState(
        exactAlarm: false,
        notifications: true,
        fullScreenIntent: true,
        ignoringBatteryOptimizations: true,
        alarmVolume: 5,
        maxAlarmVolume: 10,
      ),
    );
    await h.initialize();
    await h.pump(tester, const PermissionCenterPage());
    await tester.scrollUntilVisible(
      find.text('一分钟后测试'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('一分钟后测试'));
    await tester.pumpAndSettle();
    expect(find.text('开启精确闹钟权限'), findsOneWidget);
    expect(find.text('去开启'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('闹钟记录页展示状态和贪睡次数', (tester) async {
    final h = AlarmWidgetHarness(allGranted);
    await h.initialize();
    await h.alarms.add(h.record(status: AlarmStatus.snoozed, snoozeCount: 2));
    await h.controller.loadRecords();
    await h.pump(tester, const AlarmRecordsPage());
    expect(find.text('闹钟记录'), findsOneWidget);
    expect(find.textContaining('起床提醒'), findsOneWidget);
    expect(find.text('A1 · 早班'), findsOneWidget);
    expect(find.text('已贪睡'), findsOneWidget);
    expect(find.text('已贪睡 2/3 次'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('登记失败记录会显示具体失败原因', (tester) async {
    final h = AlarmWidgetHarness(allGranted);
    await h.initialize();
    await h.alarms.add(
      h.record(status: AlarmStatus.failed, failureReason: '系统拒绝登记'),
    );
    await h.controller.loadRecords();
    await h.pump(tester, const AlarmRecordsPage());
    expect(find.text('登记失败'), findsOneWidget);
    expect(find.text('系统拒绝登记'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('深色模式下权限中心可以完整渲染', (tester) async {
    final h = AlarmWidgetHarness(allGranted);
    await h.initialize();
    await h.pump(
      tester,
      const PermissionCenterPage(),
      brightness: Brightness.dark,
    );
    expect(find.text('权限中心'), findsOneWidget);
    expect(find.byType(Card), findsWidgets);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    await h.dispose(tester);
  });
}
