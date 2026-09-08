import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/services/file_service.dart';
import '../../domain/models/download_task.dart';

class DownloadCompleteDialog extends StatelessWidget {
  final DownloadTask task;
  final FileService fileService;

  const DownloadCompleteDialog({
    super.key,
    required this.task,
    required this.fileService,
  });

  static Future<void> show(
    BuildContext context, {
    required DownloadTask task,
    required FileService fileService,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DownloadCompleteDialog(
        task: task,
        fileService: fileService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completedColor = theme.extension<DownloadStatusColors>()?.completed ??
        const Color(0xFF198754);

    return AlertDialog(
      icon: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: completedColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_rounded,
            color: completedColor,
            size: 36,
          ),
        ),
      ),
      title: const Text('Download Completed'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: 'File name: ${task.fileName}',
                child: Text(
                  task.fileName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: 'Total size: ${task.formattedTotalSize}',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Icon(
                      Icons.data_usage_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      task.formattedTotalSize,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                label: 'Saved to: ${task.savePath}',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        task.savePath,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Dismiss'),
        ),
        if (AppUtils.isDesktop)
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('Show in Folder'),
            onPressed: () {
              Navigator.of(context).pop();
              fileService.openContainingFolder(task.savePath);
            },
          ),
        FilledButton.icon(
          icon: const Icon(Icons.file_open_outlined, size: 18),
          label: const Text('Open File'),
          onPressed: () {
            Navigator.of(context).pop();
            fileService.openFile(task.savePath);
          },
        ),
      ],
    );
  }
}

