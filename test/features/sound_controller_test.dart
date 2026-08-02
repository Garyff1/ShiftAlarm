import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/data/models/alarm_sound.dart';
import 'package:shift_alarm/data/models/sound_ids.dart';
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
import 'package:shift_alarm/services/alarm/alarm_sync_coordinator.dart';
import 'package:shift_alarm/services/alarm/native_alarm_scheduler.dart';
import 'package:shift_alarm/services/sounds/native_sound_service.dart';

class _Harness {
  const _Harness({
    required this.controller,
    required this.repository,
    required this.native,
    required this.app,
  });
  final SoundController controller;
  final LocalAlarmSoundRepository repository;
  final MemoryNativeSoundService native;
  final AppController app;
}

SoundImportCandidate _candidate({
  String checksum = 'candidate-checksum',
  String name = 'wake.mp3',
}) => SoundImportCandidate(
  tempPath: '/temp/$name',
  displayName: name.replaceAll('.mp3', ''),
  sourceName: name,
  sourceUri: 'content://downloads/$name',
  mimeType: 'audio/mpeg',
  format: 'mp3',
  fileSize: 2048,
  durationMilliseconds: 7000,
  checksum: checksum,
);

AlarmSound _sound(String id, {bool available = true, String? failureReason}) =>
    AlarmSound(
      id: id,
      displayName: '铃声 $id',
      internalPath: '/files/$id.mp3',
      sourceName: '$id.mp3',
      mimeType: 'audio/mpeg',
      format: 'mp3',
      fileSize: 1024,
      durationMilliseconds: 5000,
      isAvailable: available,
      checksum: 'checksum-$id',
      importedAt: DateTime(2026),
      failureReason: failureReason,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<_Harness> _createHarness({AlarmSound? seed}) async {
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
  final shifts = ShiftController(
    shiftRepository,
    alarmSyncCoordinator: coordinator,
  );
  final alarms = AlarmController(
    coordinator: coordinator,
    repository: alarmRepository,
    nativeScheduler: nativeAlarm,
  );
  await shifts.initialize();
  await alarms.initialize();
  final native = MemoryNativeSoundService();
  final controller = SoundController(
    repository: soundRepository,
    nativeService: native,
    appController: app,
    shiftController: shifts,
    alarmController: alarms,
    alarmSyncCoordinator: coordinator,
  );
  await controller.initialize();
  return _Harness(
    controller: controller,
    repository: soundRepository,
    native: native,
    app: app,
  );
}

void main() {
  test('初始化会清理临时文件和孤立文件', () async {
    final harness = await _createHarness(seed: _sound('one'));
    addTearDown(harness.controller.dispose);
    expect(harness.native.cleanupTempsCalls, 1);
    expect(harness.native.cleanupOrphansCalls, 1);
    expect(harness.native.retainedPaths, ['/files/one.mp3']);
  });

  test('导入候选提交后写入完整铃声记录', () async {
    final harness = await _createHarness();
    addTearDown(harness.controller.dispose);
    final result = await harness.controller.commitCandidate(_candidate());
    expect(result.internalPath, '/internal/sound_1.mp3');
    expect(result.displayName, 'wake');
    expect(result.fileSize, 2048);
    expect(
      (await harness.repository.getAll()).single.checksum,
      'candidate-checksum',
    );
  });

  test('重复导入可按校验值找到已有记录', () async {
    final harness = await _createHarness(seed: _sound('one'));
    addTearDown(harness.controller.dispose);
    final duplicate = await harness.controller.findDuplicate(
      _candidate(checksum: 'checksum-one'),
    );
    expect(duplicate?.id, 'one');
  });

  test('重命名去除首尾空白并保留文件', () async {
    final harness = await _createHarness(seed: _sound('one'));
    addTearDown(harness.controller.dispose);
    await harness.controller.rename(harness.controller.items.single, '  新铃声  ');
    final result = await harness.repository.getById('one');
    expect(result?.displayName, '新铃声');
    expect(result?.internalPath, '/files/one.mp3');
  });

  test('设置应用默认铃声同步保存设置和铃声标志', () async {
    final harness = await _createHarness(seed: _sound('one'));
    addTearDown(harness.controller.dispose);
    await harness.controller.setDefault(harness.controller.items.single);
    expect(harness.app.settings.defaultSoundId, 'one');
    expect((await harness.repository.getById('one'))?.isDefault, isTrue);
  });

  test('改回系统默认会清除自定义默认标志', () async {
    final harness = await _createHarness(seed: _sound('one'));
    addTearDown(harness.controller.dispose);
    await harness.controller.setDefault(harness.controller.items.single);
    await harness.controller.setDefault(null);
    expect(harness.app.settings.defaultSoundId, SoundIds.system);
    expect((await harness.repository.getById('one'))?.isDefault, isFalse);
  });

  test('同一铃声再次点击会暂停试听', () async {
    final harness = await _createHarness(seed: _sound('one'));
    addTearDown(harness.controller.dispose);
    final sound = harness.controller.items.single;
    await harness.controller.playPreview(sound);
    expect(harness.controller.previewState.isPlaying, isTrue);
    await harness.controller.playPreview(sound);
    expect(harness.controller.previewState.isPlaying, isFalse);
  });

  test('切换试听铃声会更新当前唯一播放 ID', () async {
    final harness = await _createHarness(seed: _sound('one'));
    addTearDown(harness.controller.dispose);
    await harness.repository.add(_sound('two'));
    await harness.controller.load();
    await harness.controller.playPreview(harness.controller.items.first);
    await harness.controller.playPreview(harness.controller.items.last);
    expect(harness.controller.previewSoundId, harness.controller.items.last.id);
  });

  test('校验失败会标记铃声不可用并保留失败原因', () async {
    final harness = await _createHarness(seed: _sound('one'));
    addTearDown(harness.controller.dispose);
    harness.native.verifications['/files/one.mp3'] = const SoundVerification(
      isAvailable: false,
      failureReason: 'checksum_mismatch',
    );
    await harness.controller.verifyAll();
    final result = await harness.repository.getById('one');
    expect(result?.isAvailable, isFalse);
    expect(result?.failureReason, 'checksum_mismatch');
  });

  test('原生正式响铃降级事件会在下次打开时提示并停用文件', () async {
    final harness = await _createHarness(seed: _sound('one'));
    addTearDown(harness.controller.dispose);
    harness.native.events.add({'soundId': 'one', 'reason': 'decode_failed'});
    await harness.controller.reconcileNativeFailures();
    expect((await harness.repository.getById('one'))?.isAvailable, isFalse);
    expect(harness.controller.noticeMessage, contains('系统默认铃声'));
  });

  test('删除铃声会先移除引用记录再删除内部文件', () async {
    final harness = await _createHarness(seed: _sound('one'));
    addTearDown(harness.controller.dispose);
    final sound = harness.controller.items.single;
    await harness.controller.replaceAndDelete(sound);
    expect(await harness.repository.getById('one'), isNull);
    expect(harness.native.deleted, contains('/files/one.mp3'));
  });
}
