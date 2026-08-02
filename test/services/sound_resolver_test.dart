import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/data/models/alarm_sound.dart';
import 'package:shift_alarm/data/models/sound_ids.dart';
import 'package:shift_alarm/services/sounds/sound_resolver.dart';

AlarmSound _sound(
  String id, {
  bool available = true,
  String path = '/files/sound.mp3',
  String checksum = 'checksum',
}) => AlarmSound(
  id: id,
  displayName: id,
  internalPath: path,
  sourceName: '$id.mp3',
  mimeType: 'audio/mpeg',
  format: 'mp3',
  fileSize: 100,
  durationMilliseconds: 1000,
  isAvailable: available,
  checksum: checksum,
  importedAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ResolvedAlarmSound _resolve({
  String? reminder,
  String? shift,
  String? app,
  Iterable<AlarmSound> sounds = const [],
}) => SoundResolver.resolve(
  reminderSoundId: reminder,
  shiftSoundId: shift,
  appDefaultSoundId: app,
  sounds: sounds,
);

void main() {
  test('全部未设置时使用系统默认铃声', () {
    expect(_resolve().id, SoundIds.system);
  });

  test('应用默认自定义铃声可被解析', () {
    final result = _resolve(app: 'app', sounds: [_sound('app')]);
    expect(result.id, 'app');
    expect(result.path, '/files/sound.mp3');
  });

  test('班次铃声优先于应用默认', () {
    final result = _resolve(
      shift: 'shift',
      app: 'app',
      sounds: [_sound('app'), _sound('shift')],
    );
    expect(result.id, 'shift');
  });

  test('单条提醒铃声优先于班次和应用默认', () {
    final result = _resolve(
      reminder: 'rule',
      shift: 'shift',
      app: 'app',
      sounds: [_sound('app'), _sound('shift'), _sound('rule')],
    );
    expect(result.id, 'rule');
  });

  test('单条提醒显式选择系统铃声会停止向下查找', () {
    final result = _resolve(
      reminder: SoundIds.system,
      shift: 'shift',
      app: 'app',
      sounds: [_sound('app'), _sound('shift')],
    );
    expect(result.isSystem, isTrue);
  });

  test('提醒铃声记录缺失时降级到班次铃声', () {
    expect(
      _resolve(
        reminder: 'missing',
        shift: 'shift',
        sounds: [_sound('shift')],
      ).id,
      'shift',
    );
  });

  test('提醒铃声不可用时降级到班次铃声', () {
    final result = _resolve(
      reminder: 'broken',
      shift: 'shift',
      sounds: [_sound('broken', available: false), _sound('shift')],
    );
    expect(result.id, 'shift');
  });

  test('班次铃声不可用时降级到应用默认', () {
    final result = _resolve(
      shift: 'broken',
      app: 'app',
      sounds: [_sound('broken', available: false), _sound('app')],
    );
    expect(result.id, 'app');
  });

  test('自定义铃声路径为空时降级到系统默认', () {
    expect(
      _resolve(
        app: 'broken',
        sounds: [_sound('broken', path: '')],
      ).isSystem,
      isTrue,
    );
  });

  test('自定义铃声校验值为空时降级到系统默认', () {
    expect(
      _resolve(
        app: 'broken',
        sounds: [_sound('broken', checksum: '')],
      ).isSystem,
      isTrue,
    );
  });
}
