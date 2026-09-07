import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/enums.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/services/file_service.dart';
import '../../domain/models/download_task.dart';

class DownloadTile extends StatefulWidget {
  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;
  final VoidCallback onDeleteFile;
  final FileService fileService;

  const DownloadTile({
    super.key,
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
    required this.onDeleteFile,
    required this.fileService,
  });

  @override
  State<DownloadTile> createState() => _DownloadTileState();
}

class _DownloadTileState extends State<DownloadTile> {
  Offset _tapPosition = Offset.zero;

  Color _getStatusColor(BuildContext context) {
    final colors = Theme.of(context).extension<DownloadStatusColors>()!;
    switch (widget.task.status) {
      case DownloadStatus.downloading:
        return colors.downloading;
      case DownloadStatus.paused:
        return colors.paused;
      case DownloadStatus.completed:
        return colors.completed;
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return colors.failed;
      case DownloadStatus.queued:
        return colors.queued;
    }
  }

  IconData _getStatusIcon() {
    switch (widget.task.status) {
      case DownloadStatus.downloading:
        return Icons.arrow_downward_rounded;
      case DownloadStatus.paused:
        return Icons.pause_rounded;
      case DownloadStatus.completed:
        return Icons.check_circle_outline_rounded;
      case DownloadStatus.failed:
        return Icons.error_outline_rounded;
      case DownloadStatus.cancelled:
        return Icons.cancel_outlined;
      case DownloadStatus.queued:
        return Icons.hourglass_top_rounded;
    }
  }

  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context) {
    final task = widget.task;
    return [
      if (task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.queued) ...[
        const PopupMenuItem(
          value: 'pause',
          child: Row(
            children: [
              Icon(Icons.pause_rounded, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Pause')),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'cancel',
          child: Row(
            children: [
              Icon(Icons.cancel_outlined, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Cancel')),
            ],
          ),
        ),
      ] else if (task.status == DownloadStatus.paused) ...[
        const PopupMenuItem(
          value: 'resume',
          child: Row(
            children: [
              Icon(Icons.play_arrow_rounded, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Resume')),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'cancel',
          child: Row(
            children: [
              Icon(Icons.cancel_outlined, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Cancel')),
            ],
          ),
        ),
      ] else if (task.status == DownloadStatus.completed) ...[
        const PopupMenuItem(
          value: 'open_file',
          child: Row(
            children: [
              Icon(Icons.file_open_outlined, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Open File')),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'open_folder',
          child: Row(
            children: [
              Icon(Icons.folder_open_outlined, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Show in Folder')),
            ],
          ),
        ),
      ],
      const PopupMenuItem(
        value: 'copy_url',
        child: Row(
          children: [
            Icon(Icons.copy_rounded, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text('Copy Download Link')),
          ],
        ),
      ),
      if (task.status != DownloadStatus.completed)
        const PopupMenuItem(
          value: 'retry',
          child: Row(
            children: [
              Icon(Icons.replay_rounded, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Restart Download')),
            ],
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'remove_list',
        child: Row(
          children: [
            Icon(Icons.delete_outline_rounded, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text('Remove from List')),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'delete_disk',
        child: Row(
          children: [
            Icon(Icons.delete_forever_rounded, size: 18, color: Colors.red),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete from Disk',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _showOptionsMenu(BuildContext context, [Offset? position]) async {
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    Offset targetPosition = position ?? _tapPosition;

    if (targetPosition == Offset.zero) {
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        targetPosition = box.localToGlobal(box.size.center(Offset.zero));
      }
    }

    final RelativeRect relativeRect = RelativeRect.fromRect(
      Rect.fromPoints(targetPosition, targetPosition),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<String>(
      context: context,
      position: relativeRect,
      items: _buildMenuItems(context),
    );

    if (selected != null && mounted) {
      _handleMenuAction(this.context, selected);
    }
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'pause':
        widget.onPause();
        break;
      case 'resume':
        widget.onResume();
        break;
      case 'cancel':
        widget.onCancel();
        break;
      case 'open_file':
        widget.fileService.openFile(widget.task.savePath);
        break;
      case 'open_folder':
        widget.fileService.openContainingFolder(widget.task.savePath);
        break;
      case 'copy_url':
        Clipboard.setData(ClipboardData(text: widget.task.url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download URL copied to clipboard'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;
      case 'retry':
        widget.onRetry();
        break;
      case 'remove_list':
        widget.onRemove();
        break;
      case 'delete_disk':
        widget.onDeleteFile();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(context);
    final categoryIcon = AppUtils.getCategoryIcon(widget.task.category);

    return InkWell(
      onTap: widget.task.status == DownloadStatus.completed
          ? () => widget.fileService.openFile(widget.task.savePath)
          : null,
      onTapDown: (details) {
        _tapPosition = details.globalPosition;
      },
      onSecondaryTapDown: (details) {
        _tapPosition = details.globalPosition;
      },
      onSecondaryTapUp: (details) {
        _tapPosition = details.globalPosition;
        _showOptionsMenu(context, details.globalPosition);
      },
      onLongPress: () {
        _showOptionsMenu(context, _tapPosition);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Category Icon Badge with subtle Status indicator
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    categoryIcon,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _getStatusIcon(),
                      size: 9,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 14),

            // Main Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // File Name & Top Stats
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.task.fileName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _buildSizeText(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      child: widget.task.isIndeterminate
                          ? LinearProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(statusColor),
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            )
                          : LinearProgressIndicator(
                              value: widget.task.status == DownloadStatus.completed ? 1.0 : widget.task.progress,
                              valueColor: AlwaysStoppedAnimation(statusColor),
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Subline status & details
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _buildStatusSubline(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: widget.task.status == DownloadStatus.failed
                                ? statusColor
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.task.status == DownloadStatus.downloading && widget.task.eta != null) ...[
                        Text(
                          'ETA: ${widget.task.formattedEta}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Quick Actions & Context Menu
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  String _buildSizeText() {
    final task = widget.task;
    if (task.status == DownloadStatus.completed) {
      return task.formattedTotalSize;
    }
    if (task.totalBytes > 0) {
      final percent = (task.progress * 100).toStringAsFixed(0);
      return '$percent% (${task.formattedDownloadedSize} / ${task.formattedTotalSize})';
    }
    if (task.downloadedBytes > 0) {
      return task.formattedDownloadedSize;
    }
    return '';
  }

  String _buildStatusSubline() {
    final task = widget.task;
    switch (task.status) {
      case DownloadStatus.downloading:
        return task.formattedSpeed;
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.completed:
        return 'Completed';
      case DownloadStatus.failed:
        return task.errorMessage ?? 'Download failed';
      case DownloadStatus.cancelled:
        return 'Cancelled';
    }
  }

  Widget _buildActionButtons(BuildContext context) {
    final task = widget.task;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Primary state action
        if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)
          IconButton(
            icon: const Icon(Icons.pause_rounded, size: 20),
            tooltip: 'Pause',
            onPressed: widget.onPause,
            visualDensity: VisualDensity.compact,
          )
        else if (task.status == DownloadStatus.paused)
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            tooltip: 'Resume',
            onPressed: widget.onResume,
            visualDensity: VisualDensity.compact,
          )
        else if (task.status == DownloadStatus.failed || task.status == DownloadStatus.cancelled)
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Retry',
            onPressed: widget.onRetry,
            visualDensity: VisualDensity.compact,
          )
        else if (task.status == DownloadStatus.completed)
          IconButton(
            icon: const Icon(Icons.folder_open_outlined, size: 20),
            tooltip: 'Open Folder',
            onPressed: () => widget.fileService.openContainingFolder(task.savePath),
            visualDensity: VisualDensity.compact,
          ),

        // 3-dot Options Menu Button
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20),
          tooltip: 'Options',
          padding: EdgeInsets.zero,
          onSelected: (value) => _handleMenuAction(context, value),
          itemBuilder: (context) => _buildMenuItems(context),
        ),
      ],
    );
  }
}
