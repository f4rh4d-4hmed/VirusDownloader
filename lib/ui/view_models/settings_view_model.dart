import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/enums.dart';
import '../../core/utils.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/browser_integration_service.dart';
import '../../data/services/integration_server_service.dart';
import '../../data/services/proxy_service.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/proxy_config.dart';

/// Result summary returned by [SettingsViewModel.addMultipleProxies].
class BatchAddProxyResult {
  final int addedCount;
  final int duplicateCount;
  final int failedCount;
  final List<String> failedLines;

  const BatchAddProxyResult({
    required this.addedCount,
    required this.duplicateCount,
    required this.failedCount,
    required this.failedLines,
  });

  bool get hasErrors => failedCount > 0;
  bool get hasDuplicates => duplicateCount > 0;
  bool get isSuccess => addedCount > 0;
}

class SettingsViewModel extends ChangeNotifier {
  final SettingsRepository repository;
  final BrowserIntegrationService browserService;
  final IntegrationServerService integrationServer;
  final ProxyService? proxyService;

  List<DetectedBrowser> _detectedBrowsers = [];
  bool _isDetectingBrowsers = false;
  String _extensionPath = '';

  SettingsViewModel({
    required this.repository,
    required this.browserService,
    required this.integrationServer,
    this.proxyService,
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

  Future<void> updateWorkerCount(int count) async {
    final updated = settings.copyWith(defaultWorkerCount: count);
    await repository.updateSettings(updated);
    notifyListeners();
  }

  Future<void> updatePlaceholderMode(bool enabled) async {
    final updated = settings.copyWith(usePlaceholderMode: enabled);
    await repository.updateSettings(updated);
    notifyListeners();
  }

  Future<void> updateSpeedLimitMode(SpeedLimitMode mode) async {
    final updated = settings.copyWith(speedLimitMode: mode);
    await repository.updateSettings(updated);
    notifyListeners();
  }

  Future<void> updateAutoRecheck(bool enabled) async {
    final updated = settings.copyWith(autoRecheckOnComplete: enabled);
    await repository.updateSettings(updated);
    notifyListeners();
  }

  String? addProxy(String input) {
    final trimmed = input.trim();
    if (trimmed.contains('\n') || trimmed.contains('\r')) {
      final res = addMultipleProxies(trimmed);
      if (res.addedCount == 0 && res.duplicateCount > 0) {
        return 'All proxies already exist in the list.';
      }
      if (res.addedCount == 0 && res.failedCount > 0) {
        return 'Invalid proxy format. Use socks5://[user:pass@]host:port or http://host:port';
      }
      return null;
    }

    final parsed = ProxyConfig.tryParse(trimmed);
    if (parsed == null) {
      return 'Invalid proxy format. Use socks5://[user:pass@]host:port or http://host:port';
    }

    // Check duplicate
    if (settings.proxyServers.any((p) => p == parsed)) {
      return 'Proxy already exists in the list.';
    }

    final list = List<ProxyConfig>.from(settings.proxyServers)..add(parsed);
    final updated = settings.copyWith(proxyServers: list);
    repository.updateSettings(updated);
    notifyListeners();
    return null;
  }

  /// Adds multiple proxies at once from line-delimited text.
  /// Skips empty lines and comment lines starting with # or //.
  BatchAddProxyResult addMultipleProxies(String multiLineInput) {
    final lines = multiLineInput
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('//'))
        .toList();

    int addedCount = 0;
    int duplicateCount = 0;
    int failedCount = 0;
    final List<String> failedLines = [];

    final currentList = List<ProxyConfig>.from(settings.proxyServers);

    for (final line in lines) {
      final parsed = ProxyConfig.tryParse(line);
      if (parsed == null) {
        failedCount++;
        failedLines.add(line);
        continue;
      }

      if (currentList.any((p) => p == parsed)) {
        duplicateCount++;
        continue;
      }

      currentList.add(parsed);
      addedCount++;
    }

    if (addedCount > 0) {
      final updated = settings.copyWith(proxyServers: currentList);
      repository.updateSettings(updated);
      notifyListeners();
    }

    return BatchAddProxyResult(
      addedCount: addedCount,
      duplicateCount: duplicateCount,
      failedCount: failedCount,
      failedLines: failedLines,
    );
  }

  /// Clears all configured proxy servers.
  void clearAllProxies() {
    if (settings.proxyServers.isEmpty) return;
    final updated = settings.copyWith(
      proxyServers: [],
      speedLimitMode: settings.speedLimitMode == SpeedLimitMode.rocket
          ? SpeedLimitMode.unlimited
          : settings.speedLimitMode,
    );
    repository.updateSettings(updated);
    notifyListeners();
  }

  void removeProxy(int index) {
    if (index < 0 || index >= settings.proxyServers.length) return;
    final list = List<ProxyConfig>.from(settings.proxyServers)..removeAt(index);
    final updated = settings.copyWith(
      proxyServers: list,
      // If no proxies remain and rocket mode was selected, revert to unlimited
      speedLimitMode: list.isEmpty && settings.speedLimitMode == SpeedLimitMode.rocket
          ? SpeedLimitMode.unlimited
          : settings.speedLimitMode,
    );
    repository.updateSettings(updated);
    notifyListeners();
  }

  Future<ProxyBenchmarkResult?> testProxy(ProxyConfig proxy) async {
    final service = proxyService ?? ProxyService();
    return await service.testProxy(proxy);
  }

  Future<ProxyBenchmarkResult?> benchmarkProxy(
    ProxyConfig proxy, {
    String testUrl = 'https://speed.cloudflare.com/__down?bytes=10000000',
  }) async {
    final service = proxyService ?? ProxyService();
    final result = await service.benchmarkProxy(
      proxy: proxy,
      downloadUrl: testUrl,
    );
    if (result.isWorking && result.speedBytesPerSec > 0) {
      final index = settings.proxyServers.indexOf(proxy);
      if (index != -1) {
        final list = List<ProxyConfig>.from(settings.proxyServers);
        list[index] = proxy.copyWith(lastBenchmarkSpeed: result.speedBytesPerSec);
        final updated = settings.copyWith(proxyServers: list);
        await repository.updateSettings(updated);
        notifyListeners();
      }
    }
    return result;
  }

  /// Tests all configured proxy servers concurrently with a limit on concurrent tests.
  Future<Map<String, ProxyBenchmarkResult>> testAllProxies({
    void Function(int completed, int total, ProxyBenchmarkResult result)? onProgress,
    int concurrency = 5,
  }) async {
    final proxies = settings.proxyServers;
    if (proxies.isEmpty) return {};

    final service = proxyService ?? ProxyService();
    final results = <String, ProxyBenchmarkResult>{};
    int completed = 0;

    for (int i = 0; i < proxies.length; i += concurrency) {
      final batch = proxies.sublist(i, math.min(i + concurrency, proxies.length));
      await Future.wait(batch.map((proxy) async {
        final res = await service.testProxy(proxy, timeout: const Duration(seconds: 4));
        results[proxy.originalUrl] = res;
        completed++;
        onProgress?.call(completed, proxies.length, res);
      }));
    }

    return results;
  }

  /// Removes all proxies matching the given URLs (failed/dead proxies).
  void removeFailedProxies(Set<String> failedUrls) {
    if (failedUrls.isEmpty || settings.proxyServers.isEmpty) return;
    final list = settings.proxyServers
        .where((p) => !failedUrls.contains(p.originalUrl) && !failedUrls.contains(p.displayUrl))
        .toList();
    final updated = settings.copyWith(
      proxyServers: list,
      speedLimitMode: list.isEmpty && settings.speedLimitMode == SpeedLimitMode.rocket
          ? SpeedLimitMode.unlimited
          : settings.speedLimitMode,
    );
    repository.updateSettings(updated);
    notifyListeners();
  }
}
