import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/http_download_service.dart';
import '../../domain/models/download_task.dart';

class ChangeDownloadLinkDialog extends StatefulWidget {
  final DownloadTask task;
  final HttpDownloadService httpService;
  final void Function(String newUrl, [Map<String, String>? headers, bool restartFromBeginning]) onConfirm;

  const ChangeDownloadLinkDialog({
    super.key,
    required this.task,
    required this.httpService,
    required this.onConfirm,
  });

  @override
  State<ChangeDownloadLinkDialog> createState() => _ChangeDownloadLinkDialogState();
}

class _ChangeDownloadLinkDialogState extends State<ChangeDownloadLinkDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  final _refererController = TextEditingController();
  final _customHeadersController = TextEditingController();
  bool _showAdvanced = false;
  bool _isVerifying = false;
  String? _verificationError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.task.url);

    if (widget.task.headers != null && widget.task.headers!.isNotEmpty) {
      final copy = Map<String, String>.from(widget.task.headers!);
      if (copy.containsKey('Referer')) {
        _refererController.text = copy.remove('Referer')!;
      } else if (copy.containsKey('referer')) {
        _refererController.text = copy.remove('referer')!;
      }
      if (copy.isNotEmpty) {
        _customHeadersController.text =
            copy.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      }
      _showAdvanced = true;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _refererController.dispose();
    _customHeadersController.dispose();
    super.dispose();
  }

  Map<String, String>? _collectHeaders() {
    final headers = <String, String>{};
    final referer = _refererController.text.trim();
    if (referer.isNotEmpty) {
      headers['Referer'] = referer;
    }
    final raw = _customHeadersController.text.trim();
    if (raw.isNotEmpty) {
      final lines = raw.split('\n');
      for (final line in lines) {
        final idx = line.indexOf(':');
        if (idx > 0) {
          final key = line.substring(0, idx).trim();
          final val = line.substring(idx + 1).trim();
          if (key.isNotEmpty && val.isNotEmpty) {
            headers[key] = val;
          }
        }
      }
    }
    return headers.isNotEmpty ? headers : null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final newUrl = _urlController.text.trim();
    final headers = _collectHeaders();

    setState(() {
      _isVerifying = true;
      _verificationError = null;
    });

    try {
      final result = await widget.httpService.verifySameFile(
        newUrl: newUrl,
        savePath: widget.task.savePath,
        expectedTotalBytes: widget.task.totalBytes,
        headers: headers,
      );

      if (!mounted) return;

      setState(() {
        _isVerifying = false;
      });

      if (result.matches) {
        widget.onConfirm(newUrl, headers, false);
        Navigator.of(context).pop();
      } else {

        final restart = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final dialogTheme = Theme.of(ctx);
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: dialogTheme.colorScheme.error,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text('Different File Detected'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The provided link appears to point to a different file from the existing download:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.reason ?? 'The first sample of data does not match the local file.',
                    style: TextStyle(color: dialogTheme.colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Resuming will corrupt your downloaded file. Would you like to restart downloading from the beginning with this new link, or cancel?',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: dialogTheme.colorScheme.error,
                    foregroundColor: dialogTheme.colorScheme.onError,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Restart from Scratch'),
                ),
              ],
            );
          },
        );

        if (restart == true && mounted) {
          widget.onConfirm(newUrl, headers, true);
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _verificationError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.link_rounded, size: 24),
          SizedBox(width: 8),
          Text('Change Download Link'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Context card showing filename and progress
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        task.totalBytes > 0
                            ? '${task.formattedDownloadedSize} of ${task.formattedTotalSize} already downloaded'
                            : (task.downloadedBytes > 0
                                ? '${task.formattedDownloadedSize} already downloaded'
                                : 'Ready to resume from new link'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // New URL Input
                TextFormField(
                  controller: _urlController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'New Download URL',
                    hintText: 'https://example.com/file.zip',
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_urlController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: 'Clear URL',
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            onPressed: () {
                              _urlController.clear();
                              setState(() {});
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.paste_rounded, size: 18),
                          tooltip: 'Paste',
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null) {
                              _urlController.text = data!.text!.trim();
                              setState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a download URL';
                    }
                    final uri = Uri.tryParse(val.trim());
                    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
                      return 'Please enter a valid HTTP or HTTPS URL';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),

                const SizedBox(height: 12),

                // Advanced Headers Toggle & Fields with >= 48dp tap target
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _showAdvanced = !_showAdvanced;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            _showAdvanced ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Advanced: Referer & HTTP Headers',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_showAdvanced) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _refererController,
                    decoration: const InputDecoration(
                      labelText: 'Referer Header (Webpage URL)',
                      hintText: 'https://example.com/source-page',
                      border: OutlineInputBorder(),
                      helperText: 'Required if host verifies referring site origin',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customHeadersController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Custom Headers (Key: Value)',
                      hintText: 'Cookie: session=xyz\nAuthorization: Bearer ...',
                      border: OutlineInputBorder(),
                      helperText: 'One per line, e.g. "Cookie: ..."',
                    ),
                  ),
                ],

                if (_isVerifying) ...[
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Verifying file match (checking 1 MB)...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_verificationError != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _verificationError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isVerifying ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isVerifying ? null : _submit,
          icon: _isVerifying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_isVerifying ? 'Verifying...' : 'Change Link'),
        ),
      ],
    );
  }
}
