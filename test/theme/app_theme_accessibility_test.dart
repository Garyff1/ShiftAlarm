import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_alarm/core/theme/app_mode_theme.dart';
import 'package:shift_alarm/core/theme/app_theme.dart';
import 'package:shift_alarm/data/models/app_enums.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final interfaceMode in AppInterfaceMode.values) {
      test('${brightness.name} ${interfaceMode.name} 提供集中模式参数', () {
        final theme = brightness == Brightness.light
            ? AppTheme.light(interfaceMode: interfaceMode)
            : AppTheme.dark(interfaceMode: interfaceMode);
        final mode = theme.extension<AppModeTheme>();
        expect(mode, isNotNull);
        expect(mode!.largeText, interfaceMode == AppInterfaceMode.largeText);
        expect(mode.simple, interfaceMode == AppInterfaceMode.simple);
        expect(mode.minimumTouchTarget, greaterThanOrEqualTo(48));
        expect(mode.primaryButtonHeight, greaterThanOrEqualTo(52));
      });
    }
  }

  for (final interfaceMode in AppInterfaceMode.values) {
    test('${interfaceMode.name} 触控尺寸符合模式规则', () {
      final mode = AppTheme.light(
        interfaceMode: interfaceMode,
      ).extension<AppModeTheme>()!;
      if (interfaceMode == AppInterfaceMode.standard) {
        expect(mode.minimumTouchTarget, 48);
        expect(mode.primaryButtonHeight, 52);
        expect(mode.navigationBarHeight, 72);
      } else {
        expect(mode.minimumTouchTarget, 56);
        expect(mode.primaryButtonHeight, 60);
        expect(mode.navigationBarHeight, greaterThanOrEqualTo(80));
      }
    });
  }

  for (final brightness in Brightness.values) {
    test('${brightness.name} 高对比度提高次要文字与边框可见性', () {
      final normal = brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark();
      final high = brightness == Brightness.light
          ? AppTheme.light(highContrast: true)
          : AppTheme.dark(highContrast: true);
      expect(
        high.colorScheme.onSurfaceVariant,
        isNot(normal.colorScheme.onSurfaceVariant),
      );
      expect(high.colorScheme.outline, isNot(normal.colorScheme.outline));
      expect(high.extension<AppModeTheme>()!.highContrast, isTrue);
    });
  }

  for (final reduceMotion in [false, true]) {
    test('减少动画 $reduceMotion 写入主题扩展', () {
      final theme = AppTheme.light(reduceMotion: reduceMotion);
      expect(theme.extension<AppModeTheme>()!.reduceMotion, reduceMotion);
      if (reduceMotion) {
        expect(theme.extension<AppModeTheme>()!.cardAnimation, Duration.zero);
      } else {
        expect(
          theme.extension<AppModeTheme>()!.cardAnimation,
          greaterThan(Duration.zero),
        );
      }
    });
  }

  test('大字模式正文和导航文字明显大于标准模式', () {
    final large = AppTheme.light(interfaceMode: AppInterfaceMode.largeText);
    expect(large.textTheme.bodyMedium!.fontSize, closeTo(18.2, 0.01));
    expect(large.textTheme.labelLarge!.fontSize, closeTo(18.2, 0.01));
  });
}
