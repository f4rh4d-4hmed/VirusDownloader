import '../../domain/models/app_settings.dart';
import '../services/storage_service.dart';

class SettingsRepository {
  final StorageService storageService;
  AppSettings _settings = const AppSettings();

  SettingsRepository({required this.storageService});

  AppSettings get currentSettings => _settings;

  Future<void> init() async {
    _settings = await storageService.loadSettings();
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    await storageService.saveSettings(newSettings);
  }
}

