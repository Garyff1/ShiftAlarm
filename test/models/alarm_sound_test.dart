import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/data/models/alarm_sound.dart';

AlarmSound _sound({
  bool available = true,
  bool isDefault = false,
  String? failureReason,
}) {
  final created = DateTime(2026, 8, 2, 10, 30);
  return AlarmSound(
    id: 'sound-1',
    displayName: '强力起床铃',
    internalPath: '/files/alarm_sounds/sound_1.mp3',
    sourceName: 'wake.mp3',
    sourceUri: 'content://downloads/wake',
    mimeType: 'audio/mpeg',
    format: 'mp3',
    fileSize: 4096,
    durationMilliseconds: 65_000,
    isDefault: isDefault,
    isAvailable: available,
    checksum: 'abc123',
    importedAt: created,
    lastVerifiedAt: created.add(const Duration(minutes: 1)),
    failureReason: failureReason,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  test('AlarmSound v4 字段可完整序列化恢复', () {
    final sound = _sound(isDefault: true);
    final restored = AlarmSound.fromMap(sound.toMap());
    expect(restored.id, sound.id);
    expect(restored.displayName, '强力起床铃');
    expect(restored.internalPath, sound.internalPath);
    expect(restored.sourceUri, sound.sourceUri);
    expect(restored.durationMilliseconds, 65_000);
    expect(restored.isDefault, isTrue);
    expect(restored.checksum, 'abc123');
  });

  test('旧铃声记录缺少 v4 字段时使用安全默认值', () {
    final restored = AlarmSound.fromMap({
      'id': 'legacy',
      'displayName': '旧铃声',
      'internalPath': '/legacy.mp3',
      'createdAt': DateTime(2025).millisecondsSinceEpoch,
    });
    expect(restored.isAvailable, isTrue);
    expect(restored.isDefault, isFalse);
    expect(restored.fileSize, 0);
    expect(restored.durationMilliseconds, 0);
    expect(restored.importedAt, DateTime(2025));
  });

  test('copyWith 重命名不会改变文件身份', () {
    final original = _sound();
    final renamed = original.copyWith(displayName: '夜班铃声');
    expect(renamed.displayName, '夜班铃声');
    expect(renamed.id, original.id);
    expect(renamed.internalPath, original.internalPath);
    expect(renamed.checksum, original.checksum);
  });

  test('copyWith 可以标记文件不可用并记录原因', () {
    final changed = _sound().copyWith(
      isAvailable: false,
      failureReason: 'checksum_mismatch',
    );
    expect(changed.isAvailable, isFalse);
    expect(changed.failureReason, 'checksum_mismatch');
  });

  test('copyWith 可以清除旧失败原因', () {
    final recovered = _sound(
      available: false,
      failureReason: 'file_missing',
    ).copyWith(isAvailable: true, clearFailureReason: true);
    expect(recovered.isAvailable, isTrue);
    expect(recovered.failureReason, isNull);
  });

  test('系统铃声标志可持久化', () {
    final map = _sound().toMap()..['isSystemSound'] = true;
    expect(AlarmSound.fromMap(map).isSystemSound, isTrue);
  });

  test('来源 URI 允许为空', () {
    final map = _sound().toMap()..['sourceUri'] = null;
    expect(AlarmSound.fromMap(map).sourceUri, isNull);
  });

  test('校验与更新时间独立保存', () {
    final sound = _sound();
    final restored = AlarmSound.fromMap(sound.toMap());
    expect(restored.lastVerifiedAt, DateTime(2026, 8, 2, 10, 31));
    expect(restored.updatedAt, DateTime(2026, 8, 2, 10, 30));
  });
}
