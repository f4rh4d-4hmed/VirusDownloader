import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/enums.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/download_task.dart';
import '../../domain/models/proxy_config.dart';
import '../models/download_task_model.dart';

class StorageService {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get prefs {
    if (_prefs == null) {
      throw StateError('StorageService not initialized. Call init() first.');
    }
    return _prefs!;
  }

  /// Loads persisted download tasks
  Future<List<DownloadTask>> loadTasks() async {
    await init();
    final jsonStr = prefs.getString(AppConstants.storageKeyTasks);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DownloadTaskModel.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Saves list of download tasks
  Future<void> saveTasks(List<DownloadTask> tasks) async {
    await init();
    final encoded = jsonEncode(tasks.map(DownloadTaskModel.toJson).toList());
    await prefs.setString(AppConstants.storageKeyTasks, encoded);
  }

  /// Loads application settings
  Future<AppSettings> loadSettings() async {
    await init();
    final jsonStr = prefs.getString(AppConstants.storageKeySettings);
    if (jsonStr == null || jsonStr.isEmpty) {
      return const AppSettings();
    }

    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final themeIndex = data['themeMode'] as int? ?? 0;
      final themeMode = (themeIndex >= 0 && themeIndex < ThemeMode.values.length)
          ? ThemeMode.values[themeIndex]
          : ThemeMode.system;

      final speedIndex = data['speedLimitMode'] as int? ?? SpeedLimitMode.unlimited.index;
      final speedLimitMode = (speedIndex >= 0 && speedIndex < SpeedLimitMode.values.length)
          ? SpeedLimitMode.values[speedIndex]
          : SpeedLimitMode.unlimited;

      List<ProxyConfig> proxyServers = [];
      if (data['proxyServers'] is List) {
        proxyServers = (data['proxyServers'] as List)
            .whereType<Map<String, dynamic>>()
            .map(ProxyConfig.fromJson)
            .toList();
      }

      return AppSettings(
        defaultSavePath: data['defaultSavePath'] as String? ?? '',
        maxConcurrentDownloads: data['maxConcurrentDownloads'] as int? ?? 3,
        themeMode: themeMode,
        confirmOnDelete: data['confirmOnDelete'] as bool? ?? true,
        defaultWorkerCount: data['defaultWorkerCount'] as int? ?? 1,
        usePlaceholderMode: data['usePlaceholderMode'] as bool? ?? false,
        speedLimitMode: speedLimitMode,
        proxyServers: proxyServers,
        autoRecheckOnComplete: data['autoRecheckOnComplete'] as bool? ?? false,
      );
    } catch (_) {
      return const AppSettings();
    }
  }

  /// Saves application settings
  Future<void> saveSettings(AppSettings settings) async {
    await init();
    final data = {
      'defaultSavePath': settings.defaultSavePath,
      'maxConcurrentDownloads': settings.maxConcurrentDownloads,
      'themeMode': settings.themeMode.index,
      'confirmOnDelete': settings.confirmOnDelete,
      'defaultWorkerCount': settings.defaultWorkerCount,
      'usePlaceholderMode': settings.usePlaceholderMode,
      'speedLimitMode': settings.speedLimitMode.index,
      'proxyServers': settings.proxyServers.map((p) => p.toJson()).toList(),
      'autoRecheckOnComplete': settings.autoRecheckOnComplete,
    };
    await prefs.setString(AppConstants.storageKeySettings, jsonEncode(data));
  }
}
