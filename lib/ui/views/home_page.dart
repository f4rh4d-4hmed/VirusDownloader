import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/utils.dart';
import '../../data/services/file_service.dart';
import '../../data/services/http_download_service.dart';
import '../../domain/models/download_task.dart';
import '../view_models/downloads_view_model.dart';
import '../view_models/settings_view_model.dart';
import 'add_download_dialog.dart';
import 'change_download_link_dialog.dart';
import 'download_tile.dart';
import 'empty_state.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  final DownloadStatus? initialStatusFilter;

  const HomePage({super.key, this.initialStatusFilter});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  final ScrollController _filterScrollController = ScrollController();
  final Set<String> _selectedTaskIds = <String>{};
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialStatusFilter != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<DownloadsViewModel>().setStatusFilter(widget.initialStatusFilter);
      });
    }
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStatusFilter != oldWidget.initialStatusFilter) {
      context.read<DownloadsViewModel>().setStatusFilter(widget.initialStatusFilter);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listScrollController.dispose();
    _filterScrollController.dispose();
    super.dispose();
  }

  void _openAddDownloadDialog(BuildContext context) async {
    final fileService = context.read<FileService>();
    final httpService = context.read<HttpDownloadService>();
    final settings = context.read<SettingsViewModel>().settings;
    final downloadsVm = context.read<DownloadsViewModel>();

    // Determine target directory
    String targetDir = settings.defaultSavePath;
    if (targetDir.isEmpty) {
      targetDir = await fileService.getDefaultDownloadDirectory();
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AddDownloadDialog(
        defaultDirectory: targetDir,
        fileService: fileService,
        httpService: httpService,
        onConfirm: ({
          required String url,
          required String fileName,
          required String targetDirectory,
          DownloadCategory? category,
          Map<String, String>? headers,
          bool? isResumable,
        }) {
          downloadsVm.addDownload(
            url: url,
            fileName: fileName,
            targetDirectory: targetDirectory,
            category: category,
            headers: headers,
            isResumable: isResumable,
          );
        },
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => const SettingsPage(),
      ),
    );
  }

  void _confirmDeleteFile(BuildContext context, String taskId, String fileName) {
    final settings = context.read<SettingsViewModel>().settings;
    final downloadsVm = context.read<DownloadsViewModel>();

    if (!settings.confirmOnDelete) {
      downloadsVm.remove(taskId, deleteFile: true);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File?'),
        content: Text(
          'Are you sure you want to permanently delete "$fileName" from your storage?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              downloadsVm.remove(taskId, deleteFile: true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _handleTileSelect(String taskId, bool isMultiSelect) {
    setState(() {
      if (isMultiSelect) {
        if (_selectedTaskIds.contains(taskId)) {
          _selectedTaskIds.remove(taskId);
        } else {
          _selectedTaskIds.add(taskId);
        }
      } else {
        if (_selectedTaskIds.length == 1 && _selectedTaskIds.contains(taskId)) {
          _selectedTaskIds.clear();
        } else {
          _selectedTaskIds
            ..clear()
            ..add(taskId);
        }
      }
    });
  }

  void _openSelectedFolder(List<DownloadTask> selectedTasks, FileService fileService) {
    final paths = selectedTasks.map((t) => t.savePath).toSet();
    for (final path in paths) {
      fileService.openContainingFolder(path);
    }
  }

  void _openSelectedFiles(List<DownloadTask> selectedTasks, FileService fileService) {
    final completed = selectedTasks.where((t) => t.status == DownloadStatus.completed).toList();
    if (completed.isEmpty) return;

    if (completed.length > 5) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Open Multiple Files?'),
          content: Text(
            'You are about to open ${completed.length} files simultaneously. This may launch multiple application windows.\n\nDo you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                for (final task in completed) {
                  fileService.openFile(task.savePath);
                }
              },
              child: Text('Open ${completed.length} Files'),
            ),
          ],
        ),
      );
    } else {
      for (final task in completed) {
        fileService.openFile(task.savePath);
      }
    }
  }

  void _pauseSelected(List<DownloadTask> selectedTasks, DownloadsViewModel downloadsVm) {
    for (final task in selectedTasks) {
      if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued) {
        downloadsVm.pause(task.id);
      }
    }
  }

  void _resumeSelected(List<DownloadTask> selectedTasks, DownloadsViewModel downloadsVm) {
    for (final task in selectedTasks) {
      if (task.status == DownloadStatus.paused) {
        downloadsVm.resume(task.id);
      }
    }
  }

  void _retrySelected(List<DownloadTask> selectedTasks, DownloadsViewModel downloadsVm) {
    for (final task in selectedTasks) {
      if (task.status == DownloadStatus.failed || task.status == DownloadStatus.cancelled) {
        downloadsVm.retry(task.id);
      }
    }
  }

  void _copySelectedUrls(List<DownloadTask> selectedTasks) {
    if (selectedTasks.isEmpty) return;
    final urls = selectedTasks.map((t) => t.url).join('\n');
    Clipboard.setData(ClipboardData(text: urls));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          selectedTasks.length == 1
              ? 'Download link copied: ${selectedTasks.first.fileName}'
              : '${selectedTasks.length} download links copied to clipboard',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openChangeUrlDialog(BuildContext context, DownloadTask task, DownloadsViewModel downloadsVm) {
    final httpService = context.read<HttpDownloadService>();
    showDialog(
      context: context,
      builder: (ctx) => ChangeDownloadLinkDialog(
        task: task,
        httpService: httpService,
        onConfirm: (newUrl, [headers, restart = false]) {
          downloadsVm.changeDownloadUrl(
            task.id,
            newUrl,
            headers: headers,
            restartFromBeginning: restart,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                restart
                    ? 'Download restarted from beginning with new link for "${task.fileName}"'
                    : 'Download link updated for "${task.fileName}"',
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  void _removeSelectedFromList(List<DownloadTask> selectedTasks, DownloadsViewModel downloadsVm) {
    for (final task in selectedTasks) {
      downloadsVm.remove(task.id, deleteFile: false);
    }
    setState(() {
      _selectedTaskIds.clear();
    });
  }

  void _deleteSelectedFromDisk(BuildContext context, List<DownloadTask> selectedTasks) {
    final settings = context.read<SettingsViewModel>().settings;
    final downloadsVm = context.read<DownloadsViewModel>();

    if (!settings.confirmOnDelete) {
      for (final task in selectedTasks) {
        downloadsVm.remove(task.id, deleteFile: true);
      }
      setState(() {
        _selectedTaskIds.clear();
      });
      return;
    }

    final isSingle = selectedTasks.length == 1;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSingle ? 'Delete File?' : 'Delete ${selectedTasks.length} Files?'),
        content: Text(
          isSingle
              ? 'Are you sure you want to permanently delete "${selectedTasks.first.fileName}" from your storage?'
              : 'Are you sure you want to permanently delete these ${selectedTasks.length} files from your storage?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              for (final task in selectedTasks) {
                downloadsVm.remove(task.id, deleteFile: true);
              }
              setState(() {
                _selectedTaskIds.clear();
              });
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _handleDeleteSelectedShortcut(BuildContext context, DownloadsViewModel downloadsVm) {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final isTextInput = primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (isTextInput) return;

    if (AppUtils.isDesktop && _selectedTaskIds.isNotEmpty) {
      final selectedTasks = downloadsVm.allTasks
          .where((t) => _selectedTaskIds.contains(t.id))
          .toList();
      if (selectedTasks.isNotEmpty) {
        _deleteSelectedFromDisk(context, selectedTasks);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadsVm = context.watch<DownloadsViewModel>();
    final fileService = context.read<FileService>();
    final httpService = context.read<HttpDownloadService>();
    final tasks = downloadsVm.tasks;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () => _openSettings(context),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedTaskIds.isNotEmpty) {
            setState(() => _selectedTaskIds.clear());
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
          if (AppUtils.isDesktop) {
            setState(() {
              _selectedTaskIds.addAll(tasks.map((t) => t.id));
            });
          }
        },
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            _handleDeleteSelectedShortcut(context, downloadsVm),
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            _handleDeleteSelectedShortcut(context, downloadsVm),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                // Top Action Toolbar
                _buildToolbar(context, downloadsVm),

                // Horizontal Filter Chips Bar (FDM Style)
                _buildFilterChipsBar(context, downloadsVm),

                const Divider(height: 1),

                // Main Download List Area
                Expanded(
                  child: tasks.isEmpty
                      ? EmptyState(
                          onAddDownload: () => _openAddDownloadDialog(context),
                          filterMessage: downloadsVm.searchQuery.isNotEmpty
                              ? 'No downloads match "${downloadsVm.searchQuery}"'
                              : (downloadsVm.categoryFilter != DownloadCategory.all ||
                                      downloadsVm.statusFilter != null
                                  ? 'No downloads match the selected filters'
                                  : null),
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (_selectedTaskIds.isNotEmpty) {
                              setState(() => _selectedTaskIds.clear());
                            }
                          },
                          child: Scrollbar(
                            controller: _listScrollController,
                            thumbVisibility: true,
                            interactive: true,
                            child: ListView.separated(
                              controller: _listScrollController,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: tasks.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final task = tasks[index];
                                return DownloadTile(
                                  key: ValueKey(task.id),
                                  task: task,
                                  fileService: fileService,
                                  httpService: httpService,
                                  isSelected: _selectedTaskIds.contains(task.id),
                                  onSelect: (isMulti) => _handleTileSelect(task.id, isMulti),
                                  onOpen: () => fileService.openFile(task.savePath),
                                  onPause: () => downloadsVm.pause(task.id),
                                  onResume: () => downloadsVm.resume(task.id),
                                  onCancel: () => downloadsVm.cancel(task.id),
                                  onRetry: () => downloadsVm.retry(task.id),
                                  onRemove: () => downloadsVm.remove(task.id, deleteFile: false),
                                  onDeleteFile: () => _confirmDeleteFile(context, task.id, task.fileName),
                                  onChangeUrl: (newUrl, [headers, restartFromBeginning = false]) {
                                    downloadsVm.changeDownloadUrl(
                                      task.id,
                                      newUrl,
                                      headers: headers,
                                      restartFromBeginning: restartFromBeginning,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          restartFromBeginning
                                              ? 'Download restarted from beginning with new link for "${task.fileName}"'
                                              : 'Download link updated for "${task.fileName}"',
                                        ),
                                        duration: const Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                ),

                const Divider(height: 1),

                // Bottom Status Bar
                _buildStatusBar(context, downloadsVm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, DownloadsViewModel vm) {
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();
    final selectedTasks = vm.allTasks.where((t) => _selectedTaskIds.contains(t.id)).toList();

    final pauseTasks = selectedTasks.where((t) =>
        t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued).toList();
    final resumeTasks = selectedTasks.where((t) => t.status == DownloadStatus.paused).toList();
    final retryTasks = selectedTasks.where((t) =>
        t.status == DownloadStatus.failed || t.status == DownloadStatus.cancelled).toList();
    final completedTasks = selectedTasks.where((t) => t.status == DownloadStatus.completed).toList();

    final canPause = pauseTasks.isNotEmpty;
    final canResume = resumeTasks.isNotEmpty;
    final canRetry = retryTasks.isNotEmpty;
    final canOpenFile = completedTasks.isNotEmpty;

    final canChangeLink = selectedTasks.length == 1 &&
        selectedTasks.first.isResumable &&
        (selectedTasks.first.status == DownloadStatus.downloading ||
            selectedTasks.first.status == DownloadStatus.paused ||
            selectedTasks.first.status == DownloadStatus.queued);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_showSearch) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(color: theme.colorScheme.surface),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back',
                  onPressed: () {
                    _searchController.clear();
                    vm.setSearchQuery('');
                    setState(() {
                      _showSearch = false;
                    });
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search downloads by name or URL...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                vm.setSearchQuery('');
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) {
                      vm.setSearchQuery(val);
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _buildSortButton(vm),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () => _openSettings(context),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Add URL Button (Square, Icon-only)
                      IconButton.filled(
                        onPressed: () => _openAddDownloadDialog(context),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        tooltip: 'Add URL',
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(36, 36),
                          fixedSize: const Size(36, 36),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Pause All Button (Square, Icon-only)
                      IconButton.outlined(
                        onPressed: vm.downloadingCount > 0 ? () => vm.pauseAll() : null,
                        icon: const Icon(Icons.pause_rounded, size: 18),
                        tooltip: 'Pause All',
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(36, 36),
                          fixedSize: const Size(36, 36),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Resume All Button (Square, Icon-only)
                      IconButton.outlined(
                        onPressed: () => vm.resumeAll(),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        tooltip: 'Resume All',
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(36, 36),
                          fixedSize: const Size(36, 36),
                        ),
                      ),

                      // --- FILE SPECIFIC SECTION ---
                      if (selectedTasks.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        // "|" vertical divider line
                        Container(
                          height: 22,
                          width: 1.5,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        const SizedBox(width: 8),

                        // Show in Folder / Open File Location icon
                        IconButton.outlined(
                          onPressed: () => _openSelectedFolder(selectedTasks, fileService),
                          icon: const Icon(Icons.folder_open_outlined, size: 18),
                          tooltip: selectedTasks.length == 1
                              ? 'Show in Folder'
                              : 'Show in Folder (${selectedTasks.length})',
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            minimumSize: const Size(36, 36),
                            fixedSize: const Size(36, 36),
                          ),
                        ),

                        // File specific Pause icon if downloading
                        if (canPause) ...[
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            onPressed: () => _pauseSelected(selectedTasks, vm),
                            icon: const Icon(Icons.pause_rounded, size: 18),
                            tooltip: pauseTasks.length == 1 ? 'Pause' : 'Pause (${pauseTasks.length})',
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              minimumSize: const Size(36, 36),
                              fixedSize: const Size(36, 36),
                            ),
                          ),
                        ],

                        // File specific Resume icon if paused
                        if (canResume) ...[
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            onPressed: () => _resumeSelected(selectedTasks, vm),
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            tooltip: resumeTasks.length == 1 ? 'Resume' : 'Resume (${resumeTasks.length})',
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              minimumSize: const Size(36, 36),
                              fixedSize: const Size(36, 36),
                            ),
                          ),
                        ],

                        // Open File icon if completed
                        if (canOpenFile) ...[
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            onPressed: () => _openSelectedFiles(selectedTasks, fileService),
                            icon: const Icon(Icons.file_open_outlined, size: 18),
                            tooltip: completedTasks.length == 1
                                ? 'Open File'
                                : 'Open Files (${completedTasks.length})',
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              minimumSize: const Size(36, 36),
                              fixedSize: const Size(36, 36),
                            ),
                          ),
                        ],

                        // Restart / Retry icon if failed/cancelled
                        if (canRetry) ...[
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            onPressed: () => _retrySelected(selectedTasks, vm),
                            icon: const Icon(Icons.replay_rounded, size: 18),
                            tooltip: retryTasks.length == 1 ? 'Restart Download' : 'Restart (${retryTasks.length})',
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              minimumSize: const Size(36, 36),
                              fixedSize: const Size(36, 36),
                            ),
                          ),
                        ],

                        // Change Download Link icon if single resumable active task
                        if (canChangeLink) ...[
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            onPressed: () => _openChangeUrlDialog(context, selectedTasks.first, vm),
                            icon: const Icon(Icons.link_rounded, size: 18),
                            tooltip: 'Change Download Link',
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              minimumSize: const Size(36, 36),
                              fixedSize: const Size(36, 36),
                            ),
                          ),
                        ],

                        // Copy Link icon
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          onPressed: () => _copySelectedUrls(selectedTasks),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          tooltip: selectedTasks.length == 1 ? 'Copy Download Link' : 'Copy Download Links (${selectedTasks.length})',
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            minimumSize: const Size(36, 36),
                            fixedSize: const Size(36, 36),
                          ),
                        ),

                        // Remove from List icon
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          onPressed: () => _removeSelectedFromList(selectedTasks, vm),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          tooltip: selectedTasks.length == 1 ? 'Remove from List' : 'Remove (${selectedTasks.length}) from List',
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            minimumSize: const Size(36, 36),
                            fixedSize: const Size(36, 36),
                          ),
                        ),

                        // Delete from Disk icon
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          onPressed: () => _deleteSelectedFromDisk(context, selectedTasks),
                          icon: Icon(Icons.delete_forever_rounded, size: 18, color: theme.colorScheme.error),
                          tooltip: selectedTasks.length == 1 ? 'Delete from Disk' : 'Delete (${selectedTasks.length}) from Disk',
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            minimumSize: const Size(36, 36),
                            fixedSize: const Size(36, 36),
                          ),
                        ),

                        // Clear selection button
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => setState(() => _selectedTaskIds.clear()),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: 'Clear selection (${selectedTasks.length})',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            fixedSize: const Size(32, 32),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Search Button
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Search',
                onPressed: () {
                  setState(() {
                    _showSearch = true;
                  });
                },
              ),

              const SizedBox(width: 4),

              // Sort Menu
              _buildSortButton(vm),

              const SizedBox(width: 4),

              // Settings Button
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => _openSettings(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortButton(DownloadsViewModel vm) {
    return PopupMenuButton<SortOrder>(
      icon: const Icon(Icons.sort_rounded),
      tooltip: 'Sort by',
      onSelected: (order) => vm.setSortOrder(order),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          checked: vm.sortOrder == SortOrder.dateAdded,
          value: SortOrder.dateAdded,
          child: const Text('Date Added'),
        ),
        CheckedPopupMenuItem(
          checked: vm.sortOrder == SortOrder.name,
          value: SortOrder.name,
          child: const Text('Name'),
        ),
        CheckedPopupMenuItem(
          checked: vm.sortOrder == SortOrder.size,
          value: SortOrder.size,
          child: const Text('Size'),
        ),
      ],
    );
  }

  Widget _buildFilterChipsBar(BuildContext context, DownloadsViewModel vm) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final barHeight = (48.0 * textScale).clamp(48.0, 72.0);

    return Container(
      height: barHeight,
      color: theme.colorScheme.surface,
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent && _filterScrollController.hasClients) {
            final delta = pointerSignal.scrollDelta.dy != 0
                ? pointerSignal.scrollDelta.dy
                : pointerSignal.scrollDelta.dx;
            final target = (_filterScrollController.offset + delta).clamp(
              0.0,
              _filterScrollController.position.maxScrollExtent,
            );
            _filterScrollController.jumpTo(target);
          }
        },
        child: ListView(
          controller: _filterScrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          children: [
            // Status Chips
            _buildFilterChip(
              label: 'All',
              count: vm.totalCount,
              isSelected: vm.statusFilter == null && vm.categoryFilter == DownloadCategory.all,
              onSelected: () {
                vm.setStatusFilter(null);
                vm.setCategoryFilter(DownloadCategory.all);
              },
            ),
            const SizedBox(width: 6),
            _buildFilterChip(
              label: 'Downloading',
              count: vm.downloadingCount,
              isSelected: vm.statusFilter == DownloadStatus.downloading,
              onSelected: () {
                vm.setStatusFilter(
                  vm.statusFilter == DownloadStatus.downloading ? null : DownloadStatus.downloading,
                );
              },
            ),
            const SizedBox(width: 6),
            _buildFilterChip(
              label: 'Completed',
              count: vm.completedCount,
              isSelected: vm.statusFilter == DownloadStatus.completed,
              onSelected: () {
                vm.setStatusFilter(
                  vm.statusFilter == DownloadStatus.completed ? null : DownloadStatus.completed,
                );
              },
            ),
            const SizedBox(width: 6),
            _buildFilterChip(
              label: 'Failed',
              count: vm.failedCount,
              isSelected: vm.statusFilter == DownloadStatus.failed,
              onSelected: () {
                vm.setStatusFilter(
                  vm.statusFilter == DownloadStatus.failed ? null : DownloadStatus.failed,
                );
              },
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: VerticalDivider(indent: 4, endIndent: 4),
            ),

            // Category Chips (Documents, Videos, Audio, Archives, Programs, Other)
            ...DownloadCategory.values.where((c) => c != DownloadCategory.all).map((cat) {
              final count = vm.getCountForCategory(cat);
              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: _buildFilterChip(
                  label: AppUtils.getCategoryLabel(cat),
                  icon: AppUtils.getCategoryIcon(cat),
                  count: count,
                  isSelected: vm.categoryFilter == cat,
                  onSelected: () {
                    vm.setCategoryFilter(
                      vm.categoryFilter == cat ? DownloadCategory.all : cat,
                    );
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    IconData? icon,
    required int count,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: icon != null ? Icon(icon, size: 16) : null,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withAlpha(50)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildStatusBar(BuildContext context, DownloadsViewModel vm) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          // Left: active downloads & speed
          Icon(
            Icons.speed_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            vm.downloadingCount > 0
                ? '${vm.downloadingCount} active (${AppUtils.formatSpeed(vm.totalSpeedBytesPerSec)})'
                : 'Idle',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const Spacer(),

          // Right: Total items & storage
          Icon(
            Icons.storage_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            '${vm.totalCount} downloads • ${AppUtils.formatFileSize(vm.totalDownloadedBytes)} downloaded',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
