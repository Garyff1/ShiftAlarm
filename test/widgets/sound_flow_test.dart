import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift_alarm/data/models/alarm_sound.dart';
import 'package:shift_alarm/data/repositories/alarm_record_repository.dart';
import 'package:shift_alarm/data/repositories/alarm_sound_repository.dart';
import 'package:shift_alarm/data/repositories/app_settings_repository.dart';
import 'package:shift_alarm/data/repositories/daily_schedule_repository.dart';
import 'package:shift_alarm/data/repositories/shift_template_repository.dart';
import 'package:shift_alarm/data/storage/memory_local_data_store.dart';
import 'package:shift_alarm/features/alarms/alarm_controller.dart';
import 'package:shift_alarm/features/settings/app_controller.dart';
import 'package:shift_alarm/features/shifts/shift_controller.dart';
import 'package:shift_alarm/features/sounds/sound_controller.dart';
import 'package:shift_alarm/features/sounds/sounds_page.dart';
import 'package:shift_alarm/services/alarm/alarm_sync_coordinator.dart';
import 'package:shift_alarm/services/alarm/native_alarm_scheduler.dart';
import 'package:shift_alarm/services/sounds/native_sound_service.dart';

class _WidgetHarness {
  const _WidgetHarness(this.controller, this.native);
  final SoundController controller;
  final MemoryNativeSoundService native;
}

AlarmSound _sound({bool available = true, String? reason}) => AlarmSound(
  id: 'one',
  displayName: '强力起床铃',
  internalPath: '/files/one.mp3',
  sourceName: 'wake.mp3',
  mimeType: 'audio/mpeg',
  format: 'mp3',
  fileSize: 2 * 1024 * 1024,
  durationMilliseconds: 65_000,
  isAvailable: available,
  checksum: 'checksum-one',
  importedAt: DateTime(2026),
  failureReason: reason,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<_WidgetHarness> _pumpSounds(
  WidgetTester tester, {
  AlarmSound? seed,
  SoundImportCandidate? candidate,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  final store = MemoryLocalDataStore();
  final settingsRepository = MemoryAppSettingsRepository();
  final app = AppController(
    store: store,
    settingsRepository: settingsRepository,
  );
  await app.initialize();
  final soundRepository = LocalAlarmSoundRepository(store);
  if (seed != null) await soundRepository.add(seed);
  final shiftRepository = LocalShiftTemplateRepository(store);
  final scheduleRepository = LocalDailyScheduleRepository(store);
  final alarmRepository = LocalAlarmRecordRepository(store);
  final nativeAlarm = MemoryNativeAlarmScheduler();
  final coordinator = AlarmSyncCoordinator(
    scheduleRepository: scheduleRepository,
    shiftRepository: shiftRepository,
    alarmRepository: alarmRepository,
    nativeScheduler: nativeAlarm,
    soundRepository: soundRepository,
    loadSettings: settingsRepository.load,
  );
  final shifts = ShiftController(shiftRepository);
  final alarms = AlarmController(
    coordinator: coordinator,
    repository: alarmRepository,
    nativeScheduler: nativeAlarm,
  );
  await shifts.initialize();
  await alarms.initialize();
  final native = MemoryNativeSoundService()..nextCandidate = candidate;
  if (seed != null && !seed.isAvailable) {
    native.verifications[seed.internalPath] = SoundVerification(
      isAvailable: false,
      failureReason: seed.failureReason,
    );
  }
  final controller = SoundController(
    repository: soundRepository,
    nativeService: native,
    appController: app,
    shiftController: shifts,
    alarmController: alarms,
    alarmSyncCoordinator: coordinator,
  );
  await controller.initialize();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: themeMode,
        home: const Scaffold(body: SoundsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(controller.dispose);
  return _WidgetHarness(controller, native);
}

SoundImportCandidate _candidate({String checksum = 'new-checksum'}) =>
    SoundImportCandidate(
      tempPath: '/temp/gentle.mp3',
      displayName: '柔和铃声',
      sourceName: 'gentle.mp3',
      sourceUri: 'content://downloads/gentle.mp3',
      mimeType: 'audio/mpeg',
      format: 'mp3',
      fileSize: 4096,
      durationMilliseconds: 8000,
      checksum: checksum,
    );

void main() {
  testWidgets('铃声库空状态展示导入入口和支持格式', (tester) async {
    await _pumpSounds(tester);
    expect(find.text('还没有自定义铃声'), findsOneWidget);
    expect(find.textContaining('MP3'), findsOneWidget);
    expect(find.byKey(const Key('import-sound-button')), findsOneWidget);
  });

  testWidgets('自定义铃声卡片展示格式、时长和大小', (tester) async {
    await _pumpSounds(tester, seed: _sound());
    expect(find.text('强力起床铃'), findsWidgets);
    expect(find.textContaining('MP3 · 1:05 · 2.0 MB'), findsOneWidget);
  });

  testWidgets('导入成功后立即出现在铃声库', (tester) async {
    await _pumpSounds(tester, candidate: _candidate());
    await tester.tap(find.byKey(const Key('import-sound-button')));
    await tester.pumpAndSettle();
    expect(find.text('柔和铃声'), findsWidgets);
    expect(find.textContaining('已导入铃声库'), findsOneWidget);
  });

  testWidgets('重复导入显示使用已有、仍然导入和取消三种处理', (tester) async {
    await _pumpSounds(
      tester,
      seed: _sound(),
      candidate: _candidate(checksum: 'checksum-one'),
    );
    await tester.tap(find.byKey(const Key('import-sound-button')));
    await tester.pumpAndSettle();
    expect(find.text('该音频已经导入过'), findsOneWidget);
    expect(find.text('使用已有铃声'), findsOneWidget);
    expect(find.text('仍然导入'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('铃声可通过更多菜单重命名', (tester) async {
    await _pumpSounds(tester, seed: _sound());
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sound-rename-field')),
      '夜班专用铃',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('夜班专用铃'), findsWidgets);
  });

  testWidgets('不可用铃声在深色模式展示异常和自动降级提示', (tester) async {
    await _pumpSounds(
      tester,
      seed: _sound(available: false, reason: 'file_missing'),
      themeMode: ThemeMode.dark,
    );
    expect(find.text('不可用'), findsOneWidget);
    expect(find.textContaining('正式闹钟会自动使用下一级铃声'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
