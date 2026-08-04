import 'package:flutter/material.dart';
import '../../data/models/app_enums.dart';
import 'app_mode_theme.dart';

abstract final class AppTheme {
  static const seed = Color(0xFF2F6FE4);

  static ThemeData light({
    AppInterfaceMode interfaceMode = AppInterfaceMode.standard,
    bool highContrast = false,
    bool reduceMotion = false,
  }) => _build(
    Brightness.light,
    interfaceMode: interfaceMode,
    highContrast: highContrast,
    reduceMotion: reduceMotion,
  );

  static ThemeData dark({
    AppInterfaceMode interfaceMode = AppInterfaceMode.standard,
    bool highContrast = false,
    bool reduceMotion = false,
  }) => _build(
    Brightness.dark,
    interfaceMode: interfaceMode,
    highContrast: highContrast,
    reduceMotion: reduceMotion,
  );

  static ThemeData _build(
    Brightness brightness, {
    required AppInterfaceMode interfaceMode,
    required bool highContrast,
    required bool reduceMotion,
  }) {
    final largeText = interfaceMode.usesLargeText;
    final simple = interfaceMode.usesSimpleNavigation;
    var scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: brightness == Brightness.light
          ? const Color(0xFFF8F8FB)
          : const Color(0xFF091327),
    );
    if (highContrast) {
      scheme = scheme.copyWith(
        onSurface: brightness == Brightness.light
            ? const Color(0xFF080B12)
            : const Color(0xFFFFFFFF),
        onSurfaceVariant: brightness == Brightness.light
            ? const Color(0xFF252B36)
            : const Color(0xFFE2E9F7),
        outline: brightness == Brightness.light
            ? const Color(0xFF3B465A)
            : const Color(0xFFAEC1E6),
        outlineVariant: brightness == Brightness.light
            ? const Color(0xFF66728A)
            : const Color(0xFF7185AB),
      );
    }
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: reduceMotion
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _NoMotionTransitionsBuilder(),
                TargetPlatform.iOS: _NoMotionTransitionsBuilder(),
                TargetPlatform.windows: _NoMotionTransitionsBuilder(),
                TargetPlatform.macOS: _NoMotionTransitionsBuilder(),
                TargetPlatform.linux: _NoMotionTransitionsBuilder(),
              },
            )
          : const PageTransitionsTheme(),
    );
    final textTheme = largeText
        ? _scaledTextTheme(theme.textTheme, 1.30)
        : simple
        ? _scaledTextTheme(theme.textTheme, 1.12)
        : theme.textTheme;
    final modeTheme = AppModeTheme(
      largeText: largeText,
      simple: simple,
      highContrast: highContrast,
      reduceMotion: reduceMotion,
      pagePadding: largeText || simple ? 20 : 16,
      cardPadding: largeText || simple ? 22 : 18,
      sectionSpacing: largeText || simple ? 24 : 20,
      minimumTouchTarget: largeText || simple ? 56 : 48,
      primaryButtonHeight: largeText || simple ? 60 : 52,
      navigationBarHeight: largeText
          ? 88
          : simple
          ? 80
          : 72,
    );
    return theme.copyWith(
      textTheme: textTheme,
      extensions: [modeTheme],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: brightness == Brightness.dark
            ? const Color(0xFF111F3A)
            : scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(
              alpha: highContrast ? 0.95 : 0.62,
            ),
            width: highContrast ? 1.3 : 1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(88, modeTheme.primaryButtonHeight),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: modeTheme.navigationBarHeight,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          (largeText ? textTheme.labelLarge : textTheme.labelMedium)?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: Size.square(modeTheme.minimumTouchTarget),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: largeText || simple ? 64 : 56,
        iconColor: scheme.primary,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 0.5,
      ),
    );
  }

  static TextTheme _scaledTextTheme(TextTheme base, double factor) {
    TextStyle? scaled(TextStyle? style, double materialSize) =>
        style?.copyWith(fontSize: (style.fontSize ?? materialSize) * factor);

    return base.copyWith(
      displayLarge: scaled(base.displayLarge, 57),
      displayMedium: scaled(base.displayMedium, 45),
      displaySmall: scaled(base.displaySmall, 36),
      headlineLarge: scaled(base.headlineLarge, 32),
      headlineMedium: scaled(base.headlineMedium, 28),
      headlineSmall: scaled(base.headlineSmall, 24),
      titleLarge: scaled(base.titleLarge, 22),
      titleMedium: scaled(base.titleMedium, 16),
      titleSmall: scaled(base.titleSmall, 14),
      bodyLarge: scaled(base.bodyLarge, 16),
      bodyMedium: scaled(base.bodyMedium, 14),
      bodySmall: scaled(base.bodySmall, 12),
      labelLarge: scaled(base.labelLarge, 14),
      labelMedium: scaled(base.labelMedium, 12),
      labelSmall: scaled(base.labelSmall, 11),
    );
  }
}

class _NoMotionTransitionsBuilder extends PageTransitionsBuilder {
  const _NoMotionTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
