import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/shift_alarm_app.dart';
import 'app/app_navigation.dart';
import 'data/repositories/app_settings_repository.dart';
import 'data/repositories/shift_template_repository.dart';
import 'data/repositories/daily_schedule_repository.dart';
import 'data/repositories/schedule_change_log_repository.dart';
import 'data/repositories/alarm_record_repository.dart';
import 'data/repositories/alarm_lifecycle_repository.dart';
import 'data/repositories/alarm_sound_repository.dart';
import 'data/storage/sqlite_local_data_store.dart';
import 'features/settings/app_controller.dart';
import 'features/shifts/shift_controller.dart';
import 'features/schedule/schedule_controller.dart';
import 'features/alarms/alarm_controller.dart';
import 'features/sounds/sound_controller.dart';
import 'services/alarm/alarm_service.dart';
import 'services/alarm/alarm_sync_coordinator.dart';
import 'services/alarm/native_alarm_scheduler.dart';
import 'services/sounds/native_sound_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppSettingsRepository settingsRepository;
  try {
    settingsRepository = SharedPreferencesAppSettingsRepository(
      await SharedPreferences.getInstance(),
    );
  } catch (error, stackTrace) {
    debugPrint('[ShiftAlarm] 设置存储初始化失败，将在本次运行使用内存设置: $error\n$stackTrace');
    settingsRepository = MemoryAppSettingsRepository();
  }

  final store = SqliteLocalDataStore();
  final syncBridge = DelegatingScheduleAlarmSyncCoordinator();
  final scheduleRepository = LocalDailyScheduleRepository(
    store,
    syncCoordinator: syncBridge,
  );
  final changeLogRepository = LocalScheduleChangeLogRepository(store);
  final shiftRepository = LocalShiftTemplateRepository(
    store,
    referenceChecker: scheduleRepository.getShiftReferenceSummary,
  );
  final appController = AppController(
    store: store,
    settingsRepository: settingsRepository,
  );
  final alarmRepository = LocalAlarmRecordRepository(store);
  final lifecycleRepository = LocalAlarmLifecycleRepository(store);
  final soundRepository = LocalAlarmSoundRepository(store);
  const nativeScheduler = MethodChannelNativeAlarmScheduler();
  final alarmSyncCoordinator = AlarmSyncCoordinator(
    scheduleRepository: scheduleRepository,
    shiftRepository: shiftRepository,
    alarmRepository: alarmRepository,
    nativeScheduler: nativeScheduler,
    soundRepository: soundRepository,
    loadSettings: settingsRepository.load,
    lifecycleRepository: lifecycleRepository,
  );
  syncBridge.delegate = alarmSyncCoordinator;
  final alarmController = AlarmController(
    coordinator: alarmSyncCoordinator,
    repository: alarmRepository,
    nativeScheduler: nativeScheduler,
    lifecycleRepository: lifecycleRepository,
  );
  final shiftController = ShiftController(
    shiftRepository,
    alarmSyncCoordinator: alarmSyncCoordinator,
  );
  final scheduleController = ScheduleController(
    repository: scheduleRepository,
    changeLogRepository: changeLogRepository,
    shiftRepository: shiftRepository,
  );
  final soundController = SoundController(
    repository: soundRepository,
    nativeService: const MethodChannelNativeSoundService(),
    appController: appController,
    shiftController: shiftController,
    alarmController: alarmController,
    alarmSyncCoordinator: alarmSyncCoordinator,
  );

  await appController.initialize();
  if (appController.initializationError == null) {
    await shiftController.initialize();
    await scheduleController.initialize();
    await alarmController.initialize();
    await soundController.initialize();
  }

  runApp(
    ShiftAlarmApp(
      appController: appController,
      shiftController: shiftController,
      scheduleController: scheduleController,
      alarmController: alarmController,
      soundController: soundController,
      navigationController: AppNavigationController(),
    ),
  );
}
