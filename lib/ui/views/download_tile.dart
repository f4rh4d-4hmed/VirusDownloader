import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/enums.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/services/ffmpeg_service.dart';
import '../../data/services/file_service.dart';
import '../../data/services/http_download_service.dart';
import '../../domain/models/download_task.dart';
import 'change_download_link_dialog.dart';
import 'hash_dialog.dart';
import 'recheck_dialog.dart';
import 'rename_dialog.dart';

class DownloadTile extends StatefulWidget {
  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;
  final VoidCallback onDeleteFile;
  final void Function(String newUrl, [Map<String, String>? headers, bool restartFromBeginning])? onChangeUrl;
  final void Function(String newName)? onRename;
  final FileService fileService;
  final HttpDownloadService? httpService;
  final FfmpegService? ffmpegService;
  final FocusNode? focusNode;
  final bool isSelected;
  final bool isSelectionMode;
  final void Function(bool isMultiSelect)? onSelect;
  final VoidCallback? onLongPressSelect;
  final VoidCallback? onOpen;

  const DownloadTile({
    super.key,
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
    required this.onDeleteFile,
    this.onChangeUrl,
    this.onRename,
    required this.fileService,
    this.httpService,
    this.ffmpegService,
    this.focusNode,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onSelect,
    this.onLongPressSelect,
    this.onOpen,
  });

  @override
  State<DownloadTile> createState() => _DownloadTileState();
}

class _MenuRouteTrackerEntry extends PopupMenuEntry<String> {
  final ValueChanged<Route<dynamic>?> onRouteCaptured;

  const _MenuRouteTrackerEntry({
    required this.onRouteCaptured,
  });

  @override
  double get height => 0.0;

  @override
  bool represents(String? value) => false;

  @override
  State<_MenuRouteTrackerEntry> createState() => _MenuRouteTrackerEntryState();
}

