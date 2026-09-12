import 'package:flutter/material.dart';
import '../../core/enums.dart';
import 'proxy_config.dart';

class AppSettings {
  final String defaultSavePath;
  final int maxConcurrentDownloads;
  final ThemeMode themeMode;
  final bool confirmOnDelete;
  final int defaultWorkerCount;
  final bool usePlaceholderMode;
  final SpeedLimitMode speedLimitMode;
  final List<ProxyConfig> proxyServers;
  final bool autoRecheckOnComplete;
  final bool runInBackground;
  final bool autoStartOnBoot;

  const AppSettings({
    this.defaultSavePath = '',
    this.maxConcurrentDownloads = 3,
    this.themeMode = ThemeMode.system,
    this.confirmOnDelete = true,
    this.defaultWorkerCount = 8,
    this.usePlaceholderMode = true,
    this.speedLimitMode = SpeedLimitMode.unlimited,
    this.proxyServers = const [],
    this.autoRecheckOnComplete = false,
    this.runInBackground = false,
    this.autoStartOnBoot = false,
  });

  AppSettings copyWith({
    String? defaultSavePath,
    int? maxConcurrentDownloads,
    ThemeMode? themeMode,
    bool? confirmOnDelete,
    int? defaultWorkerCount,
    bool? usePlaceholderMode,
    SpeedLimitMode? speedLimitMode,
    List<ProxyConfig>? proxyServers,
    bool? autoRecheckOnComplete,
    bool? runInBackground,
    bool? autoStartOnBoot,
  }) {
    return AppSettings(
      defaultSavePath: defaultSavePath ?? this.defaultSavePath,
      maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      themeMode: themeMode ?? this.themeMode,
      confirmOnDelete: confirmOnDelete ?? this.confirmOnDelete,
      defaultWorkerCount: defaultWorkerCount ?? this.defaultWorkerCount,
      usePlaceholderMode: usePlaceholderMode ?? this.usePlaceholderMode,
      speedLimitMode: speedLimitMode ?? this.speedLimitMode,
      proxyServers: proxyServers ?? this.proxyServers,
      autoRecheckOnComplete: autoRecheckOnComplete ?? this.autoRecheckOnComplete,
      runInBackground: runInBackground ?? this.runInBackground,
      autoStartOnBoot: autoStartOnBoot ?? this.autoStartOnBoot,
    );
  }
}
