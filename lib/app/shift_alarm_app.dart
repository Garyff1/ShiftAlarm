import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../data/models/app_enums.dart';
import '../features/settings/app_controller.dart';
import '../features/settings/interface_mode_page.dart';
import '../features/alarms/alarm_controller.dart';
import '../features/shifts/shift_controller.dart';
import '../features/schedule/schedule_controller.dart';
import '../features/sounds/sound_controller.dart';
import '../shared/widgets/async_states.dart';
import 'app_navigation.dart';
import 'main_shell.dart';

class ShiftAlarmApp extends StatefulWidget {
  const ShiftAlarmApp({
    super.key,
    required this.appController,
    required this.shiftController,
    required this.scheduleController,
    required this.alarmController,
    required this.soundController,
    required this.navigationController,
  });

  final AppController appController;
  final ShiftController shiftController;
  final ScheduleController scheduleController;
  final AlarmController alarmController;
  final SoundController soundController;
  final AppNavigationController navigationController;

  @override
  State<ShiftAlarmApp> createState() => _ShiftAlarmAppState();
}

class _ShiftAlarmAppState extends State<ShiftAlarmApp>
    with WidgetsBindingObserver {
  Timer? _clockTimer;
  late DateTime _lastClockSample;
  bool _checkingClock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastClockSample = DateTime.now();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_checkClock()),
    );
  }

  Future<void> _checkClock({bool force = false}) async {
    if (_checkingClock) return;
    final current = DateTime.now();
    final previous = _lastClockSample;
    _lastClockSample = current;
    final dateChanged =
        current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
    final timezoneChanged = current.timeZoneOffset != previous.timeZoneOffset;
    if (!force && !dateChanged && !timezoneChanged) return;
    _checkingClock = true;
    try {
      await widget.scheduleController.refreshForClockChange(
        previous: previous,
        current: current,
      );
    } finally {
      _checkingClock = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkClock(force: true));
      unawaited(widget.alarmController.handleResume());
      unawaited(widget.soundController.handleResume());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(widget.soundController.stopPreview());
    }
  }

  ThemeMode _themeMode(AppThemeMode mode) => switch (mode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: widget.appController),
      ChangeNotifierProvider.value(value: widget.shiftController),
      ChangeNotifierProvider.value(value: widget.scheduleController),
      ChangeNotifierProvider.value(value: widget.alarmController),
      ChangeNotifierProvider.value(value: widget.soundController),
      ChangeNotifierProvider.value(value: widget.navigationController),
    ],
    child: Consumer<AppController>(
      builder: (context, app, _) => MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(
          interfaceMode: app.settings.interfaceMode,
          highContrast: app.settings.highContrastEnabled,
          reduceMotion: app.settings.reduceMotion,
        ),
        darkTheme: AppTheme.dark(
          interfaceMode: app.settings.interfaceMode,
          highContrast: app.settings.highContrastEnabled,
          reduceMotion: app.settings.reduceMotion,
        ),
        themeMode: _themeMode(app.settings.themeMode),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              disableAnimations:
                  media.disableAnimations || app.settings.reduceMotion,
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: app.initializationError == null
            ? app.settings.onboardingCompleted
                  ? const MainShell()
                  : const InterfaceModePage(onboarding: true)
            : Scaffold(
                appBar: AppBar(title: const Text(AppConstants.appName)),
                body: ErrorState(
                  message: app.initializationError!,
                  onRetry: app.initialize,
                ),
              ),
      ),
    ),
  );

  @override
  void dispose() {
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