class _MenuRouteTrackerEntryState extends State<_MenuRouteTrackerEntry> {
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route = route;
      widget.onRouteCaptured(_route);
    }
  }

  @override
  void dispose() {
    widget.onRouteCaptured(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _DownloadTileState extends State<DownloadTile> {
  Offset _tapPosition = Offset.zero;
  Route<dynamic>? _activeMenuRoute;
  int _lastTapTime = 0;
  String? _thumbnailPath;

  @override
  void initState() {
    super.initState();
    _loadThumbnailIfNeeded();
  }

  void _closeMenuIfOpen() {
    final route = _activeMenuRoute;
    if (route != null && route.isActive) {
      if (route.isCurrent) {
        route.navigator?.pop();
      } else {
        route.navigator?.removeRoute(route);
      }
      _activeMenuRoute = null;
    }
  }

  void _loadThumbnailIfNeeded() {
    if (widget.task.status != DownloadStatus.completed) {
      if (_thumbnailPath != null) {
        setState(() {
          _thumbnailPath = null;
        });
      }
      return;
    }

    final savePath = widget.task.savePath;
    if (savePath.isEmpty) return;

    if (AppUtils.isImageFormat(savePath)) {
      if (_thumbnailPath != savePath) {
        setState(() {
          _thumbnailPath = savePath;
        });
      }
      return;
    }

    if (AppUtils.isVideoFormat(savePath) || AppUtils.isAudioFormat(savePath)) {
      final ffmpeg = widget.ffmpegService ?? _getFfmpegService();
      if (ffmpeg != null) {
        final cached = ffmpeg.getCachedThumbnail(savePath);
        if (cached != null) {
          if (_thumbnailPath != cached) {
            setState(() {
              _thumbnailPath = cached;
            });
          }
          return;
        }

        ffmpeg.generateThumbnail(savePath).then((thumb) {
          if (mounted && thumb != null && widget.task.savePath == savePath) {
            setState(() {
              _thumbnailPath = thumb;
            });
          }
        });
      }
    }
  }

  FfmpegService? _getFfmpegService() {
    try {
      return context.read<FfmpegService>();
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(DownloadTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.status != oldWidget.task.status ||
        widget.task.savePath != oldWidget.task.savePath) {
      _loadThumbnailIfNeeded();
      if (widget.task.status != oldWidget.task.status) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _closeMenuIfOpen();
        });
      }
    }
  }

  @override
  void dispose() {
    final route = _activeMenuRoute;
    if (route != null && route.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) {
          if (route.isCurrent) {
            route.navigator?.pop();
          } else {
            route.navigator?.removeRoute(route);
          }
        }
      });
    }
    super.dispose();
  }

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
    final isActive = task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.queued ||
        task.status == DownloadStatus.paused;
    final canChangeLink = isActive && task.isResumable;

    return [
      _MenuRouteTrackerEntry(
        onRouteCaptured: (route) {
          _activeMenuRoute = route;
        },
      ),
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
        if (AppUtils.isDesktop)
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
        if (task.isResumable)
          const PopupMenuItem(
            value: 'recheck',
            child: Row(
              children: [
                Icon(Icons.verified_outlined, size: 18),
                SizedBox(width: 10),
                Expanded(child: Text('Recheck File')),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'hash',
          child: Row(
            children: [
              Icon(Icons.fingerprint_rounded, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('File Hash')),
            ],
          ),
        ),
      ],
      const PopupMenuItem(
        value: 'rename',
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text('Rename')),
          ],
        ),
      ),
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
      if (canChangeLink)
        const PopupMenuItem(
          value: 'change_url',
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Change Download Link')),
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
      PopupMenuItem(
        value: 'delete_disk',
        child: Row(
          children: [
            Icon(
              Icons.delete_forever_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete from Disk',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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

    _activeMenuRoute = null;

    if (selected != null && mounted) {
      _handleMenuAction(this.context, selected);
    }
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'pause':
        if (widget.task.status == DownloadStatus.downloading ||
            widget.task.status == DownloadStatus.queued) {
          widget.onPause();
        }
        break;
      case 'resume':
        if (widget.task.status == DownloadStatus.paused) {
          widget.onResume();
        }
        break;
      case 'cancel':
        if (widget.task.status != DownloadStatus.completed &&
            widget.task.status != DownloadStatus.cancelled) {
          widget.onCancel();
        }
        break;
      case 'open_file':
        if (widget.task.status == DownloadStatus.completed) {
          widget.fileService.openFile(widget.task.savePath);
        }
        break;
      case 'open_folder':
        widget.fileService.openContainingFolder(widget.task.savePath);
        break;
      case 'recheck':
        RecheckDialog.show(context, widget.task);
        break;
      case 'hash':
        HashDialog.show(context, widget.task);
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
      case 'change_url':
        final isActive = widget.task.status == DownloadStatus.downloading ||
            widget.task.status == DownloadStatus.queued ||
            widget.task.status == DownloadStatus.paused;
        if (isActive && widget.task.isResumable) {
          _showChangeUrlDialog(context);
        }
        break;
      case 'retry':
        if (widget.task.status != DownloadStatus.downloading &&
            widget.task.status != DownloadStatus.queued) {
          widget.onRetry();
        }
        break;
      case 'remove_list':
        widget.onRemove();
        break;
      case 'delete_disk':
        widget.onDeleteFile();
        break;
      case 'rename':
        RenameDialog.show(
          context,
          widget.task.fileName,
          onConfirm: (newName) {
            widget.onRename?.call(newName);
          },
        );
        break;
    }
  }

  void _showChangeUrlDialog(BuildContext context) {
    final http = widget.httpService ?? HttpDownloadService();
    showDialog(
      context: context,
      builder: (ctx) => ChangeDownloadLinkDialog(
        task: widget.task,
        httpService: http,
        onConfirm: (newUrl, [headers, restartFromBeginning = false]) {
          widget.onChangeUrl?.call(newUrl, headers, restartFromBeginning);
        },
      ),
    );
  }

  void _handlePrimaryAction() {
    switch (widget.task.status) {
      case DownloadStatus.completed:
        widget.fileService.openFile(widget.task.savePath);
        break;
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        widget.onPause();
        break;
      case DownloadStatus.paused:
        widget.onResume();
        break;
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        widget.onRetry();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(context);
    final categoryIcon = AppUtils.getCategoryIcon(widget.task.category);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final isLargeText = textScale >= 1.3;

    return Semantics(
      container: true,
      selected: widget.isSelected,
      label: '${widget.task.fileName}, ${widget.task.status.name}',
      value: _buildSizeText(),
      hint: 'Press Shift+F10 for options',
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.contextMenu): () => _showOptionsMenu(context),
          const SingleActivator(LogicalKeyboardKey.f10, shift: true): () => _showOptionsMenu(context),
          const SingleActivator(LogicalKeyboardKey.enter): _handlePrimaryAction,
          const SingleActivator(LogicalKeyboardKey.space): _handlePrimaryAction,
        },
        child: Focus(
          focusNode: widget.focusNode,
          child: Builder(
            builder: (focusContext) {
              final isFocused = Focus.of(focusContext).hasFocus;
              return Container(
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? theme.colorScheme.primaryContainer.withAlpha(80)
                      : null,
                  border: widget.isSelected
                      ? Border.all(color: theme.colorScheme.primary.withAlpha(180), width: 1.5)
                      : (isFocused
                          ? Border.all(color: theme.colorScheme.primary, width: 2)
                          : null),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    final isRapidSecondTap = (now - _lastTapTime) < 300;
                    _lastTapTime = now;

                    if (isRapidSecondTap && widget.task.status == DownloadStatus.completed) {
                      if (widget.onOpen != null) {
                        widget.onOpen!();
                      } else {
                        widget.fileService.openFile(widget.task.savePath);
                      }
                      return;
                    }

                    if (AppUtils.isDesktop) {
                      final isMulti = HardwareKeyboard.instance.isControlPressed ||
                          HardwareKeyboard.instance.isMetaPressed;
                      widget.onSelect?.call(isMulti);
                    } else {
                      // Mobile: if in selection mode, toggle selection
                      if (widget.isSelectionMode) {
                        widget.onSelect?.call(true);
                      } else if (widget.task.status == DownloadStatus.completed) {
                        widget.fileService.openFile(widget.task.savePath);
                      } else {
                        widget.onSelect?.call(false);
                      }
                    }
                  },
                  onTapDown: (details) {
                    _tapPosition = details.globalPosition;
                  },
                  onSecondaryTapDown: (details) {
                    _tapPosition = details.globalPosition;
                  },
                  onSecondaryTapUp: (details) {
                    _tapPosition = details.globalPosition;
                    if (AppUtils.isDesktop && !widget.isSelected) {
                      widget.onSelect?.call(false);
                    }
                    _showOptionsMenu(context, details.globalPosition);
                  },
                  onLongPress: () {
                    if (AppUtils.isMobile) {
                      // Mobile: long-press enters selection mode
                      widget.onLongPressSelect?.call();
                    } else {
                      _showOptionsMenu(context, _tapPosition);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Category Icon Badge with subtle Status indicator (decorative)
                        ExcludeSemantics(
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _buildLeadingThumbnail(categoryIcon, theme),
                              ),
                              if (widget.task.fileMissing)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.error,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: theme.scaffoldBackgroundColor,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.warning_rounded,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ),
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
                        ),

                        const SizedBox(width: 14),

                        // Main Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // File Name & Top Stats
                              if (isLargeText) ...[
                                Text(
                                  widget.task.fileName,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  softWrap: true,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _buildSizeText(),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.task.fileName,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        softWrap: true,
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
                              ],

                              const SizedBox(height: 6),

                              // Progress Bar with Semantics
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  height: 4,
                                  child: widget.task.isIndeterminate
                                      ? LinearProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation(statusColor),
                                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                          semanticsLabel: 'Download progress for ${widget.task.fileName}',
                                          semanticsValue: 'indeterminate',
                                        )
                                      : LinearProgressIndicator(
                                          value: widget.task.status == DownloadStatus.completed
                                              ? 1.0
                                              : widget.task.progress,
                                          valueColor: AlwaysStoppedAnimation(statusColor),
                                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                          semanticsLabel: 'Download progress for ${widget.task.fileName}',
                                          semanticsValue:
                                              '${(widget.task.progress * 100).toStringAsFixed(0)}%',
                                        ),
                                ),
                              ),

                              const SizedBox(height: 6),

                              // Subline status & details
                              if (isLargeText &&
                                  widget.task.status == DownloadStatus.downloading &&
                                  widget.task.eta != null) ...[
                                Text(
                                  _buildStatusSubline(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: widget.task.status == DownloadStatus.failed
                                        ? statusColor
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ETA: ${widget.task.formattedEta}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ] else ...[
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
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (widget.task.status == DownloadStatus.downloading &&
                                        widget.task.eta != null) ...[
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
                            ],
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Quick Actions & Context Menu
                        _buildActionButtons(context),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
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
        if (task.fileMissing) {
          return 'File missing from disk';
        }
        return 'Completed';
      case DownloadStatus.failed:
        return task.errorMessage != null
            ? AppUtils.getHumanReadableError(task.errorMessage)
            : 'Download failed';
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
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          )
        else if (task.status == DownloadStatus.paused)
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            tooltip: 'Resume',
            onPressed: widget.onResume,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          )
        else if (task.status == DownloadStatus.failed || task.status == DownloadStatus.cancelled)
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Retry',
            onPressed: widget.onRetry,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          )
        else if (task.status == DownloadStatus.completed)
          AppUtils.isMobile
              ? IconButton(
                  icon: const Icon(Icons.file_open_outlined, size: 20),
                  tooltip: 'Open File',
                  onPressed: () => widget.fileService.openFile(task.savePath),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                )
              : IconButton(
                  icon: const Icon(Icons.folder_open_outlined, size: 20),
                  tooltip: 'Open Folder',
                  onPressed: () => widget.fileService.openContainingFolder(task.savePath),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                ),

        // 3-dot Options Menu Button
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20),
          tooltip: 'More options for ${widget.task.fileName}',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onCanceled: () => _activeMenuRoute = null,
          onSelected: (value) {
            _activeMenuRoute = null;
            _handleMenuAction(context, value);
          },
          itemBuilder: (context) => _buildMenuItems(context),
        ),
      ],
    );
  }

  Widget _buildLeadingThumbnail(IconData categoryIcon, ThemeData theme) {
    if (widget.task.status == DownloadStatus.completed &&
        _thumbnailPath != null &&
        File(_thumbnailPath!).existsSync()) {
      return Image.file(
        File(_thumbnailPath!),
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        cacheWidth: 88,
        cacheHeight: 88,
        errorBuilder: (_, __, ___) => Icon(
          categoryIcon,
          size: 22,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Icon(
      categoryIcon,
      size: 22,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }
}
