import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/utils.dart';
import '../../domain/models/proxy_config.dart';
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
  final Map<int, bool> _testingIndices = {};

  @override
  void dispose() {
    _proxyInputController.dispose();
    super.dispose();
  }

  void _handleAddProxy(SettingsViewModel vm) {
    final text = _proxyInputController.text.trim();
    if (text.isEmpty) return;

    final err = vm.addProxy(text);
    if (err != null) {
      setState(() => _inputError = err);
    } else {
      _proxyInputController.clear();
      setState(() => _inputError = null);
    }
  }

  void _testProxy(SettingsViewModel vm, int index, ProxyConfig proxy) async {
    setState(() {
      _testingIndices[index] = true;
      _testResults.remove(index);
    });

    final res = await vm.testProxy(proxy);
    if (mounted) {
      setState(() {
        _testingIndices[index] = false;
        if (res != null && res.isWorking) {
          _testResults[index] = 'OK (${res.latency.inMilliseconds}ms)';
        } else {
          _testResults[index] = 'Failed';
        }
      });
    }
  }

  void _benchmarkProxy(SettingsViewModel vm, int index, ProxyConfig proxy) async {
    setState(() {
      _testingIndices[index] = true;
      _testResults.remove(index);
    });

    final res = await vm.benchmarkProxy(proxy);
    if (mounted) {
      setState(() {
        _testingIndices[index] = false;
        if (res != null && res.isWorking) {
          _testResults[index] = AppUtils.formatSpeed(res.speedBytesPerSec);
        } else {
          _testResults[index] = 'Speed test failed';
        }
      });
    }
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
            Row(
              children: [
                const Icon(Icons.hub_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Proxy Servers',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${proxies.length} configured',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Add HTTP or SOCKS5 proxies to bypass restrictions or accelerate downloads in Rocket mode.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Input field to add proxy
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _proxyInputController,
                    decoration: InputDecoration(
                      hintText: 'e.g. socks5://127.0.0.1:1080 or http://user:pass@host:port',
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
                  final isTesting = _testingIndices[index] ?? false;
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
                    subtitle: proxy.lastBenchmarkSpeed != null && proxy.lastBenchmarkSpeed! > 0
                        ? Text(
                            'Last Speed: ${AppUtils.formatSpeed(proxy.lastBenchmarkSpeed!)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (testRes != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: testRes.contains('OK') || testRes.contains('/s')
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              testRes,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: testRes.contains('OK') || testRes.contains('/s')
                                    ? Colors.green.shade800
                                    : theme.colorScheme.error,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (isTesting)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else ...[
                          IconButton(
                            icon: const Icon(Icons.speed_rounded, size: 18),
                            tooltip: 'Benchmark Speed',
                            onPressed: () => _benchmarkProxy(vm, index, proxy),
                          ),
                          IconButton(
                            icon: const Icon(Icons.network_check_rounded, size: 18),
                            tooltip: 'Test Connection',
                            onPressed: () => _testProxy(vm, index, proxy),
                          ),
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

