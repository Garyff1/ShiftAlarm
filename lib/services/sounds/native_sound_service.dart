import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';

class SoundImportCandidate {
  const SoundImportCandidate({
    required this.tempPath,
    required this.displayName,
    required this.sourceName,
    required this.sourceUri,
    required this.mimeType,
    required this.format,
    required this.fileSize,
    required this.durationMilliseconds,
    required this.checksum,
  });

  final String tempPath;
  final String displayName;
  final String sourceName;
  final String sourceUri;
  final String mimeType;
  final String format;
  final int fileSize;
  final int durationMilliseconds;
  final String checksum;

  factory SoundImportCandidate.fromMap(Map<Object?, Object?> map) =>
      SoundImportCandidate(
        tempPath: map['tempPath']?.toString() ?? '',
        displayName: map['displayName']?.toString() ?? '自定义铃声',
        sourceName: map['sourceName']?.toString() ?? '',
        sourceUri: map['sourceUri']?.toString() ?? '',
        mimeType:
            map['mimeType']?.toString() ??
            map['providerMimeType']?.toString() ??
            'audio/*',
        format: map['format']?.toString() ?? '',
        fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
        durationMilliseconds:
            (map['durationMilliseconds'] as num?)?.toInt() ?? 0,
        checksum: map['checksum']?.toString() ?? '',
      );
}

class SoundVerification {
  const SoundVerification({
    required this.isAvailable,
    this.failureReason,
    this.fileSize,
    this.durationMilliseconds,
    this.checksum,
    this.mimeType,
    this.format,
  });
  final bool isAvailable;
  final String? failureReason;
  final int? fileSize;
  final int? durationMilliseconds;
  final String? checksum;
  final String? mimeType;
  final String? format;

  factory SoundVerification.fromMap(Map<Object?, Object?> map) =>
      SoundVerification(
        isAvailable: map['isAvailable'] == true,
        failureReason: map['failureReason']?.toString(),
        fileSize: (map['fileSize'] as num?)?.toInt(),
        durationMilliseconds: (map['durationMilliseconds'] as num?)?.toInt(),
        checksum: map['checksum']?.toString(),
        mimeType: map['mimeType']?.toString(),
        format: map['format']?.toString(),
      );
}

class SoundPreviewState {
  const SoundPreviewState({
    this.isPlaying = false,
    this.positionMilliseconds = 0,
    this.durationMilliseconds = 0,
    this.path,
    this.isSystem = false,
  });
  final bool isPlaying;
  final int positionMilliseconds;
  final int durationMilliseconds;
  final String? path;
  final bool isSystem;
  factory SoundPreviewState.fromMap(
    Map<Object?, Object?> map,
  ) => SoundPreviewState(
    isPlaying: map['isPlaying'] == true,
    positionMilliseconds: (map['positionMilliseconds'] as num?)?.toInt() ?? 0,
    durationMilliseconds: (map['durationMilliseconds'] as num?)?.toInt() ?? 0,
    path: map['path']?.toString(),
    isSystem: map['isSystem'] == true,
  );
}

abstract interface class NativeSoundService {
  Future<SoundImportCandidate?> pickSound();
  Future<String> commitImport(String tempPath);
  Future<void> discardImport(String tempPath);
  Future<SoundVerification> verify(String path, String checksum);
  Future<bool> deleteFile(String path);
  Future<int> cleanupTemps();
  Future<int> cleanupOrphans(Iterable<String> retainedPaths);
  Future<SoundPreviewState> playPreview({String? path, bool system = false});
  Future<SoundPreviewState> pausePreview();
  Future<SoundPreviewState> resumePreview();
  Future<void> stopPreview();
  Future<SoundPreviewState> previewState();
  Future<List<Map<String, Object?>>> consumeSoundEvents();
}

class MethodChannelNativeSoundService implements NativeSoundService {
  const MethodChannelNativeSoundService();
  static const _channel = MethodChannel(AppConstants.alarmChannel);

