import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/app/app_navigation.dart';
import 'package:shift_alarm/app/shift_alarm_app.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/app_settings.dart';
import 'package:shift_alarm/data/repositories/app_settings_repository.dart';
import 'package:shift_alarm/data/repositories/alarm_record_repository.dart';
import 'package:shift_alarm/data/repositories/alarm_sound_repository.dart';
import 'package:shift_alarm/data/repositories/daily_schedule_repository.dart';
import 'package:shift_alarm/data/repositories/schedule_change_log_repository.dart';
import 'package:shift_alarm/data/repositories/shift_template_repository.dart';
import 'package:shift_alarm/data/storage/memory_local_data_store.dart';
import 'package:shift_alarm/features/settings/app_controller.dart';
import 'package:shift_alarm/features/alarms/alarm_controller.dart';
import 'package:shift_alarm/features/schedule/schedule_controller.dart';
import 'package:shift_alarm/features/shifts/shift_controller.dart';
import 'package:shift_alarm/features/sounds/sound_controller.dart';
import 'package:shift_alarm/services/alarm/alarm_sync_coordinator.dart';
import 'package:shift_alarm/services/alarm/native_alarm_scheduler.dart';
import 'package:shift_alarm/services/sounds/native_sound_service.dart';

class _Harness {
  _Harness({
    required this.store,
    required this.repository,
    required this.settingsRepository,
    required this.appController,
    required this.shiftController,
    required this.scheduleController,
  });

  final MemoryLocalDataStore store;
  final LocalShiftTemplateRepository repository;
  final MemoryAppSettingsRepository settingsRepository;
  final AppController appController;
  final ShiftController shiftController;
  final ScheduleController scheduleController;
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  MemoryAppSettingsRepository? settingsRepository,
}) async {
  final store = MemoryLocalDataStore();
  final scheduleRepository = LocalDailyScheduleRepository(store);
  final changeLogRepository = LocalScheduleChangeLogRepository(store);
  final repository = LocalShiftTemplateRepository(
    store,
    referenceChecker: scheduleRepository.getShiftReferenceSummary,
  );
  final settings =
      settingsRepository ??
      MemoryAppSettingsRepository(const AppSettings(onboardingCompleted: true));
  final appController = AppController(
    store: store,
    settingsRepository: settings,
  );
  final shiftController = ShiftController(repository);
  final alarmRepository = LocalAlarmRecordRepository(store);
  final soundRepository = LocalAlarmSoundRepository(store);
  final nativeScheduler = MemoryNativeAlarmScheduler();
  final alarmCoordinator = AlarmSyncCoordinator(
    scheduleRepository: scheduleRepository,
    shiftRepository: repository,
    alarmRepository: alarmRepository,
    nativeScheduler: nativeScheduler,
    soundRepository: soundRepository,
    loadSettings: settings.load,
  );
  final alarmController = AlarmController(
    coordinator: alarmCoordinator,
    repository: alarmRepository,
    nativeScheduler: nativeScheduler,
  );
  final scheduleController = ScheduleController(
    repository: scheduleRepository,
    changeLogRepository: changeLogRepository,
    shiftRepository: repository,
  );
  final soundController = SoundController(
    repository: soundRepository,
    nativeService: MemoryNativeSoundService(),
    appController: appController,
    shiftController: shiftController,
    alarmController: alarmController,
    alarmSyncCoordinator: alarmCoordinator,
  );
  await appController.initialize();
  await shiftController.initialize();
  await scheduleController.initialize();
  await alarmController.initialize();
  await soundController.initialize();
  await tester.pumpWidget(
    ShiftAlarmApp(
      appController: appController,
      shiftController: shiftController,
      scheduleController: scheduleController,
      alarmController: alarmController,
      soundController: soundController,
      navigationController: AppNavigationController(),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(
    store: store,
    repository: repository,
    settingsRepository: settings,
    appController: appController,
    shiftController: shiftController,
    scheduleController: scheduleController,
  );
}

Future<void> openShiftPage(WidgetTester tester) async {
  await tester.tap(find.text('班次').last);
  await tester.pumpAndSettle();
}

Future<void> openNewShift(WidgetTester tester) async {
  await openShiftPage(tester);
  await tester.tap(find.text('新建班次'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('班次列表显示完整空状态', (tester) async {
    await _pumpApp(tester);
    await openShiftPage(tester);

    expect(find.text('还没有班次'), findsOneWidget);
    expect(find.text('创建工作、休息或请假班次，作为后续排班的模板'), findsOneWidget);
  });

  testWidgets('新建工作班后列表立即刷新并包含三条默认提醒', (tester) async {
    final harness = await _pumpApp(tester);
    await openNewShift(tester);

    await tester.enterText(find.byKey(const Key('shift-code-field')), 'A1');
    await tester.enterText(find.byKey(const Key('shift-name-field')), '早班');
    await tester.tap(find.text('保存').first);
    await tester.pumpAndSettle();

    expect(find.text('早班'), findsOneWidget);
    final saved = (await harness.repository.getAll()).single;
    expect(saved.code, 'A1');
    expect(saved.arrivalTime?.format(), '08:00');
    expect(saved.reminderRules.map((rule) => rule.minutesBeforeArrival), [
      120,
      60,
      20,
    ]);
  });

  testWidgets('可新建不包含工作提醒的休息班', (tester) async {
    final harness = await _pumpApp(tester);
    await openNewShift(tester);

    await tester.enterText(find.byKey(const Key('shift-code-field')), 'OFF');
    await tester.enterText(find.byKey(const Key('shift-name-field')), '休息');
    await tester.tap(find.byType(DropdownButtonFormField<ShiftType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('休息').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存').first);
    await tester.pumpAndSettle();

    final saved = (await harness.repository.getAll()).single;
    expect(saved.type, ShiftType.rest);
    expect(saved.arrivalTime, isNull);
    expect(saved.reminderRules, isEmpty);
  });

  testWidgets('空表单保存会显示清晰校验错误', (tester) async {
    await _pumpApp(tester);
    await openNewShift(tester);

    await tester.tap(find.text('保存').first);
    await tester.pump();

    expect(find.text('请输入班次代码'), findsOneWidget);
    expect(find.text('请输入班次名称'), findsOneWidget);
  });

  testWidgets('设置修改后离开页面并重新初始化仍有效', (tester) async {
    final settingsRepository = MemoryAppSettingsRepository(
      const AppSettings(onboardingCompleted: true),
    );
    await _pumpApp(tester, settingsRepository: settingsRepository);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    final settingsScroll = find.byKey(const PageStorageKey('settings-page'));
    await tester.dragUntilVisible(
      find.text('使用 24 小时制'),
      settingsScroll,
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    expect(find.text('使用 24 小时制'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, '使用 24 小时制'));
    await tester.pumpAndSettle();
    expect((await settingsRepository.load()).use24HourFormat, isFalse);

    await tester.tap(find.text('首页').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();

    final reopenedStore = MemoryLocalDataStore();
    final reopenedController = AppController(
      store: reopenedStore,
      settingsRepository: settingsRepository,
    );
    await reopenedController.initialize();
    expect(reopenedController.settings.use24HourFormat, isFalse);
  });
}
