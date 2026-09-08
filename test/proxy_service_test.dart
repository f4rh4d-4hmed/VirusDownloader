import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/domain/models/proxy_config.dart';

void main() {
  group('ProxyConfig Parsing & Serialization Tests', () {
    test('Parses socks5 proxy with username and password', () {
      const input = 'socks5://admin:secret123@192.168.1.100:1080';
      final proxy = ProxyConfig.tryParse(input);

      expect(proxy, isNotNull);
      expect(proxy!.type, ProxyType.socks5);
      expect(proxy.host, '192.168.1.100');
      expect(proxy.port, 1080);
      expect(proxy.username, 'admin');
      expect(proxy.password, 'secret123');
      expect(proxy.displayUrl, 'socks5://admin:***@192.168.1.100:1080');
    });

    test('Parses http proxy without credentials', () {
      const input = 'http://proxy.example.com:8080';
      final proxy = ProxyConfig.tryParse(input);

      expect(proxy, isNotNull);
      expect(proxy!.type, ProxyType.http);
      expect(proxy.host, 'proxy.example.com');
      expect(proxy.port, 8080);
      expect(proxy.username, isNull);
      expect(proxy.password, isNull);
      expect(proxy.displayUrl, 'http://proxy.example.com:8080');
    });

    test('Parses raw host:port as default http', () {
      const input = '127.0.0.1:8888';
      final proxy = ProxyConfig.tryParse(input);

      expect(proxy, isNotNull);
      expect(proxy!.type, ProxyType.http);
      expect(proxy.host, '127.0.0.1');
      expect(proxy.port, 8888);
    });

    test('Parses socks4 proxy', () {
      const input = 'socks4://10.0.0.1:9050';
      final proxy = ProxyConfig.tryParse(input);

      expect(proxy, isNotNull);
      expect(proxy!.type, ProxyType.socks4);
      expect(proxy.host, '10.0.0.1');
      expect(proxy.port, 9050);
    });

    test('Rejects invalid proxy inputs', () {
      expect(ProxyConfig.tryParse(''), isNull);
      expect(ProxyConfig.tryParse('invalid'), isNull);
      expect(ProxyConfig.tryParse('http://host:invalidport'), isNull);
      expect(ProxyConfig.tryParse('http://host:999999'), isNull);
    });

    test('Serializes to and from JSON', () {
      const original = ProxyConfig(
        host: '127.0.0.1',
        port: 1080,
        type: ProxyType.socks5,
        username: 'user',
        password: 'pwd',
        lastBenchmarkSpeed: 1024000.0,
      );

      final json = original.toJson();
      final restored = ProxyConfig.fromJson(json);

      expect(restored.host, original.host);
      expect(restored.port, original.port);
      expect(restored.type, original.type);
      expect(restored.username, original.username);
      expect(restored.password, original.password);
      expect(restored.lastBenchmarkSpeed, original.lastBenchmarkSpeed);
    });
  });
}

