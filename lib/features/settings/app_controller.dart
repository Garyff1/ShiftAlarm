import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../data/models/app_settings.dart';
import '../../data/repositories/app_settings_repository.dart';
import '../../data/storage/local_data_store.dart';

class AppController extends ChangeNotifier {
  AppController({required this.store, required this.settingsRepository});

  final LocalDataStore store;
  final AppSettingsRepository settingsRepository;
  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;
  String? initializationError;
  String? settingsError;

  Future<void> initialize() async {
    try {
      await store.initialize();
      _settings = await settingsRepository.load();
      initializationError = null;
    } on AppException catch (error) {
      initializationError = error.userMessage;
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 应用初始化失败: $error\n$stackTrace');
      initializationError = '应用初始化失败，请重新打开应用';
    }
    notifyListeners();
  }

  Future<bool> updateSettings(AppSettings value) async {
    final previous = _settings;
    _settings = value;
    settingsError = null;
    notifyListeners();
    try {
      await settingsRepository.save(value);
      return true;
    } catch (error, stackTrace) {
      debugPrint('[ShiftAlarm] 设置保存失败: $error\n$stackTrace');
      _settings = previous;
      settingsError = '设置保存失败，已恢复原设置';
      notifyListeners();
      return false;
    }
  }
}
