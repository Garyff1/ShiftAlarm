import 'package:flutter/services.dart';
import '../../data/models/app_settings.dart';

abstract final class InteractionFeedbackService {
  static Future<void> selection(AppSettings settings) async {
    if (settings.hapticFeedbackEnabled) {
      await HapticFeedback.selectionClick();
    }
  }

  static Future<void> success(AppSettings settings) async {
    if (settings.hapticFeedbackEnabled) {
      await HapticFeedback.lightImpact();
    }
  }

  static Future<void> warning(AppSettings settings) async {
    if (settings.hapticFeedbackEnabled) {
      await HapticFeedback.mediumImpact();
    }
  }
}
