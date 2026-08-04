import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/data/models/app_enums.dart';
import 'package:shift_alarm/data/models/app_settings.dart';

void main() {
  group('AppInterfaceMode', () {
    for (final mode in AppInterfaceMode.values) {
      test('${mode.name} 使用稳定存储值并保留中文说明', () {
        expect(mode.storageValue, isNotEmpty);
        expect(mode.label, isNotEmpty);
        expect(mode.description, isNotEmpty);
      });

      test('${mode.name} 可从存储值恢复', () {
        expect(AppInterfaceMode.fromStorage(mode.storageValue), mode);
      });
    }

    for (final value in <Object?>[null, '', 'legacy', 99, false]) {
      test('未知界面模式 $value 安全回退标准模式', () {
        expect(AppInterfaceMode.fromStorage(value), AppInterfaceMode.standard);
      });
    }
  });

  group('AppSettings accessibility fields', () {
    test('新安装默认进入首次界面选择', () {
      const settings = AppSettings();
      expect(settings.interfaceMode, AppInterfaceMode.standard);
      expect(settings.onboardingCompleted, isFalse);
      expect(settings.reduceMotion, isFalse);
      expect(settings.highContrastEnabled, isFalse);
      expect(settings.readAloudEnabled, isFalse);
      expect(settings.hapticFeedbackEnabled, isTrue);
    });

    test('Beta002 新字段完整序列化恢复', () {
      const original = AppSettings(
        themeMode: AppThemeMode.dark,
        interfaceMode: AppInterfaceMode.simple,
        reduceMotion: true,
        highContrastEnabled: true,
        readAloudEnabled: true,
        hapticFeedbackEnabled: false,
        onboardingCompleted: true,
      );
      final restored = AppSettings.fromMap(original.toMap());
      expect(restored.themeMode, AppThemeMode.dark);
      expect(restored.interfaceMode, AppInterfaceMode.simple);
      expect(restored.reduceMotion, isTrue);
      expect(restored.highContrastEnabled, isTrue);
      expect(restored.readAloudEnabled, isTrue);
      expect(restored.hapticFeedbackEnabled, isFalse);
      expect(restored.onboardingCompleted, isTrue);
    });

    test('copyWith 只修改适老化设置并保留闹钟默认值', () {
      const original = AppSettings(
        alarmGenerationDays: 21,
        defaultSnoozeMinutes: 7,
        defaultMaxSnoozeCount: 4,
      );
      final changed = original.copyWith(
        interfaceMode: AppInterfaceMode.largeText,
        reduceMotion: true,
        highContrastEnabled: true,
        hapticFeedbackEnabled: false,
        onboardingCompleted: true,
      );
      expect(changed.interfaceMode, AppInterfaceMode.largeText);
      expect(changed.reduceMotion, isTrue);
      expect(changed.highContrastEnabled, isTrue);
      expect(changed.hapticFeedbackEnabled, isFalse);
      expect(changed.onboardingCompleted, isTrue);
      expect(changed.alarmGenerationDays, 21);
      expect(changed.defaultSnoozeMinutes, 7);
      expect(changed.defaultMaxSnoozeCount, 4);
    });

    test('Beta001 旧设置没有 interfaceMode 时不强制再次引导', () {
      final legacy = const AppSettings(
        themeMode: AppThemeMode.dark,
        onboardingCompleted: false,
      ).toMap()..remove('interfaceMode');
      final restored = AppSettings.fromMap(legacy);
      expect(restored.interfaceMode, AppInterfaceMode.standard);
      expect(restored.onboardingCompleted, isTrue);
    });

    test('Beta002 设置明确未完成引导时保持未完成', () {
      final restored = AppSettings.fromMap(
        const AppSettings(onboardingCompleted: false).toMap(),
      );
      expect(restored.onboardingCompleted, isFalse);
    });

    for (final entry in <MapEntry<int, int>>[
      const MapEntry(-8, 1),
      const MapEntry(0, 1),
      const MapEntry(3, 3),
      const MapEntry(9, 7),
    ]) {
      test('一周起始日 ${entry.key} 限制为 ${entry.value}', () {
        expect(
          AppSettings.fromMap({'weekStartDay': entry.key}).weekStartDay,
          entry.value,
        );
      });
    }

    for (final entry in <MapEntry<int, int>>[
      const MapEntry(-1, 1),
      const MapEntry(22, 22),
      const MapEntry(120, 90),
    ]) {
      test('闹钟生成天数 ${entry.key} 限制为 ${entry.value}', () {
        expect(
          AppSettings.fromMap({
            'alarmGenerationDays': entry.key,
          }).alarmGenerationDays,
          entry.value,
        );
      });
    }

    for (final entry in <MapEntry<int, int>>[
      const MapEntry(-1, 1),
      const MapEntry(15, 15),
      const MapEntry(90, 60),
    ]) {
      test('贪睡分钟 ${entry.key} 限制为 ${entry.value}', () {
        expect(
          AppSettings.fromMap({
            'defaultSnoozeMinutes': entry.key,
          }).defaultSnoozeMinutes,
          entry.value,
        );
      });
    }

    for (final entry in <MapEntry<int, int>>[
      const MapEntry(-1, 0),
      const MapEntry(6, 6),
      const MapEntry(30, 10),
    ]) {
      test('最大贪睡次数 ${entry.key} 限制为 ${entry.value}', () {
        expect(
          AppSettings.fromMap({
            'defaultMaxSnoozeCount': entry.key,
          }).defaultMaxSnoozeCount,
          entry.value,
        );
      });
    }
  });
}
