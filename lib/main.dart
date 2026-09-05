import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/constants.dart';
import 'data/repositories/download_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/file_service.dart';
import 'data/services/http_download_service.dart';
import 'data/services/storage_service.dart';
import 'ui/view_models/downloads_view_model.dart';
import 'ui/view_models/settings_view_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop Window Configuration
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1080, 720),
        minimumSize: Size(820, 560),
        center: true,
        title: AppConstants.appName,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('Window manager initialization failed: $e');
    }
  }

  // Initialize Core Services & Repositories
  final storageService = StorageService();
  await storageService.init();

  final fileService = FileService();
  final httpService = HttpDownloadService();

  final settingsRepository = SettingsRepository(storageService: storageService);
  await settingsRepository.init();

  final downloadRepository = DownloadRepository(
    httpService: httpService,
    storageService: storageService,
    fileService: fileService,
    settingsRepo: settingsRepository,
  );
  await downloadRepository.init();

  runApp(
    MultiProvider(
      providers: [
        // Services
        Provider<StorageService>.value(value: storageService),
        Provider<FileService>.value(value: fileService),
        Provider<HttpDownloadService>.value(value: httpService),

        // Repositories
        ChangeNotifierProvider<DownloadRepository>.value(value: downloadRepository),
        Provider<SettingsRepository>.value(value: settingsRepository),

        // ViewModels
        ChangeNotifierProvider<DownloadsViewModel>(
          create: (_) => DownloadsViewModel(repository: downloadRepository),
        ),
        ChangeNotifierProvider<SettingsViewModel>(
          create: (_) => SettingsViewModel(repository: settingsRepository),
        ),
      ],
      child: const VirusDownloaderApp(),
    ),
  );
}
