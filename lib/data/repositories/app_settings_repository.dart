import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

abstract interface class AppSettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
  Stream<AppSettings> watch();
  Future<void> clearForTesting();
}

class SharedPreferencesAppSettingsRepository implements AppSettingsRepository {
  SharedPreferencesAppSettingsRepository(this.preferences);
  static const _key = 'app_settings_v1';
  final SharedPreferences preferences;
  final ValueNotifier<AppSettings?> _changes = ValueNotifier(null);

  @override
  Future<AppSettings> load() async {
    final raw = preferences.getString(_key);
    if (raw == null) return const AppSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const AppSettings();
      return AppSettings.fromMap(decoded);
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 设置数据损坏，已使用默认值: $error\n$stackTrace');
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    final succeeded = await preferences.setString(
      _key,
      jsonEncode(settings.toMap()),
    );
    if (!succeeded) throw StateError('SharedPreferences write failed');
    _changes.value = settings;
  }

  @override
  Stream<AppSettings> watch() async* {
    await for (final _ in _valueListenableStream(_changes)) {
      final value = _changes.value;
      if (value != null) yield value;
    }
  }

  Stream<void> _valueListenableStream(ValueListenable<Object?> listenable) {
    late void Function() listener;
    return Stream<void>.multi((controller) {
      listener = () => controller.add(null);
      listenable.addListener(listener);
      controller.onCancel = () => listenable.removeListener(listener);
    });
  }

  @override
  Future<void> clearForTesting() async {
    await preferences.remove(_key);
    _changes.value = const AppSettings();
  }
}

class MemoryAppSettingsRepository implements AppSettingsRepository {
  MemoryAppSettingsRepository([this._settings = const AppSettings()]);
  AppSettings _settings;
  final ValueNotifier<AppSettings?> _changes = ValueNotifier(null);

  @override
  Future<AppSettings> load() async => _settings;
  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
    _changes.value = settings;
  }

  @override
  Stream<AppSettings> watch() async* {
    yield _settings;
  }

  @override
  Future<void> clearForTesting() async => _settings = const AppSettings();
}
