import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/integrity_service.dart';
import '../../domain/models/download_task.dart';
import '../view_models/downloads_view_model.dart';

class RecheckDialog extends StatefulWidget {
  final DownloadTask task;

  const RecheckDialog({super.key, required this.task});

  static Future<void> show(BuildContext context, DownloadTask task) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RecheckDialog(task: task),
    );
  }

  @override
  State<RecheckDialog> createState() => _RecheckDialogState();
}

class _RecheckDialogState extends State<RecheckDialog> {
  bool _isChecking = true;
  double _progress = 0.0;
  String _statusText = 'Starting file integrity recheck...';
  RecheckResult? _result;

  @override
  void initState() {
    super.initState();
    _startRecheck();
  }

  void _startRecheck() async {
    final downloadsVm = context.read<DownloadsViewModel>();
    try {
      final res = await downloadsVm.recheck(
        widget.task.id,
        onProgress: (prog, status) {
          if (mounted) {
            setState(() {
              _progress = prog;
              _statusText = status;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isChecking = false;
          _result = res;
          _statusText = res.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _result = RecheckResult(
            isVerified: false,
            verifiedBytes: 0,
            totalBytes: widget.task.totalBytes,
            message: 'Error during recheck: $e',
          );
          _statusText = 'Recheck failed with error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final res = _result;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isChecking
                ? Icons.sync_rounded
                : (res?.isVerified ?? false
                    ? Icons.verified_rounded
                    : Icons.warning_amber_rounded),
            color: _isChecking
                ? theme.colorScheme.primary
                : (res?.isVerified ?? false ? Colors.green : theme.colorScheme.error),
          ),
          const SizedBox(width: 8),
          const Text('Recheck File Integrity'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.task.fileName,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),

            if (_isChecking) ...[
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}% • $_statusText',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (res?.isVerified ?? false)
                      ? Colors.green.withValues(alpha: 0.12)
                      : theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      (res?.isVerified ?? false)
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      color: (res?.isVerified ?? false) ? Colors.green : theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusText,
                        style: TextStyle(
                          fontSize: 13,
                          color: (res?.isVerified ?? false)
                              ? Colors.green.shade800
                              : theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isChecking)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        if (!_isChecking && !(res?.isVerified ?? true))
          FilledButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry Download'),
            onPressed: () {
              Navigator.of(context).pop();
              context.read<DownloadsViewModel>().retry(widget.task.id);
            },
          ),
      ],
    );
  }
}

