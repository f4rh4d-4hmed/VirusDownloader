import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/settings_view_model.dart';

class ProxySettingsSection extends StatefulWidget {
  const ProxySettingsSection({super.key});

  @override
  State<ProxySettingsSection> createState() => _ProxySettingsSectionState();
}

class _ProxySettingsSectionState extends State<ProxySettingsSection> {
  final TextEditingController _proxyInputController = TextEditingController();
  String? _inputError;
  final Map<int, String> _testResults = {};
  bool _isTestingAll = false;
  int _testAllCompleted = 0;
  int _testAllTotal = 0;
  final Set<String> _failedUrls = {};

  @override
  void dispose() {
    _proxyInputController.dispose();
    super.dispose();
  }

  void _handleAddProxy(SettingsViewModel vm) {
    final text = _proxyInputController.text.trim();
    if (text.isEmpty) return;

    final isMulti = text.contains('\n') ||
        text.contains('\r') ||
        text.contains(',') ||
        text.contains(';');

    if (isMulti) {
      final res = vm.addMultipleProxies(text);
      if (res.addedCount > 0) {
        _proxyInputController.clear();
        setState(() => _inputError = null);
        final msgParts = <String>[
          'Added ${res.addedCount} ${res.addedCount == 1 ? 'proxy' : 'proxies'}.'
        ];
        if (res.duplicateCount > 0) {
          msgParts.add('${res.duplicateCount} duplicate(s) skipped.');
        }
        if (res.failedCount > 0) {
          msgParts.add('${res.failedCount} invalid skipped.');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msgParts.join(' ')),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (res.duplicateCount > 0) {
        setState(() => _inputError = 'All entered proxies already exist in the list.');
      } else {
        setState(() => _inputError = 'No valid proxies found.');
      }
      return;
    }

    final err = vm.addProxy(text);
    if (err != null) {
      setState(() => _inputError = err);
    } else {
      _proxyInputController.clear();
      setState(() => _inputError = null);
    }
  }

  void _handleTestAll(SettingsViewModel vm) async {
    final proxies = vm.settings.proxyServers;
    if (proxies.isEmpty || _isTestingAll) return;

    setState(() {
      _isTestingAll = true;
      _testAllCompleted = 0;
      _testAllTotal = proxies.length;
      _failedUrls.clear();
      _testResults.clear();
    });

    int workingCount = 0;
    int failedCount = 0;

    await vm.testAllProxies(
      onProgress: (completed, total, res) {
        if (!mounted) return;
        final idx = vm.settings.proxyServers.indexWhere(
          (p) => p.originalUrl == res.proxy.originalUrl || p.displayUrl == res.proxy.displayUrl,
        );
        setState(() {
          _testAllCompleted = completed;
          if (idx != -1) {
            if (res.isWorking) {
              _testResults[idx] = 'OK (${res.latency.inMilliseconds}ms)';
              workingCount++;
            } else {
              _testResults[idx] = 'Failed';
              _failedUrls.add(res.proxy.originalUrl);
              _failedUrls.add(res.proxy.displayUrl);
              failedCount++;
            }
          }
        });
      },
    );

    if (mounted) {
      setState(() {
        _isTestingAll = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Testing completed: $workingCount working, $failedCount failed.',
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleRemoveFailed(BuildContext context, SettingsViewModel vm) {
    if (_failedUrls.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Dead Proxies?'),
        content: const Text(
          'Are you sure you want to remove all unreachable/failed proxies from your list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              vm.removeFailedProxies(_failedUrls);
              setState(() {
                _failedUrls.clear();
                _testResults.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Unreachable proxies have been removed.'),
                  duration: Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Remove Dead'),
          ),
        ],
      ),
    );
  }


  void _confirmClearAll(BuildContext context, SettingsViewModel vm) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Proxies?'),
        content: Text(
          'Are you sure you want to remove all ${vm.settings.proxyServers.length} configured proxy servers?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              vm.clearAllProxies();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All proxy servers have been removed.'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.watch<SettingsViewModel>();
    final proxies = vm.settings.proxyServers;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  'Proxy Servers',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (_isTestingAll) ...[
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: _testAllTotal > 0 ? _testAllCompleted / _testAllTotal : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_testAllCompleted/$_testAllTotal tested',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else ...[
                      Text(
                        '${proxies.length} configured',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (proxies.isNotEmpty && !_isTestingAll) ...[
                      TextButton.icon(
                        icon: const Icon(Icons.network_check_rounded, size: 16),
                        label: const Text('Test All', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _handleTestAll(vm),
                      ),
                      if (_failedUrls.isNotEmpty) ...[
                        TextButton.icon(
                          icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                          label: Text(
                            'Remove Dead (${_failedUrls.length ~/ 2 > 0 ? _failedUrls.length ~/ 2 : _failedUrls.length})',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _handleRemoveFailed(context, vm),
                        ),
                      ],
                      TextButton.icon(
                        icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                        label: const Text('Clear All', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _confirmClearAll(context, vm),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Input field to add single or multiple proxies
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _proxyInputController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'e.g. socks5://host:port (paste multiple separated by line or comma)',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      errorText: _inputError,
                    ),
                    onSubmitted: (_) => _handleAddProxy(vm),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                  onPressed: () => _handleAddProxy(vm),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Proxies list
            if (proxies.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Center(
                  child: Text(
                    'No proxy servers configured yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: proxies.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, index) {
                  final proxy = proxies[index];
                  final testRes = _testResults[index];

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        proxy.type.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    title: Text(
                      proxy.displayUrl,
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (testRes != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: testRes.contains('OK')
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              testRes,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: testRes.contains('OK')
                                    ? Colors.green.shade800
                                    : theme.colorScheme.error,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          tooltip: 'Remove',
                          onPressed: () => vm.removeProxy(index),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

