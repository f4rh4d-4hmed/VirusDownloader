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

              // Browser Integration & Extension Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Browser Integration & Extension',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showExtensionGuideDialog(context, settingsVm),
                    icon: const Icon(Icons.help_outline_rounded, size: 16),
                    label: const Text('Setup Guide'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    // Server Bridge Status
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: settingsVm.isServerRunning
                              ? Colors.green.withValues(alpha: 0.12)
                              : Colors.red.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          settingsVm.isServerRunning
                              ? Icons.sensors_rounded
                              : Icons.sensors_off_rounded,
                          color: settingsVm.isServerRunning ? Colors.green : Colors.red,
                          size: 20,
                        ),
                      ),
                      title: Row(
                        children: [
                          const Text('Extension Bridge Server'),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: settingsVm.isServerRunning
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              settingsVm.isServerRunning ? 'RUNNING' : 'STOPPED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: settingsVm.isServerRunning ? Colors.green : Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'Listening on 127.0.0.1:${settingsVm.serverPort} • Tasks received: ${settingsVm.receivedTasksCount}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.folder_outlined, size: 20),
                            tooltip: 'Open Extension Files Folder',
                            onPressed: () => settingsVm.openExtensionFolder(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'Copy Extension Path',
                            onPressed: () async {
                              final p = await settingsVm.copyExtensionPath();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Extension path copied: $p'),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(),

                    // Detected Browsers Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Installed Browsers (Auto-Add Extension)',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            tooltip: 'Rescan Browsers',
                            onPressed: () => settingsVm.initBrowserIntegration(),
                          ),
                        ],
                      ),
                    ),

                    if (settingsVm.isDetectingBrowsers)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else if (settingsVm.detectedBrowsers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'No standard Chromium browsers auto-detected.',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              onPressed: () => _showExtensionGuideDialog(context, settingsVm),
                              icon: const Icon(Icons.add_to_home_screen_rounded, size: 16),
                              label: const Text('Manual Browser Installation'),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: settingsVm.detectedBrowsers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, index) {
                          final browser = settingsVm.detectedBrowsers[index];
                          return ListTile(
                            leading: Icon(
                              _getBrowserIcon(browser.name),
                              color: theme.colorScheme.primary,
                            ),
                            title: Text(browser.name),
                            subtitle: Text(
                              browser.executablePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: FilledButton.tonalIcon(
                              icon: const Icon(Icons.launch_rounded, size: 16),
                              label: const Text('Auto-Add & Launch'),
                              onPressed: () async {
                                final success = await settingsVm.launchBrowser(browser);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        success
                                            ? '${browser.name} launched with extension! Path copied to clipboard.'
                                            : 'Failed to launch ${browser.name}.',
                                      ),
                                      action: SnackBarAction(
                                        label: 'Guide',
                                        onPressed: () => _showExtensionGuideDialog(context, settingsVm),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          );
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

  IconData _getBrowserIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('chrome')) return Icons.circle_outlined;
    if (lower.contains('edge')) return Icons.language_rounded;
    if (lower.contains('brave')) return Icons.shield_outlined;
    if (lower.contains('opera')) return Icons.radio_button_checked;
    if (lower.contains('firefox')) return Icons.local_fire_department_outlined;
    return Icons.public;
  }

  void _showExtensionGuideDialog(BuildContext context, SettingsViewModel settingsVm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.extension_rounded),
            SizedBox(width: 8),
            Text('Browser Extension Setup Guide'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'VirusDownloader includes a high-powered Chromium extension for video sniffing and download interception.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 14),
                _buildGuideStep(
                  step: '1',
                  title: 'Copy the extension path or click "Auto-Add & Launch"',
                  desc: 'The extension directory has been extracted from the app assets.',
                ),
                _buildGuideStep(
                  step: '2',
                  title: 'Open your browser\'s Extension Manager',
                  desc: 'Go to chrome://extensions or edge://extensions in your browser.',
                ),
                _buildGuideStep(
                  step: '3',
                  title: 'Enable "Developer mode"',
                  desc: 'Toggle the switch in the top-right corner of the extensions page.',
                ),
                _buildGuideStep(
                  step: '4',
                  title: 'Click "Load unpacked"',
                  desc: 'Select the extension directory (or paste the copied path).',
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Extension folder: ${settingsVm.extensionPath}',
                          style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              settingsVm.openExtensionFolder();
            },
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Open Folder'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final path = await settingsVm.copyExtensionPath();
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied: $path')),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Path'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideStep({
    required String step,
    required String title,
    required String desc,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            child: Text(step, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
