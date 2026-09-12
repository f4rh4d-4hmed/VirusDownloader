import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/constants.dart';
import 'core/utils.dart';
import 'data/repositories/download_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/background_service.dart';
import 'data/services/browser_integration_service.dart';
import 'data/services/ffmpeg_service.dart';
import 'data/services/file_service.dart';
import 'data/services/http_download_service.dart';
import 'data/services/integrity_service.dart';
import 'data/services/integration_server_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/permission_service.dart';
import 'data/services/proxy_service.dart';
import 'data/services/segmented_download_service.dart';
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

  // Initialize Core Services & Startup Permissions
  final permissionService = PermissionService();
  await permissionService.checkAndRequestAllPermissions();

  final notificationService = NotificationService();
  await notificationService.init();

  final storageService = StorageService();
  await storageService.init();

  final fileService = FileService();
  final httpService = HttpDownloadService();
  final ffmpegService = FfmpegService();
  final proxyService = ProxyService();
  final integrityService = IntegrityService();

  final segmentedService = SegmentedDownloadService(
    proxyService: proxyService,
    fileService: fileService,
  );

  final backgroundService = BackgroundService();

  final settingsRepository = SettingsRepository(storageService: storageService);
  await settingsRepository.init();

  if (settingsRepository.currentSettings.runInBackground) {
    await backgroundService.startBackgroundService();
  }

  final downloadRepository = DownloadRepository(
    httpService: httpService,
    segmentedService: segmentedService,
    storageService: storageService,
    fileService: fileService,
    settingsRepo: settingsRepository,
    ffmpegService: ffmpegService,
    notificationService: notificationService,
    integrityService: integrityService,
  );
  await downloadRepository.init();

  // Initialize Browser Integration & Start Local Server
  final browserIntegrationService = BrowserIntegrationService();
  final integrationServer = IntegrationServerService(
    downloadRepository: downloadRepository,
    fileService: fileService,
  );
  if (!AppUtils.isMobile) {
    await integrationServer.start();
  }

  runApp(
    MultiProvider(
      providers: [
        // Services
        Provider<PermissionService>.value(value: permissionService),
        Provider<NotificationService>.value(value: notificationService),
        Provider<StorageService>.value(value: storageService),
        Provider<FileService>.value(value: fileService),
        Provider<HttpDownloadService>.value(value: httpService),
        Provider<FfmpegService>.value(value: ffmpegService),
        Provider<ProxyService>.value(value: proxyService),
        Provider<IntegrityService>.value(value: integrityService),
        Provider<SegmentedDownloadService>.value(value: segmentedService),
        Provider<BackgroundService>.value(value: backgroundService),
        Provider<BrowserIntegrationService>.value(value: browserIntegrationService),
        ChangeNotifierProvider<IntegrationServerService>.value(value: integrationServer),

        // Repositories
        ChangeNotifierProvider<DownloadRepository>.value(value: downloadRepository),
        Provider<SettingsRepository>.value(value: settingsRepository),

        // ViewModels
        ChangeNotifierProvider<DownloadsViewModel>(
          create: (_) => DownloadsViewModel(repository: downloadRepository),
        ),
        ChangeNotifierProvider<SettingsViewModel>(
          create: (_) => SettingsViewModel(
            repository: settingsRepository,
            browserService: browserIntegrationService,
            integrationServer: integrationServer,
            proxyService: proxyService,
            backgroundService: backgroundService,
          ),
        ),
      ],
      child: const VirusDownloaderApp(),
    ),
  );
}
