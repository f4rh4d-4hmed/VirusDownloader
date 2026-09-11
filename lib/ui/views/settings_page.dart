import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/enums.dart';
import '../../core/utils.dart';
import '../view_models/settings_view_model.dart';
import '../widgets/app_animated_dropdown.dart';
import 'proxy_settings_section.dart';

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

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
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
                      Text(
                        'Theme',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_outlined),
                            tooltip: 'System',
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined),
                            tooltip: 'Light',
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined),
                            tooltip: 'Dark',
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
                      title: const Text('Save Location'),
                      subtitle: Text(
                        settings.defaultSavePath.isNotEmpty
                            ? settings.defaultSavePath
                            : 'System Default',
                      ),
                      trailing: OutlinedButton(
                        onPressed: () async {
                          final selected = await FilePicker.platform.getDirectoryPath(
                            dialogTitle: 'Select Downloads Directory',
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
                      title: const Text('Max Concurrent Downloads'),
                      trailing: AppAnimatedDropdown<int>(
                        value: settings.maxConcurrentDownloads,
                        width: 200,
                        menuWidth: 200,
                        items: [1, 2, 3, 4, 5, 8].map((count) {
                          return AppDropdownItem<int>(
                            value: count,
                            label: count == 1 ? '1 task' : '$count tasks',
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
                    // Per-file worker concurrency
                    ListTile(
                      title: const Text('Download Parts'),
                      trailing: AppAnimatedDropdown<int>(
                        value: settings.defaultWorkerCount,
                        width: 200,
                        menuWidth: 200,
                        items: [1, 2, 4, 6, 8, 12, 16].map((parts) {
                          return AppDropdownItem<int>(
                            value: parts,
                            label: parts == 1 ? '1 part (Single)' : '$parts parts',
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            settingsVm.updateWorkerCount(val);
                          }
                        },
                      ),
                    ),
                    const Divider(),
                    // Speed limit mode
                    ListTile(
                      title: const Text('Speed Mode'),
                      trailing: AppAnimatedDropdown<SpeedLimitMode>(
                        value: settings.speedLimitMode,
                        width: 200,
                        menuWidth: 200,
                        items: SpeedLimitMode.values.map((mode) {
                          return AppDropdownItem<SpeedLimitMode>(
                            value: mode,
                            label: mode.label,
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            if (val == SpeedLimitMode.rocket && settings.proxyServers.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Rocket Mode requires at least one proxy server added below.'),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                              return;
                            }
                            settingsVm.updateSpeedLimitMode(val);
                          }
                        },
                      ),
                    ),
                    const Divider(),
                    // Placeholder pre-allocation
                    SwitchListTile(
                      title: const Text('Placeholder Pre-allocation (< 3GB)'),
                      value: settings.usePlaceholderMode,
                      onChanged: (val) {
                        settingsVm.updatePlaceholderMode(val);
                      },
                    ),
                    const Divider(),
                    // Auto-recheck
                    SwitchListTile(
                      title: const Text('Auto-verify Integrity on Complete'),
                      value: settings.autoRecheckOnComplete,
                      onChanged: (val) {
                        settingsVm.updateAutoRecheck(val);
                      },
                    ),
                    const Divider(),
                    // Confirm before deleting file
                    SwitchListTile(
                      title: const Text('Confirm on File Deletion'),
                      value: settings.confirmOnDelete,
                      onChanged: (val) {
                        settingsVm.updateConfirmDelete(val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Proxy Section
              Text(
                'Proxy',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const ProxySettingsSection(),

              const SizedBox(height: 28),

              if (!AppUtils.isMobile) ...[
                // Browser Extension Section
                Text(
                  'Browser Extension',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      // Bridge Status & quick actions
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: settingsVm.isServerRunning ? Colors.green : Colors.red,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              settingsVm.isServerRunning
                                  ? 'Bridge Running (Port ${settingsVm.serverPort})'
                                  : 'Bridge Stopped',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.folder_open_outlined, size: 20),
                              tooltip: 'Open Extension Folder',
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
                            IconButton(
                              icon: const Icon(Icons.help_outline_rounded, size: 18),
                              tooltip: 'Setup Guide',
                              onPressed: () => _showExtensionGuideDialog(context, settingsVm),
                            ),
                          ],
                        ),
                      ),

                      // Detected Browsers
                      if (settingsVm.isDetectingBrowsers)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (settingsVm.detectedBrowsers.isNotEmpty) ...[
                        const Divider(height: 1),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: settingsVm.detectedBrowsers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final browser = settingsVm.detectedBrowsers[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                _getBrowserIcon(browser.name),
                                color: theme.colorScheme.primary,
                                size: 22,
                              ),
                              title: Text(browser.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                              trailing: FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                onPressed: () async {
                                  final success = await settingsVm.launchBrowser(browser);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? '${browser.name} launched with extension!'
                                              : 'Failed to launch ${browser.name}.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Launch'),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 28),
              ],

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
