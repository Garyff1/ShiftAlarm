import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/app/app_navigation.dart';
import 'package:shift_alarm/app/shift_alarm_app.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/app_settings.dart';
import 'package:shift_alarm/data/models/clock_time.dart';
import 'package:shift_alarm/data/models/daily_schedule.dart';
import 'package:shift_alarm/data/models/reminder_rule.dart';
import 'package:shift_alarm/data/models/shift_template.dart';
import 'package:shift_alarm/data/repositories/app_settings_repository.dart';
import 'package:shift_alarm/data/repositories/alarm_record_repository.dart';
import 'package:shift_alarm/data/repositories/alarm_sound_repository.dart';
import 'package:shift_alarm/data/repositories/daily_schedule_repository.dart';
import 'package:shift_alarm/data/repositories/schedule_change_log_repository.dart';
import 'package:shift_alarm/data/repositories/shift_template_repository.dart';
import 'package:shift_alarm/data/storage/memory_local_data_store.dart';
import 'package:shift_alarm/features/schedule/schedule_controller.dart';
import 'package:shift_alarm/features/alarms/alarm_controller.dart';
import 'package:shift_alarm/features/settings/app_controller.dart';
import 'package:shift_alarm/features/shifts/shift_controller.dart';
import 'package:shift_alarm/features/sounds/sound_controller.dart';
import 'package:shift_alarm/services/alarm/alarm_sync_coordinator.dart';
import 'package:shift_alarm/services/alarm/native_alarm_scheduler.dart';
import 'package:shift_alarm/services/sounds/native_sound_service.dart';

class _Harness {
  const _Harness({
    required this.scheduleRepository,
    required this.shiftRepository,
    required this.scheduleController,
  });

  final LocalDailyScheduleRepository scheduleRepository;
  final LocalShiftTemplateRepository shiftRepository;
  final ScheduleController scheduleController;
}

ShiftTemplate _shift(
  String id,
  String code,
  String name, {
  ShiftType type = ShiftType.work,
}) {
  final now = DateTime(2026, 1, 1);
  return ShiftTemplate(
    id: id,
    code: code,
    name: name,
    type: type,
    colorValue: type == ShiftType.work ? 0xFF3157C8 : 0xFF56615A,
    arrivalTime: type == ShiftType.work
        ? const ClockTime(hour: 8, minute: 0)
        : null,
    reminderRules: type == ShiftType.work
        ? const [
            ReminderRule(
              id: 'before-60',
              name: '出发准备',
              timeMode: ReminderTimeMode.beforeArrival,
              minutesBeforeArrival: 60,
            ),
          ]
        : const [],
    createdAt: now,
    updatedAt: now,
  );
}

Future<_Harness> _pumpScheduleApp(
  WidgetTester tester, {
  List<ShiftTemplate> shifts = const [],
  List<MapEntry<DateTime, ShiftTemplate>> schedules = const [],
  AppSettings settings = const AppSettings(),
}) async {
  final store = MemoryLocalDataStore();
  final scheduleRepository = LocalDailyScheduleRepository(store);
  final logRepository = LocalScheduleChangeLogRepository(store);
  final shiftRepository = LocalShiftTemplateRepository(
    store,
    referenceChecker: scheduleRepository.getShiftReferenceSummary,
  );
  final appController = AppController(
    store: store,
    settingsRepository: MemoryAppSettingsRepository(settings),
  );
  await appController.initialize();
  for (final shift in shifts) {
    await shiftRepository.add(shift);
  }
  final templateMap = {for (final shift in shifts) shift.id: shift};
  for (final entry in schedules) {
    await scheduleRepository.setShift(
      entry.key,
      entry.value,
      templates: templateMap,
    );
  }
  final shiftController = ShiftController(shiftRepository);
  final alarmRepository = LocalAlarmRecordRepository(store);
  final soundRepository = LocalAlarmSoundRepository(store);
  final nativeScheduler = MemoryNativeAlarmScheduler();
  final alarmCoordinator = AlarmSyncCoordinator(
    scheduleRepository: scheduleRepository,
    shiftRepository: shiftRepository,
    alarmRepository: alarmRepository,
    nativeScheduler: nativeScheduler,
    soundRepository: soundRepository,
    loadSettings: () async => settings,
  );
  final alarmController = AlarmController(
    coordinator: alarmCoordinator,
    repository: alarmRepository,
    nativeScheduler: nativeScheduler,
  );
  final scheduleController = ScheduleController(
    repository: scheduleRepository,
    changeLogRepository: logRepository,
    shiftRepository: shiftRepository,
  );
  final soundController = SoundController(
    repository: soundRepository,
    nativeService: MemoryNativeSoundService(),
    appController: appController,
    shiftController: shiftController,
    alarmController: alarmController,
    alarmSyncCoordinator: alarmCoordinator,
  );
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
    scheduleRepository: scheduleRepository,
    shiftRepository: shiftRepository,
    scheduleController: scheduleController,
  );
}

