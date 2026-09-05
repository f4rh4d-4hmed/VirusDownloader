import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/enums.dart';
import '../../core/utils.dart';
import '../../data/services/file_service.dart';
import '../../data/services/http_download_service.dart';

class AddDownloadDialog extends StatefulWidget {
  final String defaultDirectory;
  final FileService fileService;
  final HttpDownloadService httpService;
  final String? initialUrl;
  final String? initialFileName;
  final Map<String, String>? initialHeaders;
  final DownloadCategory? initialCategory;
  final Function({
    required String url,
    required String fileName,
    required String targetDirectory,
    DownloadCategory? category,
    Map<String, String>? headers,
  }) onConfirm;

  const AddDownloadDialog({
    super.key,
    required this.defaultDirectory,
    required this.fileService,
    required this.httpService,
    required this.onConfirm,
    this.initialUrl,
    this.initialFileName,
    this.initialHeaders,
    this.initialCategory,
  });

  @override
  State<AddDownloadDialog> createState() => _AddDownloadDialogState();
}

class _AddDownloadDialogState extends State<AddDownloadDialog> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _fileNameController = TextEditingController();
  final _refererController = TextEditingController();
  final _customHeadersController = TextEditingController();
  late String _selectedDirectory;
  DownloadCategory _selectedCategory = DownloadCategory.other;
  bool _isProbing = false;
  int _probedSize = 0;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _selectedDirectory = widget.defaultDirectory;
    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory!;
    }
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _urlController.text = widget.initialUrl!;
      _fileNameController.text =
          widget.initialFileName ?? AppUtils.extractFileName(widget.initialUrl!);
      _updateCategory(_fileNameController.text);
    } else {
      _checkClipboard();
    }

    if (widget.initialHeaders != null && widget.initialHeaders!.isNotEmpty) {
      final copy = Map<String, String>.from(widget.initialHeaders!);
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
    _fileNameController.dispose();
    _refererController.dispose();
    _customHeadersController.dispose();
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipData?.text?.trim() ?? '';
      if (text.startsWith('http://') || text.startsWith('https://')) {
        _urlController.text = text;
        _onUrlChanged(text);
      }
    } catch (_) {}
  }

  void _onUrlChanged(String url) {
    if (url.trim().isEmpty) return;
    final extracted = AppUtils.extractFileName(url);
    _fileNameController.text = extracted;
    _updateCategory(extracted);
    _probeUrl(url);
  }

  void _updateCategory(String fileName) {
    final cat = AppUtils.categoryFromExtension(fileName);
    setState(() {
      _selectedCategory = cat;
    });
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

  Future<void> _probeUrl(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;
    setState(() {
      _isProbing = true;
    });

    try {
      final headers = _collectHeaders();
      final info = await widget.httpService.probeUrl(url, headers: headers);
      if (!mounted) return;

      if (info.fileName != null && info.fileName!.isNotEmpty) {
        _fileNameController.text = info.fileName!;
        _updateCategory(info.fileName!);
      }
      setState(() {
        _probedSize = info.totalBytes;
      });
    } catch (_) {} finally {
      if (mounted) {
        setState(() {
          _isProbing = false;
        });
      }
    }
  }

  Future<void> _browseFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Download Directory',
      initialDirectory: _selectedDirectory,
    );
    if (result != null && result.isNotEmpty) {
      setState(() {
        _selectedDirectory = result;
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final url = _urlController.text.trim();
    var fileName = _fileNameController.text.trim();
    if (fileName.isEmpty) {
      fileName = AppUtils.extractFileName(url);
    }

    widget.onConfirm(
      url: url,
      fileName: fileName,
      targetDirectory: _selectedDirectory,
      category: _selectedCategory,
      headers: _collectHeaders(),
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Add Download'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // URL input
                TextFormField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'Download URL',
                    hintText: 'https://example.com/file.zip',
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_urlController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _urlController.clear();
                              setState(() {});
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.paste_rounded, size: 18),
                          tooltip: 'Paste',
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null) {
                              _urlController.text = data!.text!.trim();
                              _onUrlChanged(_urlController.text);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  autofocus: true,
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
                  onChanged: (val) {
                    if (val.contains('/')) {
                      _onUrlChanged(val);
                    }
                  },
                ),

                const SizedBox(height: 16),

                // File name input
                TextFormField(
                  controller: _fileNameController,
                  decoration: InputDecoration(
                    labelText: 'File Name',
                    border: const OutlineInputBorder(),
                    helperText: _probedSize > 0
                        ? 'Estimated size: ${AppUtils.formatFileSize(_probedSize)}'
                        : (_isProbing ? 'Checking file info...' : null),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'File name cannot be empty';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Save directory
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Save Location',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedDirectory.isNotEmpty ? _selectedDirectory : 'Default Directory',
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _browseFolder,
                        icon: const Icon(Icons.folder_open_outlined, size: 16),
                        label: const Text('Browse'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Category selector
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<DownloadCategory>(
                      value: _selectedCategory,
                      isDense: true,
                      isExpanded: true,
                      items: DownloadCategory.values
                          .where((c) => c != DownloadCategory.all)
                          .map((cat) => DropdownMenuItem(
                                value: cat,
                                child: Row(
                                  children: [
                                    Icon(AppUtils.getCategoryIcon(cat), size: 18),
                                    const SizedBox(width: 10),
                                    Text(AppUtils.getCategoryLabel(cat)),
                                  ],
                                ),
                              ))
                          .toList(),
                      onChanged: (cat) {
                        if (cat != null) {
                          setState(() {
                            _selectedCategory = cat;
                          });
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Advanced Headers Toggle & Fields
                InkWell(
                  onTap: () {
                    setState(() {
                      _showAdvanced = !_showAdvanced;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 2.0),
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

                if (_showAdvanced) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _refererController,
                    decoration: const InputDecoration(
                      labelText: 'Referer Header (Webpage URL)',
                      hintText: 'https://example.com/watch-video',
                      border: OutlineInputBorder(),
                      helperText: 'Required for videos and CDNs verifying page origin',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customHeadersController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Custom Headers (Key: Value)',
                      hintText: 'Cookie: session=xyz\nOrigin: https://example.com',
                      border: OutlineInputBorder(),
                      helperText: 'One per line, e.g. "Cookie: ..."',
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download'),
        ),
      ],
    );
  }
}
