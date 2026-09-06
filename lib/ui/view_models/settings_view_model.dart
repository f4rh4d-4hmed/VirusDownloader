import 'package:flutter/material.dart';
import '../../core/utils.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/browser_integration_service.dart';
import '../../data/services/integration_server_service.dart';
import '../../domain/models/app_settings.dart';

class SettingsViewModel extends ChangeNotifier {
  final SettingsRepository repository;
  final BrowserIntegrationService browserService;
  final IntegrationServerService integrationServer;

  List<DetectedBrowser> _detectedBrowsers = [];
  bool _isDetectingBrowsers = false;
  String _extensionPath = '';

  SettingsViewModel({
    required this.repository,
    required this.browserService,
    required this.integrationServer,
  }) {
    integrationServer.addListener(_onServerStateChanged);
    initBrowserIntegration();
  }

  @override
  void dispose() {
    integrationServer.removeListener(_onServerStateChanged);
    super.dispose();
  }

  void _onServerStateChanged() {
    notifyListeners();
  }

  AppSettings get settings => repository.currentSettings;
  List<DetectedBrowser> get detectedBrowsers => List.unmodifiable(_detectedBrowsers);
  bool get isDetectingBrowsers => _isDetectingBrowsers;
  String get extensionPath => _extensionPath;

  bool get isServerRunning => integrationServer.isRunning;
  int get serverPort => integrationServer.serverPort;
  DateTime? get lastConnectedTime => integrationServer.lastConnectedTime;
  int get receivedTasksCount => integrationServer.receivedTasksCount;

  Future<void> initBrowserIntegration() async {
    if (AppUtils.isMobile) return;

    _isDetectingBrowsers = true;
    notifyListeners();

    try {
      _extensionPath = await browserService.getExtensionPath();
      _detectedBrowsers = await browserService.detectInstalledBrowsers();
    } catch (e) {
      debugPrint('Error detecting browsers: $e');
    } finally {
      _isDetectingBrowsers = false;
      notifyListeners();
    }
  }

  Future<bool> launchBrowser(DetectedBrowser browser) async {
    return await browserService.launchBrowserWithExtension(browser);
  }

  Future<void> openExtensionFolder() async {
    await browserService.openExtensionFolder();
  }

  Future<String> copyExtensionPath() async {
    return await browserService.copyExtensionPathToClipboard();
  }

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