Future<void> _openSchedule(WidgetTester tester) async {
  await tester.tap(find.text('排班').last);
  await tester.pumpAndSettle();
}

Finder _calendarCell(DateTime date) =>
    find.byKey(Key('calendar-${DailySchedule.dateKeyOf(date)}'));

void main() {
  final today = DailySchedule.normalizeDate(DateTime.now());
  final a1 = _shift('a1', 'A1', '早班');
  final b1 = _shift('b1', 'B1', '晚班');

  testWidgets('空月份显示 42 格日历和引导空状态', (tester) async {
    await _pumpScheduleApp(tester);
    await _openSchedule(tester);

    expect(_calendarCell(today), findsOneWidget);
    expect(find.byTooltip('上个月'), findsOneWidget);
    expect(find.byTooltip('下个月'), findsOneWidget);
    await tester.drag(
      find.byKey(const PageStorageKey('schedule-calendar')),
      const Offset(0, -1400),
    );
    await tester.pumpAndSettle();
    expect(find.text('本月暂无排班，点击日期开始安排，长按日期可进入批量模式。'), findsOneWidget);
  });

  testWidgets('点击未排班日期打开当天详情', (tester) async {
    await _pumpScheduleApp(tester);
    await _openSchedule(tester);

    await tester.tap(_calendarCell(today));
    await tester.pumpAndSettle();

    expect(find.text('当天尚未排班'), findsOneWidget);
    expect(find.text('设置班次'), findsOneWidget);
    expect(find.text('标记休息'), findsOneWidget);
  });

  testWidgets('可通过日期详情选择班次并立即刷新日历', (tester) async {
    final harness = await _pumpScheduleApp(tester, shifts: [a1]);
    await _openSchedule(tester);

    await tester.tap(_calendarCell(today));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置班次'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('早班'));
    await tester.pumpAndSettle();

    expect(find.text('排班已保存'), findsOneWidget);
    expect(
      (await harness.scheduleRepository.getByDate(today))?.shiftTemplateId,
      a1.id,
    );
    expect(find.text('A1'), findsOneWidget);
  });

  testWidgets('更换已有班次后显示临时调班标记并保留原班次', (tester) async {
    final harness = await _pumpScheduleApp(
      tester,
      shifts: [a1, b1],
      schedules: [MapEntry(today, a1)],
    );
    await _openSchedule(tester);

    await tester.tap(_calendarCell(today));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更换班次 / 临时调班'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('晚班'));
    await tester.pumpAndSettle();
    expect(find.text('确认临时调班'), findsOneWidget);
    await tester.tap(find.text('确认调整'));
    await tester.pumpAndSettle();

    final saved = await harness.scheduleRepository.getByDate(today);
    expect(saved?.shiftTemplateId, b1.id);
    expect(saved?.originalShiftTemplateId, a1.id);
    expect(saved?.isTemporaryChanged, isTrue);
    expect(find.text('调'), findsOneWidget);
    expect(find.text('临时调班已完成'), findsOneWidget);
  });

  testWidgets('临时调班后可从详情恢复原排班', (tester) async {
    final harness = await _pumpScheduleApp(
      tester,
      shifts: [a1, b1],
      schedules: [MapEntry(today, a1)],
    );
    await harness.scheduleRepository.setShift(
      today,
      b1,
      templates: {a1.id: a1, b1.id: b1},
    );
    await tester.pumpAndSettle();
    await _openSchedule(tester);

    await tester.tap(_calendarCell(today));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('恢复原排班'));
    await tester.tap(find.text('恢复原排班'));
    await tester.pumpAndSettle();
    expect(find.text('恢复原排班？'), findsOneWidget);
    await tester.tap(find.text('确认恢复'));
    await tester.pumpAndSettle();

    final saved = await harness.scheduleRepository.getByDate(today);
    expect(saved?.shiftTemplateId, a1.id);
    expect(saved?.isTemporaryChanged, isFalse);
    expect(find.text('已恢复原排班'), findsOneWidget);
  });

  testWidgets('删除当天排班需要确认并写入删除结果', (tester) async {
    final harness = await _pumpScheduleApp(
      tester,
      shifts: [a1],
      schedules: [MapEntry(today, a1)],
    );
    await _openSchedule(tester);

    await tester.tap(_calendarCell(today));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('删除当天排班'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('删除当天排班'));
    await tester.pumpAndSettle();
    expect(find.text('删除当天排班？'), findsOneWidget);
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(await harness.scheduleRepository.getByDate(today), isNull);
    expect(find.text('已删除当天排班'), findsOneWidget);
  });

  testWidgets('首页展示今天明天真实排班和计划提醒免责声明', (tester) async {
    await _pumpScheduleApp(
      tester,
      shifts: [a1, b1],
      schedules: [
        MapEntry(today, a1),
        MapEntry(today.add(const Duration(days: 1)), b1),
      ],
    );

    expect(find.text('A1 · 早班'), findsOneWidget);
    expect(find.text('B1 · 晚班'), findsOneWidget);
    expect(find.text('闹钟已开启'), findsOneWidget);
    expect(find.text('今天'), findsWidgets);
    expect(find.text('明天'), findsWidgets);
  });

  testWidgets('长按日期进入批量模式并可多选和退出', (tester) async {
    final next = today.day < DateTime(today.year, today.month + 1, 0).day
        ? today.add(const Duration(days: 1))
        : today.subtract(const Duration(days: 1));
    final harness = await _pumpScheduleApp(tester, shifts: [a1]);
    await _openSchedule(tester);

    await tester.longPress(_calendarCell(today));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 天'), findsOneWidget);
    await tester.tap(_calendarCell(next));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 天'), findsOneWidget);
    expect(find.text('设置班次'), findsOneWidget);
    await tester.tap(find.byTooltip('退出批量模式'));
    await tester.pumpAndSettle();
    expect(find.text('排班'), findsWidgets);
    expect(harness.scheduleController.batchMode, isFalse);
    expect(harness.scheduleController.selectedDateKeys, isEmpty);
  });

  testWidgets('连续切换月份 30 次后仍可返回当前月', (tester) async {
    final harness = await _pumpScheduleApp(tester, shifts: [a1]);
    await _openSchedule(tester);

    for (var index = 0; index < 15; index++) {
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
    }
    for (var index = 0; index < 15; index++) {
      await tester.tap(find.byTooltip('上个月'));
      await tester.pumpAndSettle();
    }

    expect(harness.scheduleController.selectedMonth.year, today.year);
    expect(harness.scheduleController.selectedMonth.month, today.month);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨月时钟变化会刷新首页并跟随原当前月份', (tester) async {
    final harness = await _pumpScheduleApp(tester, shifts: [a1]);
    final previous = DateTime(2030, 1, 31, 23, 59);
    final current = DateTime(2030, 2, 1);
    await harness.scheduleController.selectMonth(previous);
    harness.scheduleController.enterBatch(previous);

    await harness.scheduleController.refreshForClockChange(
      previous: previous,
      current: current,
    );

    expect(harness.scheduleController.selectedMonth, DateTime(2030, 2));
    expect(harness.scheduleController.batchMode, isFalse);
    expect(harness.scheduleController.selectedDateKeys, isEmpty);
  });

  testWidgets('批量标记休息可在缺少模板时快速创建 OFF', (tester) async {
    final harness = await _pumpScheduleApp(tester);
    await _openSchedule(tester);
    await tester.longPress(_calendarCell(today));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('标记休息'));
    await tester.pumpAndSettle();

    expect(find.text('还没有休息班次'), findsOneWidget);
    await tester.tap(find.text('快速创建'));
    await tester.pumpAndSettle();

    final schedule = await harness.scheduleRepository.getByDate(today);
    final shift = await harness.shiftRepository.getById(
      schedule!.shiftTemplateId,
    );
    expect(shift?.code, 'OFF');
    expect(shift?.type, ShiftType.rest);
    expect(find.textContaining('已为 1 个日期设置 OFF 休息'), findsOneWidget);
  });

  testWidgets('深色主题下日历可正常渲染和打开详情', (tester) async {
    await _pumpScheduleApp(
      tester,
      shifts: [a1],
      schedules: [MapEntry(today, a1)],
      settings: const AppSettings(themeMode: AppThemeMode.dark),
    );
    await _openSchedule(tester);

    final context = tester.element(_calendarCell(today));
    expect(Theme.of(context).brightness, Brightness.dark);
    await tester.tap(_calendarCell(today));
    await tester.pumpAndSettle();
    expect(find.text('早班'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
