import 'package:flutter/material.dart';

@immutable
class AppModeTheme extends ThemeExtension<AppModeTheme> {
  const AppModeTheme({
    required this.largeText,
    required this.simple,
    required this.highContrast,
    required this.reduceMotion,
    required this.pagePadding,
    required this.cardPadding,
    required this.sectionSpacing,
    required this.minimumTouchTarget,
    required this.primaryButtonHeight,
    required this.navigationBarHeight,
  });

  final bool largeText;
  final bool simple;
  final bool highContrast;
  final bool reduceMotion;
  final double pagePadding;
  final double cardPadding;
  final double sectionSpacing;
  final double minimumTouchTarget;
  final double primaryButtonHeight;
  final double navigationBarHeight;

  Duration get shortAnimation =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 140);
  Duration get cardAnimation =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

  static AppModeTheme of(BuildContext context) =>
      Theme.of(context).extension<AppModeTheme>() ?? standard;

  static const standard = AppModeTheme(
    largeText: false,
    simple: false,
    highContrast: false,
    reduceMotion: false,
    pagePadding: 16,
    cardPadding: 18,
    sectionSpacing: 20,
    minimumTouchTarget: 48,
    primaryButtonHeight: 52,
    navigationBarHeight: 72,
  );

  @override
  AppModeTheme copyWith({
    bool? largeText,
    bool? simple,
    bool? highContrast,
    bool? reduceMotion,
    double? pagePadding,
    double? cardPadding,
    double? sectionSpacing,
    double? minimumTouchTarget,
    double? primaryButtonHeight,
    double? navigationBarHeight,
  }) => AppModeTheme(
    largeText: largeText ?? this.largeText,
    simple: simple ?? this.simple,
    highContrast: highContrast ?? this.highContrast,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    pagePadding: pagePadding ?? this.pagePadding,
    cardPadding: cardPadding ?? this.cardPadding,
    sectionSpacing: sectionSpacing ?? this.sectionSpacing,
    minimumTouchTarget: minimumTouchTarget ?? this.minimumTouchTarget,
    primaryButtonHeight: primaryButtonHeight ?? this.primaryButtonHeight,
    navigationBarHeight: navigationBarHeight ?? this.navigationBarHeight,
  );

  @override
  AppModeTheme lerp(covariant AppModeTheme? other, double t) {
    if (other == null) return this;
    return AppModeTheme(
      largeText: t < 0.5 ? largeText : other.largeText,
      simple: t < 0.5 ? simple : other.simple,
      highContrast: t < 0.5 ? highContrast : other.highContrast,
      reduceMotion: t < 0.5 ? reduceMotion : other.reduceMotion,
      pagePadding: lerpDouble(pagePadding, other.pagePadding, t),
      cardPadding: lerpDouble(cardPadding, other.cardPadding, t),
      sectionSpacing: lerpDouble(sectionSpacing, other.sectionSpacing, t),
      minimumTouchTarget: lerpDouble(
        minimumTouchTarget,
        other.minimumTouchTarget,
        t,
      ),
      primaryButtonHeight: lerpDouble(
        primaryButtonHeight,
        other.primaryButtonHeight,
        t,
      ),
      navigationBarHeight: lerpDouble(
        navigationBarHeight,
        other.navigationBarHeight,
        t,
      ),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
