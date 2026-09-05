import 'package:flutter/material.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/app_settings.dart';

class SettingsViewModel extends ChangeNotifier {
  final SettingsRepository repository;

  SettingsViewModel({required this.repository});

  AppSettings get settings => repository.currentSettings;

  Future<void> updateSavePath(String path) async {
    final updated = settings.copyWith(defaultSavePath: path);
    await repository.updateSettings(updated);
    notifyListeners();
  }

  Future<void> updateMaxConcurrent(int maxConcurrent) async {
    final updated = settings.copyWith(maxConcurrentDownloads: maxConcurrent);
    await repository.updateSettings(updated);
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    final updated = settings.copyWith(themeMode: mode);
    await repository.updateSettings(updated);
    notifyListeners();
  }

  Future<void> updateConfirmDelete(bool confirm) async {
    final updated = settings.copyWith(confirmOnDelete: confirm);
    await repository.updateSettings(updated);
    notifyListeners();
  }
}