  @override
  Future<SoundImportCandidate?> pickSound() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('pickSound');
    return map == null ? null : SoundImportCandidate.fromMap(map);
  }

  @override
  Future<String> commitImport(String tempPath) async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'commitSoundImport',
      {'tempPath': tempPath},
    );
    return map?['internalPath']?.toString() ?? '';
  }

  @override
  Future<void> discardImport(String tempPath) =>
      _channel.invokeMethod<void>('discardSoundImport', {'tempPath': tempPath});

  @override
  Future<SoundVerification> verify(String path, String checksum) async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'verifySound',
      {'path': path, 'checksum': checksum},
    );
    return SoundVerification.fromMap(map ?? const {});
  }

  @override
  Future<bool> deleteFile(String path) async =>
      await _channel.invokeMethod<bool>('deleteSoundFile', {'path': path}) ??
      false;
  @override
  Future<int> cleanupTemps() async =>
      await _channel.invokeMethod<int>('cleanupSoundTemps') ?? 0;
  @override
  Future<int> cleanupOrphans(Iterable<String> retainedPaths) async =>
      await _channel.invokeMethod<int>('cleanupOrphanSounds', {
        'retainedPaths': retainedPaths.toList(),
      }) ??
      0;

  @override
  Future<SoundPreviewState> playPreview({
    String? path,
    bool system = false,
  }) async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'playSoundPreview',
      {'path': path, 'system': system},
    );
    return SoundPreviewState.fromMap(map ?? const {});
  }

  Future<SoundPreviewState> _stateMethod(String method) async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(method);
    return SoundPreviewState.fromMap(map ?? const {});
  }

  @override
  Future<SoundPreviewState> pausePreview() => _stateMethod('pauseSoundPreview');
  @override
  Future<SoundPreviewState> resumePreview() =>
      _stateMethod('resumeSoundPreview');
  @override
  Future<void> stopPreview() => _channel.invokeMethod<void>('stopSoundPreview');
  @override
  Future<SoundPreviewState> previewState() =>
      _stateMethod('getSoundPreviewState');

  @override
  Future<List<Map<String, Object?>>> consumeSoundEvents() async {
    final values = await _channel.invokeListMethod<Object?>(
      'consumeSoundEvents',
    );
    return (values ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList();
  }
}

class MemoryNativeSoundService implements NativeSoundService {
  SoundImportCandidate? nextCandidate;
  final Map<String, SoundVerification> verifications = {};
  final List<Map<String, Object?>> events = [];
  SoundPreviewState state = const SoundPreviewState();
  final Set<String> deleted = {};
  final List<String> discarded = [];
  List<String> retainedPaths = [];
  int commits = 0;
  int cleanupTempsCalls = 0;
  int cleanupOrphansCalls = 0;
  bool deleteSucceeds = true;

  @override
  Future<SoundImportCandidate?> pickSound() async => nextCandidate;
  @override
  Future<String> commitImport(String tempPath) async {
    commits++;
    return '/internal/sound_$commits.mp3';
  }

  @override
  Future<void> discardImport(String tempPath) async {
    discarded.add(tempPath);
  }

  @override
  Future<SoundVerification> verify(String path, String checksum) async =>
      verifications[path] ?? const SoundVerification(isAvailable: true);
  @override
  Future<bool> deleteFile(String path) async {
    deleted.add(path);
    return deleteSucceeds;
  }

  @override
  Future<int> cleanupTemps() async {
    cleanupTempsCalls++;
    return 0;
  }

  @override
  Future<int> cleanupOrphans(Iterable<String> retainedPaths) async {
    cleanupOrphansCalls++;
    this.retainedPaths = retainedPaths.toList();
    return 0;
  }

  @override
  Future<SoundPreviewState> playPreview({
    String? path,
    bool system = false,
  }) async => state = SoundPreviewState(
    isPlaying: true,
    positionMilliseconds: 0,
    durationMilliseconds: 1000,
    path: path,
    isSystem: system,
  );
  @override
  Future<SoundPreviewState> pausePreview() async => state = SoundPreviewState(
    isPlaying: false,
    positionMilliseconds: state.positionMilliseconds,
    durationMilliseconds: state.durationMilliseconds,
    path: state.path,
    isSystem: state.isSystem,
  );
  @override
  Future<SoundPreviewState> resumePreview() async => state = SoundPreviewState(
    isPlaying: true,
    positionMilliseconds: state.positionMilliseconds,
    durationMilliseconds: state.durationMilliseconds,
    path: state.path,
    isSystem: state.isSystem,
  );
  @override
  Future<void> stopPreview() async => state = const SoundPreviewState();
  @override
  Future<SoundPreviewState> previewState() async => state;
  @override
  Future<List<Map<String, Object?>>> consumeSoundEvents() async {
    final result = List<Map<String, Object?>>.of(events);
    events.clear();
    return result;
  }
}
