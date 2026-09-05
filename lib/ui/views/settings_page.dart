import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../view_models/settings_view_model.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsVm = context.watch<SettingsViewModel>();
    final settings = settingsVm.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            interactive: true,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(24.0),
              children: [
              // Appearance Section
              Text(
                'Appearance',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Theme',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Choose your preferred appearance',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_outlined),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (selection) {
                          if (selection.isNotEmpty) {
                            settingsVm.updateThemeMode(selection.first);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Downloads Section
              Text(
                'Downloads',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    // Default save folder
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: const Text('Default Save Directory'),
                      subtitle: Text(
                        settings.defaultSavePath.isNotEmpty
                            ? settings.defaultSavePath
                            : 'System Default Downloads Folder',
                      ),
                      trailing: OutlinedButton(
                        onPressed: () async {
                          final selected = await FilePicker.platform.getDirectoryPath(
                            dialogTitle: 'Select Default Downloads Directory',
                            initialDirectory: settings.defaultSavePath.isNotEmpty
                                ? settings.defaultSavePath
                                : null,
                          );
                          if (selected != null && selected.isNotEmpty) {
                            settingsVm.updateSavePath(selected);
                          }
                        },
                        child: const Text('Change'),
                      ),
                    ),
                    const Divider(),
                    // Max concurrent downloads
                    ListTile(
                      leading: const Icon(Icons.speed_outlined),
                      title: const Text('Max Concurrent Downloads'),
                      subtitle: const Text('Limit active simultaneous downloads'),
                      trailing: DropdownButton<int>(
                        value: settings.maxConcurrentDownloads,
                        underline: const SizedBox(),
                        items: [1, 2, 3, 4, 5, 8].map((count) {
                          return DropdownMenuItem(
                            value: count,
                            child: Text('$count tasks'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            settingsVm.updateMaxConcurrent(val);
                          }
                        },
                      ),
                    ),
                    const Divider(),
                    // Confirm before deleting file
                    SwitchListTile(
                      secondary: const Icon(Icons.delete_sweep_outlined),
                      title: const Text('Confirm on File Deletion'),
                      subtitle: const Text('Ask before permanently deleting downloaded files'),
                      value: settings.confirmOnDelete,
                      onChanged: (val) {
                        settingsVm.updateConfirmDelete(val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // About Section
              Text(
                'About',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.downloading_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppConstants.appName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FutureBuilder<PackageInfo>(
                              future: PackageInfo.fromPlatform(),
                              builder: (context, snapshot) {
                                final info = snapshot.data;
                                final versionStr = info != null
                                    ? 'Version ${info.version} (build ${info.buildNumber})'
                                    : 'Version 1.0.0 (build 1)';
                                return Text(
                                  versionStr,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
