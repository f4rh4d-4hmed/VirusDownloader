import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/utils.dart';
import '../../data/services/ffmpeg_service.dart';
import '../../data/services/file_service.dart';
import '../../domain/models/download_task.dart';

class FilePreviewDialog extends StatefulWidget {
  final DownloadTask task;
  final FileService fileService;
  final FfmpegService? ffmpegService;

  const FilePreviewDialog({
    super.key,
    required this.task,
    required this.fileService,
    this.ffmpegService,
  });

  static Future<void> show(
    BuildContext context, {
    required DownloadTask task,
    required FileService fileService,
    FfmpegService? ffmpegService,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => FilePreviewDialog(
        task: task,
        fileService: fileService,
        ffmpegService: ffmpegService,
      ),
    );
  }

  @override
  State<FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<FilePreviewDialog> {
  bool _fileExists = true;
  int _fileSize = 0;
  String? _videoThumbnailPath;
  Map<String, String> _mediaInfo = {};
  bool _isLoadingMedia = true;
  String? _textContent;
  ui.Image? _decodedImage;
  final TransformationController _zoomController = TransformationController();

  @override
  void initState() {
    super.initState();
    _loadFileDetails();
  }

  @override
  void dispose() {
    _zoomController.dispose();
    super.dispose();
  }

  Future<void> _loadFileDetails() async {
    final file = File(widget.task.savePath);
    final exists = await file.exists();

    if (!mounted) return;
    if (!exists) {
      setState(() {
        _fileExists = false;
        _isLoadingMedia = false;
      });
      return;
    }

    final length = await file.length();
    _fileSize = length;

    final path = widget.task.savePath;

    // Handle Image
    if (AppUtils.isImageFormat(path)) {
      try {
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        if (mounted) {
          _decodedImage = frame.image;
        }
      } catch (_) {}
    }
    // Handle Video
    else if (AppUtils.isVideoFormat(path) && widget.ffmpegService != null) {
      try {
        final thumb = await widget.ffmpegService!.generateVideoThumbnail(path);
        final info = await widget.ffmpegService!.getVideoInfo(path);
        if (mounted) {
          _videoThumbnailPath = thumb;
          _mediaInfo = info;
        }
      } catch (_) {}
    }
    // Handle Audio
    else if (AppUtils.isAudioFormat(path) && widget.ffmpegService != null) {
      try {
        final info = await widget.ffmpegService!.getVideoInfo(path);
        if (mounted) {
          _mediaInfo = info;
        }
      } catch (_) {}
    }
    // Handle Text Document
    else if (AppUtils.isTextFormat(path)) {
      try {
        if (length < 2 * 1024 * 1024) {
          final content = await file.readAsString();
          if (mounted) {
            _textContent = content.length > 50000 ? '${content.substring(0, 50000)}\n\n[Content truncated...]' : content;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isLoadingMedia = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = AppUtils.isDesktop;
    final extension = AppUtils.extractExtension(widget.task.fileName).toUpperCase();

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 750 : double.infinity,
          maxHeight: isDesktop ? 650 : double.infinity,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      AppUtils.getCategoryIcon(widget.task.category),
                      size: 20,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.task.fileName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                extension.isNotEmpty ? extension : 'FILE',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppUtils.formatBytes(_fileSize > 0 ? _fileSize : widget.task.totalBytes),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (_decodedImage != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '•   ${_decodedImage!.width} × ${_decodedImage!.height}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ] else if (_mediaInfo['duration'] != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '•   ${_mediaInfo['duration']}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content Body
            Expanded(
              child: Container(
                color: theme.colorScheme.surfaceContainerLowest,
                child: _buildPreviewContent(context),
              ),
            ),

            // Footer Toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left side: Show in folder
                  TextButton.icon(
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Show in Folder'),
                    onPressed: () => widget.fileService.openContainingFolder(widget.task.savePath),
                  ),

                  // Right side: Open file in default system player/app
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Dismiss'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: Icon(
                          AppUtils.isVideoFormat(widget.task.savePath)
                              ? Icons.play_arrow_rounded
                              : (AppUtils.isAudioFormat(widget.task.savePath)
                                  ? Icons.audiotrack_rounded
                                  : Icons.file_open_outlined),
                          size: 18,
                        ),
                        label: Text(
                          AppUtils.isVideoFormat(widget.task.savePath)
                              ? 'Play Video'
                              : (AppUtils.isAudioFormat(widget.task.savePath)
                                  ? 'Play Audio'
                                  : 'Open File'),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.fileService.openFile(widget.task.savePath);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewContent(BuildContext context) {
    final theme = Theme.of(context);

    if (!_fileExists) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'File does not exist on disk',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              widget.task.savePath,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_isLoadingMedia) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final path = widget.task.savePath;

    // 1. Image Preview
    if (AppUtils.isImageFormat(path)) {
      return Stack(
        children: [
          Center(
            child: InteractiveViewer(
              transformationController: _zoomController,
              minScale: 0.5,
              maxScale: 5.0,
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (ctx, error, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 8),
                      const Text('Failed to decode image preview'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.zoom_in_rounded, size: 18),
                    tooltip: 'Zoom In',
                    onPressed: () {
                      _zoomController.value = _zoomController.value * Matrix4.diagonal3Values(1.2, 1.2, 1.0);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_out_rounded, size: 18),
                    tooltip: 'Zoom Out',
                    onPressed: () {
                      _zoomController.value = _zoomController.value * Matrix4.diagonal3Values(0.8, 0.8, 1.0);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: 'Reset Zoom',
                    onPressed: () {
                      _zoomController.value = Matrix4.identity();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 2. Video Preview
    if (AppUtils.isVideoFormat(path)) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thumbnail Poster or Placeholder with Play Overlay
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  widget.fileService.openFile(widget.task.savePath);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 480,
                  height: 270,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_videoThumbnailPath != null && File(_videoThumbnailPath!).existsSync())
                        Positioned.fill(
                          child: Image.file(
                            File(_videoThumbnailPath!),
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Positioned.fill(
                          child: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.movie_outlined,
                              size: 72,
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      // Play Overlay Icon
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 38,
                          color: Colors.white,
                        ),
                      ),
                      if (_mediaInfo['resolution'] != null)
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _mediaInfo['resolution']!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Video Metadata Details
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (_mediaInfo['duration'] != null)
                    _buildInfoChip(
                      icon: Icons.timer_outlined,
                      label: 'Duration: ${_mediaInfo['duration']}',
                      theme: theme,
                    ),
                  if (_mediaInfo['resolution'] != null)
                    _buildInfoChip(
                      icon: Icons.aspect_ratio_rounded,
                      label: 'Resolution: ${_mediaInfo['resolution']}',
                      theme: theme,
                    ),
                  if (_mediaInfo['videoCodec'] != null)
                    _buildInfoChip(
                      icon: Icons.video_settings_rounded,
                      label: 'Video: ${_mediaInfo['videoCodec']}',
                      theme: theme,
                    ),
                  if (_mediaInfo['audioCodec'] != null)
                    _buildInfoChip(
                      icon: Icons.audiotrack_rounded,
                      label: 'Audio: ${_mediaInfo['audioCodec']}',
                      theme: theme,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Click poster or "Play Video" below to play with your default media player.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Audio / Music Preview
    if (AppUtils.isAudioFormat(path)) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.tertiaryContainer,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.music_note_rounded,
                    size: 64,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.task.fileName,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildInfoChip(
                    icon: Icons.audio_file_outlined,
                    label: '${AppUtils.extractExtension(path).toUpperCase()} Audio',
                    theme: theme,
                  ),
                  _buildInfoChip(
                    icon: Icons.data_usage_rounded,
                    label: AppUtils.formatBytes(_fileSize),
                    theme: theme,
                  ),
                  if (_mediaInfo['duration'] != null)
                    _buildInfoChip(
                      icon: Icons.timer_outlined,
                      label: _mediaInfo['duration']!,
                      theme: theme,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text('Play with Default Audio Player'),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.fileService.openFile(widget.task.savePath);
                },
              ),
            ],
          ),
        ),
      );
    }

    // 4. Text / Document Preview
    if (AppUtils.isTextFormat(path) && _textContent != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: SelectableText(
            _textContent!,
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    // 5. Generic / Other preview card
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppUtils.getCategoryIcon(widget.task.category),
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            widget.task.fileName,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '${AppUtils.getCategoryLabel(widget.task.category)} • ${AppUtils.formatBytes(_fileSize)}',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open with Default Application'),
            onPressed: () {
              Navigator.of(context).pop();
              widget.fileService.openFile(widget.task.savePath);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

