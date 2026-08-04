import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift_alarm/app/app_navigation.dart';
import 'package:shift_alarm/app/shift_alarm_app.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/app_settings.dart';
import 'package:shift_alarm/data/repositories/alarm_record_repository.dart';
import 'package:shift_alarm/data/repositories/alarm_sound_repository.dart';
import 'package:shift_alarm/data/repositories/app_settings_repository.dart';
import 'package:shift_alarm/data/repositories/daily_schedule_repository.dart';
import 'package:shift_alarm/data/repositories/schedule_change_log_repository.dart';
import 'package:shift_alarm/data/repositories/shift_template_repository.dart';
import 'package:shift_alarm/data/storage/memory_local_data_store.dart';
import 'package:shift_alarm/features/alarms/alarm_controller.dart';
import 'package:shift_alarm/features/alarms/permission_center_page.dart';
import 'package:shift_alarm/features/schedule/schedule_controller.dart';
import 'package:shift_alarm/features/settings/app_controller.dart';
import 'package:shift_alarm/features/shifts/shift_controller.dart';
import 'package:shift_alarm/features/sounds/sound_controller.dart';
import 'package:shift_alarm/services/alarm/alarm_sync_coordinator.dart';
import 'package:shift_alarm/services/alarm/native_alarm_scheduler.dart';
import 'package:shift_alarm/services/sounds/native_sound_service.dart';

class _ModeHarness {
  const _ModeHarness({
    required this.settings,
    required this.app,
    required this.alarms,
  });

  final MemoryAppSettingsRepository settings;
  final AppController app;
  final AlarmController alarms;
}

Future<_ModeHarness> _pumpApp(
  WidgetTester tester, {
  AppSettings settings = const AppSettings(),
}) async {
  final store = MemoryLocalDataStore();
  final settingsRepository = MemoryAppSettingsRepository(settings);
  final app = AppController(
    store: store,
    settingsRepository: settingsRepository,
  );
  final schedules = LocalDailyScheduleRepository(store);
  final shifts = LocalShiftTemplateRepository(
    store,
    referenceChecker: schedules.getShiftReferenceSummary,
  );
  final alarmRecords = LocalAlarmRecordRepository(store);
  final sounds = LocalAlarmSoundRepository(store);
  final nativeAlarms = MemoryNativeAlarmScheduler();
  final coordinator = AlarmSyncCoordinator(
    scheduleRepository: schedules,
    shiftRepository: shifts,
    alarmRepository: alarmRecords,
    nativeScheduler: nativeAlarms,
    soundRepository: sounds,
    loadSettings: settingsRepository.load,
  );
  final appShifts = ShiftController(shifts);
  final appAlarms = AlarmController(
    coordinator: coordinator,
    repository: alarmRecords,
    nativeScheduler: nativeAlarms,
  );
  final appSchedules = ScheduleController(
    repository: schedules,
    changeLogRepository: LocalScheduleChangeLogRepository(store),
    shiftRepository: shifts,
  );
  final appSounds = SoundController(
    repository: sounds,
    nativeService: MemoryNativeSoundService(),
    appController: app,
    shiftController: appShifts,
    alarmController: appAlarms,
    alarmSyncCoordinator: coordinator,
  );
  await app.initialize();
  await appShifts.initialize();
  await appSchedules.initialize();
  await appAlarms.initialize();
  await appSounds.initialize();
  await tester.pumpWidget(
    ShiftAlarmApp(
      appController: app,
      shiftController: appShifts,
      scheduleController: appSchedules,
      alarmController: appAlarms,
      soundController: appSounds,
      navigationController: AppNavigationController(),
    ),
  );
  await tester.pumpAndSettle();
  return _ModeHarness(
    settings: settingsRepository,
    app: app,
    alarms: appAlarms,
  );
}

