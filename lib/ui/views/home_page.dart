import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/utils.dart';
import '../../data/services/file_service.dart';
import '../../data/services/http_download_service.dart';
import '../view_models/downloads_view_model.dart';
import '../view_models/settings_view_model.dart';
import 'add_download_dialog.dart';
import 'download_tile.dart';
import 'empty_state.dart';

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
        }) {
          downloadsVm.addDownload(
            url: url,
            fileName: fileName,
            targetDirectory: targetDirectory,
            category: category,
          );
        },
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

  @override
  Widget build(BuildContext context) {
    final downloadsVm = context.watch<DownloadsViewModel>();
    final fileService = context.read<FileService>();
    final tasks = downloadsVm.tasks;

    return Scaffold(
      body: Column(
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
                : Scrollbar(
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
                          onPause: () => downloadsVm.pause(task.id),
                          onResume: () => downloadsVm.resume(task.id),
                          onCancel: () => downloadsVm.cancel(task.id),
                          onRetry: () => downloadsVm.retry(task.id),
                          onRemove: () => downloadsVm.remove(task.id, deleteFile: false),
                          onDeleteFile: () => _confirmDeleteFile(context, task.id, task.fileName),
                        );
                      },
                    ),
                  ),
          ),

          const Divider(height: 1),

          // Bottom Status Bar
          _buildStatusBar(context, downloadsVm),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, DownloadsViewModel vm) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          // Add URL Button
          FilledButton.icon(
            onPressed: () => _openAddDownloadDialog(context),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add URL'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),

          const SizedBox(width: 12),

          // Pause All
          OutlinedButton.icon(
            onPressed: vm.downloadingCount > 0 ? () => vm.pauseAll() : null,
            icon: const Icon(Icons.pause_rounded, size: 18),
            label: const Text('Pause All'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),

          const SizedBox(width: 8),

          // Resume All
          OutlinedButton.icon(
            onPressed: () => vm.resumeAll(),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Resume All'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),

          const Spacer(),

          // Search Field
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _showSearch ? 260 : 44,
            child: _showSearch
                ? TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search downloads...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          vm.setSearchQuery('');
                          setState(() {
                            _showSearch = false;
                          });
                        },
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onChanged: (val) => vm.setSearchQuery(val),
                  )
                : IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search',
                    onPressed: () {
                      setState(() {
                        _showSearch = true;
                      });
                    },
                  ),
          ),

          const SizedBox(width: 8),

          // Sort Menu
          PopupMenuButton<SortOrder>(
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
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChipsBar(BuildContext context, DownloadsViewModel vm) {
    final theme = Theme.of(context);

    return Container(
      height: 48,
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
