import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_scroll_behavior.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'ui/shell.dart';
import 'ui/view_models/settings_view_model.dart';

class VirusDownloaderApp extends StatelessWidget {
  const VirusDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsVm = context.watch<SettingsViewModel>();

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settingsVm.settings.themeMode,
      home: const Shell(),
    );
  }
}
