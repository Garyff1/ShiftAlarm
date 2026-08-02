import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/utils/id_generator.dart';
import '../../data/models/alarm_sound.dart';
import '../../data/models/sound_ids.dart';
import '../../data/repositories/alarm_sound_repository.dart';
import '../../services/alarm/alarm_sync_coordinator.dart';
import '../../services/sounds/native_sound_service.dart';
import '../alarms/alarm_controller.dart';
import '../settings/app_controller.dart';
import '../shifts/shift_controller.dart';

class SoundController extends ChangeNotifier {
  SoundController({
    required this.repository,
    required this.nativeService,
    required this.appController,
    required this.shiftController,
    required this.alarmController,
    required this.alarmSyncCoordinator,
  });

  final AlarmSoundRepository repository;
  final NativeSoundService nativeService;
  final AppController appController;
  final ShiftController shiftController;
  final AlarmController alarmController;
  final AlarmSyncCoordinator alarmSyncCoordinator;

  List<AlarmSound> items = const [];
  Map<String, SoundReferenceSummary> usageBySoundId = const {};
  bool isLoading = true;
  bool isBusy = false;
  String? errorMessage;
  String? noticeMessage;
  String? previewSoundId;
  SoundPreviewState previewState = const SoundPreviewState();
  StreamSubscription<void>? _subscription;
  Timer? _previewTimer;
  bool _disposed = false;

  String get defaultSoundId =>
      appController.settings.defaultSoundId ?? SoundIds.system;
  AlarmSound? get defaultCustomSound =>
      items.where((item) => item.id == defaultSoundId).firstOrNull;

  Future<bool> scheduleTestAlarm(AlarmSound sound, {int delaySeconds = 60}) =>
      alarmController.startTestAlarm(sound: sound, delaySeconds: delaySeconds);

  Future<void> initialize() async {
    _subscription ??= repository.watch().listen((_) => load());
    await nativeService.cleanupTemps();
    await load(showLoading: true);
    await nativeService.cleanupOrphans(items.map((item) => item.internalPath));
    await verifyAll();
    await reconcileNativeFailures();
  }

