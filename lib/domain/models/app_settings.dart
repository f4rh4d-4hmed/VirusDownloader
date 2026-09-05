import 'package:flutter/material.dart';

class AppSettings {
  final String defaultSavePath;
  final int maxConcurrentDownloads;
  final ThemeMode themeMode;
  final bool confirmOnDelete;

  const AppSettings({
    this.defaultSavePath = '',
    this.maxConcurrentDownloads = 3,
    this.themeMode = ThemeMode.system,
    this.confirmOnDelete = true,
  });

  AppSettings copyWith({
    String? defaultSavePath,
    int? maxConcurrentDownloads,
    ThemeMode? themeMode,
    bool? confirmOnDelete,
  }) {
    return AppSettings(
      defaultSavePath: defaultSavePath ?? this.defaultSavePath,
      maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      themeMode: themeMode ?? this.themeMode,
      confirmOnDelete: confirmOnDelete ?? this.confirmOnDelete,
    );
  }
}

