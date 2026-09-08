import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/data/repositories/settings_repository.dart';
import 'package:virusdownloader/data/services/browser_integration_service.dart';
import 'package:virusdownloader/data/services/file_service.dart';
import 'package:virusdownloader/data/services/integration_server_service.dart';
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
  });
}