Future<void> _chooseMode(WidgetTester tester, AppInterfaceMode mode) async {
  final list = find.byType(ListView).first;
  final card = find.byKey(Key('interface-mode-${mode.storageValue}'));
  await tester.dragUntilVisible(card, list, const Offset(0, -180));
  await tester.tap(card);
  await tester.pump();
  final button = find.byKey(const Key('use-interface-mode-button'));
  await tester.dragUntilVisible(button, list, const Offset(0, -180));
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首次启动展示三种界面模式和数据安全说明', (tester) async {
    await _pumpApp(tester);
    expect(find.byKey(const Key('interface-mode-title')), findsOneWidget);
    expect(find.text('标准模式'), findsOneWidget);
    expect(find.text('大字模式'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('interface-mode-simple')),
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    expect(find.text('简易模式'), findsOneWidget);
    final explanation = find.textContaining('不影响排班和闹钟');
    await tester.dragUntilVisible(
      explanation,
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    expect(explanation, findsOneWidget);
  });

  testWidgets('首次选择标准模式后进入五项导航', (tester) async {
    final harness = await _pumpApp(tester);
    await _chooseMode(tester, AppInterfaceMode.standard);
    expect((await harness.settings.load()).onboardingCompleted, isTrue);
    expect(
      (await harness.settings.load()).interfaceMode,
      AppInterfaceMode.standard,
    );
    for (final label in ['首页', '排班', '班次', '铃声', '设置']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('首次选择大字模式后保留标准五项导航', (tester) async {
    final harness = await _pumpApp(tester);
    await _chooseMode(tester, AppInterfaceMode.largeText);
    expect(
      (await harness.settings.load()).interfaceMode,
      AppInterfaceMode.largeText,
    );
    expect(find.text('首页'), findsWidgets);
    expect(find.text('班次'), findsWidgets);
    expect(find.text('铃声'), findsWidgets);
  });

  testWidgets('首次选择简易模式后进入三项导航', (tester) async {
    final harness = await _pumpApp(tester);
    await _chooseMode(tester, AppInterfaceMode.simple);
    expect(
      (await harness.settings.load()).interfaceMode,
      AppInterfaceMode.simple,
    );
    expect(find.text('今天'), findsWidgets);
    expect(find.text('排班'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    expect(find.text('首页'), findsNothing);
  });

  testWidgets('简易首页明确展示今天明天和下一次闹钟', (tester) async {
    await _pumpApp(
      tester,
      settings: const AppSettings(
        interfaceMode: AppInterfaceMode.simple,
        onboardingCompleted: true,
      ),
    );
    expect(find.byKey(const Key('simple-today-card')), findsOneWidget);
    expect(find.text('下一次闹钟'), findsWidgets);
    expect(find.text('安排今天班次'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('simple-tomorrow-card')),
      find.byKey(const PageStorageKey('simple-home-page')),
      const Offset(0, -180),
    );
    expect(find.byKey(const Key('simple-tomorrow-card')), findsOneWidget);
  });

  testWidgets('简易排班无班次时提供明显的新建入口', (tester) async {
    await _pumpApp(
      tester,
      settings: const AppSettings(
        interfaceMode: AppInterfaceMode.simple,
        onboardingCompleted: true,
      ),
    );
    await tester.tap(find.text('排班').last);
    await tester.pumpAndSettle();
    expect(find.text('查看整月排班'), findsOneWidget);
    expect(find.text('还没有班次规则'), findsOneWidget);
    expect(find.text('新建第一个班次'), findsOneWidget);
  });

  testWidgets('简易更多页使用可见文字入口', (tester) async {
    await _pumpApp(
      tester,
      settings: const AppSettings(
        interfaceMode: AppInterfaceMode.simple,
        onboardingCompleted: true,
      ),
    );
    await tester.tap(find.text('更多').last);
    await tester.pumpAndSettle();
    expect(find.text('班次管理'), findsOneWidget);
    expect(find.text('铃声'), findsOneWidget);
    expect(find.text('权限检查'), findsOneWidget);
    expect(find.text('界面模式'), findsOneWidget);
  });

  testWidgets('简易权限中心使用普通中文名称', (tester) async {
    final harness = await _pumpApp(
      tester,
      settings: const AppSettings(
        interfaceMode: AppInterfaceMode.simple,
        onboardingCompleted: true,
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AlarmController>.value(
        value: harness.alarms,
        child: const MaterialApp(home: PermissionCenterPage(simpleMode: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('允许闹钟准时响'), findsOneWidget);
    expect(find.text('允许显示闹钟提醒'), findsOneWidget);
    expect(find.text('允许锁屏时显示闹钟画面'), findsOneWidget);
    expect(find.text('防止手机限制闹钟运行'), findsOneWidget);
  });

  testWidgets('设置页可切换高对比度并持久化', (tester) async {
    final harness = await _pumpApp(
      tester,
      settings: const AppSettings(onboardingCompleted: true),
    );
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(SwitchListTile, '高对比度显示');
    await tester.dragUntilVisible(
      tile,
      find.byKey(const PageStorageKey('settings-page')),
      const Offset(0, -120),
    );
    tester.widget<SwitchListTile>(tile).onChanged!(true);
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).highContrastEnabled, isTrue);
  });

  testWidgets('设置页可切换减少动态效果并持久化', (tester) async {
    final harness = await _pumpApp(
      tester,
      settings: const AppSettings(onboardingCompleted: true),
    );
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(SwitchListTile, '减少动态效果');
    await tester.dragUntilVisible(
      tile,
      find.byKey(const PageStorageKey('settings-page')),
      const Offset(0, -120),
    );
    tester.widget<SwitchListTile>(tile).onChanged!(true);
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).reduceMotion, isTrue);
  });
}
