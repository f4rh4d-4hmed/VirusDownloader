import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/data/repositories/settings_repository.dart';
import 'package:virusdownloader/data/services/browser_integration_service.dart';
import 'package:virusdownloader/data/services/integration_server_service.dart';
import 'package:virusdownloader/data/services/proxy_service.dart';
import 'package:virusdownloader/data/services/storage_service.dart';
import 'package:virusdownloader/domain/models/app_settings.dart';
import 'package:virusdownloader/domain/models/proxy_config.dart';
import 'package:virusdownloader/ui/view_models/settings_view_model.dart';
import 'package:virusdownloader/ui/views/proxy_settings_section.dart';

class MockStorageService implements StorageService {
  AppSettings storedSettings = const AppSettings();

  @override
  Future<AppSettings> loadSettings() async => storedSettings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    storedSettings = settings;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockIntegrationServerService extends ChangeNotifier implements IntegrationServerService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockProxyService implements ProxyService {
  @override
  Future<ProxyBenchmarkResult> testProxy(
    ProxyConfig proxy, {
    String testUrl = 'https://www.google.com',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final isWorking = !proxy.host.contains('dead');
    return ProxyBenchmarkResult(
      proxy: proxy,
      isWorking: isWorking,
      speedBytesPerSec: isWorking ? 1024000.0 : 0.0,
      latency: Duration(milliseconds: isWorking ? 120 : 5000),
      errorMessage: isWorking ? null : 'Connection timed out',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockStorageService storage;
  late SettingsRepository repository;
  late SettingsViewModel vm;

  setUp(() {
    storage = MockStorageService();
    repository = SettingsRepository(storageService: storage);
    vm = SettingsViewModel(
      repository: repository,
      browserService: BrowserIntegrationService(),
      integrationServer: MockIntegrationServerService(),
      proxyService: MockProxyService(),
    );
  });

  group('Batch Add Proxy Unit Tests', () {
    test('addMultipleProxies parses multiple lines and ignores comments and blanks', () {
      const multiLineInput = '''
# Free proxies list
socks5://127.0.0.1:1080

// Secondary proxy
http://user:pass@192.168.1.100:8080
10.0.0.1:3128
invalid-proxy-without-port
''';

      final res = vm.addMultipleProxies(multiLineInput);

      expect(res.addedCount, 3);
      expect(res.failedCount, 1);
      expect(res.failedLines, ['invalid-proxy-without-port']);
      expect(res.duplicateCount, 0);
      expect(vm.settings.proxyServers.length, 3);

      expect(vm.settings.proxyServers[0].type, ProxyType.socks5);
      expect(vm.settings.proxyServers[0].port, 1080);
      expect(vm.settings.proxyServers[1].type, ProxyType.http);
      expect(vm.settings.proxyServers[1].username, 'user');
      expect(vm.settings.proxyServers[2].host, '10.0.0.1');
      expect(vm.settings.proxyServers[2].port, 3128);
    });

    test('addMultipleProxies detects duplicates within batch and existing list', () {
      vm.addProxy('socks5://127.0.0.1:1080');
      expect(vm.settings.proxyServers.length, 1);

      const batchInput = '''
socks5://127.0.0.1:1080
http://192.168.1.50:8080
http://192.168.1.50:8080
''';

      final res = vm.addMultipleProxies(batchInput);

      expect(res.addedCount, 1); // Only 192.168.1.50 added
      expect(res.duplicateCount, 2); // 127.0.0.1 and second 192.168.1.50
      expect(vm.settings.proxyServers.length, 2);
    });

    test('clearAllProxies removes all proxies and resets rocket mode if active', () {
      vm.addMultipleProxies('socks5://127.0.0.1:1080\nhttp://10.0.0.1:8080');
      vm.updateSpeedLimitMode(SpeedLimitMode.rocket);
      expect(vm.settings.proxyServers.length, 2);
      expect(vm.settings.speedLimitMode, SpeedLimitMode.rocket);

      vm.clearAllProxies();
      expect(vm.settings.proxyServers.isEmpty, isTrue);
      expect(vm.settings.speedLimitMode, SpeedLimitMode.unlimited);
    });

    test('single input field handles pasted multiline text seamlessly', () {
      const input = 'socks5://127.0.0.1:1080\nhttp://10.0.0.1:8080';
      final err = vm.addProxy(input);

      expect(err, isNull);
      expect(vm.settings.proxyServers.length, 2);
    });

    test('testAllProxies tests all proxies and reports progress', () async {
      vm.addMultipleProxies('http://live.proxy.com:8080\nhttp://dead.proxy.com:8080');
      expect(vm.settings.proxyServers.length, 2);

      int progressCount = 0;
      final results = await vm.testAllProxies(
        onProgress: (completed, total, res) {
          progressCount++;
        },
      );

      expect(results.length, 2);
      expect(progressCount, 2);
      expect(results['http://live.proxy.com:8080']?.isWorking, isTrue);
      expect(results['http://dead.proxy.com:8080']?.isWorking, isFalse);
    });

    test('removeFailedProxies removes specified dead proxies', () {
      vm.addMultipleProxies('http://live1.proxy.com:8080\nhttp://dead1.proxy.com:8080\nhttp://live2.proxy.com:8080');
      expect(vm.settings.proxyServers.length, 3);

      vm.removeFailedProxies({'http://dead1.proxy.com:8080'});
      expect(vm.settings.proxyServers.length, 2);
      expect(vm.settings.proxyServers.any((p) => p.host.contains('dead1')), isFalse);
      expect(vm.settings.proxyServers.any((p) => p.host.contains('live1')), isTrue);
      expect(vm.settings.proxyServers.any((p) => p.host.contains('live2')), isTrue);
    });
  });

  group('ProxySettingsSection Widget Tests', () {
    testWidgets('shows Add Multiple button and opens dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<SettingsViewModel>.value(
              value: vm,
              child: const ProxySettingsSection(),
            ),
          ),
        ),
      );

      // Verify "Add Multiple" button is present
      expect(find.text('Add Multiple'), findsOneWidget);

      // Tap "Add Multiple"
      await tester.tap(find.text('Add Multiple'));
      await tester.pumpAndSettle();

      // Dialog should be open
      expect(find.text('Add Multiple Proxies'), findsOneWidget);
      expect(find.textContaining('Paste proxy servers line by line'), findsOneWidget);
      expect(find.text('Paste Clipboard'), findsOneWidget);

      // Enter proxy lines into the dialog TextField
      await tester.enterText(
        find.byType(TextField).last,
        'socks5://1.2.3.4:1080\nhttp://5.6.7.8:8080',
      );
      await tester.pump();

      expect(find.text('2 proxies detected'), findsOneWidget);

      // Tap "Add (2)" button
      await tester.tap(find.text('Add (2)'));
      await tester.pumpAndSettle();

      // Dialog dismissed and proxies added
      expect(find.text('Add Multiple Proxies'), findsNothing);
      expect(vm.settings.proxyServers.length, 2);
      expect(find.text('2 configured'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);
    });

    testWidgets('shows Test All button and removes dead proxies in widget', (tester) async {
      vm.addMultipleProxies('http://live.proxy.com:8080\nhttp://dead.proxy.com:8080');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<SettingsViewModel>.value(
              value: vm,
              child: const ProxySettingsSection(),
            ),
          ),
        ),
      );

      expect(find.text('Test All'), findsOneWidget);

      await tester.tap(find.text('Test All'));
      await tester.pumpAndSettle();

      expect(find.textContaining('OK (120ms)'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.textContaining('Remove Dead'), findsOneWidget);

      // Tap Remove Dead
      await tester.tap(find.textContaining('Remove Dead'));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Remove Dead Proxies?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove Dead'));
      await tester.pumpAndSettle();

      // Dead proxy removed, only live proxy remains
      expect(vm.settings.proxyServers.length, 1);
      expect(find.text('1 configured'), findsOneWidget);
      expect(find.textContaining('Remove Dead'), findsNothing);
    });
  });
}