  Future<void> load({bool showLoading = false}) async {
    if (_disposed) return;
    if (showLoading) {
      isLoading = true;
      notifyListeners();
    }
    try {
      items = await repository.getAll();
      usageBySoundId = {
        for (final item in items)
          item.id: (await repository.getReferenceSummary(
            item.id,
          )).copyWith(isAppDefault: defaultSoundId == item.id),
      };
      errorMessage = null;
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 铃声库加载失败: $error\n$stackTrace');
      errorMessage = '铃声库加载失败，请重试';
    } finally {
      isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<SoundImportCandidate?> pickSound() async {
    noticeMessage = null;
    errorMessage = null;
    try {
      final candidate = await nativeService.pickSound();
      if (candidate == null) noticeMessage = '没有选择音频文件';
      notifyListeners();
      return candidate;
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 铃声选择失败: $error\n$stackTrace');
      errorMessage = _friendlyImportError(error.toString());
      notifyListeners();
      return null;
    }
  }

  Future<AlarmSound?> findDuplicate(SoundImportCandidate candidate) =>
      repository.findByChecksum(candidate.checksum);

  Future<AlarmSound> commitCandidate(
    SoundImportCandidate candidate, {
    String? displayName,
  }) async {
    isBusy = true;
    notifyListeners();
    String? internalPath;
    try {
      internalPath = await nativeService.commitImport(candidate.tempPath);
      if (internalPath.isEmpty) throw StateError('内部铃声路径为空');
      final now = DateTime.now();
      final sound = AlarmSound(
        id: IdGenerator.create('sound'),
        displayName: (displayName ?? candidate.displayName).trim().take(80),
        internalPath: internalPath,
        sourceName: candidate.sourceName,
        sourceUri: candidate.sourceUri,
        mimeType: candidate.mimeType,
        format: candidate.format,
        fileSize: candidate.fileSize,
        durationMilliseconds: candidate.durationMilliseconds,
        checksum: candidate.checksum,
        importedAt: now,
        lastVerifiedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await repository.add(sound);
      noticeMessage = '“${sound.displayName}”已导入';
      await load();
      return sound;
    } catch (_) {
      if (internalPath != null) await nativeService.deleteFile(internalPath);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> discardCandidate(SoundImportCandidate candidate) =>
      nativeService.discardImport(candidate.tempPath);

  Future<void> rename(AlarmSound sound, String name) async {
    final normalized = name.trim().take(80);
    if (normalized.isEmpty) throw ArgumentError('铃声名称不能为空');
    await repository.update(sound.copyWith(displayName: normalized));
    noticeMessage = '铃声已重命名';
  }

  Future<void> setDefault(AlarmSound? sound) async {
    final nextId = sound?.id ?? SoundIds.system;
    final previous = appController.settings;
    final ok = await appController.updateSettings(
      previous.copyWith(defaultSoundId: nextId),
    );
    if (!ok) throw StateError('默认铃声保存失败');
    for (final item in items) {
      final shouldDefault = item.id == sound?.id;
      if (item.isDefault != shouldDefault) {
        await repository.update(item.copyWith(isDefault: shouldDefault));
      }
    }
    await alarmSyncCoordinator.synchronizeAll();
    await alarmController.loadRecords();
    noticeMessage = sound == null
        ? '已使用系统默认闹钟铃声'
        : '“${sound.displayName}”已设为应用默认';
    await load();
  }

  Future<SoundReferenceSummary> usageFor(AlarmSound sound) async {
    final summary = await repository.getReferenceSummary(sound.id);
    return summary.copyWith(isAppDefault: defaultSoundId == sound.id);
  }

  SoundReferenceSummary usageSnapshot(AlarmSound sound) =>
      usageBySoundId[sound.id] ?? const SoundReferenceSummary();

  void clearMessages() {
    errorMessage = null;
    noticeMessage = null;
  }

  Future<SoundReferenceSummary> replaceAndDelete(
    AlarmSound sound, {
    String replacementId = SoundIds.system,
  }) async {
    await stopPreview();
    final wasDefault = defaultSoundId == sound.id;
    final previousSettings = appController.settings;
    if (wasDefault) {
      final ok = await appController.updateSettings(
        appController.settings.copyWith(defaultSoundId: replacementId),
      );
      if (!ok) throw StateError('替代铃声保存失败');
    }
    late final SoundReferenceSummary summary;
    try {
      summary = await repository.replaceReferencesAndDelete(
        sound.id,
        replacementId,
        transferDefault: wasDefault,
      );
    } catch (_) {
      if (wasDefault) await appController.updateSettings(previousSettings);
      rethrow;
    }
    await shiftController.load(showLoading: false);
    await alarmSyncCoordinator.synchronizeAll();
    await alarmController.loadRecords();
    final fileDeleted = await nativeService.deleteFile(sound.internalPath);
    if (!fileDeleted) noticeMessage = '引用已替换，音频文件将在下次启动时继续清理';
    await load();
    noticeMessage ??= '铃声已删除，相关提醒已改用系统默认铃声';
    return summary.copyWith(isAppDefault: wasDefault);
  }

  Future<void> verifyAll() async {
    var resync = false;
    for (final sound in List<AlarmSound>.of(items)) {
      final result = await nativeService.verify(
        sound.internalPath,
        sound.checksum,
      );
      final changed =
          result.isAvailable != sound.isAvailable ||
          result.failureReason != sound.failureReason ||
          (result.checksum != null && result.checksum != sound.checksum);
      if (!changed) continue;
      await repository.update(
        sound.copyWith(
          isAvailable: result.isAvailable,
          fileSize: result.fileSize,
          durationMilliseconds: result.durationMilliseconds,
          checksum: result.checksum,
          mimeType: result.mimeType,
          format: result.format,
          lastVerifiedAt: DateTime.now(),
          failureReason: result.failureReason,
          clearFailureReason: result.isAvailable,
        ),
      );
      resync = true;
    }
    if (resync) {
      await load();
      await alarmSyncCoordinator.synchronizeAll();
      await alarmController.loadRecords();
      await load();
    }
  }

  Future<void> reconcileNativeFailures() async {
    final events = await nativeService.consumeSoundEvents();
    for (final event in events) {
      final id = event['soundId']?.toString();
      if (id == null || id == SoundIds.system) continue;
      final sound = await repository.getById(id);
      if (sound == null) continue;
      final reason = event['reason']?.toString() ?? 'decode_failed';
      await repository.update(
        sound.copyWith(
          isAvailable: false,
          failureReason: reason,
          lastVerifiedAt: DateTime.now(),
        ),
      );
      noticeMessage = '“${sound.displayName}”无法播放，相关提醒已临时使用系统默认铃声';
    }
    if (events.isNotEmpty) {
      await load();
      await alarmSyncCoordinator.synchronizeAll();
      await alarmController.loadRecords();
      await load();
    }
  }

  Future<void> playSystemPreview() => _play(id: SoundIds.system, system: true);
  Future<void> playPreview(AlarmSound sound) =>
      _play(id: sound.id, path: sound.internalPath);

  Future<void> _play({
    required String id,
    String? path,
    bool system = false,
  }) async {
    if (previewSoundId == id && previewState.isPlaying) {
      previewState = await nativeService.pausePreview();
      _previewTimer?.cancel();
      notifyListeners();
      return;
    }
    previewState = await nativeService.playPreview(path: path, system: system);
    previewSoundId = id;
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_refreshPreviewState());
    });
    notifyListeners();
  }

  Future<void> _refreshPreviewState() async {
    previewState = await nativeService.previewState();
    if (!previewState.isPlaying) _previewTimer?.cancel();
    notifyListeners();
  }

  Future<void> stopPreview() async {
    _previewTimer?.cancel();
    await nativeService.stopPreview();
    previewState = const SoundPreviewState();
    previewSoundId = null;
    notifyListeners();
  }

  Future<void> handleResume() async {
    await verifyAll();
    await reconcileNativeFailures();
  }

  String _friendlyImportError(String raw) {
    if (raw.contains('file_too_large')) return '文件超过 50MB，无法导入';
    if (raw.contains('file_empty')) return '所选文件为空';
    if (raw.contains('format_unsupported')) return '仅支持 MP3、WAV、M4A、AAC 和 OGG';
    if (raw.contains('decode_failed') || raw.contains('not_audio')) {
      return '文件不是可正常解码的音频';
    }
    if (raw.contains('file_unreadable')) return '无法读取所选文件';
    return '铃声导入失败，请选择其他音频';
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _previewTimer?.cancel();
    unawaited(nativeService.stopPreview());
    super.dispose();
  }
}

extension on String {
  String take(int maxLength) =>
      length <= maxLength ? this : substring(0, maxLength);
}
