import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/enums.dart';
import '../../data/services/integrity_service.dart';
import '../../domain/models/download_task.dart';
import '../view_models/downloads_view_model.dart';

class HashDialog extends StatefulWidget {
  final DownloadTask task;

  const HashDialog({super.key, required this.task});

  static Future<void> show(BuildContext context, DownloadTask task) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => HashDialog(task: task),
    );
  }

  @override
  State<HashDialog> createState() => _HashDialogState();
}

class _HashDialogState extends State<HashDialog> {
  HashAlgorithm _selectedAlgorithm = HashAlgorithm.sha256;
  final TextEditingController _compareController = TextEditingController();
  String? _calculatedHash;
  bool _isCalculating = false;
  double _calcProgress = 0.0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Auto-calculate with initial algorithm
    _startCalculation(_selectedAlgorithm);
  }

  @override
  void dispose() {
    _compareController.dispose();
    super.dispose();
  }

  void _startCalculation(HashAlgorithm algo) async {
    setState(() {
      _selectedAlgorithm = algo;
      _isCalculating = true;
      _calcProgress = 0.0;
      _errorMessage = null;
    });

    final downloadsVm = context.read<DownloadsViewModel>();
    try {
      final hash = await downloadsVm.calculateHash(
        widget.task.id,
        algo,
        onProgress: (prog) {
          if (mounted) {
            setState(() => _calcProgress = prog);
          }
        },
      );
      if (mounted) {
        setState(() {
          _calculatedHash = hash;
          _isCalculating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isCalculating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final integrityService = IntegrityService();

    final enteredText = _compareController.text.trim();
    final hasInput = enteredText.isNotEmpty;
    final isMatch = hasInput &&
        _calculatedHash != null &&
        integrityService.compareHashes(_calculatedHash!, enteredText);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.fingerprint_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('File Checksum / Hash'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.task.fileName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),

              // Algorithm Picker
              Row(
                children: [
                  Text('Algorithm:', style: theme.textTheme.bodyMedium),
                  const SizedBox(width: 12),
                  DropdownButton<HashAlgorithm>(
                    value: _selectedAlgorithm,
                    underline: const SizedBox(),
                    items: HashAlgorithm.values.map((algo) {
                      return DropdownMenuItem(
                        value: algo,
                        child: Text(algo.name.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: _isCalculating
                        ? null
                        : (val) {
                            if (val != null) {
                              _startCalculation(val);
                            }
                          },
                  ),
                  const Spacer(),
                  if (_isCalculating)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Progress Bar if calculating
              if (_isCalculating) ...[
                LinearProgressIndicator(value: _calcProgress > 0 ? _calcProgress : null),
                const SizedBox(height: 4),
                Text(
                  'Hashing file (${(_calcProgress * 100).toStringAsFixed(0)}%)...',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
              ],

              // Calculated Hash Display Card
              if (_calculatedHash != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _calculatedHash!,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        tooltip: 'Copy Hash',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _calculatedHash!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Hash copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
                const SizedBox(height: 16),
              ],

              // Paste Expected Hash to Compare
              Text(
                'Verify with expected hash:',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _compareController,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Paste expected hash to check for match...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: hasInput
                      ? Icon(
                          isMatch ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: isMatch ? Colors.green : Colors.red,
                        )
                      : null,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: hasInput
                          ? (isMatch ? Colors.green : Colors.red)
                          : theme.colorScheme.outline,
                      width: hasInput ? 2.0 : 1.0,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: hasInput
                          ? (isMatch ? Colors.green : Colors.red)
                          : theme.colorScheme.primary,
                      width: 2.0,
                    ),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),

              if (hasInput && _calculatedHash != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isMatch ? Icons.verified_rounded : Icons.warning_amber_rounded,
                      size: 16,
                      color: isMatch ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isMatch ? 'Hashes match perfectly!' : 'Hashes do not match!',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isMatch ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.tonal(
          onPressed: _isCalculating ? null : () => _startCalculation(_selectedAlgorithm),
          child: const Text('Recalculate'),
        ),
      ],
    );
  }
}

